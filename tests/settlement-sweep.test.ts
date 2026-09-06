/**
 * tests/settlement-sweep.test.ts — Package 2 (PAYMENTS_RELIABILITY_2026-09).
 *
 * Loads the REAL enforce-transfer-expiry handler (tests/helpers/edge-vm.ts)
 * with the real pure modules (payout-logic, payout-policy) and a mocked
 * payouts.executePayoutAttempt, and pins Phase 0 — settlement reconciliation:
 *   * get_unsettled_payments(50) is the work list; every row's PaymentIntent
 *     is re-fetched from Stripe (latest_charge + its refunds expanded) and
 *     settled through settle_verified_payment(p_source 'sweep');
 *   * a partially refunded charge is passed through as-is and settles (the
 *     contract decides; the sweep never refunds a settled row) — MAJOR-1;
 *   * an `unfulfillable` row is refunded in full EXACTLY once (deterministic
 *     idempotency key), recorded through record_payment_refund (Package 3),
 *     and its review row is resolved; "already refunded" is keyed on
 *     status = refunded / amount_refunded_cents >= total, never on
 *     stripe_refund_id — MAJOR-1;
 *   * an unfulfillable row that already carries a transfer is parked under
 *     'unfulfillable:manual_review' with ONE Sentry capture and is not
 *     re-listed — MINOR-4;
 *   * a `settled` outcome cancels every other pending PaymentIntent on that
 *     listing (best effort; the row is failed only when Stripe canceled) — NOTE-9;
 *   * `legacy_unknown_mode` rows (stripe_livemode NULL) are counted, never
 *     fetched from Stripe — MINOR-5;
 *   * when record_payment_refund does not exist yet (PGRST202) the fallback
 *     writes payments directly, guarded on status <> refunded.
 * Later phases run against empty mocks and are not under test here.
 */
import { describe, expect, it } from 'vitest';
import { json, loadEdgeHandler, mockStripe, mockSupabase, type QueryCall, type StripeCall } from './helpers/edge-vm';
import { isCrossModeStripeError, rowIsLiveActionable, classifyPayoutStripeError, reasonCodeForErrorClass, shouldPageSentry } from '../supabase/functions/_shared/payout-logic';
import { classifyPayout, DEFAULT_POLICY } from '../supabase/functions/_shared/payout-policy';

const CRON = 'cron-secret-test';
const LISTING = 'listing-0001';

interface WorkRow { payment_id: string; stripe_payment_intent_id: string; listing_id: string; mode: string; status: string; paid_at: string | null; kind: string }
interface PayRow { id: string; status: string; stripe_refund_id: string | null; stripe_livemode: boolean | null; total: number; listing_id: string; amount_refunded_cents?: number | null }
interface PendingRow { id: string; stripe_payment_intent_id: string | null; buyer_id: string }

function row(id: string, kind: string, status = 'succeeded'): WorkRow {
  return { payment_id: id, stripe_payment_intent_id: `pi_${id}`, listing_id: LISTING, mode: 'buy_now', status, paid_at: new Date(Date.now() - 10 * 60_000).toISOString(), kind };
}

function piData(pi: string, over: Record<string, unknown> = {}) {
  return { id: pi, status: 'succeeded', amount_received: 22000, currency: 'usd', livemode: true, payment_method_types: ['card'], metadata: { mode: 'buy_now', listing_id: LISTING }, latest_charge: { id: 'ch', amount_refunded: 0, refunds: { data: [] } }, ...over };
}

