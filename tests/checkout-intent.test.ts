/**
 * tests/checkout-intent.test.ts — Package 1 (PAYMENTS_RELIABILITY_2026-09).
 *
 * Loads the REAL create-payment-intent handler (tests/helpers/edge-vm.ts) and
 * pins the reservation-authority contract (investigation F01, ratified
 * decision 3):
 *   * Buy-Now: only the LIVE reservation holder can mint a PaymentIntent.
 *   * Auction: the winner is refused while the listing is sold or while another
 *     buyer's Buy-Now hold is live.
 *   * A refused buyer's stale `pending` PaymentIntent is cancelled at Stripe
 *     and its row marked `failed` (explicit expired/superseded handling).
 *   * The legitimate holder still gets the byte-compatible 200 response.
 * Every DB query and Stripe call the handler makes is recorded by the mocks
 * and asserted on exactly — no network, no database, no real key.
 */
import { describe, expect, it } from 'vitest';
import { authedJsonRequest, json, loadEdgeHandler, mockStripe, mockSupabase, type QueryCall, type StripeCall } from './helpers/edge-vm';
import { dollarsToCents, feeBreakdown, totalMismatch } from '../supabase/functions/_shared/money';

const LISTING = 'listing-0001';
const SELLER  = 'seller-0001';
const HOLDER  = 'buyer-holder';
const OTHER   = 'buyer-other';
const CUSTOMER = 'cus_test_1';
const STRIPE_MOBILE_API_VERSION = '2024-04-10';

const inFuture = () => new Date(Date.now() + 5 * 60_000).toISOString();
const inPast   = () => new Date(Date.now() - 60_000).toISOString();

interface ListingRow {
  id: string; seller_id: string; current_bid: number; buy_now_price: number | null; buy_now_enabled: boolean;
  status: string; auction_status: string; winner_user_id: string | null; winning_bid_amount: number | null;
  reserved_by: string | null; reserved_until: string | null; ends_at: string;
}

function listing(over: Partial<ListingRow> = {}): ListingRow {
  return {
    id: LISTING, seller_id: SELLER, current_bid: 100, buy_now_price: 200, buy_now_enabled: true,
    status: 'active', auction_status: 'active', winner_user_id: null, winning_bid_amount: null,
    reserved_by: null, reserved_until: null, ends_at: inFuture(),
    ...over,
  };
}

interface PaymentRow { id: string; stripe_payment_intent_id: string; status: string; listing_id: string; buyer_id: string; mode: string }

