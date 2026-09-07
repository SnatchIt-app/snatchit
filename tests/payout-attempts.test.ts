/**
 * tests/payout-attempts.test.ts — the payout ATTEMPT protocol end to end:
 * the REAL _shared/payouts.ts (executePayoutAttempt / createSellerPayout /
 * findTransferByAttempt, loaded via payouts-vm) against a Stripe model with
 * real idempotency-key + transfer_group semantics and a DB model with the
 * exact RPC predicates of migration 20260906120000; then the REAL
 * confirm-and-release and enforce-transfer-expiry handlers on top of it.
 *
 * Every scenario ends with exactly ONE real Stripe transfer per obligation
 * and a DB row that knows its id — including the F07 (dispute mid-payout)
 * and F08 (lost response / 24h key expiry / destination change) cases.
 */
import { describe, expect, it } from 'vitest';
import { authedJsonRequest, json, loadEdgeHandler, mockStripe, mockSupabase, type QueryCall, type StripeCall } from './helpers/edge-vm';
import { loadPayoutsModule } from './helpers/payouts-vm';
import { AttemptLedger, HOUR, LEASE_MS, StripeTransfersMock } from './helpers/payout-protocol';

const ARGS = { transferId: 't1', paymentId: 'p1', sellerId: 'seller-1', actor: 'edge:test' };

function setup(opts: { onStripe?: (c: StripeCall, ledger: AttemptLedger) => void } = {}) {
  const ledger = new AttemptLedger();
  const stripeMock = new StripeTransfersMock();
  const stripe = mockStripe(async (c) => {
    const r = await stripeMock.route(c);
    opts.onStripe?.(c, ledger);
    return r;
  });
  const payouts = loadPayoutsModule(stripe);
  const rpcLog: Array<{ name: string; params: Record<string, unknown> }> = [];
  const db = { rpc: async (name: string, params: Record<string, unknown>) => { rpcLog.push({ name, params }); return ledger.rpc(name, params); } };
  const run = () => payouts.executePayoutAttempt(db, ARGS);
  const posts = () => stripe.calls.filter((c) => c.method === 'POST' && c.path === '/transfers');
  return { ledger, stripeMock, stripe, payouts, db, rpcLog, run, posts };
}

