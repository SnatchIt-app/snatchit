/**
 * tests/refund-lifecycle.test.ts — refund lifecycle accuracy (migration 150,
 * design docs/release/REFUND_LIFECYCLE_TRACE_AND_FIX_20260924.md §A.6).
 *
 * A Stripe refund has its own status (pending, requires_action, succeeded,
 * failed, canceled) and a card refund can report succeeded and later fail. Every
 * refund fact now goes through record_refund_state with the refund's OWN status,
 * taken from Stripe's object; nothing calls record_payment_refund directly any
 * more (the SQL writer counts only non-failed refunds).
 *
 * Loads the REAL handlers (tests/helpers/edge-vm.ts):
 *   W  stripe-webhook — refund.created / refund.updated / refund.failed re-fetch
 *      GET /v1/refunds/{id} and write its latest state; charge.refunded writes each
 *      refund with its own status;
 *   E  enforce-transfer-expiry Phase 1 — the create response's status is written
 *      (create_response); the buyer push states the stage and THIS refund's amount,
 *      never "full"; a failed create sends no refund push;
 *   H  Phase 1b — reconciles with Stripe before any POST: an existing refund is
 *      recorded (reconcile) instead of creating another; a failed-only history is
 *      recorded and NOT retried; none → one POST under the expiry key; the
 *      selection skips payments with a failed refund;
 *   U  Phase 0 — the unfulfillable refund is written through record_refund_state and
 *      a missing writer fails loudly (no raw payments fallback).
 */
import { describe, expect, it } from 'vitest';
import { loadEdgeHandler, mockStripe, mockSupabase, signedStripeWebhookRequest, type QueryCall, type StripeCall } from './helpers/edge-vm';

