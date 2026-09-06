/**
 * tests/settlement-confirm.test.ts — Package 2 (PAYMENTS_RELIABILITY_2026-09).
 *
 * Loads the REAL confirm-payment handler (tests/helpers/edge-vm.ts) and pins:
 *   * the buyer can only confirm a PaymentIntent that is theirs: Stripe's
 *     metadata.buyer_id === JWT user OR the payments row for that PI has
 *     buyer_id === JWT user (review round 1, MINOR-2) — otherwise 403 and no
 *     settle call; a missing row with no metadata is 403;
 *   * a succeeded PaymentIntent settles through settle_verified_payment with
 *     the facts from the expanded latest_charge, and the handler no longer
 *     writes payments or inserts transfers itself (F05);
 *   * a not-yet-succeeded PaymentIntent / a Stripe fetch failure keep the
 *     current client contract (200, stripe_verified:false, no DB write);
 *   * an RPC error is a 500 so the client treats the purchase as unverified.
 */
import { describe, expect, it } from 'vitest';
import { authedJsonRequest, json, loadEdgeHandler, mockStripe, mockSupabase, type StripeCall } from './helpers/edge-vm';

const BUYER   = 'buyer-0001';
const OTHER   = 'buyer-other';
const LISTING = 'listing-0001';
const SELLER  = 'seller-0001';
const PI      = 'pi_confirm_1';

function pi(over: Record<string, unknown> = {}) {
  return {
    id: PI, object: 'payment_intent', status: 'succeeded', amount: 22000, amount_received: 22000, currency: 'usd', livemode: false,
    payment_method_types: ['card'],
    metadata: { mode: 'buy_now', listing_id: LISTING, buyer_id: BUYER, seller_id: SELLER },
    latest_charge: { id: 'ch_1', amount: 22000, amount_refunded: 0, refunds: { data: [] } },
    ...over,
  };
}

