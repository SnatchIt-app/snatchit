/**
 * tests/settlement-webhook.test.ts — Package 2 (PAYMENTS_RELIABILITY_2026-09).
 *
 * Loads the REAL stripe-webhook handler (tests/helpers/edge-vm.ts) and pins
 * the settlement acknowledgment contract (investigation F02 / F05 / F06,
 * ratified decision 5):
 *   * payment_intent.succeeded is ONE call to settle_verified_payment with the
 *     event's PaymentIntent facts. An RPC error is NOT terminal (non-2xx +
 *     fail_stripe_webhook_event, so Stripe redelivers and the retry calls the
 *     RPC AGAIN); every RPC outcome IS terminal (200 + complete) because the
 *     RPC recorded the review rows. Push notifications only on `settled`.
 *   * payment_intent.payment_failed / .canceled never touch a succeeded or
 *     refunded row, release a Buy-Now reservation, and answer non-2xx when
 *     the authoritative write fails.
 * Every RPC and query the handler makes is recorded by the mocks and asserted
 * on exactly — no network, no database, no real key.
 */
import { describe, expect, it } from 'vitest';
import { json, loadEdgeHandler, mockSupabase, signedStripeWebhookRequest, type RpcHandler } from './helpers/edge-vm';

const SECRET  = 'whsec_test_only';
const LISTING = 'listing-0001';
const BUYER   = 'buyer-0001';
const SELLER  = 'seller-0001';
const PI      = 'pi_settle_1';

type Outcome = 'settled' | 'already_settled' | 'refunded' | 'not_succeeded' | 'canceled' | 'unfulfillable' | 'unknown_payment' | 'binding_mismatch';
type SettleStep = { outcome: Outcome; transfer_id?: string | null } | { error: string; code?: string };

function piEvent(id: string, type: string, over: Record<string, unknown> = {}) {
  return {
    id, type,
    data: { object: {
      id: PI, object: 'payment_intent', status: 'succeeded', amount: 22000, amount_received: 22000, currency: 'usd', livemode: true,
      latest_charge: 'ch_1', payment_method_types: ['card'],
      metadata: { mode: 'buy_now', listing_id: LISTING, buyer_id: BUYER, seller_id: SELLER },
      ...over,
    } },
  };
}

