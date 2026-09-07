/**
 * tests/ops-refund-classify.test.ts — pure decision logic of the console
 * refund executor (supabase/functions/ops-refund-execute/classify.ts).
 *
 * Mirrors tests/payout-logic.test.ts: what is deterministic (request guard,
 * idempotency key, mode boundary, preconditions, request body, Stripe
 * outcome classification) is tested here; the executor flow over injected
 * adapters is tests/ops-refund-handler.test.ts; the Deno shell in index.ts is
 * type-checked in CI and verified against the deployed function.
 */
import { describe, expect, it } from 'vitest';

import {
  assertNoClientPaymentReference,
  buildOpsRefundIdempotencyKey,
  checkActionPreconditions,
  checkModeConsistency,
  checkPaymentPreconditions,
  classifyRefundCreate,
  classifyRefundObject,
  findExistingRefund,
  httpStatusForState,
  planRefundBody,
  refundMismatch,
  sanitizeErrorMessage,
  stripeKeyMode,
  validateRequest,
  type RefundExpectation,
  type StripeRefundObject,
} from '../supabase/functions/ops-refund-execute/classify';

const ACTION_ID = '11111111-2222-4333-8444-555555555555';
const PAYMENT_ID = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

const ACTION = {
  id: ACTION_ID,
  action_type: 'refund_execute',
  subject_kind: 'payment',
  subject_id: PAYMENT_ID,
  state: 'processing',
  params: { reason_code: 'duplicate' },
  result: { handoff: 'ops-refund-execute', amount_cents: 5000 },
  approval_id: null,
};
const APPROVED = [{ id: 'x', state: 'approved' }];
const PAYMENT = {
  id: PAYMENT_ID,
  status: 'succeeded',
  total: 5000,
  stripe_payment_intent_id: 'pi_123abc',
  stripe_livemode: true,
};

describe('request guard — the only client input is action_id', () => {
  it('accepts { action_id }', () => {
    expect(validateRequest({ action_id: ACTION_ID })).toEqual({ ok: true, action_id: ACTION_ID });
  });

  it.each([
    'payment_id', 'payment_intent', 'stripe_payment_intent_id', 'charge', 'charge_id',
    'amount', 'amount_cents', 'destination', 'stripe_refund_id',
  ])('refuses a body naming the money via %s', (k) => {
    const v = assertNoClientPaymentReference({ action_id: ACTION_ID, [k]: 'x' });
    expect(v.ok).toBe(false);
    if (!v.ok) expect(v.code).toBe('client_supplied_payment_reference');
    const full = validateRequest({ action_id: ACTION_ID, [k]: 1 });
    expect(full.ok).toBe(false);
  });

  it('refuses any unknown field (not just the forbidden list)', () => {
    const v = validateRequest({ action_id: ACTION_ID, note: 'hi' });
    expect(v).toMatchObject({ ok: false, code: 'unexpected_field' });
  });

  it('refuses a non-uuid, nil uuid, array or missing action_id', () => {
    expect(validateRequest({ action_id: 'nope' })).toMatchObject({ ok: false, code: 'invalid_input' });
    expect(validateRequest({ action_id: '00000000-0000-0000-0000-000000000000' })).toMatchObject({ ok: false });
    expect(validateRequest({})).toMatchObject({ ok: false, code: 'invalid_input' });
    expect(validateRequest([ACTION_ID])).toMatchObject({ ok: false, code: 'invalid_input' });
    expect(validateRequest(null)).toMatchObject({ ok: false, code: 'invalid_input' });
  });

  it('null-valued forbidden keys are ignored by the guard but rejected as unexpected fields', () => {
    expect(assertNoClientPaymentReference({ payment_id: null }).ok).toBe(true);
    expect(validateRequest({ action_id: ACTION_ID, payment_id: null })).toMatchObject({ ok: false, code: 'unexpected_field' });
  });
});

