/**
 * refunds-4 (DESIGN-199-FINAL §5.1): a Stripe refund that FAILS or is CANCELED
 * converges kernel.refund through exactly one verb,
 * kernel.record_refund_stripe_failure, called by stripe-webhook's refund.* branch.
 *
 * Before this, nothing called the verb (contract review wf_a09ba978-0f5, F1):
 * a refund that succeeded and then failed stayed `succeeded` in kernel.refund
 * forever — no audit row, no page, a venue refund_void debit for money that
 * never reached the buyer.
 *
 *   C  the pure decisions (stripe-webhook/refund-failure.ts)
 *   R  the real handler (tests/helpers/edge-vm.ts): when the verb is called,
 *      in what order, and what each of its answers does to the delivery
 */
import { describe, expect, it } from 'vitest';
import { loadEdgeHandler, mockStripe, mockSupabase, signedStripeWebhookRequest, type StripeCall } from './helpers/edge-vm';
import {
  REFUND_FAILURE_UNBOUND_GRACE_SECONDS,
  classifyRefundFailureResult,
  needsRefundFailureConvergence,
} from '../supabase/functions/stripe-webhook/refund-failure';

const REFUND_ID = 'aaaa1111-bbbb-4ccc-8ddd-eeee11112222';
const SETTLEMENT = 'bbbb2222-cccc-4ddd-8eee-ffff22223333';
const OBLIGATION = 'cccc3333-dddd-4eee-8fff-aaaa33334444';
const ATOM = 'dddd4444-eeee-4fff-8aaa-bbbb44445555';
const OURS = { source: 'refund-execute', refund_id: REFUND_ID };

const SUCCEEDED_TO_FAILED = {
  status: 'ok', transition: 'succeeded_to_failed', refund_id: REFUND_ID,
  failure_code: 'expired_or_canceled_card', stripe_status: 'failed', command_key: 'webhook:evt_1',
  payment_id: 'p1', order_id: null, amount_minor: 11000,
  refund_void_line: { line_id: 'l1', settlement_id: SETTLEMENT, amount_minor: 11000, settlement_status: 'open' },
  settlement_shortfall_obligation: { obligation_id: OBLIGATION, status: 'open', amount_minor: 11000 },
  unlined_reversal_obligation: null, refund_clawback_obligation: null,
  compensated_market_sale_ids: [], atoms_voided: [ATOM], promoter_commission_lined: false,
  settlement_review_required: true,
};

// ── C: pure decisions ─────────────────────────────────────────────────────────
describe('C: which observations reach the verb', () => {
  it.each(['failed', 'canceled'])('C1 a %s refund converges', (status) => {
    expect(needsRefundFailureConvergence(status, { recorded: true })).toBe(true);
  });
  it('C2 a stale observation of an already-failed refund converges too (the earlier delivery may not have)', () => {
    expect(needsRefundFailureConvergence('succeeded', { recorded: false, reason: 'stale_observation', refund_status: 'failed' })).toBe(true);
  });
  it.each(['pending', 'requires_action', 'succeeded', null, undefined])('C3 control: %s with a normal write does not', (status) => {
    expect(needsRefundFailureConvergence(status as string | null | undefined, { recorded: true })).toBe(false);
    expect(needsRefundFailureConvergence(status as string | null | undefined, null)).toBe(false);
  });
});