// ── W: stripe-webhook ────────────────────────────────────────────────────────
const SECRET = 'whsec_test_only';
const WH_ENV = { STRIPE_WEBHOOK_SECRET: SECRET, SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test', STRIPE_SECRET_KEY: 'sk_test_x' };

async function webhook(opts: { refunds?: Record<string, Record<string, unknown>>; rpcFail?: string; fetchFail?: boolean } = {}) {
  const stripe = mockStripe((c: StripeCall) => {
    const m = /^\/refunds\/(re_[A-Za-z0-9_]+)$/.exec(c.path);
    if (c.method === 'GET' && m) {
      if (opts.fetchFail) return { ok: false, status: 500, data: { error: { message: 'stripe down' } } };
      const r = opts.refunds?.[m[1]];
      return r ? { ok: true, data: r } : { ok: false, status: 404, data: { error: { message: 'No such refund' } } };
    }
    return { ok: false, status: 404, data: { error: { message: `unmocked ${c.method} ${c.path}` } } };
  });
  const sb = mockSupabase({
    rpc: async (name) => {
      if (name === 'claim_stripe_webhook_event') return { data: 'claimed' };
      if (name === 'record_refund_state') {
        if (opts.rpcFail) return { data: null, error: { message: opts.rpcFail } };
        return { data: { recorded: true, payment_id: 'p1' } };
      }
      return { data: true };
    },
  });
  const edge = await loadEdgeHandler('supabase/functions/stripe-webhook/index.ts', { supabase: sb, env: WH_ENV, provide: { stripeFetchRaw: stripe.stripeFetchRaw } });
  const send = (type: string, object: Record<string, unknown>, id = 'evt_1') => edge.handler(signedStripeWebhookRequest(SECRET, { id, type, data: { object } }));
  const writes = () => sb.rpcs.filter((r) => r.name === 'record_refund_state').map((r) => r.params);
  const names = () => sb.rpcs.map((r) => r.name);
  return { sb, stripe, send, writes, names };
}
const refundObj = (id: string, status: string, over: Record<string, unknown> = {}) =>
  ({ id, object: 'refund', status, amount: 11000, payment_intent: 'pi_1', failure_reason: null, metadata: {}, ...over });

describe('W: refund.* events', () => {
  it('W1 refund.failed re-fetches the refund and writes its failure through record_refund_state (never record_payment_refund)', async () => {
    const h = await webhook({ refunds: { re_1: refundObj('re_1', 'failed', { failure_reason: 'expired_or_canceled_card' }) } });
    const res = await h.send('refund.failed', refundObj('re_1', 'failed'));
    expect(res.status).toBe(200);
    expect(h.stripe.calls.map((c) => `${c.method} ${c.path}`)).toEqual(['GET /refunds/re_1']);
    expect(h.writes()).toEqual([{
      p_payment_intent_id: 'pi_1', p_stripe_refund_id: 're_1', p_status: 'failed', p_amount_cents: 11000,
      p_failure_reason: 'expired_or_canceled_card', p_source: 'dashboard', p_observed_via: 'webhook',
    }]);
    expect(h.names()).not.toContain('record_payment_refund');
    expect(h.names().at(-1)).toBe('complete_stripe_webhook_event');
  });

  it('W2 refund.updated writes the LATEST state from Stripe, not the (stale) event payload', async () => {
    const h = await webhook({ refunds: { re_2: refundObj('re_2', 'succeeded') } });
    const res = await h.send('refund.updated', refundObj('re_2', 'pending'));
    expect(res.status).toBe(200);
    expect(h.writes()[0]).toMatchObject({ p_stripe_refund_id: 're_2', p_status: 'succeeded' });
  });

  it('W3 refund.created maps the source from metadata (expiry / unfulfillable / dashboard)', async () => {
    const h = await webhook({ refunds: {
      re_e: refundObj('re_e', 'pending', { metadata: { source: 'enforce-transfer-expiry', reason: 'transfer_expired' } }),
      re_u: refundObj('re_u', 'succeeded', { metadata: { source: 'enforce-transfer-expiry', reason: 'unfulfillable' } }),
      re_d: refundObj('re_d', 'pending'),
    } });
    await h.send('refund.created', refundObj('re_e', 'pending'), 'evt_e');
    await h.send('refund.created', refundObj('re_u', 'pending'), 'evt_u');
    await h.send('refund.created', refundObj('re_d', 'pending'), 'evt_d');
    expect(h.writes().map((w) => w.p_source)).toEqual(['expiry', 'unfulfillable', 'dashboard']);
  });

  it('W4 a refund fetch failure answers non-2xx and writes nothing (Stripe retries)', async () => {
    const h = await webhook({ fetchFail: true });
    const res = await h.send('refund.failed', refundObj('re_1', 'failed'));
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(h.writes()).toHaveLength(0);
    expect(h.names()).toContain('fail_stripe_webhook_event');
  });

  it('W5 a DB failure answers non-2xx and releases the lease', async () => {
    const h = await webhook({ refunds: { re_1: refundObj('re_1', 'failed') }, rpcFail: 'connection reset' });
    const res = await h.send('refund.failed', refundObj('re_1', 'failed'));
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(h.names()).toContain('fail_stripe_webhook_event');
    expect(h.names()).not.toContain('complete_stripe_webhook_event');
  });

  it('W6 a refund with no payment_intent is acknowledged and not written', async () => {
    const h = await webhook({ refunds: { re_x: refundObj('re_x', 'succeeded', { payment_intent: null }) } });
    const res = await h.send('refund.created', refundObj('re_x', 'succeeded', { payment_intent: null }));
    expect(res.status).toBe(200);
    expect(h.writes()).toHaveLength(0);
  });
});

describe('W: charge.refunded', () => {
  it('W7 writes every refund with ITS OWN status — a failed refund in the list is never recorded as money returned', async () => {
    const h = await webhook();
    const res = await h.send('charge.refunded', {
      id: 'ch_1', payment_intent: 'pi_1', refunded: false, amount_refunded: 5000,
      refunds: { data: [refundObj('re_ok', 'succeeded', { amount: 5000 }), refundObj('re_bad', 'failed', { amount: 6000, failure_reason: 'declined' })] },
    });
    expect(res.status).toBe(200);
    expect(h.writes()).toEqual([
      { p_payment_intent_id: 'pi_1', p_stripe_refund_id: 're_ok', p_status: 'succeeded', p_amount_cents: 5000, p_failure_reason: null, p_source: 'dashboard', p_observed_via: 'webhook' },
      { p_payment_intent_id: 'pi_1', p_stripe_refund_id: 're_bad', p_status: 'failed', p_amount_cents: 6000, p_failure_reason: 'declined', p_source: 'dashboard', p_observed_via: 'webhook' },
    ]);
    expect(h.names()).not.toContain('record_payment_refund');
  });

  it('W8 a listed refund without a status is re-fetched before it is written', async () => {
    const h = await webhook({ refunds: { re_ns: refundObj('re_ns', 'pending', { amount: 4000 }) } });
    const res = await h.send('charge.refunded', { id: 'ch_1', payment_intent: 'pi_1', refunds: { data: [{ id: 're_ns', amount: 4000 }] } });
    expect(res.status).toBe(200);
    expect(h.stripe.calls.some((c) => c.path === '/refunds/re_ns')).toBe(true);
    expect(h.writes()[0]).toMatchObject({ p_stripe_refund_id: 're_ns', p_status: 'pending', p_amount_cents: 4000 });
  });
});

// ── E / H / U: enforce-transfer-expiry ───────────────────────────────────────
interface ExpWorld {
  expired?: Array<{ transfer_id: string; payment_id: string; listing_id: string; buyer_id: string; seller_id: string }>;
  payment?: Record<string, unknown>;
  create?: (c: StripeCall) => Record<string, unknown>;             // POST /refunds response
  list?: Record<string, Array<Record<string, unknown>>>;          // GET /refunds?payment_intent=pi → data
  unrefunded?: Array<Record<string, unknown>>;                    // Phase 1b rows
  writer?: 'ok' | 'missing';
  unsettled?: Array<Record<string, unknown>>;                     // Phase 0 work
  listFail?: boolean;                                             // GET /refunds?payment_intent= fails
}
async function expiry(w: ExpWorld) {
  const pushes: Array<{ user_id: string; title: string; body: string }> = [];
  const stripe = mockStripe((c: StripeCall) => {
    if (c.method === 'POST' && c.path === '/refunds') {
      const body = c.body as Record<string, string>;
      return { ok: true, data: { id: 're_new', amount: 11000, status: 'pending', payment_intent: body.payment_intent, ...(w.create?.(c) ?? {}) } };
    }
    if (c.method === 'GET' && c.path.startsWith('/refunds?')) {
      if (w.listFail) return { ok: false, status: 500, data: { error: { message: 'stripe down' } } };
      const pi = new URLSearchParams(c.path.split('?')[1]).get('payment_intent') ?? '';
      return { ok: true, data: { object: 'list', has_more: false, data: w.list?.[pi] ?? [] } };
    }
    if (c.method === 'GET' && c.path.startsWith('/payment_intents/')) {
      const pi = c.path.split('/')[2].split('?')[0];
      return { ok: true, data: { id: pi, status: 'succeeded', amount_received: 11000, currency: 'usd', livemode: true, payment_method_types: ['card'], metadata: { mode: 'buy_now', listing_id: 'l1' }, latest_charge: { id: 'ch_1', amount_refunded: 0, refunds: { data: [] } } } };
    }
    return { ok: false, status: 404, data: { error: { message: `unmocked ${c.method} ${c.path}` } } };
  });
  const sb = mockSupabase({
    rpc: (name) => {
      if (name === 'enforce_transfer_expiry') return { data: w.expired ?? [] };
      if (name === 'get_unsettled_payments') return { data: w.unsettled ?? [] };
      if (name === 'settle_verified_payment') return { data: [{ payment_id: 'u1', payment_status: 'succeeded', listing_status: 'active', transfer_id: null, outcome: 'unfulfillable' }] };
      if (name === 'record_refund_state') {
        if (w.writer === 'missing') return { data: null, error: { message: 'Could not find the function public.record_refund_state(...) in the schema cache', code: 'PGRST202' } };
        return { data: { recorded: true } };
      }
      if (name === 'get_auto_release_candidates') return { data: [] };
      return { data: [] };
    },
    tables: {
      payments: (q: QueryCall) => {
        if (q.op !== 'select') return { data: null };
        return { data: q.terminal === 'list' ? [w.payment] : (w.payment ?? null) };
      },
      transfers: (q: QueryCall) => {
        if (q.op === 'select' && q.filters.some(([op, col, v]) => op === 'eq' && col === 'status' && v === 'expired')) return { data: w.unrefunded ?? [] };
        return { data: q.terminal === 'list' ? [] : null };
      },
      listings: () => ({ data: { event_name: 'Fixture Night' } }),
      payout_policy: () => ({ data: null }),
      transfer_notifications: () => ({ data: [] }),
      webhook_retries: () => ({ data: null }),
      payout_attempts: () => ({ data: [] }),
    },
  });
  const edge = await loadEdgeHandler('supabase/functions/enforce-transfer-expiry/index.ts', {
    supabase: sb,
    env: { STRIPE_SECRET_KEY: 'sk_test_only', SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'srv', INTERNAL_CRON_SECRET: 'cron-secret' },
    fetch: (async (_url: string, init?: { body?: string }) => { if (init?.body) pushes.push(JSON.parse(init.body)); return new Response('{}', { status: 200 }); }) as unknown as typeof fetch,
    provide: {
      executePayoutAttempt: async () => ({ kind: 'not_eligible', reason: 'TEST' }), stripeFetch: stripe.stripeFetch,
      isCrossModeStripeError: () => false, rowIsLiveActionable: (v: unknown) => v === true, allowTestModeMoney: () => false,
      classifyPayout: () => ({ action: 'hold', tier: 'low', reasons: [], hold_until: null }), DEFAULT_POLICY: {},
      PayoutCandidate: undefined, PayoutPolicyConfig: undefined,
    },
  });
  const res = await edge.handler(new Request('https://edge.test/enforce', { method: 'POST', headers: { authorization: 'Bearer cron-secret' } }));
  const writes = () => sb.rpcs.filter((r) => r.name === 'record_refund_state').map((r) => r.params);
  const posts = () => stripe.calls.filter((c) => c.method === 'POST' && c.path === '/refunds');
  return { res, sb, stripe, pushes, writes, posts, edge };
}
const EXPIRED = [{ transfer_id: 't1', payment_id: 'p1', listing_id: 'l1', buyer_id: 'buyer-1', seller_id: 'seller-1' }];
const PAY = { id: 'p1', stripe_payment_intent_id: 'pi_1', status: 'succeeded', stripe_refund_id: null, stripe_livemode: true, total: 11000, amount_refunded_cents: null };

describe('E: Phase 1 expiry refund', () => {
  it('E1 a pending create is written as pending (create_response); the buyer is told a refund was REQUESTED, with its amount', async () => {
    const h = await expiry({ expired: EXPIRED, payment: PAY });
    expect(h.res.status).toBe(200);
    expect(h.posts()).toHaveLength(1);
    expect(h.posts()[0].idempotencyKey).toBe('refund_expiry_t1');
    expect(h.writes()).toEqual([{
      p_payment_intent_id: 'pi_1', p_stripe_refund_id: 're_new', p_status: 'pending', p_amount_cents: 11000,
      p_failure_reason: null, p_source: 'expiry', p_observed_via: 'create_response',
    }]);
    expect(h.sb.rpcs.some((r) => r.name === 'record_payment_refund')).toBe(false);
    const buyer = h.pushes.find((p) => p.user_id === 'buyer-1')!;
    expect(buyer.body).toMatch(/requested a refund of \$110\.00/);
    expect(`${buyer.title} ${buyer.body}`).not.toMatch(/full/i);
    expect(`${buyer.title} ${buyer.body}`).not.toMatch(/\bprocessed\b|\bissued\b/i);
    const seller = h.pushes.find((p) => p.user_id === 'seller-1')!;
    expect(seller.body).toMatch(/being refunded/);
    expect(seller.body).not.toMatch(/has been refunded/);
  });

  it('E2 a succeeded create tells the buyer the amount was refunded (still never "full")', async () => {
    const h = await expiry({ expired: EXPIRED, payment: PAY, create: () => ({ status: 'succeeded' }) });
    const buyer = h.pushes.find((p) => p.user_id === 'buyer-1')!;
    expect(buyer.body).toMatch(/refunded \$110\.00/);
    expect(`${buyer.title} ${buyer.body}`).not.toMatch(/full/i);
    expect(h.writes()[0]).toMatchObject({ p_status: 'succeeded' });
  });

  it('E3 after an earlier partial refund the push states THIS refund\'s amount, not "full"', async () => {
    const h = await expiry({ expired: EXPIRED, payment: { ...PAY, amount_refunded_cents: 3000 }, create: () => ({ amount: 8000 }) });
    const buyer = h.pushes.find((p) => p.user_id === 'buyer-1')!;
    expect(buyer.body).toMatch(/\$80\.00/);
    expect(buyer.body).not.toMatch(/\$110\.00/);
    expect(`${buyer.title} ${buyer.body}`).not.toMatch(/full/i);
  });

  it('E4 a failed create is written as failed and sends the buyer NO refund push', async () => {
    const h = await expiry({ expired: EXPIRED, payment: PAY, create: () => ({ status: 'failed', failure_reason: 'declined' }) });
    expect(h.writes()[0]).toMatchObject({ p_status: 'failed', p_failure_reason: 'declined' });
    expect(h.pushes.filter((p) => p.user_id === 'buyer-1')).toHaveLength(0);
  });
});

describe('H: Phase 1b reconciles before it refunds', () => {
  const ROW = { id: 't9', payment_id: 'p9', listing_id: 'l9', buyer_id: 'buyer-9', seller_id: 'seller-9',
                payments: { id: 'p9', status: 'succeeded', stripe_payment_intent_id: 'pi_9', stripe_refund_id: null, stripe_livemode: true, total: 11000, amount_refunded_cents: null } };

  it('H1 an existing refund at Stripe (our write was lost) is RECORDED, never re-created', async () => {
    const h = await expiry({ unrefunded: [ROW], list: { pi_9: [refundObj('re_lost', 'succeeded', { payment_intent: 'pi_9', metadata: { source: 'enforce-transfer-expiry', transfer_id: 't9', reason: 'transfer_expired' } })] } });
    expect(h.posts()).toHaveLength(0);
    expect(h.writes()).toEqual([{
      p_payment_intent_id: 'pi_9', p_stripe_refund_id: 're_lost', p_status: 'succeeded', p_amount_cents: 11000,
      p_failure_reason: null, p_source: 'expiry', p_observed_via: 'reconcile',
    }]);
  });

  it('H2 a failed-only history is recorded and NOT retried (Stripe: arrange an alternative; an operator case opens)', async () => {
    const h = await expiry({ unrefunded: [ROW], list: { pi_9: [refundObj('re_f', 'failed', { payment_intent: 'pi_9', failure_reason: 'lost_or_stolen_card', metadata: { source: 'enforce-transfer-expiry', transfer_id: 't9' } })] } });
    expect(h.posts()).toHaveLength(0);
    expect(h.writes()[0]).toMatchObject({ p_stripe_refund_id: 're_f', p_status: 'failed', p_observed_via: 'reconcile' });
  });

  it('H2b a failed refund that is NOT ours (a failed Dashboard refund) also blocks automatic creation', async () => {
    const h = await expiry({ unrefunded: [ROW], list: { pi_9: [refundObj('re_dash_f', 'failed', { payment_intent: 'pi_9', failure_reason: 'declined' })] } });
    expect(h.posts()).toHaveLength(0);
    expect(h.writes()[0]).toMatchObject({ p_stripe_refund_id: 're_dash_f', p_status: 'failed', p_source: 'dashboard', p_observed_via: 'reconcile' });
  });

  it('H6 a Dashboard PARTIAL refund (not ours, succeeded) is recorded and the remaining balance is still refunded', async () => {
    const h = await expiry({ unrefunded: [ROW], list: { pi_9: [refundObj('re_part', 'succeeded', { payment_intent: 'pi_9', amount: 3000 })] }, create: () => ({ amount: 8000 }) });
    expect(h.writes()[0]).toMatchObject({ p_stripe_refund_id: 're_part', p_status: 'succeeded', p_amount_cents: 3000, p_observed_via: 'reconcile' });
    expect(h.posts()).toHaveLength(1);
    expect((h.posts()[0].body as Record<string, string>).amount).toBeUndefined();   // amount-less: Stripe refunds the remaining balance
    expect(h.writes()[1]).toMatchObject({ p_amount_cents: 8000, p_observed_via: 'create_response' });
  });

  it('H7 refunds that have not failed already cover the total → recorded, nothing created', async () => {
    const h = await expiry({ unrefunded: [ROW], list: { pi_9: [refundObj('re_full', 'pending', { payment_intent: 'pi_9', amount: 11000 })] } });
    expect(h.posts()).toHaveLength(0);
    expect(h.writes()).toHaveLength(1);
  });

  it('H3 no refund at Stripe → exactly one POST under the expiry key, written from the create response', async () => {
    const h = await expiry({ unrefunded: [ROW], list: { pi_9: [] } });
    expect(h.posts()).toHaveLength(1);
    expect(h.posts()[0].idempotencyKey).toBe('refund_expiry_t9');
    expect(h.writes()[0]).toMatchObject({ p_payment_intent_id: 'pi_9', p_observed_via: 'create_response' });
  });

  it('H4 the selection skips payments that already carry a failed refund (they would starve the 20-row window)', async () => {
    const h = await expiry({ unrefunded: [] });
    const q = h.sb.queries.find((x) => x.table === 'transfers' && x.filters.some(([op, col, v]) => op === 'eq' && col === 'status' && v === 'expired'))!;
    expect(q.filters).toContainEqual(['eq', 'payments.refund_failed_cents', 0]);
  });

  it('H5 a reconcile read failure skips the row this run: no POST, no write (it is retried next run)', async () => {
    const h = await expiry({ unrefunded: [ROW], listFail: true });
    expect(h.res.status).toBe(200);
    expect(h.posts()).toHaveLength(0);
    expect(h.writes()).toHaveLength(0);
  });
});

describe('U: Phase 0 unfulfillable refund', () => {
  const U = [{ payment_id: 'u1', stripe_payment_intent_id: 'pi_u1', listing_id: 'l1', mode: 'buy_now', status: 'succeeded', paid_at: new Date(Date.now() - 600_000).toISOString(), kind: 'paid_unsettled' }];

  it('U1 the unfulfillable refund is written through record_refund_state (source unfulfillable, create_response)', async () => {
    const h = await expiry({ unsettled: U, payment: { id: 'u1', status: 'succeeded', stripe_refund_id: null, stripe_livemode: true, total: 11000, listing_id: 'l1', amount_refunded_cents: null } });
    expect(h.posts()[0]?.idempotencyKey).toBe('refund_unfulfillable_u1');
    expect(h.writes()[0]).toMatchObject({ p_payment_intent_id: 'pi_u1', p_source: 'unfulfillable', p_observed_via: 'create_response', p_status: 'pending' });
  });

  it('U2 a missing writer fails loudly: no raw payments write marks the payment refunded', async () => {
    const h = await expiry({ unsettled: U, writer: 'missing', payment: { id: 'u1', status: 'succeeded', stripe_refund_id: null, stripe_livemode: true, total: 11000, listing_id: 'l1', amount_refunded_cents: null } });
    const raw = h.sb.queries.filter((q) => q.table === 'payments' && q.op === 'update' && (q.body as Record<string, unknown>)?.status === 'refunded');
    expect(raw).toHaveLength(0);
    expect(h.edge.sentry.length).toBeGreaterThan(0);
  });
});