describe('idempotency key — stable across retries', () => {
  it('is derived from the action id only', () => {
    expect(buildOpsRefundIdempotencyKey(ACTION_ID)).toBe(`ops_action_${ACTION_ID}`);
    expect(buildOpsRefundIdempotencyKey(ACTION_ID)).toBe(buildOpsRefundIdempotencyKey(ACTION_ID));
  });
  it('refuses to mint a key from a non-uuid', () => {
    expect(() => buildOpsRefundIdempotencyKey('re_123')).toThrow();
  });
});

describe('mode boundary — fail closed', () => {
  it('derives mode from the key prefix without exposing the key', () => {
    expect(stripeKeyMode('sk_live_abc')).toBe('live');
    expect(stripeKeyMode('rk_test_abc')).toBe('test');
    expect(stripeKeyMode('sk_test_abc')).toBe('test');
    expect(stripeKeyMode('')).toBeNull();
    expect(stripeKeyMode(undefined)).toBeNull();
    expect(stripeKeyMode('whsec_abc')).toBeNull();
  });

  it('live key + live row / test key + test row pass', () => {
    expect(checkModeConsistency('live', true).ok).toBe(true);
    expect(checkModeConsistency('test', false).ok).toBe(true);
  });

  it('cross-mode and unclassified rows are refused', () => {
    expect(checkModeConsistency('live', false)).toMatchObject({ ok: false, code: 'cross_mode' });
    expect(checkModeConsistency('test', true)).toMatchObject({ ok: false, code: 'cross_mode' });
    expect(checkModeConsistency('live', null)).toMatchObject({ ok: false, code: 'row_mode_unclassified' });
    expect(checkModeConsistency(null, true)).toMatchObject({ ok: false, code: 'key_mode_unknown' });
  });
});

describe('action preconditions', () => {
  it('processing + approved is executable', () => {
    expect(checkActionPreconditions(ACTION, APPROVED)).toEqual({ ok: true });
  });
  it('retry from unknown is allowed', () => {
    expect(checkActionPreconditions({ ...ACTION, state: 'unknown' }, APPROVED)).toEqual({ ok: true });
  });
  it.each(['requested', 'awaiting_approval', 'failed', 'rejected'])('%s is not executable', (state) => {
    expect(checkActionPreconditions({ ...ACTION, state }, APPROVED)).toMatchObject({ ok: false, code: 'not_executable' });
  });
  it('succeeded / succeeded_at_provider are reported distinctly (money moved; not retryable)', () => {
    expect(checkActionPreconditions({ ...ACTION, state: 'succeeded' }, APPROVED)).toMatchObject({ ok: false, code: 'already_succeeded' });
    expect(checkActionPreconditions({ ...ACTION, state: 'succeeded_at_provider' }, APPROVED)).toMatchObject({ ok: false, code: 'succeeded_at_provider' });
  });
  it('wrong action type / subject / missing action are refused', () => {
    expect(checkActionPreconditions({ ...ACTION, action_type: 'payout_release' }, APPROVED)).toMatchObject({ ok: false, code: 'wrong_action_type' });
    expect(checkActionPreconditions({ ...ACTION, subject_kind: 'transfer' }, APPROVED)).toMatchObject({ ok: false, code: 'bad_subject' });
    expect(checkActionPreconditions(null, APPROVED)).toMatchObject({ ok: false, code: 'action_not_found' });
  });
  it('no approved approval → not_approved (pending/denied/stale do not count)', () => {
    expect(checkActionPreconditions(ACTION, [])).toMatchObject({ ok: false, code: 'not_approved' });
    expect(checkActionPreconditions(ACTION, null)).toMatchObject({ ok: false, code: 'not_approved' });
    expect(checkActionPreconditions(ACTION, [{ id: 'y', state: 'pending' }, { id: 'z', state: 'denied' }]))
      .toMatchObject({ ok: false, code: 'not_approved' });
  });
});