describe('C: what the verb\'s answer means for the delivery', () => {
  const fresh = { metadata: OURS, ageSeconds: 5 };

  it('C4 succeeded→failed is ACKed and pages failed_after_success with ids and counts only', () => {
    const d = classifyRefundFailureResult({ data: SUCCEEDED_TO_FAILED, error: null }, fresh);
    expect(d.ack).toBe(true);
    if (!d.ack) return;
    expect(d.page?.tag).toBe('refund-webhook:failed_after_success');
    expect(d.page?.facts).toEqual({
      refund_id: REFUND_ID, failure_code: 'expired_or_canceled_card', settlement_review_required: true,
      settlement_id: SETTLEMENT, settlement_shortfall_obligation_id: OBLIGATION,
      unlined_reversal_obligation_id: null, refund_clawback_obligation_id: null,
      atoms_voided: 1, compensated_market_sales: 0, promoter_commission_lined: false,
    });
  });

  it('C5 submitted→failed is ACKed and pages refund_failed', () => {
    const d = classifyRefundFailureResult({ data: { status: 'ok', transition: 'submitted_to_failed', refund_id: REFUND_ID, failure_code: 'refund_canceled', settlement_review_required: false }, error: null }, fresh);
    expect(d).toMatchObject({ ack: true, page: { tag: 'refund-webhook:refund_failed', facts: { refund_id: REFUND_ID, failure_code: 'refund_canceled' } } });
  });

  it.each(['noop_replay', 'in_flight', 'not_failed'])('C6 %s is ACKed silently', (status) => {
    expect(classifyRefundFailureResult({ data: { status, refund_id: REFUND_ID }, error: null }, fresh)).toMatchObject({ ack: true, page: null });
  });

  it('C7 not_bound on OUR refund inside the grace window is a bounded retry (the executor may not have bound its ref yet)', () => {
    expect(classifyRefundFailureResult({ data: { status: 'not_bound' }, error: null }, fresh)).toMatchObject({ ack: false });
  });
  it('C8 not_bound on OUR refund past the grace window is ACKed and paged failure_unbound', () => {
    const d = classifyRefundFailureResult({ data: { status: 'not_bound' }, error: null }, { metadata: OURS, ageSeconds: REFUND_FAILURE_UNBOUND_GRACE_SECONDS });
    expect(d).toMatchObject({ ack: true, page: { tag: 'refund-webhook:failure_unbound', facts: { refund_id: REFUND_ID } } });
  });
  it('C9 not_bound on an undatable event is treated as past the window (never an unbounded retry)', () => {
    const d = classifyRefundFailureResult({ data: { status: 'not_bound' }, error: null }, { metadata: OURS, ageSeconds: Number.POSITIVE_INFINITY });
    expect(d).toMatchObject({ ack: true, page: { tag: 'refund-webhook:failure_unbound' } });
  });
  it('C10 not_bound on a refund that is NOT ours (Dashboard, expiry, ops rail) is ACKed silently', () => {
    expect(classifyRefundFailureResult({ data: { status: 'not_bound' }, error: null }, { metadata: {}, ageSeconds: 5 })).toMatchObject({ ack: true, page: null });
    expect(classifyRefundFailureResult({ data: { status: 'not_bound' }, error: null }, { metadata: null, ageSeconds: 5 })).toMatchObject({ ack: true, page: null });
  });
  it('C11 not_bound with source refund-execute but no uuid refund_id is not retried', () => {
    const d = classifyRefundFailureResult({ data: { status: 'not_bound' }, error: null }, { metadata: { source: 'refund-execute', refund_id: 'nope' }, ageSeconds: 5 });
    expect(d).toMatchObject({ ack: true, page: { tag: 'refund-webhook:failure_unbound', facts: { refund_id: null } } });
  });

  it.each([
    'precondition_failed: refund_not_submitted (refund x is pending)',
    'conflict_locked: refund_amount_mismatch (1 observed, 2 recorded)',
    'invalid_input: command_key must match ^[A-Za-z0-9._:-]{1,80}$',
    'not_found: refund',
  ])('C12 a deterministic refusal (%s) is ACKed and paged — it must not loop for 3 days', (message) => {
    expect(classifyRefundFailureResult({ data: null, error: { message, code: 'P0001' } }, fresh)).toMatchObject({ ack: true, page: { tag: 'refund-webhook:verb_refused' } });
  });
  it('C13 the verb missing (PGRST202, e.g. after a SQL rollback) is ACKed and paged verb_missing', () => {
    expect(classifyRefundFailureResult({ data: null, error: { message: 'Could not find the function kernel.record_refund_stripe_failure', code: 'PGRST202' } }, fresh))
      .toMatchObject({ ack: true, page: { tag: 'refund-webhook:verb_missing' } });
  });
  it.each([
    [{ message: 'terminating connection due to administrator command', code: '57P01' }],
    [{ message: 'connection reset' }],
    [{ message: 'canceling statement due to statement timeout', code: '57014' }],
  ])('C14 a transport or transient fault (%o) is retried', (error) => {
    expect(classifyRefundFailureResult({ data: null, error }, fresh)).toMatchObject({ ack: false });
  });
  it('C15 an answer the contract does not name is ACKed and paged (contract drift does not fix itself on redelivery)', () => {
    expect(classifyRefundFailureResult({ data: { status: 'something_new' }, error: null }, fresh)).toMatchObject({ ack: true, page: { tag: 'refund-webhook:verb_unrecognized' } });
    expect(classifyRefundFailureResult({ data: true, error: null }, fresh)).toMatchObject({ ack: true, page: { tag: 'refund-webhook:verb_unrecognized' } });
  });
});

