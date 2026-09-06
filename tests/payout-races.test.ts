/**
 * AUDIT 5 (rewritten for the attempt protocol, PAYMENTS_RELIABILITY_2026-09
 * Package 3) — deterministic simulation of the payout release protocol.
 *
 * WHAT THIS PROVES (and what it doesn't): Postgres and Stripe are separate
 * systems — there is NO cross-system atomicity, and these tests don't claim
 * any. They verify the PROTOCOL the production code implements, running the
 * REAL _shared/payouts.ts (executePayoutAttempt) against:
 *
 *   1. AttemptLedger — the payout_attempts RPC predicates of migration
 *      20260906120000 (claim with lease + frozen params, one open attempt,
 *      state only advances, a transfer Stripe reports is ALWAYS recorded)
 *      plus the pre-existing transfer state machine (039 apply_auto_release,
 *      002 confirm_transfer_received, 056a freeze, 065 seller-win).
 *   2. StripeTransfersMock — real Idempotency-Key semantics INCLUDING the
 *      24h key expiry that made the old `payout_<id>_<acct>_src` scheme
 *      double-pay (F08), and transfer_group listing.
 *
 * Every interleaving asserted below must end with exactly ONE real Stripe
 * Transfer per obligation and a DB row that knows its id.
 */
import { describe, expect, it } from 'vitest';
import { mockStripe, type StripeCall } from './helpers/edge-vm';
import { loadPayoutsModule } from './helpers/payouts-vm';
import { AttemptLedger, HOUR, LEASE_MS, StripeTransfersMock } from './helpers/payout-protocol';

const CRON  = { transferId: 't1', paymentId: 'p1', sellerId: 'seller-1', actor: 'cron:enforce-transfer-expiry' };
const BUYER = { transferId: 't1', paymentId: 'p1', sellerId: 'seller-1', actor: 'edge:confirm-and-release' };

function world(opts: { onStripe?: (c: StripeCall) => void } = {}) {
  const ledger = new AttemptLedger();
  const stripe = new StripeTransfersMock();
  const transport = mockStripe(async (c) => { const r = await stripe.route(c); opts.onStripe?.(c); return r; });
  const payouts = loadPayoutsModule(transport);
  const pay = (args = CRON) => payouts.executePayoutAttempt({ rpc: ledger.rpc }, args);
  const row = () => ledger.transfers.get('t1')!;
  return { ledger, stripe, transport, pay, row };
}

