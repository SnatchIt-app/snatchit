/**
 * tests/payout-decisions-buyer-confirmed.test.ts — F-CR-148-SHARED follow-up,
 * edge writers a1/a2 (A, 2026-09-24). SQL writers a3/a4: pgTAP 216.
 *
 * payout_decisions.buyer_confirmed (and the BUYER_CONFIRMED reason code) state
 * that the BUYER confirmed receipt. The only record of that act is
 * transfers.buyer_confirmed_at, written by confirm_transfer_received (0550).
 * confirm-and-release hard-coded both on its two audit writes — a1 payoutDeferred
 * and a2 the release audit — and reaches them for rows the buyer never
 * confirmed: a seller-win resolution (065: status buyer_confirmed,
 * buyer_confirmed_at NULL) and an auto-released row, both through the
 * "already confirmed" bypass of the confirm RPC's error.
 *
 * The harness is exact where it matters:
 *   • confirm_transfer_received mirrors 0550: anything but seller_sent RAISES
 *     "Transfer cannot be confirmed from current status: <status>." — the
 *     string the bypass matches — and a real confirmation sets buyer_confirmed_at.
 *   • the transfers read returns ONLY the selected columns, so a writer that
 *     reads a column §5 does not select sees undefined, as in production.
 *   • claim / Stripe run through the real _shared/payouts.ts (#92's, which maps
 *     PAYOUT_HELD / PAYOUT_UNDER_REVIEW to not_eligible → payoutDeferred).
 */
import { describe, expect, it } from 'vitest';
import { authedJsonRequest, json, loadEdgeHandler, mockStripe, mockSupabase, type QueryCall } from './helpers/edge-vm';
import { loadPayoutsModule } from './helpers/payouts-vm';
import { AttemptLedger, StripeTransfersMock, type TransferRow } from './helpers/payout-protocol';