describe('payment preconditions', () => {
  it('succeeded live payment with a PI is refundable', () => {
    expect(checkPaymentPreconditions(PAYMENT, 'live')).toEqual({ ok: true, kind: 'refundable', payment_intent: 'pi_123abc' });
  });
  it('already refunded locally is an idempotent success, not an error', () => {
    expect(checkPaymentPreconditions({ ...PAYMENT, status: 'refunded' }, 'live')).toEqual({ ok: true, kind: 'already_refunded_locally' });
  });
  it('pending/failed payments, missing PI, missing row are refused', () => {
    expect(checkPaymentPreconditions({ ...PAYMENT, status: 'pending' }, 'live')).toMatchObject({ ok: false, code: 'payment_not_succeeded' });
    expect(checkPaymentPreconditions({ ...PAYMENT, stripe_payment_intent_id: null }, 'live')).toMatchObject({ ok: false, code: 'no_payment_intent' });
    expect(checkPaymentPreconditions(null, 'live')).toMatchObject({ ok: false, code: 'payment_not_found' });
  });
  it('mode mismatch is refused before any Stripe call', () => {
    expect(checkPaymentPreconditions({ ...PAYMENT, stripe_livemode: false }, 'live')).toMatchObject({ ok: false, code: 'cross_mode' });
    expect(checkPaymentPreconditions({ ...PAYMENT, stripe_livemode: null }, 'live')).toMatchObject({ ok: false, code: 'row_mode_unclassified' });
  });
});

describe('Stripe request body — full refunds only', () => {
  const base = { actionId: ACTION_ID, paymentId: PAYMENT_ID, paymentIntent: 'pi_123abc' };

  it('sends the full amount explicitly; carries metadata and source', () => {
    const b = planRefundBody({ ...base, amountCents: 5000, reasonCode: 'duplicate' });
    expect(b).toEqual({
      payment_intent: 'pi_123abc',
      amount: '5000',
      reason: 'duplicate',
      'metadata[ops_action_id]': ACTION_ID,
      'metadata[payment_id]': PAYMENT_ID,
      'metadata[source]': 'ops-refund-execute',
    });
  });

  it('has no partial mode: a non-positive or non-integer amount is refused, never omitted', () => {
    expect(() => planRefundBody({ ...base, amountCents: 0, reasonCode: null })).toThrow();
    expect(() => planRefundBody({ ...base, amountCents: 12.5, reasonCode: null })).toThrow();
    expect(() => planRefundBody({ ...base, amountCents: -1, reasonCode: null })).toThrow();
    expect(() => planRefundBody({ ...base, amountCents: Number.NaN, reasonCode: null })).toThrow();
  });

  it('unknown reason codes fall back to requested_by_customer', () => {
    expect(planRefundBody({ ...base, amountCents: 5000, reasonCode: 'buyer_unhappy' }).reason).toBe('requested_by_customer');
    expect(planRefundBody({ ...base, amountCents: 5000, reasonCode: 'fraudulent' }).reason).toBe('fraudulent');
    expect(planRefundBody({ ...base, amountCents: 5000, reasonCode: undefined }).reason).toBe('requested_by_customer');
  });
});