async function scenario(opts: { listing: ListingRow; user: string; payments?: PaymentRow[]; piStatus?: string }) {
  const payments = opts.payments ?? [];
  const sb = mockSupabase({
    user: { id: opts.user, email: `${opts.user}@example.test` },
    rpc: (name) => (name === 'check_rate_limit' ? { data: true } : { data: null }),
    tables: {
      listings: (q) => (q.filters.some((f) => f[0] === 'eq' && f[1] === 'id' && f[2] === opts.listing.id) ? { data: opts.listing } : { data: null, error: { message: 'not found' } }),
      profiles: () => ({ data: { stripe_customer_id: CUSTOMER } }),
      payments: (q) => {
        if (q.op === 'select') {
          let rows = payments;
          for (const f of q.filters) if (f[0] === 'eq') rows = rows.filter((r) => (r as unknown as Record<string, unknown>)[f[1] as string] === f[2]);
          return { data: q.terminal === 'list' ? rows : rows[0] ?? null };
        }
        return { data: null };
      },
    },
  });
  const stripe = mockStripe((c: StripeCall) => {
    if (c.method === 'GET' && c.path === `/customers/${CUSTOMER}`) return { ok: true, data: { id: CUSTOMER } };
    if (c.method === 'POST' && c.path === '/ephemeral_keys') return { ok: true, data: { secret: 'ek_test_secret' } };
    if (c.method === 'POST' && c.path === '/payment_intents') return { ok: true, data: { id: 'pi_new', client_secret: 'pi_new_secret', status: 'requires_payment_method', livemode: false } };
    if (c.method === 'GET' && c.path.startsWith('/payment_intents/')) return { ok: true, data: { id: c.path.split('/')[2], status: opts.piStatus ?? 'requires_payment_method', client_secret: 'pi_old_secret' } };
    if (c.method === 'POST' && c.path.endsWith('/cancel')) return { ok: true, data: { id: c.path.split('/')[2], status: 'canceled' } };
    return { ok: false, status: 404, data: { error: { message: `unmocked ${c.method} ${c.path}` } } };
  });
  const edge = await loadEdgeHandler('supabase/functions/create-payment-intent/index.ts', {
    supabase: sb,
    env: { STRIPE_SECRET_KEY: 'sk_test_only', SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test' },
    provide: { feeBreakdown, dollarsToCents, totalMismatch, stripeFetch: stripe.stripeFetch, stripeFetchRaw: stripe.stripeFetchRaw, STRIPE_MOBILE_API_VERSION },
  });
  const run = async (body: Record<string, unknown>) => {
    const res = await edge.handler(authedJsonRequest(body));
    return { res, body: await json(res) };
  };
  return { sb, stripe, edge, run };
}

const paymentInserts = (qs: QueryCall[]) => qs.filter((q) => q.table === 'payments' && q.op === 'insert');
const piCreates = (cs: StripeCall[]) => cs.filter((c) => c.method === 'POST' && c.path === '/payment_intents');
const piCancels = (cs: StripeCall[]) => cs.filter((c) => c.method === 'POST' && c.path.endsWith('/cancel'));

describe('create-payment-intent — Buy-Now reservation authority', () => {
  it('refuses a buyer who is NOT the live reservation holder: no payments insert, no PaymentIntent', async () => {
    const s = await scenario({ listing: listing({ status: 'reserved', reserved_by: HOLDER, reserved_until: inFuture() }), user: OTHER });
    const { res, body } = await s.run({ listing_id: LISTING, mode: 'buy_now' });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(res.status).toBeLessThan(500);
    expect(String(body.error)).toMatch(/already reserved/i);
    expect(paymentInserts(s.sb.queries)).toHaveLength(0);
    expect(piCreates(s.stripe.calls)).toHaveLength(0);
    const listingQ = s.sb.queries.find((q) => q.table === 'listings');
    expect(listingQ?.filters).toEqual([['eq', 'id', LISTING]]);
    for (const col of ['reserved_by', 'reserved_until', 'ends_at']) expect(listingQ?.select).toContain(col);
  });

  it('refuses the holder whose reservation EXPIRED, cancels its pending PaymentIntent and marks the row failed', async () => {
    const stale: PaymentRow = { id: 'pay_stale', stripe_payment_intent_id: 'pi_stale', status: 'pending', listing_id: LISTING, buyer_id: HOLDER, mode: 'buy_now' };
    const s = await scenario({ listing: listing({ status: 'reserved', reserved_by: HOLDER, reserved_until: inPast() }), user: HOLDER, payments: [stale] });
    const { res, body } = await s.run({ listing_id: LISTING, mode: 'buy_now' });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(res.status).toBeLessThan(500);
    expect(String(body.error)).toMatch(/reservation expired/i);
    expect(paymentInserts(s.sb.queries)).toHaveLength(0);
    expect(piCreates(s.stripe.calls)).toHaveLength(0);

    // Exactly this buyer's pending row for this (listing, mode) is looked up ...
    const lookup = s.sb.queries.find((q) => q.table === 'payments' && q.op === 'select');
    expect(lookup?.filters).toEqual([['eq', 'listing_id', LISTING], ['eq', 'buyer_id', HOLDER], ['eq', 'mode', 'buy_now'], ['eq', 'status', 'pending']]);
    // ... its PaymentIntent is cancelled at Stripe ...
    expect(piCancels(s.stripe.calls).map((c) => c.path)).toEqual(['/payment_intents/pi_stale/cancel']);
    // ... and the row is retired, guarded on status='pending'.
    const retire = s.sb.queries.find((q) => q.table === 'payments' && q.op === 'update');
    expect(retire?.body).toEqual({ status: 'failed' });
    expect(retire?.filters).toEqual([['eq', 'id', 'pay_stale'], ['eq', 'status', 'pending']]);
  });

  it('refuses when the listing is not reserved at all (unchanged message for shipped clients)', async () => {
    const s = await scenario({ listing: listing({ status: 'active' }), user: HOLDER });
    const { res, body } = await s.run({ listing_id: LISTING, mode: 'buy_now' });
    expect(res.status).toBe(400);
    expect(String(body.error)).toMatch(/not reserved for purchase/i);
    expect(piCreates(s.stripe.calls)).toHaveLength(0);
  });

  it('serves the live holder: 200 with the byte-compatible response, 10/10 fees, reserved_until in PI metadata', async () => {
    const until = inFuture();
    const s = await scenario({ listing: listing({ status: 'reserved', reserved_by: HOLDER, reserved_until: until }), user: HOLDER });
    const { res, body } = await s.run({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(res.status).toBe(200);
    expect(Object.keys(body).sort()).toEqual(['amount', 'buyer_fee', 'clientSecret', 'customerEphemeralKeySecret', 'customerId', 'paymentIntentId', 'seller_fee', 'total'].sort());
    expect(body).toMatchObject({ amount: 20000, buyer_fee: 2000, seller_fee: 2000, total: 22000, paymentIntentId: 'pi_new', clientSecret: 'pi_new_secret', customerId: CUSTOMER, customerEphemeralKeySecret: 'ek_test_secret' });

    const create = piCreates(s.stripe.calls);
    expect(create).toHaveLength(1);
    expect(create[0].idempotencyKey).toBe(`pi_${LISTING}_${HOLDER}_buy_now_22000_c${CUSTOMER}`);
    expect(create[0].body).toMatchObject({ amount: '22000', currency: 'usd', 'metadata[listing_id]': LISTING, 'metadata[buyer_id]': HOLDER, 'metadata[seller_id]': SELLER, 'metadata[mode]': 'buy_now', 'metadata[reserved_until]': until });

    const ins = paymentInserts(s.sb.queries);
    expect(ins).toHaveLength(1);
    expect(ins[0].body).toMatchObject({ listing_id: LISTING, buyer_id: HOLDER, seller_id: SELLER, amount: 20000, buyer_fee: 2000, seller_fee: 2000, total: 22000, stripe_payment_intent_id: 'pi_new', status: 'pending', mode: 'buy_now' });
    expect(piCancels(s.stripe.calls)).toHaveLength(0);
  });

  it('mode mismatch: buy_now on an ended auction is refused', async () => {
    const s = await scenario({ listing: listing({ status: 'active', auction_status: 'ended', winner_user_id: HOLDER, winning_bid_amount: 150 }), user: HOLDER });
    const { res, body } = await s.run({ listing_id: LISTING, mode: 'buy_now' });
    expect(res.status).toBe(400);
    expect(String(body.error)).toMatch(/not reserved for purchase/i);
    expect(piCreates(s.stripe.calls)).toHaveLength(0);
  });
});

describe('create-payment-intent — auction branch', () => {
  it('refuses the winner while another buyer holds a LIVE Buy-Now reservation', async () => {
    const s = await scenario({ listing: listing({ status: 'reserved', reserved_by: OTHER, reserved_until: inFuture(), auction_status: 'ended', winner_user_id: HOLDER, winning_bid_amount: 150 }), user: HOLDER });
    const { res, body } = await s.run({ listing_id: LISTING, mode: 'auction' });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(res.status).toBeLessThan(500);
    expect(String(body.error)).toMatch(/already reserved/i);
    expect(paymentInserts(s.sb.queries)).toHaveLength(0);
    expect(piCreates(s.stripe.calls)).toHaveLength(0);
  });

  it('refuses the winner once the listing is sold (status=sold), cancelling a stale pending intent', async () => {
    const stale: PaymentRow = { id: 'pay_stale_a', stripe_payment_intent_id: 'pi_stale_a', status: 'pending', listing_id: LISTING, buyer_id: HOLDER, mode: 'auction' };
    const s = await scenario({ listing: listing({ status: 'sold', auction_status: 'ended', winner_user_id: HOLDER, winning_bid_amount: 150 }), user: HOLDER, payments: [stale] });
    const { res, body } = await s.run({ listing_id: LISTING, mode: 'auction' });
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(res.status).toBeLessThan(500);
    expect(String(body.error)).toMatch(/already sold/i);
    expect(piCreates(s.stripe.calls)).toHaveLength(0);
    expect(piCancels(s.stripe.calls).map((c) => c.path)).toEqual(['/payment_intents/pi_stale_a/cancel']);
    const lookup = s.sb.queries.find((q) => q.table === 'payments' && q.op === 'select');
    expect(lookup?.filters).toEqual([['eq', 'listing_id', LISTING], ['eq', 'buyer_id', HOLDER], ['eq', 'mode', 'auction'], ['eq', 'status', 'pending']]);
    const retire = s.sb.queries.find((q) => q.table === 'payments' && q.op === 'update');
    expect(retire?.body).toEqual({ status: 'failed' });
    expect(retire?.filters).toEqual([['eq', 'id', 'pay_stale_a'], ['eq', 'status', 'pending']]);
  });

  it('a lapsed foreign reservation does not block the winner', async () => {
    const s = await scenario({ listing: listing({ status: 'reserved', reserved_by: OTHER, reserved_until: inPast(), auction_status: 'ended', winner_user_id: HOLDER, winning_bid_amount: 150 }), user: HOLDER });
    const { res, body } = await s.run({ listing_id: LISTING, mode: 'auction' });
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ amount: 15000, buyer_fee: 1500, seller_fee: 1500, total: 16500 });
    expect(piCreates(s.stripe.calls)).toHaveLength(1);
    expect(piCreates(s.stripe.calls)[0].idempotencyKey).toBe(`pi_${LISTING}_${HOLDER}_auction_16500_c${CUSTOMER}`);
  });

  it('mode mismatch: auction on a live Buy-Now reservation is refused (auction not ended)', async () => {
    const s = await scenario({ listing: listing({ status: 'reserved', reserved_by: HOLDER, reserved_until: inFuture() }), user: HOLDER });
    const { res, body } = await s.run({ listing_id: LISTING, mode: 'auction' });
    expect(res.status).toBe(400);
    expect(String(body.error)).toMatch(/auction.*not ended/i);
    expect(piCreates(s.stripe.calls)).toHaveLength(0);
  });

  it('a non-winner is refused', async () => {
    const s = await scenario({ listing: listing({ auction_status: 'ended', winner_user_id: HOLDER, winning_bid_amount: 150 }), user: OTHER });
    const { res, body } = await s.run({ listing_id: LISTING, mode: 'auction' });
    expect(res.status).toBe(400);
    expect(String(body.error)).toMatch(/not the (auction )?winner/i);
    expect(piCreates(s.stripe.calls)).toHaveLength(0);
  });
});