async function scenario(opts: {
  work: WorkRow[] | ((run: number, state: { marked: Set<string> }) => WorkRow[]);
  payments?: Record<string, PayRow>;
  pendingOnListing?: PendingRow[];
  transfers?: Record<string, { id: string; status: string }>;   // payment_id -> transfer
  outcomes?: Record<string, string>;            // pi -> outcome
  piFetch?: (pi: string) => { ok: boolean; status?: number; data: unknown };
  cancel?: (pi: string) => { ok: boolean; status?: number; data: unknown };
  recordRefund?: 'ok' | 'missing' | 'error';
  runs?: number;
}) {
  const state = { marked: new Set<string>() };
  const sb = mockSupabase({
    rpc: (name, params) => {
      if (name === 'get_unsettled_payments') return { data: typeof opts.work === 'function' ? opts.work(runIdx, state) : opts.work };
      if (name === 'settle_verified_payment') {
        const pi = String(params.p_payment_intent_id);
        const outcome = opts.outcomes?.[pi] ?? 'settled';
        return { data: [{ payment_id: pi.replace(/^pi_/, ''), payment_status: 'succeeded', listing_status: 'sold', transfer_id: outcome === 'settled' ? 'tr_row' : null, outcome }] };
      }
      if (name === 'record_payment_refund') {
        if (opts.recordRefund === 'missing') return { data: null, error: { message: 'Could not find the function public.record_payment_refund(...) in the schema cache', code: 'PGRST202' } };
        if (opts.recordRefund === 'error') return { data: null, error: { message: 'boom' } };
        return { data: { payment_id: 'x', status: 'refunded', recorded: true } };
      }
      return { data: [] };
    },
    tables: {
      payments: (q: QueryCall) => {
        if (q.op === 'select') {
          const idF = q.filters.find((f) => f[0] === 'eq' && f[1] === 'id');
          if (idF) {
            const r = opts.payments?.[String(idF[2])];
            return { data: q.terminal === 'list' ? (r ? [r] : []) : (r ?? null) };
          }
          const byListing = q.filters.find((f) => f[0] === 'eq' && f[1] === 'listing_id');
          if (byListing) return { data: opts.pendingOnListing ?? [] };
          return { data: q.terminal === 'list' ? [] : null };
        }
        return { data: null };
      },
      transfers: (q: QueryCall) => {
        const byPay = q.filters.find((f) => f[0] === 'eq' && f[1] === 'payment_id');
        const t = byPay ? opts.transfers?.[String(byPay[2])] : undefined;
        return { data: q.terminal === 'list' ? (t ? [t] : []) : (t ?? null) };
      },
      webhook_retries: (q: QueryCall) => {
        if (q.op === 'update' && (q.body as Record<string, unknown>)?.error_message === 'unfulfillable:manual_review') {
          const pid = q.filters.find((f) => f[0] === 'eq' && f[1] === 'payment_id');
          if (pid) state.marked.add(String(pid[2]));
        }
        return { data: null };
      },
      listings: () => ({ data: { event_name: 'Fixture' } }),
      payout_policy: () => ({ data: null }),
      transfer_notifications: () => ({ data: [] }),
    },
  });
  const stripe = mockStripe((c: StripeCall) => {
    if (c.method === 'GET' && c.path.startsWith('/payment_intents/')) {
      const pi = c.path.split('/')[2].split('?')[0];
      if (opts.piFetch) return opts.piFetch(pi);
      return { ok: true, data: piData(pi) };
    }
    if (c.method === 'POST' && /^\/payment_intents\/[^/]+\/cancel$/.test(c.path)) {
      const pi = c.path.split('/')[2];
      if (opts.cancel) return opts.cancel(pi);
      return { ok: true, data: { id: pi, status: 'canceled' } };
    }
    if (c.method === 'POST' && c.path === '/refunds') return { ok: true, data: { id: 're_sweep_1', amount: 22000, payment_intent: (c.body as Record<string, string>).payment_intent } };
    return { ok: false, status: 404, data: { error: { message: `unmocked ${c.method} ${c.path}` } } };
  });
  const edge = await loadEdgeHandler('supabase/functions/enforce-transfer-expiry/index.ts', {
    supabase: sb,
    env: { STRIPE_SECRET_KEY: 'sk_test_only', SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test', INTERNAL_CRON_SECRET: CRON },
    provide: {
      stripeFetch: stripe.stripeFetch,
      classifyPayoutStripeError, reasonCodeForErrorClass, shouldPageSentry,
      createSellerPayout: async () => ({ ok: false, error: 'not under test' }),
      // Package 3 replaced the payout call with the attempt protocol; Phase 2/2b is not under test here.
      executePayoutAttempt: async () => ({ ok: false, outcome: 'not_under_test' }),
      isCrossModeStripeError, rowIsLiveActionable,
      classifyPayout, DEFAULT_POLICY, PayoutCandidate: undefined, PayoutPolicyConfig: undefined,
    },
  });
  let runIdx = 0;
  const bodies: Record<string, unknown>[] = [];
  let res: Response | undefined;
  for (runIdx = 0; runIdx < (opts.runs ?? 1); runIdx++) {
    res = await edge.handler(new Request('https://edge.test/enforce-transfer-expiry', { method: 'POST', headers: { authorization: `Bearer ${CRON}` } }));
    bodies.push(await json(res));
  }
  return { sb, stripe, edge, res: res!, body: bodies[0], bodies, state };
}

const settles = (sb: ReturnType<typeof mockSupabase>) => sb.rpcs.filter((r) => r.name === 'settle_verified_payment');
const refunds = (calls: StripeCall[]) => calls.filter((c) => c.method === 'POST' && c.path === '/refunds');
const cancels = (calls: StripeCall[]) => calls.filter((c) => c.method === 'POST' && /\/cancel$/.test(c.path));
const piGets  = (calls: StripeCall[]) => calls.filter((c) => c.method === 'GET' && c.path.startsWith('/payment_intents/'));
const reviewUpdates = (sb: ReturnType<typeof mockSupabase>) => sb.queries.filter((q) => q.table === 'webhook_retries' && q.op === 'update');

describe('enforce-transfer-expiry — Phase 0 settlement reconciliation', () => {
  it('calls get_unsettled_payments(50), re-fetches each PI with latest_charge + refunds expanded, settles each with p_source sweep', async () => {
    const s = await scenario({ work: [row('p1', 'paid_unsettled'), row('p2', 'pending_stale', 'pending')] });
    expect(s.res.status).toBe(200);
    expect(s.sb.rpcs[0]).toMatchObject({ name: 'get_unsettled_payments', params: { p_limit: 50 } });
    expect(piGets(s.stripe.calls).map((c) => c.path)).toEqual([
      '/payment_intents/pi_p1?expand[]=latest_charge&expand[]=latest_charge.refunds',
      '/payment_intents/pi_p2?expand[]=latest_charge&expand[]=latest_charge.refunds',
    ]);
    const calls = settles(s.sb);
    expect(calls).toHaveLength(2);
    expect(calls[0].params).toEqual({
      p_payment_intent_id: 'pi_p1', p_stripe_status: 'succeeded', p_amount_received: 22000, p_currency: 'usd', p_livemode: true,
      p_amount_refunded: 0, p_stripe_refund_id: null, p_payment_method: 'card', p_metadata: { mode: 'buy_now', listing_id: LISTING }, p_source: 'sweep',
    });
    expect(refunds(s.stripe.calls)).toHaveLength(0);
    expect(s.body).toMatchObject({ reconciled_settled: 2, reconciled_refunded: 0 });
  });

  it('a Stripe fetch failure skips that row (no settle call) and counts it, without stopping the batch', async () => {
    const s = await scenario({
      work: [row('bad', 'paid_unsettled'), row('good', 'paid_unsettled')],
      piFetch: (pi) => (pi === 'pi_bad' ? { ok: false, status: 404, data: { error: { message: 'No such payment_intent' } } } : { ok: true, data: piData(pi, { metadata: {} }) }),
    });
    expect(s.res.status).toBe(200);
    expect(settles(s.sb).map((r) => r.params.p_payment_intent_id)).toEqual(['pi_good']);
    expect(s.body).toMatchObject({ reconciled_settled: 1, reconciled_errors: 1 });
  });

  it('a partially refunded charge is passed through (amount + refund id) and settles; the sweep issues no refund (MAJOR-1)', async () => {
    const s = await scenario({
      work: [row('pr', 'pending_stale', 'pending')],
      piFetch: (pi) => ({ ok: true, data: piData(pi, { latest_charge: { id: 'ch', amount_refunded: 500, refunds: { data: [{ id: 're_partial' }] } } }) }),
    });
    expect(s.res.status).toBe(200);
    expect(settles(s.sb)[0].params).toMatchObject({ p_amount_refunded: 500, p_stripe_refund_id: 're_partial', p_stripe_status: 'succeeded' });
    expect(refunds(s.stripe.calls)).toHaveLength(0);
    expect(s.sb.rpcs.some((r) => r.name === 'record_payment_refund')).toBe(false);
    expect(s.body).toMatchObject({ reconciled_settled: 1, reconciled_refunded: 0, reconciled_errors: 0 });
  });

  it('an unfulfillable row is refunded in full EXACTLY once with the deterministic key, recorded via record_payment_refund, review row resolved', async () => {
    const s = await scenario({
      work: [row('u1', 'paid_unsettled')],
      payments: { u1: { id: 'u1', status: 'succeeded', stripe_refund_id: null, stripe_livemode: true, total: 22000, listing_id: LISTING, amount_refunded_cents: null } },
      outcomes: { pi_u1: 'unfulfillable' },
      recordRefund: 'ok',
    });
    expect(s.res.status).toBe(200);
    const rf = refunds(s.stripe.calls);
    expect(rf).toHaveLength(1);
    expect(rf[0].idempotencyKey).toBe('refund_unfulfillable_u1');
    expect(rf[0].body).toMatchObject({ payment_intent: 'pi_u1' });
    expect((rf[0].body as Record<string, string>).amount).toBeUndefined();   // full refund

    const rec = s.sb.rpcs.find((r) => r.name === 'record_payment_refund');
    expect(rec?.params).toEqual({ p_payment_intent_id: 'pi_u1', p_stripe_refund_id: 're_sweep_1', p_stripe_dispute_id: null, p_amount_cents: 22000, p_source: 'unfulfillable' });
    // No direct payments write when the RPC exists.
    expect(s.sb.queries.filter((q) => q.table === 'payments' && q.op !== 'select')).toHaveLength(0);
    const resolve = reviewUpdates(s.sb)[0];
    expect(resolve?.body).toEqual({ resolved: true });
    expect(resolve?.filters).toEqual(expect.arrayContaining([['eq', 'payment_id', 'u1'], ['like', 'error_message', 'unfulfillable%']]));
    expect(s.body).toMatchObject({ reconciled_refunded: 1 });
  });

  it('"already refunded" keys on status / amount_refunded_cents >= total: a fully refunded row is skipped and resolved (MAJOR-1)', async () => {
    const s = await scenario({
      work: [row('u2', 'review_unfulfillable')],
      payments: { u2: { id: 'u2', status: 'succeeded', stripe_refund_id: 're_done', stripe_livemode: true, total: 22000, listing_id: LISTING, amount_refunded_cents: 22000 } },
      outcomes: { pi_u2: 'unfulfillable' },
      recordRefund: 'ok',
    });
    expect(s.res.status).toBe(200);
    expect(refunds(s.stripe.calls)).toHaveLength(0);
    expect(s.sb.rpcs.some((r) => r.name === 'record_payment_refund')).toBe(false);
    expect(reviewUpdates(s.sb)[0]?.body).toEqual({ resolved: true });
  });

  it('...while a PARTIALLY refunded unfulfillable row (stripe_refund_id set, amount < total) still gets the remaining refund (MAJOR-1)', async () => {
    const s = await scenario({
      work: [row('u2b', 'review_unfulfillable')],
      payments: { u2b: { id: 'u2b', status: 'succeeded', stripe_refund_id: 're_partial', stripe_livemode: true, total: 22000, listing_id: LISTING, amount_refunded_cents: 500 } },
      outcomes: { pi_u2b: 'unfulfillable' },
      recordRefund: 'ok',
    });
    expect(refunds(s.stripe.calls)).toHaveLength(1);
    expect(refunds(s.stripe.calls)[0].idempotencyKey).toBe('refund_unfulfillable_u2b');
    expect(s.body).toMatchObject({ reconciled_refunded: 1 });
  });

  it('fallback when record_payment_refund is missing (PGRST202): payments update guarded on status <> refunded', async () => {
    const s = await scenario({
      work: [row('u3', 'review_unfulfillable', 'pending')],
      payments: { u3: { id: 'u3', status: 'pending', stripe_refund_id: null, stripe_livemode: true, total: 22000, listing_id: LISTING } },
      outcomes: { pi_u3: 'unfulfillable' },
      recordRefund: 'missing',
    });
    expect(s.res.status).toBe(200);
    expect(refunds(s.stripe.calls)).toHaveLength(1);
    const upd = s.sb.queries.find((q) => q.table === 'payments' && q.op === 'update');
    expect(upd?.body).toMatchObject({ status: 'refunded', stripe_refund_id: 're_sweep_1' });
    expect(typeof (upd?.body as Record<string, unknown>).refunded_at).toBe('string');
    expect(upd?.filters).toEqual([['eq', 'stripe_payment_intent_id', 'pi_u3'], ['not', 'status', 'in', '("refunded")']]);
    expect(s.body).toMatchObject({ reconciled_refunded: 1 });
  });

  it('a review_unfulfillable row that now settles is resolved without a refund', async () => {
    const s = await scenario({
      work: [row('u4', 'review_unfulfillable')],
      payments: { u4: { id: 'u4', status: 'succeeded', stripe_refund_id: null, stripe_livemode: true, total: 22000, listing_id: LISTING } },
      outcomes: { pi_u4: 'already_settled' },
    });
    expect(refunds(s.stripe.calls)).toHaveLength(0);
    expect(reviewUpdates(s.sb)[0]?.body).toEqual({ resolved: true });
  });

  it('unfulfillable row that already carries a transfer: NO refund, review row parked as unfulfillable:manual_review, ONE Sentry capture, not re-listed next run (MINOR-4)', async () => {
    const s = await scenario({
      work: (_run, state) => (state.marked.has('u9') ? [] : [row('u9', 'review_unfulfillable')]),
      payments: { u9: { id: 'u9', status: 'succeeded', stripe_refund_id: null, stripe_livemode: true, total: 22000, listing_id: LISTING, amount_refunded_cents: null } },
      transfers: { u9: { id: 'tr_9', status: 'seller_sent' } },
      outcomes: { pi_u9: 'unfulfillable' },
      recordRefund: 'ok',
      runs: 2,
    });
    expect(refunds(s.stripe.calls)).toHaveLength(0);
    expect(s.sb.rpcs.some((r) => r.name === 'record_payment_refund')).toBe(false);
    const mark = reviewUpdates(s.sb);
    expect(mark).toHaveLength(1);
    expect(mark[0].body).toEqual({ error_message: 'unfulfillable:manual_review' });
    expect(mark[0].filters).toEqual(expect.arrayContaining([['eq', 'payment_id', 'u9'], ['eq', 'resolved', false], ['like', 'error_message', 'unfulfillable%']]));
    expect(s.edge.sentry.filter((e) => e.tag === 'enforce-transfer-expiry:phase0-unfulfillable-manual-review')).toHaveLength(1);
    // second run: the marker keeps the row off the work list — no second GET, no second settle
    expect(settles(s.sb)).toHaveLength(1);
    expect(piGets(s.stripe.calls)).toHaveLength(1);
    expect(s.bodies[0]).toMatchObject({ reconciled_manual_review: 1, reconciled_refunded: 0 });
    expect(s.bodies[1]).toMatchObject({ reconciled_manual_review: 0 });
  });

  it('a settled outcome cancels every OTHER pending PaymentIntent on the listing; the row is failed only when Stripe canceled (NOTE-9)', async () => {
    const s = await scenario({
      work: [row('p1', 'paid_unsettled')],
      pendingOnListing: [
        { id: 'o1', stripe_payment_intent_id: 'pi_o1', buyer_id: 'buyer-B' },
        { id: 'o2', stripe_payment_intent_id: 'pi_o2', buyer_id: 'buyer-C' },
        { id: 'o3', stripe_payment_intent_id: null,   buyer_id: 'buyer-D' },
      ],
      cancel: (pi) => (pi === 'pi_o2'
        ? { ok: false, status: 400, data: { error: { code: 'payment_intent_unexpected_state', message: 'You cannot cancel this PaymentIntent because it has a status of succeeded.' } } }
        : { ok: true, data: { id: pi, status: 'canceled' } }),
    });
    expect(s.res.status).toBe(200);
    expect(s.body).toMatchObject({ reconciled_settled: 1 });
    const lookup = s.sb.queries.find((q) => q.table === 'payments' && q.op === 'select' && q.filters.some((f) => f[1] === 'listing_id'));
    expect(lookup?.filters).toEqual(expect.arrayContaining([['eq', 'listing_id', LISTING], ['eq', 'status', 'pending'], ['neq', 'id', 'p1']]));
    expect(cancels(s.stripe.calls).map((c) => c.path)).toEqual(['/payment_intents/pi_o1/cancel', '/payment_intents/pi_o2/cancel']);
    const fails = s.sb.queries.filter((q) => q.table === 'payments' && q.op === 'update');
    expect(fails).toHaveLength(2);   // o1 (canceled at Stripe) and o3 (no PI to cancel) — never o2
    expect(fails.map((q) => q.filters)).toEqual([
      [['eq', 'id', 'o1'], ['eq', 'status', 'pending']],
      [['eq', 'id', 'o3'], ['eq', 'status', 'pending']],
    ]);
    expect(fails.every((q) => JSON.stringify(q.body) === JSON.stringify({ status: 'failed' }))).toBe(true);
  });

  it('already_settled does not retire other PaymentIntents (only the first settlement does)', async () => {
    const s = await scenario({
      work: [row('p1', 'paid_unsettled')],
      pendingOnListing: [{ id: 'o1', stripe_payment_intent_id: 'pi_o1', buyer_id: 'buyer-B' }],
      outcomes: { pi_p1: 'already_settled' },
    });
    expect(cancels(s.stripe.calls)).toHaveLength(0);
    expect(s.sb.queries.filter((q) => q.table === 'payments' && q.op === 'update')).toHaveLength(0);
  });

  it('legacy_unknown_mode rows (stripe_livemode NULL) are counted only — no Stripe call, no settle (MINOR-5)', async () => {
    const s = await scenario({ work: [row('lg1', 'legacy_unknown_mode'), row('lg2', 'legacy_unknown_mode', 'pending'), row('p1', 'paid_unsettled')] });
    expect(s.res.status).toBe(200);
    expect(piGets(s.stripe.calls).map((c) => c.path)).toEqual(['/payment_intents/pi_p1?expand[]=latest_charge&expand[]=latest_charge.refunds']);
    expect(settles(s.sb).map((r) => r.params.p_payment_intent_id)).toEqual(['pi_p1']);
    expect(s.body).toMatchObject({ reconciled_settled: 1, reconciled_legacy_unknown_mode: 2, reconciled_errors: 0 });
  });

  it('Phase 0 runs before Phase 1 and never blocks it', async () => {
    const s = await scenario({ work: [] });
    expect(s.res.status).toBe(200);
    const names = s.sb.rpcs.map((r) => r.name);
    expect(names.indexOf('get_unsettled_payments')).toBeLessThan(names.indexOf('enforce_transfer_expiry'));
  });
});