describe('Stripe outcome classification → ops.action state', () => {
  const stripeErr = (status: number, error: Record<string, unknown>) => ({ ok: false, status, data: { error } });

  it('2xx → created (an object exists; its status is classified separately)', () => {
    const v = classifyRefundCreate({ ok: true, status: 200, data: { id: 're_1', status: 'succeeded', amount: 5000, currency: 'usd' } });
    expect(v).toMatchObject({ kind: 'created', refund: { id: 're_1' } });
    const p = classifyRefundCreate({ ok: true, status: 200, data: { id: 're_2', status: 'pending' } });
    expect(p).toMatchObject({ kind: 'created', refund: { status: 'pending' } });
  });

  it('transport error → unknown/network', () => {
    expect(classifyRefundCreate(new Error('fetch failed'))).toMatchObject({ kind: 'unknown', errorClass: 'network' });
  });

  it('5xx / api_error → unknown/api_error', () => {
    expect(classifyRefundCreate(stripeErr(502, { type: 'api_error' }))).toMatchObject({ kind: 'unknown', errorClass: 'api_error' });
    expect(classifyRefundCreate(stripeErr(200 + 300, { type: 'api_connection_error' }))).toMatchObject({ kind: 'unknown', errorClass: 'api_error' });
  });

  it('transient 4xx (429, 409 key-in-use, balance_insufficient) → unknown, not terminal', () => {
    expect(classifyRefundCreate(stripeErr(429, { type: 'rate_limit_error' }))).toMatchObject({ kind: 'unknown', errorClass: 'rate_limited' });
    expect(classifyRefundCreate(stripeErr(409, { code: 'idempotency_key_in_use' }))).toMatchObject({ kind: 'unknown', errorClass: 'idempotency_in_use' });
    expect(classifyRefundCreate(stripeErr(402, { code: 'balance_insufficient' }))).toMatchObject({ kind: 'unknown', errorClass: 'balance_insufficient' });
  });

  it('charge_already_refunded → resolve by listing', () => {
    expect(classifyRefundCreate(stripeErr(400, { type: 'invalid_request_error', code: 'charge_already_refunded', message: 'Charge ch_1 has already been refunded.' })))
      .toMatchObject({ kind: 'already_refunded', code: 'charge_already_refunded' });
  });

  it('definite 4xx → failed with the Stripe code (never the key)', () => {
    expect(classifyRefundCreate(stripeErr(400, { type: 'invalid_request_error', code: 'idempotency_error', message: 'Keys for idempotent requests…' })))
      .toMatchObject({ kind: 'failed', errorClass: 'idempotency_conflict' });
    expect(classifyRefundCreate(stripeErr(400, { type: 'invalid_request_error', code: 'charge_disputed' })))
      .toMatchObject({ kind: 'failed', errorClass: 'charge_disputed' });
    expect(classifyRefundCreate(stripeErr(404, { type: 'invalid_request_error', code: 'resource_missing', message: 'No such payment_intent: pi_1' })))
      .toMatchObject({ kind: 'failed', errorClass: 'resource_missing' });
    expect(classifyRefundCreate(stripeErr(404, { type: 'invalid_request_error', code: 'resource_missing',
      message: "No such payment_intent: 'pi_1'; a similar object exists in test mode, but a live mode key was used" })))
      .toMatchObject({ kind: 'failed', errorClass: 'cross_mode' });
    expect(classifyRefundCreate(stripeErr(400, { type: 'invalid_request_error', code: 'parameter_invalid_integer', message: 'bad amount' })))
      .toMatchObject({ kind: 'failed', errorClass: 'invalid_request', code: 'parameter_invalid_integer' });
    const v = classifyRefundCreate(stripeErr(400, { message: 'Invalid API Key provided: sk_live_abcdef123' }));
    expect(v.kind).toBe('failed');
    if (v.kind === 'failed') expect(v.message).not.toContain('sk_live_abcdef123');
  });
});

const EXPECTED: RefundExpectation = { actionId: ACTION_ID, paymentIntent: 'pi_123abc', amountCents: 5000, currency: 'usd' };
const ours = (over: Partial<StripeRefundObject> = {}): StripeRefundObject => ({
  id: 're_ours', status: 'succeeded', amount: 5000, currency: 'usd', payment_intent: 'pi_123abc',
  metadata: { ops_action_id: ACTION_ID, source: 'ops-refund-execute' }, ...over,
});