const ENV = { SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test', STRIPE_SECRET_KEY: 'sk_test_x', INTERNAL_CRON_SECRET: 'cron-secret' };
const MIN = 60_000;
const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();

type Kind = 'genuine' | 'seller_win' | 'auto_released';
type Decision = { decision: string; reason_codes: string[]; buyer_confirmed: boolean; dispute_open: boolean };
type Opts = { holdFuture?: boolean; review?: 'manual_review' | 'held' | null; onboarded?: boolean; destinationNotReady?: boolean };

function pick(row: Record<string, unknown>, select: string | null): Record<string, unknown> {
  if (!select || select.trim() === '*') return { ...row };
  const out: Record<string, unknown> = {};
  for (const c of select.split(',').map((s) => s.trim()).filter(Boolean)) if (c in row) out[c] = row[c];
  return out;
}

async function world(kind: Kind, o: Opts = {}) {
  const ledger = new AttemptLedger();
  const row = ledger.seedReleasable({ status: 'seller_sent' }) as TransferRow & Record<string, unknown>;
  if (kind === 'seller_win') {
    Object.assign(row, {
      status: 'buyer_confirmed', dispute_resolution: 'resolved_seller_paid', buyer_confirmed_at: null,
      disputed_at: null, dispute_resolved_at: iso(-60 * MIN),
    });
  } else if (kind === 'auto_released') {
    row.status = 'auto_released';
  }
  if (o.holdFuture) row.payout_hold_until = iso(60 * MIN);
  if (o.review) row.payout_review_status = o.review;
  if (o.onboarded === false) ledger.profiles.set('seller-1', { stripe_connect_id: null });

  const stripeMock = new StripeTransfersMock();
  if (o.destinationNotReady) stripeMock.accountCapability = 'inactive';
  const stripe = mockStripe(async (c) => stripeMock.route(c));
  const payouts = loadPayoutsModule(stripe);
  const decisions: Decision[] = [];
  const sb = mockSupabase({
    user: { id: 'buyer-1' },
    rpc: async (name, params) => {
      if (name === 'check_rate_limit') return { data: true };
      if (name === 'confirm_transfer_received') {
        // 0550: identity first, then status; only seller_sent confirms
        const t = ledger.transfers.get(params.p_transfer_id as string)!;
        if (t.status !== 'seller_sent') return { data: null, error: { message: `Transfer cannot be confirmed from current status: ${t.status}.` } };
        t.status = 'buyer_confirmed'; t.buyer_confirmed_at = iso(0);
        return { data: null };
      }
      return ledger.rpc(name, params);
    },
    tables: {
      transfers: (q: QueryCall) => {
        const id = q.filters.find((f) => f[0] === 'eq' && f[1] === 'id')?.[2] as string;
        const t = ledger.transfers.get(id);
        return { data: t ? pick(t as unknown as Record<string, unknown>, q.select) : null };
      },
      payout_decisions: (q: QueryCall) => {
        if (q.op === 'insert') decisions.push(q.body as Decision);
        return { data: null };
      },
      payments: () => ({ data: { amount: 10000, seller_fee: 1000, status: 'succeeded', stripe_payment_intent_id: 'pi_1' } }),
    },
  });
  const edge = await loadEdgeHandler('supabase/functions/confirm-and-release/index.ts', {
    supabase: sb, env: ENV,
    provide: { executePayoutAttempt: payouts.executePayoutAttempt, stripeFetch: stripe.stripeFetch },
  });
  const call = async () => { const res = await edge.handler(authedJsonRequest({ transfer_id: 't1' })); return { status: res.status, body: await json(res) }; };
  const posts = () => stripe.calls.filter((c) => c.method === 'POST' && c.path === '/transfers');
  const confirmedAt = () => ledger.transfers.get('t1')!.buyer_confirmed_at;
  return { ledger, stripe, sb, call, posts, decisions, confirmedAt };
}

/** the audit record is truthful: the flag, the code and the row agree */
function truthful(w: Awaited<ReturnType<typeof world>>) {
  for (const d of w.decisions) {
    expect(d.buyer_confirmed, 'buyer_confirmed equals whether buyer_confirmed_at is set').toBe(w.confirmedAt() != null);
    expect(d.reason_codes.includes('BUYER_CONFIRMED'), 'BUYER_CONFIRMED only with a real confirmation').toBe(d.buyer_confirmed);
  }
}

describe('a2 — release audit (successful payout)', () => {
  it('BC-R1 genuine buyer confirmation: release audit says buyer_confirmed true, BUYER_CONFIRMED', async () => {
    const w = await world('genuine');
    const r = await w.call();
    expect(r.body).toMatchObject({ success: true, stripe_transfer_id: 'tr_1' });
    expect(w.confirmedAt()).not.toBeNull();
    expect(w.posts()).toHaveLength(1);
    expect(w.decisions).toEqual([expect.objectContaining({ decision: 'release', reason_codes: ['BUYER_CONFIRMED'], buyer_confirmed: true, dispute_open: false })]);
    truthful(w);
  });

  it('BC-R2 seller-win resolution: paid, but the release audit says buyer_confirmed false and names the resolution', async () => {
    const w = await world('seller_win');
    const r = await w.call();
    expect(r.body).toMatchObject({ success: true, stripe_transfer_id: 'tr_1' });
    expect(w.confirmedAt(), 'the bypass never manufactures a confirmation').toBeNull();
    expect(w.posts()).toHaveLength(1);
    expect(w.decisions).toEqual([expect.objectContaining({ decision: 'release', reason_codes: ['DISPUTE_RESOLVED_SELLER'], buyer_confirmed: false })]);
    truthful(w);
  });

  it('BC-R3 auto-released row: the release audit says buyer_confirmed false (AUTO_RELEASED)', async () => {
    const w = await world('auto_released');
    const r = await w.call();
    expect(r.body).toMatchObject({ success: true, stripe_transfer_id: 'tr_1' });
    expect(w.decisions).toEqual([expect.objectContaining({ decision: 'release', reason_codes: ['AUTO_RELEASED'], buyer_confirmed: false })]);
    truthful(w);
  });
});

describe('a1 — payoutDeferred (deferred payout)', () => {
  it('BC-H1 seller-win under a future hold: claim refuses PAYOUT_HELD → pending_review, no Stripe call, buyer_confirmed false', async () => {
    const w = await world('seller_win', { holdFuture: true, review: 'held' });
    const r = await w.call();
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ success: true, payout_status: 'pending_review' });
    expect(w.stripe.calls).toHaveLength(0);
    expect(w.ledger.attempts).toHaveLength(0);
    expect(w.decisions).toEqual([expect.objectContaining({ decision: 'manual_review', reason_codes: ['DISPUTE_RESOLVED_SELLER', 'PAYOUT_HELD'], buyer_confirmed: false })]);
    truthful(w);
  });

  it('BC-H2 seller-win under manual review: PAYOUT_UNDER_REVIEW → pending_review, buyer_confirmed false', async () => {
    const w = await world('seller_win', { review: 'manual_review' });
    const r = await w.call();
    expect(r.body).toMatchObject({ success: true, payout_status: 'pending_review' });
    expect(w.stripe.calls).toHaveLength(0);
    expect(w.decisions).toEqual([expect.objectContaining({ decision: 'manual_review', reason_codes: ['DISPUTE_RESOLVED_SELLER', 'PAYOUT_UNDER_REVIEW'], buyer_confirmed: false })]);
    truthful(w);
  });

  it('BC-D1 seller-win, seller not onboarded (a refusal v37 already knew): buyer_confirmed false', async () => {
    const w = await world('seller_win', { onboarded: false });
    const r = await w.call();
    expect(r.body).toMatchObject({ success: true, payout_status: 'pending_review' });
    expect(w.decisions).toEqual([expect.objectContaining({ decision: 'manual_review', reason_codes: ['DISPUTE_RESOLVED_SELLER', 'SELLER_NOT_ONBOARDED'], buyer_confirmed: false })]);
    truthful(w);
  });

  it('BC-D2 seller-win, destination not ready (pre-flight deferral): buyer_confirmed false', async () => {
    const w = await world('seller_win', { destinationNotReady: true });
    const r = await w.call();
    expect(r.body).toMatchObject({ success: true, payout_status: 'pending_review' });
    expect(w.posts()).toHaveLength(0);
    expect(w.decisions).toEqual([expect.objectContaining({ decision: 'manual_review', reason_codes: ['DISPUTE_RESOLVED_SELLER', 'PAYOUT_DESTINATION_NOT_READY'], buyer_confirmed: false })]);
    truthful(w);
  });

  it('BC-D3 genuine confirmation, seller not onboarded: unchanged — buyer_confirmed true, BUYER_CONFIRMED first', async () => {
    const w = await world('genuine', { onboarded: false });
    const r = await w.call();
    expect(r.body).toMatchObject({ success: true, payout_status: 'pending_review' });
    expect(w.decisions).toEqual([expect.objectContaining({ decision: 'manual_review', reason_codes: ['BUYER_CONFIRMED', 'SELLER_NOT_ONBOARDED'], buyer_confirmed: true })]);
    truthful(w);
  });

  it('BC-D4 genuine confirmation, destination not ready: unchanged — buyer_confirmed true', async () => {
    const w = await world('genuine', { destinationNotReady: true });
    const r = await w.call();
    expect(r.body).toMatchObject({ success: true, payout_status: 'pending_review' });
    expect(w.decisions).toEqual([expect.objectContaining({ decision: 'manual_review', reason_codes: ['BUYER_CONFIRMED', 'PAYOUT_DESTINATION_NOT_READY'], buyer_confirmed: true })]);
    truthful(w);
  });

  it('BC-D5 genuine confirmation under a future hold: the hold does not bind a real confirmation (148) — paid, buyer_confirmed true', async () => {
    const w = await world('genuine', { holdFuture: true, review: 'held' });
    const r = await w.call();
    expect(r.body).toMatchObject({ success: true, stripe_transfer_id: 'tr_1' });
    expect(w.decisions).toEqual([expect.objectContaining({ decision: 'release', reason_codes: ['BUYER_CONFIRMED'], buyer_confirmed: true })]);
    truthful(w);
  });
});

describe('the confirmation is READ, not inferred', () => {
  it('BC-S1 §5 selects buyer_confirmed_at and dispute_resolution (the harness returns only selected columns)', async () => {
    const w = await world('genuine');
    await w.call();
    const read = w.sb.queries.find((q) => q.table === 'transfers' && q.op === 'select' && (q.select ?? '').includes('payout_released_at'));
    expect(read?.select).toMatch(/\bbuyer_confirmed_at\b/);
    expect(read?.select).toMatch(/\bdispute_resolution\b/);
  });
});