/** A stateful lease + scripted settle outcomes, like the real DB would behave. */
function harness(opts: { settle?: SettleStep[]; paymentsUpdate?: (q: unknown) => { data?: unknown; error?: { message: string; code?: string } }; releaseError?: boolean } = {}) {
  const completed = new Set<string>();
  const settleScript = [...(opts.settle ?? [])];
  let settleCalls = 0;
  const rpc: RpcHandler = (name, params) => {
    if (name === 'claim_stripe_webhook_event') return { data: completed.has(String(params.p_event_id)) ? 'already_processed' : 'claimed' };
    if (name === 'complete_stripe_webhook_event') { completed.add(String(params.p_event_id)); return { data: true }; }
    if (name === 'fail_stripe_webhook_event') return { data: true };
    if (name === 'settle_verified_payment') {
      settleCalls++;
      const step = settleScript.shift() ?? { outcome: 'already_settled' as const };
      if ('error' in step) return { data: null, error: { message: step.error, code: step.code } };
      return { data: [{ payment_id: 'pay_1', payment_status: step.outcome === 'refunded' ? 'refunded' : 'succeeded', listing_status: 'sold', transfer_id: step.transfer_id ?? 'tr_row_1', outcome: step.outcome }] };
    }
    if (name === 'release_reservation') return opts.releaseError ? { data: null, error: { message: 'release boom' } } : { data: null };
    return { data: null };
  };
  const sb = mockSupabase({
    rpc,
    tables: {
      listings: () => ({ data: { event_name: 'Fixture Event', transfer_method: 'mobile_transfer' } }),
      payments: (q) => (opts.paymentsUpdate ? opts.paymentsUpdate(q) : { data: { id: 'pay_1', listing_id: LISTING } }),
    },
  });
  const pushes: Array<{ url: string; body: Record<string, unknown> }> = [];
  const fetchMock = (async (url: string | URL | Request, init?: RequestInit) => {
    pushes.push({ url: String(url), body: JSON.parse(String(init?.body ?? '{}')) as Record<string, unknown> });
    return new Response('{}', { status: 200 });
  }) as unknown as typeof fetch;
  const load = () => loadEdgeHandler('supabase/functions/stripe-webhook/index.ts', {
    supabase: sb,
    env: { STRIPE_WEBHOOK_SECRET: SECRET, STRIPE_SECRET_KEY: 'sk_test_only', SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test' },
    fetch: fetchMock,
    // Package 3 added a stripeFetchRaw import (charge.refunded branch); not exercised here.
    provide: { stripeFetchRaw: async () => ({ ok: false, status: 500, data: {} }) },
  });
  const deliver = async (event: Record<string, unknown>) => {
    const edge = await load();
    const res = await edge.handler(signedStripeWebhookRequest(SECRET, event));
    return { res, body: await json(res), edge };
  };
  return { sb, pushes, deliver, settleCalls: () => settleCalls, completed };
}

const rpcNames = (sb: ReturnType<typeof mockSupabase>) => sb.rpcs.map((r) => r.name);

describe('stripe-webhook — payment_intent.succeeded settles through settle_verified_payment', () => {
  it('calls the RPC with the PaymentIntent facts, no direct payments/transfers writes, 200 + complete, pushes on settled', async () => {
    const h = harness({ settle: [{ outcome: 'settled', transfer_id: 'tr_row_1' }] });
    const { res, body } = await h.deliver(piEvent('evt_s1', 'payment_intent.succeeded'));
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ received: true, outcome: 'settled' });

    expect(rpcNames(h.sb)).toEqual(['claim_stripe_webhook_event', 'settle_verified_payment', 'complete_stripe_webhook_event']);
    const settle = h.sb.rpcs[1];
    expect(settle.params).toEqual({
      p_payment_intent_id: PI,
      p_stripe_status:     'succeeded',
      p_amount_received:   22000,
      p_currency:          'usd',
      p_livemode:          true,
      p_amount_refunded:   0,
      p_stripe_refund_id:  null,
      p_payment_method:    'card',
      p_metadata:          { mode: 'buy_now', listing_id: LISTING, buyer_id: BUYER, seller_id: SELLER },
      p_source:            'webhook:evt_s1',
    });
    // The handler no longer promotes payments or inserts transfers itself.
    expect(h.sb.queries.filter((q) => q.table === 'payments' && q.op !== 'select')).toHaveLength(0);
    expect(h.sb.queries.filter((q) => q.table === 'transfers')).toHaveLength(0);
    // Buyer + seller pushes, deep-linking to the transfer the RPC returned.
    expect(h.pushes).toHaveLength(2);
    expect(h.pushes.map((p) => p.body.user_id).sort()).toEqual([BUYER, SELLER].sort());
    for (const p of h.pushes) expect((p.body.data as Record<string, unknown>).transferId).toBe('tr_row_1');
  });

  it('F02: an RPC error is NOT terminal — 500 + fail; the retry of the SAME event calls settle AGAIN and completes', async () => {
    const h = harness({ settle: [{ error: 'connection reset', code: '08006' }, { outcome: 'settled' }] });
    const first = await h.deliver(piEvent('evt_f02', 'payment_intent.succeeded'));
    expect(first.res.status).toBe(500);
    expect(rpcNames(h.sb)).toEqual(['claim_stripe_webhook_event', 'settle_verified_payment', 'fail_stripe_webhook_event']);
    expect(h.completed.has('evt_f02')).toBe(false);
    expect(h.pushes).toHaveLength(0);

    const retry = await h.deliver(piEvent('evt_f02', 'payment_intent.succeeded'));
    expect(retry.res.status).toBe(200);
    expect(h.settleCalls()).toBe(2);
    expect(rpcNames(h.sb).slice(3)).toEqual(['claim_stripe_webhook_event', 'settle_verified_payment', 'complete_stripe_webhook_event']);
    expect(h.completed.has('evt_f02')).toBe(true);
    expect(h.pushes).toHaveLength(2);
  });

  it('a duplicate delivery of the SAME event id is already_processed (no settle call)', async () => {
    const h = harness({ settle: [{ outcome: 'settled' }] });
    await h.deliver(piEvent('evt_dup', 'payment_intent.succeeded'));
    const second = await h.deliver(piEvent('evt_dup', 'payment_intent.succeeded'));
    expect(second.res.status).toBe(200);
    expect(second.body).toMatchObject({ received: true, duplicate: true });
    expect(h.settleCalls()).toBe(1);
  });

  it('two DIFFERENT events for one PaymentIntent: the second is already_settled, 200, no second push', async () => {
    const h = harness({ settle: [{ outcome: 'settled' }, { outcome: 'already_settled' }] });
    await h.deliver(piEvent('evt_a', 'payment_intent.succeeded'));
    const second = await h.deliver(piEvent('evt_b', 'payment_intent.succeeded'));
    expect(second.res.status).toBe(200);
    expect(second.body).toMatchObject({ outcome: 'already_settled' });
    expect(h.settleCalls()).toBe(2);
    expect(h.pushes).toHaveLength(2);
    expect(h.completed.has('evt_b')).toBe(true);
  });

  it('refund-before-success: RPC says refunded => 200 terminal and NO push', async () => {
    const h = harness({ settle: [{ outcome: 'refunded' }] });
    const { res, body } = await h.deliver(piEvent('evt_r', 'payment_intent.succeeded'));
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ outcome: 'refunded' });
    expect(h.pushes).toHaveLength(0);
    expect(rpcNames(h.sb).at(-1)).toBe('complete_stripe_webhook_event');
  });

  it('unfulfillable => 200 terminal (no 3-day retry loop), a warning is logged, no push', async () => {
    const h = harness({ settle: [{ outcome: 'unfulfillable', transfer_id: null }] });
    const { res, body, edge } = await h.deliver(piEvent('evt_u', 'payment_intent.succeeded'));
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ outcome: 'unfulfillable' });
    expect(rpcNames(h.sb)).toEqual(['claim_stripe_webhook_event', 'settle_verified_payment', 'complete_stripe_webhook_event']);
    expect(edge.logs.some((l) => l.level === 'warn' && JSON.stringify(l.args).includes('unfulfillable'))).toBe(true);
    expect(h.pushes).toHaveLength(0);
  });

  it.each(['unknown_payment', 'binding_mismatch', 'not_succeeded'] as const)('%s => 200 terminal, no push', async (outcome) => {
    const h = harness({ settle: [{ outcome }] });
    const { res, body } = await h.deliver(piEvent(`evt_${outcome}`, 'payment_intent.succeeded'));
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ outcome });
    expect(rpcNames(h.sb).at(-1)).toBe('complete_stripe_webhook_event');
    expect(h.pushes).toHaveLength(0);
  });

  it('an RPC that returns no row is treated as incomplete (500 + fail)', async () => {
    const h = harness();
    // Script an empty result by overriding the settle handler through the table-less path.
    const sbEmpty = mockSupabase({ rpc: (name) => (name === 'settle_verified_payment' ? { data: [] } : { data: 'claimed' }) });
    const edge = await loadEdgeHandler('supabase/functions/stripe-webhook/index.ts', {
      supabase: sbEmpty,
      env: { STRIPE_WEBHOOK_SECRET: SECRET, SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test' },
      provide: { stripeFetchRaw: async () => ({ ok: false, status: 500, data: {} }) },
    });
    const res = await edge.handler(signedStripeWebhookRequest(SECRET, piEvent('evt_empty', 'payment_intent.succeeded')));
    expect(res.status).toBe(500);
    expect(sbEmpty.rpcs.map((r) => r.name)).toEqual(['claim_stripe_webhook_event', 'settle_verified_payment', 'fail_stripe_webhook_event']);
    void h;
  });
});