describe('refund object classification — status AND identity', () => {
  it.each([
    ['succeeded', 'succeeded'], ['pending', 'pending'], ['requires_action', 'requires_action'],
    ['failed', 'failed'], ['canceled', 'canceled'], ['brand_new', 'unknown'], [undefined, 'unknown'],
  ] as const)('status %s → %s when identity matches', (status, verdict) => {
    expect(classifyRefundObject(ours({ status }), EXPECTED)).toBe(verdict);
  });

  it('identity mismatch wins over status', () => {
    expect(classifyRefundObject(ours({ amount: 4999 }), EXPECTED)).toBe('mismatch');
    expect(classifyRefundObject(ours({ payment_intent: 'pi_other' }), EXPECTED)).toBe('mismatch');
    expect(classifyRefundObject(ours({ currency: 'eur' }), EXPECTED)).toBe('mismatch');
    expect(classifyRefundObject(ours({ metadata: {} }), EXPECTED)).toBe('mismatch');
    expect(classifyRefundObject(null, EXPECTED)).toBe('mismatch');
    expect(classifyRefundObject({ id: 're_1', status: 'succeeded' }, EXPECTED)).toBe('mismatch');
  });

  it('currency compares case-insensitively; expanded payment_intent objects are accepted', () => {
    expect(classifyRefundObject(ours({ currency: 'USD' }), EXPECTED)).toBe('succeeded');
    expect(classifyRefundObject(ours({ payment_intent: { id: 'pi_123abc' } }), EXPECTED)).toBe('succeeded');
  });

  it('refundMismatch names every differing field', () => {
    expect(refundMismatch(ours(), EXPECTED)).toBeNull();
    expect(refundMismatch(ours({ amount: 1, currency: 'eur' }), EXPECTED)).toEqual({
      amount: { expected: 5000, actual: 1 },
      currency: { expected: 'usd', actual: 'eur' },
    });
  });
});

describe('resolving an ambiguous outcome from GET /v1/refunds', () => {
  const list: { data: StripeRefundObject[] } = { data: [
    ours({ id: 're_other', metadata: { source: 'dashboard' } }),
    ours(),
  ] };

  it('only a refund with our metadata AND matching facts counts', () => {
    expect(findExistingRefund(list, EXPECTED)?.id).toBe('re_ours');
    expect(findExistingRefund({ data: [ours({ id: 're_other', metadata: {} })] }, EXPECTED)).toBeNull();
    expect(findExistingRefund({ data: [ours({ amount: 100 })] }, EXPECTED)).toBeNull();
    expect(findExistingRefund({ data: [ours({ payment_intent: 'pi_x' })] }, EXPECTED)).toBeNull();
    expect(findExistingRefund(null, EXPECTED)).toBeNull();
    expect(findExistingRefund({ data: [] }, EXPECTED)).toBeNull();
  });

  it('a foreign refund is never adopted, even when it is the only one (charge_already_refunded path)', () => {
    expect(findExistingRefund({ data: [ours({ id: 're_dash', metadata: { source: 'dashboard' } })] }, EXPECTED)).toBeNull();
  });

  it('prefers a live/succeeded refund of ours over a failed one', () => {
    const l = { data: [ours({ id: 're_failed', status: 'failed' }), ours({ id: 're_live', status: 'pending' })] };
    expect(findExistingRefund(l, EXPECTED)?.id).toBe('re_live');
  });
});

describe('response status by recorded state', () => {
  it('200 / 202 / 422 / 502', () => {
    expect(httpStatusForState('succeeded')).toBe(200);
    expect(httpStatusForState('succeeded_at_provider')).toBe(200);
    expect(httpStatusForState('processing')).toBe(202);
    expect(httpStatusForState('failed')).toBe(422);
    expect(httpStatusForState('unknown')).toBe(502);
  });
});

describe('secret redaction', () => {
  it('strips Stripe keys and bearer tokens', () => {
    expect(sanitizeErrorMessage('used sk_live_ABC123 with Bearer eyJhbGci.xyz')).toBe('used [redacted] with Bearer [redacted]');
    expect(sanitizeErrorMessage('x'.repeat(600)).length).toBe(500);
  });
});