async function scenario(opts: { user?: string; pi?: Record<string, unknown> | null; stripeOk?: boolean; rpcError?: string; outcome?: string; paymentRow?: { buyer_id: string } | null } = {}) {
  const sb = mockSupabase({
    user: { id: opts.user ?? BUYER },
    rpc: (name) => {
      if (name === 'check_rate_limit') return { data: true };
      if (name === 'settle_verified_payment') {
        if (opts.rpcError) return { data: null, error: { message: opts.rpcError } };
        return { data: [{ payment_id: 'pay_1', payment_status: 'succeeded', listing_status: 'sold', transfer_id: 'tr_row_1', outcome: opts.outcome ?? 'settled' }] };
      }
      return { data: null };
    },
    tables: { payments: () => ({ data: opts.paymentRow ?? null }), transfers: () => ({ data: null }), listings: () => ({ data: null }) },
  });
  const stripe = mockStripe((c: StripeCall) => {
    if (opts.stripeOk === false) return { ok: false, status: 500, data: { error: { message: 'stripe down' } } };
    if (c.method === 'GET' && c.path.startsWith(`/payment_intents/${PI}`)) return { ok: true, data: opts.pi === null ? {} : (opts.pi ?? pi()) };
    return { ok: false, status: 404, data: { error: { message: `unmocked ${c.method} ${c.path}` } } };
  });
  const edge = await loadEdgeHandler('supabase/functions/confirm-payment/index.ts', {
    supabase: sb,
    env: { STRIPE_SECRET_KEY: 'sk_test_only', SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test' },
    provide: { stripeFetchRaw: stripe.stripeFetchRaw },
  });
  const res = await edge.handler(authedJsonRequest({ payment_intent_id: PI }));
  return { sb, stripe, edge, res, body: await json(res) };
}

const settleCalls = (sb: ReturnType<typeof mockSupabase>) => sb.rpcs.filter((r) => r.name === 'settle_verified_payment');
const directWrites = (sb: ReturnType<typeof mockSupabase>) => sb.queries.filter((q) => (q.table === 'payments' || q.table === 'transfers') && q.op !== 'select');

describe('confirm-payment — settles through settle_verified_payment', () => {
  it('succeeded PI: fetches with latest_charge expanded, calls the RPC with the Stripe facts, no direct payments/transfers writes', async () => {
    const s = await scenario();
    expect(s.res.status).toBe(200);
    expect(s.body).toEqual({ success: true, stripe_verified: true, outcome: 'settled', transfer_id: 'tr_row_1' });

    expect(s.stripe.calls).toHaveLength(1);
    // latest_charge.refunds must be expanded explicitly: under the pinned API
    // version (2024-09-30) a Charge no longer embeds its refunds list, so the
    // refund id the contract records would otherwise always be null.
    expect(s.stripe.calls[0]).toMatchObject({ method: 'GET', path: `/payment_intents/${PI}?expand[]=latest_charge&expand[]=latest_charge.refunds` });

    const calls = settleCalls(s.sb);
    expect(calls).toHaveLength(1);
    expect(calls[0].params).toEqual({
      p_payment_intent_id: PI,
      p_stripe_status:     'succeeded',
      p_amount_received:   22000,
      p_currency:          'usd',
      p_livemode:          false,
      p_amount_refunded:   0,
      p_stripe_refund_id:  null,
      p_payment_method:    'card',
      p_metadata:          { mode: 'buy_now', listing_id: LISTING, buyer_id: BUYER, seller_id: SELLER },
      p_source:            'confirm-payment',
    });
    expect(directWrites(s.sb)).toHaveLength(0);
  });

  it('a refunded charge passes amount_refunded and the refund id from latest_charge; stripe_verified stays true (PI succeeded)', async () => {
    const s = await scenario({ pi: pi({ latest_charge: { id: 'ch_1', amount: 22000, amount_refunded: 22000, refunds: { data: [{ id: 're_1' }] } } }), outcome: 'refunded' });
    expect(s.res.status).toBe(200);
    expect(s.body).toMatchObject({ success: true, stripe_verified: true, outcome: 'refunded' });
    expect(settleCalls(s.sb)[0].params).toMatchObject({ p_amount_refunded: 22000, p_stripe_refund_id: 're_1' });
  });

  it('PI whose metadata.buyer_id is NOT the caller (and the row is not theirs either) => 403 and NO settle call', async () => {
    const s = await scenario({ user: OTHER, paymentRow: { buyer_id: BUYER } });
    expect(s.res.status).toBe(403);
    expect(settleCalls(s.sb)).toHaveLength(0);
    expect(directWrites(s.sb)).toHaveLength(0);
  });

  it('legacy PI without metadata: the payments row for that PI is owned by the caller => settles (MINOR-2)', async () => {
    const s = await scenario({ pi: pi({ metadata: {} }), paymentRow: { buyer_id: BUYER } });
    expect(s.res.status).toBe(200);
    expect(s.body).toMatchObject({ success: true, stripe_verified: true, outcome: 'settled' });
    const lookup = s.sb.queries.find((q) => q.table === 'payments' && q.op === 'select');
    expect(lookup?.filters).toEqual([['eq', 'stripe_payment_intent_id', PI]]);
    expect(settleCalls(s.sb)).toHaveLength(1);
    expect(settleCalls(s.sb)[0].params).toMatchObject({ p_metadata: {} });
  });

  it('legacy PI without metadata: the payments row belongs to someone else => 403, no settle call', async () => {
    const s = await scenario({ pi: pi({ metadata: {} }), user: OTHER, paymentRow: { buyer_id: BUYER } });
    expect(s.res.status).toBe(403);
    expect(settleCalls(s.sb)).toHaveLength(0);
  });

  it('no metadata and no payments row => 403 (ownership cannot be established)', async () => {
    const s = await scenario({ pi: pi({ metadata: {} }), paymentRow: null });
    expect(s.res.status).toBe(403);
    expect(settleCalls(s.sb)).toHaveLength(0);
  });

  it('metadata.buyer_id === caller settles without consulting the payments row', async () => {
    const s = await scenario({ paymentRow: null });
    expect(s.res.status).toBe(200);
    expect(s.sb.queries.filter((q) => q.table === 'payments')).toHaveLength(0);
  });

  it('PI not succeeded => 200 stripe_verified:false, no RPC, no DB write (current client contract)', async () => {
    const s = await scenario({ pi: pi({ status: 'processing', amount_received: 0 }) });
    expect(s.res.status).toBe(200);
    expect(s.body).toMatchObject({ success: true, stripe_verified: false });
    expect(settleCalls(s.sb)).toHaveLength(0);
    expect(directWrites(s.sb)).toHaveLength(0);
  });

  it('Stripe fetch failure => 200 stripe_verified:false, no RPC, no DB write', async () => {
    const s = await scenario({ stripeOk: false });
    expect(s.res.status).toBe(200);
    expect(s.body).toMatchObject({ success: true, stripe_verified: false });
    expect(settleCalls(s.sb)).toHaveLength(0);
    expect(directWrites(s.sb)).toHaveLength(0);
  });

  it('RPC error => 500 (client treats the purchase as unverified and does not pay again)', async () => {
    const s = await scenario({ rpcError: 'connection reset' });
    expect(s.res.status).toBe(500);
    expect(settleCalls(s.sb)).toHaveLength(1);
    expect(directWrites(s.sb)).toHaveLength(0);
  });
});