describe('executePayoutAttempt — claim → (reconcile) → pre-flight → mark → POST → record', () => {
  it('happy path: one POST under the attempt key, frozen params, transfer_group + attempt metadata, recorded', async () => {
    const s = setup();
    s.ledger.seedReleasable({ status: 'auto_released' });
    const out = await s.run();
    expect(out.kind).toBe('succeeded');
    expect(s.rpcLog.map((r) => r.name)).toEqual(['claim_payout_attempt', 'mark_payout_requested', 'record_payout_attempt_result']);
    const post = s.posts()[0];
    expect(post.idempotencyKey).toBe('payout_t1_a1');
    const body = post.body as Record<string, string>;
    expect(body.transfer_group).toBe('t1');
    expect(body['metadata[attempt_id]']).toBe('att_1');
    expect(body.destination).toBe('acct_A');
    expect(body.amount).toBe('9000');
    expect(body.source_transaction).toBe('ch_1');
    expect(s.ledger.transfers.get('t1')!.stripe_transfer_id).toBe('tr_1');
    expect(s.ledger.transfers.get('t1')!.payout_released_at).not.toBeNull();
    expect(s.ledger.attempts[0].state).toBe('succeeded');
    // pre-flights happen BEFORE mark_payout_requested, POST after it
    const order = s.stripe.calls.map((c) => c.method + ' ' + c.path.split('?')[0]);
    // the legacy-aware pre-flight (destination listing, release review A3 §2.2) runs before the
    // capability / funding-charge probes; nothing is POSTed until all three have passed
    expect(order).toEqual(['GET /transfers', 'GET /accounts/acct_A', 'GET /payment_intents/pi_1', 'POST /transfers']);
  });

  it('F07: a dispute landing between claim and record is STILL recorded — tr_ id on the row, attempt reversal_required, review decision', async () => {
    const s = setup({ onStripe: (c, ledger) => { if (c.method === 'POST') expect(ledger.freezeForDispute('t1')).toBe(true); } });
    s.ledger.seedReleasable({ status: 'buyer_confirmed' });
    const out = await s.run();
    expect(out.kind).toBe('reversal_required');
    expect(s.rpcLog.map((r) => r.name)).toEqual(['claim_payout_attempt', 'mark_payout_requested', 'record_payout_attempt_result']);
    expect(s.rpcLog[2].params).toMatchObject({ p_stripe_transfer_id: 'tr_1', p_outcome: 'succeeded' });
    const row = s.ledger.transfers.get('t1')!;
    expect(row.status).toBe('disputed');
    expect(row.stripe_transfer_id).toBe('tr_1');          // never lost
    expect(row.payout_released_at).not.toBeNull();
    expect(s.ledger.attempts[0].state).toBe('reversal_required');
    expect(s.ledger.decisions[0]).toMatchObject({ decision: 'manual_review', reason_codes: ['PAID_DURING_DISPUTE'] });
    // …and a seller-win later does NOT pay a second time (the §7 compounding case)
    s.ledger.resolveSellerWin('t1');
    const again = await s.run();
    expect(again.kind).toBe('already_released');
    expect(s.stripeMock.created).toBe(1);
  });

  it('F08(c): Stripe accepts but the response is lost → next run reconciles via transfer_group, NO second POST', async () => {
    const s = setup();
    s.ledger.seedReleasable({ status: 'auto_released' });
    s.stripeMock.nextPostFault = { kind: 'lost_response' };
    const r1 = await s.run();
    expect(r1.kind).toBe('unknown');
    expect(s.stripeMock.created).toBe(1);
    expect(s.ledger.attempts[0].state).toBe('unknown');
    expect(s.ledger.transfers.get('t1')!.stripe_transfer_id).toBeNull();   // honest: DB doesn't know yet

    // Lease still live → another worker must not touch it.
    const r2 = await s.run();
    expect(r2.kind).toBe('in_progress');
    expect(s.posts()).toHaveLength(1);

    s.ledger.advance(LEASE_MS + 1);
    const r3 = await s.run();
    expect(r3).toMatchObject({ kind: 'reconciled', found: true, state: 'succeeded', stripeTransferId: 'tr_1' });
    expect(s.posts()).toHaveLength(1);                                     // reconcile, not replay
    expect(s.stripe.calls.some((c) => c.method === 'GET' && c.path.startsWith('/transfers?transfer_group=t1'))).toBe(true);
    expect(s.ledger.transfers.get('t1')!.stripe_transfer_id).toBe('tr_1');
    expect(s.stripeMock.created).toBe(1);
  });

  it('F08(d): retry after the 24h key window → still ONE transfer (the ledger, not the key, is the guard)', async () => {
    const s = setup();
    s.ledger.seedReleasable({ status: 'auto_released' });
    s.stripeMock.nextPostFault = { kind: 'lost_response' };
    await s.run();
    s.ledger.advance(25 * HOUR); s.stripeMock.advance(25 * HOUR);          // Stripe has forgotten the key
    const r = await s.run();
    expect(r).toMatchObject({ kind: 'reconciled', found: true });
    expect(s.stripeMock.created).toBe(1);
    expect(s.posts()).toHaveLength(1);
  });

  it('a NEW attempt (new key) opens only after the previous one is terminal', async () => {
    const s = setup();
    s.ledger.seedReleasable({ status: 'auto_released' });
    s.stripeMock.nextPostFault = { kind: 'network' };                      // nothing created
    expect((await s.run()).kind).toBe('unknown');
    s.ledger.advance(LEASE_MS + 1);
    expect(await s.run()).toMatchObject({ kind: 'reconciled', found: false, state: 'failed' });
    expect(s.posts()).toHaveLength(1);                                     // the reconcile run never POSTs
    const r3 = await s.run();
    expect(r3).toMatchObject({ kind: 'succeeded', attemptNo: 2 });
    expect(s.posts()[1].idempotencyKey).toBe('payout_t1_a2');
    expect(s.stripeMock.created).toBe(1);
    expect(s.ledger.attempts.map((a) => a.state)).toEqual(['failed', 'succeeded']);
  });

  it('F08(e): destination changes during recovery → the frozen destination is what gets reconciled; profiles are never re-read', async () => {
    const s = setup();
    s.ledger.seedReleasable({ status: 'auto_released', destination: 'acct_A' });
    s.stripeMock.nextPostFault = { kind: 'lost_response' };
    await s.run();
    s.ledger.profiles.set('seller-1', { stripe_connect_id: 'acct_B' });   // seller re-onboards mid-recovery
    s.ledger.advance(LEASE_MS + 1);
    const r = await s.run();
    expect(r).toMatchObject({ kind: 'reconciled', found: true, stripeTransferId: 'tr_1' });
    expect(s.stripeMock.transfers).toHaveLength(1);
    expect(s.stripeMock.transfers[0].destination).toBe('acct_A');
    expect(s.ledger.attempts[0].destination).toBe('acct_A');
  });

  it('a genuinely new attempt after a terminal one uses the CURRENT destination (re-onboarding is legitimate)', async () => {
    const s = setup();
    s.ledger.seedReleasable({ status: 'auto_released', destination: 'acct_A' });
    s.stripeMock.nextPostFault = { kind: 'network' };
    await s.run();
    s.ledger.profiles.set('seller-1', { stripe_connect_id: 'acct_B' });
    s.ledger.advance(LEASE_MS + 1);
    await s.run();                                                          // reconcile → failed
    const r = await s.run();
    expect(r).toMatchObject({ kind: 'succeeded', attemptNo: 2, destination: 'acct_B' });
    expect(s.stripeMock.transfers).toHaveLength(1);
  });

  it('pre-flight refusal closes the attempt WITHOUT a POST and without marking it requested', async () => {
    const s = setup();
    s.ledger.seedReleasable({ status: 'auto_released' });
    s.stripeMock.accountCapability = 'inactive';
    const r = await s.run();
    expect(r).toMatchObject({ kind: 'deferred', reasonCode: 'PAYOUT_DESTINATION_NOT_READY', page: false });
    expect(s.posts()).toHaveLength(0);
    expect(s.rpcLog.map((x) => x.name)).toEqual(['claim_payout_attempt', 'record_payout_attempt_result']);
    expect(s.ledger.attempts[0].state).toBe('failed');
    // refunded funding charge → same shape
    const s2 = setup(); s2.ledger.seedReleasable({ status: 'auto_released' }); s2.stripeMock.chargeRefunded = true;
    expect(await s2.run()).toMatchObject({ kind: 'deferred', reasonCode: 'PAYOUT_SOURCE_CHARGE_UNAVAILABLE' });
    expect(s2.posts()).toHaveLength(0);
  });

  it('Stripe outcomes: definite 4xx → failed_not_created (deferred); 5xx / 409 / idempotency_error → unknown (reconciled later)', async () => {
    const s = setup(); s.ledger.seedReleasable({ status: 'auto_released' });
    s.stripeMock.nextPostFault = { kind: 'status', status: 402, message: 'Insufficient funds in Stripe account.' };
    expect(await s.run()).toMatchObject({ kind: 'deferred', reasonCode: 'PAYOUT_INSUFFICIENT_FUNDS', page: false });
    expect(s.ledger.attempts[0].state).toBe('failed');

    const s5 = setup(); s5.ledger.seedReleasable({ status: 'auto_released' });
    s5.stripeMock.nextPostFault = { kind: 'status', status: 500, message: 'boom' };
    expect((await s5.run()).kind).toBe('unknown');
    expect(s5.ledger.attempts[0].state).toBe('unknown');

    const s9 = setup(); s9.ledger.seedReleasable({ status: 'auto_released' });
    s9.stripeMock.nextPostFault = { kind: 'status', status: 409, message: 'in flight' };
    expect((await s9.run()).kind).toBe('unknown');

    const s4 = setup(); s4.ledger.seedReleasable({ status: 'auto_released' });
    s4.stripeMock.nextPostFault = { kind: 'status', status: 400, type: 'idempotency_error', message: 'Keys for idempotent requests can only be used with the same parameters' };
    expect((await s4.run()).kind).toBe('unknown');

    const s3 = setup(); s3.ledger.seedReleasable({ status: 'auto_released' });
    s3.stripeMock.nextPostFault = { kind: 'status', status: 400, message: 'No such destination' };
    expect(await s3.run()).toMatchObject({ kind: 'deferred', reasonCode: 'PAYOUT_TRANSFER_FAILED', page: true });
  });

  it('claim refusals map to outcomes: already released / disputed / not releasable / DB error', async () => {
    const s = setup(); s.ledger.seedReleasable({ status: 'auto_released' });
    s.ledger.transfers.get('t1')!.payout_released_at = 'earlier'; s.ledger.transfers.get('t1')!.stripe_transfer_id = 'tr_old';
    expect((await s.run()).kind).toBe('already_released');
    const s2 = setup(); s2.ledger.seedReleasable({ status: 'buyer_confirmed' }); s2.ledger.freezeForDispute('t1');
    expect(await s2.run()).toMatchObject({ kind: 'not_eligible', reason: 'DISPUTED' });
    const s3 = setup(); s3.ledger.seedReleasable({ status: 'seller_sent' });
    expect(await s3.run()).toMatchObject({ kind: 'not_eligible', reason: 'TRANSFER_NOT_RELEASABLE' });
    const s4 = setup(); s4.ledger.seedReleasable({ status: 'auto_released' }); s4.ledger.failNext.set('claim_payout_attempt', 'connection reset');
    expect(await s4.run()).toMatchObject({ kind: 'db_error', stage: 'claim' });
    for (const x of [s, s2, s3, s4]) expect(x.posts()).toHaveLength(0);
  });

  it('mark_payout_requested failure → nothing is sent to Stripe', async () => {
    const s = setup(); s.ledger.seedReleasable({ status: 'auto_released' });
    s.ledger.failNext.set('mark_payout_requested', 'connection reset');
    expect(await s.run()).toMatchObject({ kind: 'db_error', stage: 'mark' });
    expect(s.posts()).toHaveLength(0);
    expect(s.ledger.attempts[0].state).toBe('claimed');
    // the next sweep (after the lease) closes it and a fresh attempt pays
    s.ledger.advance(LEASE_MS + 1);
    expect(await s.run()).toMatchObject({ kind: 'reconciled', found: false });
    expect(await s.run()).toMatchObject({ kind: 'succeeded', attemptNo: 2 });
    expect(s.stripeMock.created).toBe(1);
  });

  it('record failure after Stripe succeeded surfaces the tr_ id (db_error), and the next sweep reconciles it', async () => {
    const s = setup(); s.ledger.seedReleasable({ status: 'auto_released' });
    s.ledger.failNext.set('record_payout_attempt_result', 'connection reset');
    expect(await s.run()).toMatchObject({ kind: 'db_error', stage: 'record', stripeTransferId: 'tr_1' });
    expect(s.ledger.transfers.get('t1')!.stripe_transfer_id).toBeNull();
    s.ledger.advance(LEASE_MS + 1);
    expect(await s.run()).toMatchObject({ kind: 'reconciled', found: true, stripeTransferId: 'tr_1' });
    expect(s.stripeMock.created).toBe(1);
    expect(s.ledger.transfers.get('t1')!.stripe_transfer_id).toBe('tr_1');
  });

  it('reconcile never closes an attempt on an inconclusive search (list error / unmatched transfers in the group)', async () => {
    const s = setup(); s.ledger.seedReleasable({ status: 'auto_released' });
    s.stripeMock.nextPostFault = { kind: 'network' };
    await s.run();
    s.ledger.advance(LEASE_MS + 1);
    s.stripeMock.listFault = { kind: 'status', status: 500, message: 'list down' };
    expect(await s.run()).toMatchObject({ kind: 'reconcile_pending' });
    expect(s.ledger.attempts[0].state).toBe('unknown');
    // a foreign transfer in the group (e.g. a manual dashboard transfer) → still open, for an operator
    s.stripeMock.createTransfer('manual', { amount: 9000, destination: 'acct_A', transfer_group: 't1', metadata: {} });
    s.ledger.advance(LEASE_MS + 1);
    expect(await s.run()).toMatchObject({ kind: 'reconcile_pending', unmatched: ['tr_1'] });
    expect(s.ledger.attempts[0].state).toBe('unknown');
    expect(s.posts()).toHaveLength(1);
  });

  it('createSellerPayout refuses a key that does not belong to the attempt', async () => {
    const s = setup();
    await expect(s.payouts.createSellerPayout({
      transferId: 't1', paymentId: 'p1', sellerId: 'seller-1', attemptId: 'att_1', attemptNo: 2,
      idempotencyKey: 'payout_t1_a1', destination: 'acct_A', paymentIntentId: 'pi_1', sellerNetCents: 9000,
    })).rejects.toThrow(/idempotency key/);
  });
});