describe('stripe-webhook — payment_intent.payment_failed / canceled', () => {
  it('payment_failed marks the row failed guarded on status NOT IN (succeeded, refunded), releases the Buy-Now hold, 200', async () => {
    const h = harness();
    const { res } = await h.deliver(piEvent('evt_pf', 'payment_intent.payment_failed', { status: 'requires_payment_method', amount_received: 0 }));
    expect(res.status).toBe(200);
    const upd = h.sb.queries.find((q) => q.table === 'payments' && q.op === 'update');
    expect(upd?.body).toMatchObject({ status: 'failed' });
    expect(upd?.filters).toEqual([['eq', 'stripe_payment_intent_id', PI], ['not', 'status', 'in', '("succeeded","refunded")']]);
    expect(rpcNames(h.sb)).toEqual(['claim_stripe_webhook_event', 'release_reservation', 'complete_stripe_webhook_event']);
    expect(h.sb.rpcs[1].params).toEqual({ p_listing_id: LISTING, p_user_id: BUYER });
  });

  it('payment_failed: a DB error on the failed-write is NOT terminal (non-2xx + fail)', async () => {
    const h = harness({ paymentsUpdate: () => ({ data: null, error: { message: 'db down' } }) });
    const { res } = await h.deliver(piEvent('evt_pf_err', 'payment_intent.payment_failed', { status: 'requires_payment_method' }));
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(rpcNames(h.sb)).toEqual(['claim_stripe_webhook_event', 'fail_stripe_webhook_event']);
  });

  it('payment_failed with no claimable row (already succeeded / unknown) is a benign 200 and does not release anything', async () => {
    const h = harness({ paymentsUpdate: () => ({ data: null }) });
    const { res } = await h.deliver(piEvent('evt_pf_late', 'payment_intent.payment_failed', { status: 'requires_payment_method' }));
    expect(res.status).toBe(200);
    expect(rpcNames(h.sb)).toEqual(['claim_stripe_webhook_event', 'complete_stripe_webhook_event']);
  });

  it('payment_intent.canceled marks the pending row failed (same predicate), releases the Buy-Now hold, 200', async () => {
    const h = harness();
    const { res } = await h.deliver(piEvent('evt_pc', 'payment_intent.canceled', { status: 'canceled', amount_received: 0 }));
    expect(res.status).toBe(200);
    const upd = h.sb.queries.find((q) => q.table === 'payments' && q.op === 'update');
    expect(upd?.body).toMatchObject({ status: 'failed' });
    expect(upd?.filters).toEqual([['eq', 'stripe_payment_intent_id', PI], ['not', 'status', 'in', '("succeeded","refunded")']]);
    expect(rpcNames(h.sb)).toEqual(['claim_stripe_webhook_event', 'release_reservation', 'complete_stripe_webhook_event']);
    expect(h.sb.rpcs[1].params).toEqual({ p_listing_id: LISTING, p_user_id: BUYER });
  });

  it('payment_intent.canceled: DB error => non-2xx + fail', async () => {
    const h = harness({ paymentsUpdate: () => ({ data: null, error: { message: 'db down' } }) });
    const { res } = await h.deliver(piEvent('evt_pc_err', 'payment_intent.canceled', { status: 'canceled' }));
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(rpcNames(h.sb)).toEqual(['claim_stripe_webhook_event', 'fail_stripe_webhook_event']);
  });

  it('auction-mode failures do not call release_reservation', async () => {
    const h = harness();
    const { res } = await h.deliver(piEvent('evt_pf_auction', 'payment_intent.payment_failed', { status: 'requires_payment_method', metadata: { mode: 'auction', listing_id: LISTING, buyer_id: BUYER, seller_id: SELLER } }));
    expect(res.status).toBe(200);
    expect(rpcNames(h.sb)).toEqual(['claim_stripe_webhook_event', 'complete_stripe_webhook_event']);
  });
});