// ── R: the real handler ───────────────────────────────────────────────────────
const SECRET = 'whsec_test_only';
const WH_ENV = { STRIPE_WEBHOOK_SECRET: SECRET, SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test', STRIPE_SECRET_KEY: 'sk_test_x' };
const refundObj = (id: string, status: string, over: Record<string, unknown> = {}) =>
  ({ id, object: 'refund', status, amount: 11000, payment_intent: 'pi_1', failure_reason: null, metadata: {}, ...over });

async function webhook(opts: {
  refund: Record<string, unknown>;
  recordAnswer?: { data?: unknown; error?: { message: string; code?: string } | null };
  verbAnswer?: { data?: unknown; error?: { message: string; code?: string } | null };
}) {
  const stripe = mockStripe((c: StripeCall) => {
    if (c.method === 'GET' && c.path === `/refunds/${opts.refund.id}`) return { ok: true, data: opts.refund };
    return { ok: false, status: 404, data: { error: { message: `unmocked ${c.method} ${c.path}` } } };
  });
  const sb = mockSupabase({
    rpc: async (name) => {
      if (name === 'claim_stripe_webhook_event') return { data: 'claimed' };
      if (name === 'record_refund_state') return opts.recordAnswer ?? { data: { recorded: true, payment_id: 'p1' } };
      if (name === 'record_refund_stripe_failure') return opts.verbAnswer ?? { data: { status: 'not_bound' } };
      return { data: true };
    },
  });
  const edge = await loadEdgeHandler('supabase/functions/stripe-webhook/index.ts', { supabase: sb, env: WH_ENV, provide: { stripeFetchRaw: stripe.stripeFetchRaw } });
  const send = (type: string, created = Math.floor(Date.now() / 1000), id = 'evt_1') =>
    edge.handler(signedStripeWebhookRequest(SECRET, { id, type, created, data: { object: refundObj(String(opts.refund.id), 'pending') } }));
  const names = () => sb.rpcs.map((r) => r.name);
  const verbCalls = () => sb.rpcs.filter((r) => r.name === 'record_refund_stripe_failure');
  return { sb, edge, send, names, verbCalls };
}

describe('R: stripe-webhook refund.* calls the converger', () => {
  it('R1 refund.failed: record_refund_state, THEN the verb on kernel (event-scoped key), THEN complete — and one failed_after_success page', async () => {
    const h = await webhook({ refund: refundObj('re_1', 'failed', { failure_reason: 'expired_or_canceled_card', metadata: OURS }), verbAnswer: { data: SUCCEEDED_TO_FAILED } });
    const res = await h.send('refund.failed');
    expect(res.status).toBe(200);
    expect(h.verbCalls()).toEqual([{ name: 'record_refund_stripe_failure', params: { p_stripe_refund_ref: 're_1', p_command_key: 'webhook:evt_1' }, schema: 'kernel' }]);
    const n = h.names();
    expect(n.indexOf('record_refund_state')).toBeLessThan(n.indexOf('record_refund_stripe_failure'));
    expect(n.indexOf('record_refund_stripe_failure')).toBeLessThan(n.indexOf('complete_stripe_webhook_event'));
    expect(n.at(-1)).toBe('complete_stripe_webhook_event');
    expect(h.edge.sentry.map((s) => s.tag)).toEqual(['refund-webhook:failed_after_success']);
  });

  it('R2 refund.updated to canceled converges too', async () => {
    const h = await webhook({ refund: refundObj('re_2', 'canceled', { metadata: OURS }), verbAnswer: { data: { status: 'ok', transition: 'submitted_to_failed', refund_id: REFUND_ID, failure_code: 'refund_canceled' } } });
    expect((await h.send('refund.updated')).status).toBe(200);
    expect(h.verbCalls()).toHaveLength(1);
    expect(h.edge.sentry.map((s) => s.tag)).toEqual(['refund-webhook:refund_failed']);
  });

  it('R3 a stale observation (Stripe now says succeeded; we already recorded failed) still converges', async () => {
    const h = await webhook({
      refund: refundObj('re_3', 'succeeded', { metadata: OURS }),
      recordAnswer: { data: { recorded: false, reason: 'stale_observation', refund_status: 'failed' } },
      verbAnswer: { data: { status: 'noop_replay', refund_id: REFUND_ID } },
    });
    expect((await h.send('refund.updated')).status).toBe(200);
    expect(h.verbCalls()).toHaveLength(1);
    expect(h.edge.sentry).toHaveLength(0);
  });

  it('R4 control: a refund that succeeded normally never reaches the verb', async () => {
    const h = await webhook({ refund: refundObj('re_4', 'succeeded', { metadata: OURS }) });
    expect((await h.send('refund.updated')).status).toBe(200);
    expect(h.names()).not.toContain('record_refund_stripe_failure');
    expect(h.names().at(-1)).toBe('complete_stripe_webhook_event');
  });

  it('R5 not_bound on our refund inside the window answers non-2xx and releases the lease — never completes', async () => {
    const h = await webhook({ refund: refundObj('re_5', 'failed', { metadata: OURS }), verbAnswer: { data: { status: 'not_bound' } } });
    const res = await h.send('refund.failed');
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(h.names()).toContain('fail_stripe_webhook_event');
    expect(h.names()).not.toContain('complete_stripe_webhook_event');
  });

  it('R6 the same not_bound two hours later is ACKed and paged failure_unbound (bounded)', async () => {
    const h = await webhook({ refund: refundObj('re_6', 'failed', { metadata: OURS }), verbAnswer: { data: { status: 'not_bound' } } });
    const res = await h.send('refund.failed', Math.floor(Date.now() / 1000) - 7200);
    expect(res.status).toBe(200);
    expect(h.names().at(-1)).toBe('complete_stripe_webhook_event');
    expect(h.edge.sentry.map((s) => s.tag)).toEqual(['refund-webhook:failure_unbound']);
  });

  it('R7 a Dashboard refund that fails (no kernel row) is ACKed with no page', async () => {
    const h = await webhook({ refund: refundObj('re_7', 'failed'), verbAnswer: { data: { status: 'not_bound' } } });
    expect((await h.send('refund.failed')).status).toBe(200);
    expect(h.names().at(-1)).toBe('complete_stripe_webhook_event');
    expect(h.edge.sentry).toHaveLength(0);
  });

  it('R8 a transport fault on the verb answers non-2xx (Stripe redelivers; both SQL steps replay idempotently)', async () => {
    const h = await webhook({ refund: refundObj('re_8', 'failed', { metadata: OURS }), verbAnswer: { data: null, error: { message: 'terminating connection due to administrator command', code: '57P01' } } });
    const res = await h.send('refund.failed');
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(h.names()).not.toContain('complete_stripe_webhook_event');
  });

  it('R9 a deterministic refusal is ACKed and paged once', async () => {
    const h = await webhook({ refund: refundObj('re_9', 'failed', { metadata: OURS }), verbAnswer: { data: null, error: { message: 'precondition_failed: refund_not_submitted (refund x is pending)', code: 'P0001' } } });
    expect((await h.send('refund.failed')).status).toBe(200);
    expect(h.names().at(-1)).toBe('complete_stripe_webhook_event');
    expect(h.edge.sentry.map((s) => s.tag)).toEqual(['refund-webhook:verb_refused']);
  });

  it('R10 a failed record_refund_state still answers non-2xx BEFORE the verb is tried (unchanged)', async () => {
    const h = await webhook({ refund: refundObj('re_10', 'failed', { metadata: OURS }), recordAnswer: { data: null, error: { message: 'connection reset' } } });
    expect((await h.send('refund.failed')).status).toBeGreaterThanOrEqual(500);
    expect(h.names()).not.toContain('record_refund_stripe_failure');
  });
});