// ── REAL confirm-and-release handler ─────────────────────────────────────────

const ENV = { SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test', STRIPE_SECRET_KEY: 'sk_test_x', INTERNAL_CRON_SECRET: 'cron-secret' };

async function loadConfirmAndRelease(opts: { onStripe?: (c: StripeCall, ledger: AttemptLedger) => void; transferStatus?: 'buyer_confirmed' | 'seller_sent' } = {}) {
  const ledger = new AttemptLedger();
  ledger.seedReleasable({ status: opts.transferStatus ?? 'seller_sent' });
  const stripeMock = new StripeTransfersMock();
  const stripe = mockStripe(async (c) => { const r = await stripeMock.route(c); opts.onStripe?.(c, ledger); return r; });
  const payouts = loadPayoutsModule(stripe);
  const decisions: unknown[] = [];
  const sb = mockSupabase({
    user: { id: 'buyer-1' },
    rpc: async (name, params) => {
      if (name === 'check_rate_limit') return { data: true };
      if (name === 'confirm_transfer_received') {
        const ok = ledger.confirmTransferReceived(params.p_transfer_id as string);
        return ok ? { data: null } : { data: null, error: { message: 'Transfer cannot be confirmed from current status: ' + ledger.transfers.get('t1')!.status } };
      }
      return ledger.rpc(name, params);
    },
    tables: {
      transfers: (q: QueryCall) => {
        const id = q.filters.find((f) => f[0] === 'eq' && f[1] === 'id')?.[2] as string;
        const row = ledger.transfers.get(id);
        return { data: row ? { ...row } : null };
      },
      payout_decisions: (q: QueryCall) => { if (q.op === 'insert') decisions.push(q.body); return { data: q.op === 'insert' ? null : null }; },
      payments: () => ({ data: { amount: 10000, seller_fee: 1000, status: 'succeeded', stripe_payment_intent_id: 'pi_1' } }),
    },
  });
  const edge = await loadEdgeHandler('supabase/functions/confirm-and-release/index.ts', {
    supabase: sb, env: ENV,
    provide: { executePayoutAttempt: payouts.executePayoutAttempt, stripeFetch: stripe.stripeFetch },
  });
  const call = () => edge.handler(authedJsonRequest({ transfer_id: 't1' }));
  const posts = () => stripe.calls.filter((c) => c.method === 'POST' && c.path === '/transfers');
  return { ledger, stripeMock, stripe, sb, edge, call, posts, decisions };
}

describe('confirm-and-release (real handler) on the attempt protocol', () => {
  it('dispute between claim and record ⇒ tr_ recorded, reversal_required, buyer told pending_review; exact RPC sequence', async () => {
    const h = await loadConfirmAndRelease({ onStripe: (c, ledger) => { if (c.method === 'POST') ledger.freezeForDispute('t1'); } });
    const res = await h.call();
    expect(res.status).toBe(200);
    expect(await json(res)).toMatchObject({ success: true, payout_status: 'pending_review' });
    expect(h.sb.rpcs.map((r) => r.name)).toEqual([
      'check_rate_limit', 'confirm_transfer_received', 'claim_payout_attempt', 'mark_payout_requested', 'record_payout_attempt_result',
    ]);
    expect(h.sb.rpcs[4].params).toMatchObject({ p_stripe_transfer_id: 'tr_1', p_outcome: 'succeeded' });
    expect(h.ledger.transfers.get('t1')!.stripe_transfer_id).toBe('tr_1');
    expect(h.ledger.attempts[0].state).toBe('reversal_required');
    expect(h.sb.queries.some((q) => q.table === 'profiles')).toBe(false);   // destination frozen at claim
  });

  it('happy path ⇒ stripe_transfer_id returned, release audit row written, one POST', async () => {
    const h = await loadConfirmAndRelease();
    const res = await h.call();
    expect(await json(res)).toMatchObject({ success: true, stripe_transfer_id: 'tr_1' });
    expect(h.posts()).toHaveLength(1);
    expect(h.decisions).toHaveLength(1);
    expect(h.decisions[0]).toMatchObject({ decision: 'release', reason_codes: ['BUYER_CONFIRMED'] });
    // replay ⇒ already_released, no second POST
    const res2 = await h.call();
    expect(await json(res2)).toMatchObject({ success: true, already_released: true });
    expect(h.posts()).toHaveLength(1);
  });

  it('Stripe accepts, response lost ⇒ buyer sees processing; the retry reconciles via list with no second POST', async () => {
    const h = await loadConfirmAndRelease();
    h.stripeMock.nextPostFault = { kind: 'lost_response' };
    expect(await json(await h.call())).toMatchObject({ success: true, payout_status: 'processing' });
    expect(h.stripeMock.created).toBe(1);
    expect(await json(await h.call())).toMatchObject({ success: true, payout_status: 'processing' }); // lease live
    h.ledger.advance(LEASE_MS + 1);
    const res = await h.call();
    expect(await json(res)).toMatchObject({ success: true, already_released: true, stripe_transfer_id: 'tr_1' });
    expect(h.sb.rpcs.filter((r) => r.name === 'reconcile_payout_attempt')).toHaveLength(1);
    expect(h.posts()).toHaveLength(1);
    expect(h.ledger.transfers.get('t1')!.stripe_transfer_id).toBe('tr_1');
  });

  it('a dispute BEFORE the claim never reaches Stripe (confirm RPC refuses the disputed row; no attempt is opened)', async () => {
    const h = await loadConfirmAndRelease({ transferStatus: 'buyer_confirmed' });
    h.ledger.freezeForDispute('t1');
    const res = await h.call();
    expect(res.status).toBe(400);                                          // "cannot be confirmed from current status: disputed"
    expect(h.stripe.calls).toHaveLength(0);
    expect(h.sb.rpcs.map((r) => r.name)).not.toContain('claim_payout_attempt');
    expect(h.ledger.attempts).toHaveLength(0);
  });

  it('a dispute arriving after confirmation but before this call ⇒ 409 frozen, no Stripe traffic', async () => {
    const h = await loadConfirmAndRelease({ transferStatus: 'buyer_confirmed' });
    h.ledger.transfers.get('t1')!.disputed_at = 'now';                       // frozen while status still reads buyer_confirmed
    const res = await h.call();
    expect(res.status).toBe(409);
    expect(h.stripe.calls).toHaveLength(0);
    expect(h.ledger.attempts).toHaveLength(0);
  });

  it('pre-flight deferral ⇒ pending_review with ONE manual_review decision carrying the reason', async () => {
    const h = await loadConfirmAndRelease();
    h.stripeMock.accountCapability = 'inactive';
    expect(await json(await h.call())).toMatchObject({ success: true, payout_status: 'pending_review' });
    expect(h.decisions[0]).toMatchObject({ decision: 'manual_review', reason_codes: ['BUYER_CONFIRMED', 'PAYOUT_DESTINATION_NOT_READY'] });
    expect(h.posts()).toHaveLength(0);
  });
});

// ── REAL enforce-transfer-expiry Phase 2b sweep ─────────────────────────────

async function loadSweep(ledger: AttemptLedger, stripeMock: StripeTransfersMock, opts: { onStripe?: (c: StripeCall) => void } = {}) {
  const stripe = mockStripe(async (c) => { const r = await stripeMock.route(c); opts.onStripe?.(c); return r; });
  const payouts = loadPayoutsModule(stripe);
  const sb = mockSupabase({
    rpc: async (name, params) => {
      if (['enforce_transfer_expiry', 'get_auto_release_candidates'].includes(name)) return { data: [] };
      return ledger.rpc(name, params);
    },
    tables: {
      transfers: (q: QueryCall) => {
        if (q.filters.some((f) => f[0] === 'in' && f[1] === 'status')) {
          const rows = [...ledger.transfers.values()].filter((t) => ['auto_released', 'buyer_confirmed'].includes(t.status) && t.stripe_transfer_id === null && t.payout_released_at === null && t.disputed_at === null);
          return { data: rows.map((t) => ({ ...t })) };
        }
        return { data: [] };
      },
      payout_attempts: () => ({
        data: ledger.attempts
          .filter((a) => ['claimed', 'requested', 'unknown'].includes(a.state) && a.lease_expires_at <= ledger.now)
          .map((a) => { const t = ledger.transfers.get(a.transfer_id)!; return { id: a.id, transfer_id: a.transfer_id, state: a.state, transfers: { id: t.id, payment_id: t.payment_id, listing_id: t.listing_id, seller_id: t.seller_id, buyer_id: t.buyer_id } }; }),
      }),
      payout_policy: () => ({ data: null }),
      listings: () => ({ data: { event_name: 'Fixture' } }),
      payout_decisions: () => ({ data: null }),
    },
  });
  const edge = await loadEdgeHandler('supabase/functions/enforce-transfer-expiry/index.ts', {
    supabase: sb, env: ENV,
    provide: {
      executePayoutAttempt: payouts.executePayoutAttempt, stripeFetch: stripe.stripeFetch,
      isCrossModeStripeError: () => false, rowIsLiveActionable: (v: unknown) => v === true, allowTestModeMoney: () => false,
      classifyPayout: () => ({ action: 'hold', tier: 'low', reasons: [], hold_until: null }), DEFAULT_POLICY: {},
      PayoutCandidate: undefined, PayoutPolicyConfig: undefined,
    },
  });
  const run = () => edge.handler(new Request('https://edge.test/enforce', { method: 'POST', headers: { authorization: 'Bearer cron-secret' } }));
  const posts = () => stripe.calls.filter((c) => c.method === 'POST' && c.path === '/transfers');
  return { edge, sb, run, posts, stripe };
}

describe('enforce-transfer-expiry Phase 2b (real handler) on the attempt protocol', () => {
  it('a stuck auto_released row is paid once; the next sweep is a no-op', async () => {
    const ledger = new AttemptLedger(); ledger.seedReleasable({ status: 'auto_released' });
    const stripeMock = new StripeTransfersMock();
    const s = await loadSweep(ledger, stripeMock);
    const res = await s.run();
    expect(res.status).toBe(200);
    expect(s.posts()).toHaveLength(1);
    expect(ledger.transfers.get('t1')!.stripe_transfer_id).toBe('tr_1');
    await s.run();
    expect(s.posts()).toHaveLength(1);
  });

  it('an attempt whose lease expired (lost response) is reconciled through the payout_attempts sweep, even on a now-disputed transfer', async () => {
    const ledger = new AttemptLedger(); ledger.seedReleasable({ status: 'auto_released' });
    const stripeMock = new StripeTransfersMock();
    stripeMock.nextPostFault = { kind: 'lost_response' };
    const s = await loadSweep(ledger, stripeMock);
    await s.run();                                                          // POST, response lost → unknown
    expect(ledger.attempts[0].state).toBe('unknown');
    ledger.freezeForDispute('t1');                                          // chargeback arrives meanwhile
    ledger.advance(LEASE_MS + 1);
    await s.run();
    expect(ledger.attempts[0].state).toBe('reversal_required');            // recorded, flagged — not orphaned
    expect(ledger.transfers.get('t1')!.stripe_transfer_id).toBe('tr_1');
    expect(s.posts()).toHaveLength(1);
    expect(stripeMock.created).toBe(1);
  });
});

describe('sandbox switch ALLOW_TEST_MODE_MONEY / app.allow_test_mode_money (default OFF)', () => {
  it('a test-mode payment is refused end to end by default (PAYMENT_NOT_LIVE, no POST) and admitted only with BOTH switches on', async () => {
    const s = setup();
    s.ledger.seedReleasable({ status: 'auto_released' });
    s.ledger.payments.get('p1')!.stripe_livemode = false;
    s.stripeMock.piLivemode = false;
    expect(await s.run()).toMatchObject({ kind: 'not_eligible', reason: 'PAYMENT_NOT_LIVE' });
    expect(s.posts()).toHaveLength(0);
    // DB switch alone: the claim succeeds but the edge pre-flight still refuses a test-mode PI (deferred, no POST)
    s.ledger.allowTestModeMoney = true;
    expect(await s.run()).toMatchObject({ kind: 'deferred', reasonCode: 'PAYOUT_SOURCE_CHARGE_UNAVAILABLE' });
    expect(s.posts()).toHaveLength(0);
    // both switches: a real Connect TEST transfer is created under the attempt key
    const g = globalThis as unknown as { Deno?: unknown };
    const saved = g.Deno;
    g.Deno = { env: { get: (k: string) => (k === 'ALLOW_TEST_MODE_MONEY' ? '1' : undefined) } };
    try {
      const out = await s.run();
      expect(out.kind).toBe('succeeded');
      expect(s.posts()).toHaveLength(1);
      expect(s.posts()[0].idempotencyKey).toMatch(/^payout_t1_a\d+$/);
    } finally {
      if (saved === undefined) delete g.Deno; else g.Deno = saved;
    }
  });
  it('NULL (unclassified) livemode is never admitted, even with both switches on', async () => {
    const s = setup();
    s.ledger.seedReleasable({ status: 'auto_released' });
    s.ledger.payments.get('p1')!.stripe_livemode = null;
    s.ledger.allowTestModeMoney = true;
    const g = globalThis as unknown as { Deno?: unknown };
    g.Deno = { env: { get: (k: string) => (k === 'ALLOW_TEST_MODE_MONEY' ? '1' : undefined) } };
    try {
      expect(await s.run()).toMatchObject({ kind: 'not_eligible', reason: 'PAYMENT_NOT_LIVE' });
      expect(s.posts()).toHaveLength(0);
    } finally { delete g.Deno; }
  });
});