describe('payout race simulations (attempt protocol)', () => {
  it('cron claim vs buyer confirmation — cron wins the row: buyer path cannot pay twice', async () => {
    const w = world(); w.ledger.seedReleasable();
    expect(w.ledger.applyAutoRelease('t1')).toBe(true);           // cron claims (row lock)
    expect(w.ledger.confirmTransferReceived('t1')).toBe(true);    // tolerated (auto_released ⊇ confirmed)
    expect((await w.pay(CRON)).kind).toBe('succeeded');
    expect((await w.pay(BUYER)).kind).toBe('already_released');
    expect(w.stripe.created).toBe(1);
    expect(w.row().stripe_transfer_id).toBe('tr_1');
  });

  it('cron claim vs buyer confirmation — buyer wins the row: cron cannot claim', async () => {
    const w = world(); w.ledger.seedReleasable();
    expect(w.ledger.confirmTransferReceived('t1')).toBe(true);
    expect(w.ledger.applyAutoRelease('t1')).toBe(false);
    expect((await w.pay(BUYER)).kind).toBe('succeeded');
    expect((await w.pay(CRON)).kind).toBe('already_released');
    expect(w.stripe.created).toBe(1);
  });

  it('two releasers overlap in time: the second claim is refused while the first holds the lease', async () => {
    const w = world({ onStripe: (c) => {
      if (c.method === 'POST') expect(() => w.ledger.claim('t1', 'B')).toThrow('PAYOUT_ATTEMPT_IN_PROGRESS');
    } });
    w.ledger.seedReleasable(); w.ledger.applyAutoRelease('t1');
    expect((await w.pay(CRON)).kind).toBe('succeeded');
    expect(w.stripe.posts).toBe(1);
    expect(w.ledger.attempts).toHaveLength(1);
  });

  it('cron vs admin release racing — one claim wins, one payout, sweep replays are no-ops', async () => {
    const w = world(); w.ledger.seedReleasable();
    expect(w.ledger.applyAutoRelease('t1')).toBe(true);
    expect(w.ledger.applyAutoRelease('t1')).toBe(false);          // admin release loses: not seller_sent
    expect((await w.pay()).kind).toBe('succeeded');
    expect((await w.pay()).kind).toBe('already_released');        // 2b sweep sees it again
    expect(w.stripe.created).toBe(1);
  });

  it('Stripe succeeds, DB record fails → the tr_ id is surfaced, the next sweep reconciles it, no double pay', async () => {
    const w = world(); w.ledger.seedReleasable(); w.ledger.applyAutoRelease('t1');
    w.ledger.failNext.set('record_payout_attempt_result', 'connection reset');
    expect(await w.pay()).toMatchObject({ kind: 'db_error', stage: 'record', stripeTransferId: 'tr_1' });
    expect(w.row().stripe_transfer_id).toBeNull();                // honest: DB doesn't know yet
    expect(w.stripe.created).toBe(1);                             // money DID move once
    w.ledger.advance(LEASE_MS + 1);
    expect(await w.pay()).toMatchObject({ kind: 'reconciled', found: true });
    expect(w.stripe.created).toBe(1);                             // reconcile, not a second transfer
    expect(w.stripe.posts).toBe(1);
    expect(w.row().stripe_transfer_id).toBe('tr_1');
  });

  it('duplicate function invocation (two overlapping crons) → one transfer', async () => {
    const w = world(); w.ledger.seedReleasable();
    const claimA = w.ledger.applyAutoRelease('t1');
    const claimB = w.ledger.applyAutoRelease('t1');
    expect([claimA, claimB].filter(Boolean)).toHaveLength(1);
    await w.pay(); await w.pay(); await w.pay();                  // both runs + a 2b sweep
    expect(w.stripe.created).toBe(1);
  });

  it('network timeout where Stripe DID create the transfer → reconciled by transfer_group, one transfer', async () => {
    const w = world(); w.ledger.seedReleasable(); w.ledger.applyAutoRelease('t1');
    w.stripe.nextPostFault = { kind: 'lost_response' };
    expect((await w.pay()).kind).toBe('unknown');
    expect(w.row().stripe_transfer_id).toBeNull();
    expect(w.stripe.created).toBe(1);
    w.ledger.advance(LEASE_MS + 1);
    expect(await w.pay()).toMatchObject({ kind: 'reconciled', found: true, stripeTransferId: 'tr_1' });
    expect(w.stripe.created).toBe(1);
    expect(w.stripe.posts).toBe(1);
    expect(w.row().stripe_transfer_id).toBe('tr_1');
  });

  it('F08(d): retry AFTER Stripe forgot the idempotency key (>24h) → still one transfer', async () => {
    const w = world(); w.ledger.seedReleasable(); w.ledger.applyAutoRelease('t1');
    w.stripe.nextPostFault = { kind: 'lost_response' };
    await w.pay();
    w.ledger.advance(25 * HOUR); w.stripe.advance(25 * HOUR);
    expect(await w.pay()).toMatchObject({ kind: 'reconciled', found: true });
    expect(w.stripe.created).toBe(1);
    expect(w.stripe.posts).toBe(1);
  });

  it('F08(e): destination changes during recovery → the attempt replays its frozen destination, one transfer', async () => {
    const w = world(); w.ledger.seedReleasable({ destination: 'acct_A' }); w.ledger.applyAutoRelease('t1');
    w.stripe.nextPostFault = { kind: 'lost_response' };
    await w.pay();
    w.ledger.profiles.set('seller-1', { stripe_connect_id: 'acct_B' });
    w.ledger.advance(LEASE_MS + 1);
    expect(await w.pay()).toMatchObject({ kind: 'reconciled', found: true });
    expect(w.stripe.transfers.map((t) => t.destination)).toEqual(['acct_A']);
  });

  it('the OLD key-only scheme really did double-pay after 24h (the hazard the ledger replaces)', () => {
    const stripe = new StripeTransfersMock();
    const params = { amount: 9000, destination: 'acct_A', transfer_group: null, metadata: {} };
    stripe.createTransfer('payout_t1_acct_A_src', params);
    stripe.advance(25 * HOUR);
    stripe.createTransfer('payout_t1_acct_A_src', params);        // "recovery" replay after key expiry
    expect(stripe.created).toBe(2);                               // two real transfers — F08(d)
  });

  it('F07: a dispute arriving between claim and record → money recorded, attempt reversal_required, review row', async () => {
    const w = world({ onStripe: (c) => { if (c.method === 'POST') w.ledger.freezeForDispute('t1'); } });
    w.ledger.seedReleasable(); w.ledger.applyAutoRelease('t1');
    expect((await w.pay()).kind).toBe('reversal_required');
    expect(w.row().status).toBe('disputed');
    expect(w.row().stripe_transfer_id).toBe('tr_1');
    expect(w.ledger.decisions).toEqual([expect.objectContaining({ reason_codes: ['PAID_DURING_DISPUTE'] })]);
    // seller-win resolution afterwards must NOT pay again (the §7 compounding path)
    w.ledger.resolveSellerWin('t1');
    expect((await w.pay()).kind).toBe('already_released');
    expect(w.stripe.created).toBe(1);
  });

  it('a dispute BEFORE the claim aborts with no Stripe traffic (cron and buyer paths)', async () => {
    const w = world(); w.ledger.seedReleasable(); w.ledger.applyAutoRelease('t1');
    w.ledger.freezeForDispute('t1');
    expect(await w.pay(CRON)).toMatchObject({ kind: 'not_eligible', reason: 'DISPUTED' });
    expect(await w.pay(BUYER)).toMatchObject({ kind: 'not_eligible', reason: 'DISPUTED' });
    expect(w.stripe.posts).toBe(0);
    // seller-win reopens it; exactly one transfer follows
    w.ledger.resolveSellerWin('t1');
    expect((await w.pay(CRON)).kind).toBe('succeeded');
    expect(w.stripe.created).toBe(1);
  });

  it('a refunded / non-live payment never reaches Stripe', async () => {
    const w = world(); w.ledger.seedReleasable(); w.ledger.applyAutoRelease('t1');
    w.ledger.payments.get('p1')!.status = 'refunded';
    expect(await w.pay()).toMatchObject({ kind: 'not_eligible', reason: 'PAYMENT_NOT_SUCCEEDED' });
    w.ledger.payments.get('p1')!.status = 'succeeded'; w.ledger.payments.get('p1')!.stripe_livemode = null;
    expect(await w.pay()).toMatchObject({ kind: 'not_eligible', reason: 'PAYMENT_NOT_LIVE' });
    expect(w.stripe.posts).toBe(0);
  });
});
