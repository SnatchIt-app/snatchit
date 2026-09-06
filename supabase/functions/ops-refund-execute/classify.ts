/**
 * ops-refund-execute/classify.ts — pure decision logic for the console refund
 * executor. No Deno globals, no I/O: this module is imported by the edge
 * (index.ts) AND by the root vitest suite (tests/ops-refund-classify.test.ts),
 * the same split `refund-execute/executor.ts` uses.
 *
 * Everything that decides WHAT to send to Stripe and HOW to read what came
 * back lives here so it can be tested deterministically; index.ts is the thin
 * I/O shell around it.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Request guard — the caller may ONLY name the action
// ─────────────────────────────────────────────────────────────────────────────

const NIL_UUID = '00000000-0000-0000-0000-000000000000';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(v: unknown): v is string {
  return typeof v === 'string' && UUID_RE.test(v) && v !== NIL_UUID;
}

/**
 * Mirrors `refund-execute/executor.ts` FORBIDDEN_REQUEST_KEYS and widens it to
 * every way a client could try to name the money or its destination. The
 * payment, PaymentIntent and amount are resolved from `ops.action` /
 * `public.payments` inside the database — a request that also carries one is
 * a confused-deputy attempt and is refused, not ignored.
 */
export const FORBIDDEN_REQUEST_KEYS = [
  'payment_id',
  'payment_intent',
  'payment_intent_id',
  'stripe_payment_intent_id',
  'charge',
  'charge_id',
  'stripe_charge_id',
  'refund_id',
  'stripe_refund_id',
  'stripe_refund_ref',
  'amount',
  'amount_cents',
  'amount_minor',
  'currency',
  'destination',
  'reverse_transfer',
  'refund_application_fee',
] as const;

export type RequestVerdict =
  | { ok: true; action_id: string }
  | { ok: false; code: 'client_supplied_payment_reference' | 'unexpected_field' | 'invalid_input'; detail: string };

export function assertNoClientPaymentReference(
  body: Record<string, unknown> | null | undefined,
): { ok: true } | { ok: false; code: 'client_supplied_payment_reference'; detail: string } {
  if (!body || typeof body !== 'object') return { ok: true };
  for (const k of FORBIDDEN_REQUEST_KEYS) {
    if (Object.prototype.hasOwnProperty.call(body, k) && body[k] != null) {
      return {
        ok: false,
        code: 'client_supplied_payment_reference',
        detail: `the caller may not name the money: '${k}' is resolved from ops.action / public.payments, never from the request`,
      };
    }
  }
  return { ok: true };
}

/** Full request validation: forbidden keys → unknown keys → action_id shape. */
export function validateRequest(body: unknown): RequestVerdict {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return { ok: false, code: 'invalid_input', detail: 'body must be a JSON object' };
  }
  const rec = body as Record<string, unknown>;
  const guard = assertNoClientPaymentReference(rec);
  if (!guard.ok) return guard;
  for (const k of Object.keys(rec)) {
    if (k !== 'action_id') {
      return { ok: false, code: 'unexpected_field', detail: `only 'action_id' is accepted; got '${k}'` };
    }
  }
  if (!isUuid(rec.action_id)) {
    return { ok: false, code: 'invalid_input', detail: 'action_id must be a uuid' };
  }
  return { ok: true, action_id: rec.action_id };
}

// ─────────────────────────────────────────────────────────────────────────────
// Stripe idempotency key — stable across retries, that is the whole point
// ─────────────────────────────────────────────────────────────────────────────

export function buildOpsRefundIdempotencyKey(actionId: string): string {
  if (!isUuid(actionId)) {
    throw new Error('ops-refund-execute: refusing to build an idempotency key from a non-uuid action id');
  }
  return `ops_action_${actionId}`;
}

// ─────────────────────────────────────────────────────────────────────────────
// Live/test mode boundary — fail closed on cross-mode
// ─────────────────────────────────────────────────────────────────────────────

export type StripeKeyMode = 'live' | 'test';

/** Derives the mode from the key PREFIX only; never returns any part of the key. */
export function stripeKeyMode(secretKey: string | undefined | null): StripeKeyMode | null {
  if (!secretKey) return null;
  if (/^(sk|rk)_live_/.test(secretKey)) return 'live';
  if (/^(sk|rk)_test_/.test(secretKey)) return 'test';
  return null;
}

/**
 * `payments.stripe_livemode` (migration 045) must be a boolean that agrees
 * with the key mode. null = unclassified → NOT actionable (the
 * `rowIsLiveActionable` rule in _shared/payout-logic.ts); a live key on a
 * test row or vice versa is a data-integrity fault, never "continue".
 */
export function checkModeConsistency(
  keyMode: StripeKeyMode | null,
  stripeLivemode: boolean | null | undefined,
): { ok: true } | { ok: false; code: 'key_mode_unknown' | 'row_mode_unclassified' | 'cross_mode'; detail: string } {
  if (keyMode === null) {
    return { ok: false, code: 'key_mode_unknown', detail: 'STRIPE_SECRET_KEY mode could not be determined' };
  }
  if (typeof stripeLivemode !== 'boolean') {
    return { ok: false, code: 'row_mode_unclassified', detail: 'payments.stripe_livemode is null; row is not actionable' };
  }
  if ((keyMode === 'live') !== stripeLivemode) {
    return {
      ok: false,
      code: 'cross_mode',
      detail: `payment row is ${stripeLivemode ? 'live' : 'test'} but the configured Stripe key is ${keyMode}`,
    };
  }
  return { ok: true };
}

/** Stripe's wrong-mode signature (same regex as _shared/payout-logic.ts). */
export function isCrossModeStripeMessage(message: string): boolean {
  return /similar object exists in (test|live) mode/i.test(message);
}

// ─────────────────────────────────────────────────────────────────────────────
// Preconditions on the action / approval / payment
// ─────────────────────────────────────────────────────────────────────────────

export const RETRYABLE_ACTION_STATES = ['processing', 'succeeded_at_provider', 'unknown'] as const;

export interface ActionRow {
  id: string;
  action_type: string;
  subject_kind: string;
  subject_id: string | null;
  state: string;
  params: Record<string, unknown> | null;
  result: Record<string, unknown> | null;
  approval_id: string | null;
}

export interface ApprovalRow {
  id: string;
  state: string;
}

export interface PaymentRow {
  id: string;
  status: string;
  total: number;
  stripe_payment_intent_id: string | null;
  stripe_livemode: boolean | null;
}

export type PreconditionVerdict =
  | { ok: true }
  | { ok: false; code: string; detail: string };

export function checkActionPreconditions(
  action: ActionRow | null | undefined,
  approvals: ApprovalRow[] | null | undefined,
): PreconditionVerdict {
  if (!action) return { ok: false, code: 'action_not_found', detail: 'no ops.action with that id' };
  if (action.action_type !== 'refund_execute') {
    return { ok: false, code: 'wrong_action_type', detail: `action is ${action.action_type}, not refund_execute` };
  }
  if (action.subject_kind !== 'payment' || !isUuid(action.subject_id)) {
    return { ok: false, code: 'bad_subject', detail: 'action subject is not a payment id' };
  }
  if (!(RETRYABLE_ACTION_STATES as readonly string[]).includes(action.state)) {
    return {
      ok: false,
      code: action.state === 'succeeded' ? 'already_succeeded' : 'not_executable',
      detail: `action is ${action.state}; only ${RETRYABLE_ACTION_STATES.join('|')} can be executed`,
    };
  }
  const approved = (approvals ?? []).some((a) => a.state === 'approved');
  if (!approved) {
    return { ok: false, code: 'not_approved', detail: 'no ops.approval in state approved for this action' };
  }
  return { ok: true };
}

export type PaymentVerdict =
  | { ok: true; kind: 'refundable'; payment_intent: string }
  | { ok: true; kind: 'already_refunded_locally' }
  | { ok: false; code: string; detail: string };

export function checkPaymentPreconditions(
  payment: PaymentRow | null | undefined,
  keyMode: StripeKeyMode | null,
): PaymentVerdict {
  if (!payment) return { ok: false, code: 'payment_not_found', detail: 'no public.payments row for action.subject_id' };
  if (payment.status === 'refunded') return { ok: true, kind: 'already_refunded_locally' };
  if (payment.status !== 'succeeded') {
    return { ok: false, code: 'payment_not_succeeded', detail: `payment is ${payment.status}; only a succeeded payment can be refunded` };
  }
  if (!payment.stripe_payment_intent_id || !/^pi_[A-Za-z0-9]+$/.test(payment.stripe_payment_intent_id)) {
    return { ok: false, code: 'no_payment_intent', detail: 'payment has no Stripe PaymentIntent id' };
  }
  const mode = checkModeConsistency(keyMode, payment.stripe_livemode);
  if (!mode.ok) return { ok: false, code: mode.code, detail: mode.detail };
  return { ok: true, kind: 'refundable', payment_intent: payment.stripe_payment_intent_id };
}

// ─────────────────────────────────────────────────────────────────────────────
// The Stripe request body
// ─────────────────────────────────────────────────────────────────────────────

export type StripeRefundReason = 'duplicate' | 'fraudulent' | 'requested_by_customer';

export function mapStripeReason(reasonCode: unknown): StripeRefundReason {
  return reasonCode === 'duplicate' || reasonCode === 'fraudulent' || reasonCode === 'requested_by_customer'
    ? reasonCode
    : 'requested_by_customer';
}

/**
 * Partial vs full: `action.result.amount_cents` was fixed by
 * ops.action_dispatch (coalesce(params.amount_cents, payments.total)). Only a
 * strictly-smaller amount is sent; equal-or-larger (or absent / malformed)
 * means a full refund and `amount` is omitted, which is Stripe's own full-
 * refund semantics.
 */
export function planRefundBody(input: {
  actionId: string;
  paymentId: string;
  paymentIntent: string;
  paymentTotal: number;
  amountCents: unknown;
  reasonCode: unknown;
}): Record<string, string> {
  const body: Record<string, string> = {
    payment_intent: input.paymentIntent,
    reason: mapStripeReason(input.reasonCode),
    'metadata[ops_action_id]': input.actionId,
    'metadata[payment_id]': input.paymentId,
    'metadata[source]': 'ops-refund-execute',
  };
  const amt = typeof input.amountCents === 'number' && Number.isInteger(input.amountCents) ? input.amountCents : null;
  if (amt !== null && amt > 0 && amt < input.paymentTotal) {
    body.amount = String(amt);
  }
  return body;
}

// ─────────────────────────────────────────────────────────────────────────────
// Outcome classification
// ─────────────────────────────────────────────────────────────────────────────

export type OutcomeState = 'succeeded' | 'succeeded_at_provider' | 'failed' | 'unknown';

export interface StripeRefundObject {
  id?: string;
  status?: string;
  amount?: number;
  currency?: string;
  metadata?: Record<string, string>;
}

export interface StripeErrorBody {
  type?: string;
  code?: string;
  message?: string;
}

export type CreateVerdict =
  /** 2xx — Stripe holds a refund object. */
  | { kind: 'created'; refund: StripeRefundObject }
  /** Definite 4xx: nothing was created; but a refund may already exist → resolve by listing. */
  | { kind: 'already_refunded'; code: string; message: string }
  /** Definite 4xx: nothing was created and nothing will be. Terminal. */
  | { kind: 'failed'; errorClass: string; code: string; message: string }
  /** Transport / 5xx / transient: Stripe MAY hold a refund → resolve by listing, else 'unknown'. */
  | { kind: 'unknown'; errorClass: string; message: string };

/**
 * Classifies the `POST /v1/refunds` response. Follows
 * `refund-execute/executor.ts#classifyStripeRefundError` for the error
 * classes, mapped onto the ops.action state machine:
 *
 *   • 2xx                                   → created (succeeded_at_provider)
 *   • charge_already_refunded               → already_refunded (list, adopt existing re_)
 *   • network / 5xx / api_error / 429 / 409 idempotency_key_in_use /
 *     balance_insufficient                  → unknown (not settled; retry is safe)
 *   • every other 4xx                       → failed (terminal; error code+message, never the key)
 *
 * 429 / 409-in-use / balance_insufficient are 4xx but NOT definite failures of
 * the refund — they are "try again later". `failed` is terminal in
 * ops.record_action_outcome (sets completed_at), so they map to `unknown`,
 * which the console shows as unresolved and allows a founder to retry under
 * the same idempotency key.
 */
export function classifyRefundCreate(
  input: { ok: boolean; status: number; data: unknown } | Error,
): CreateVerdict {
  if (input instanceof Error) {
    return { kind: 'unknown', errorClass: 'network', message: sanitizeErrorMessage(input.message) };
  }
  if (input.ok) {
    return { kind: 'created', refund: (input.data ?? {}) as StripeRefundObject };
  }
  const err = ((input.data as { error?: StripeErrorBody } | null)?.error) ?? {};
  const status = input.status ?? 0;
  const code = err.code ?? '';
  const type = err.type ?? '';
  const message = sanitizeErrorMessage(err.message ?? `HTTP ${status}`);

  if (code === 'charge_already_refunded') {
    return { kind: 'already_refunded', code, message };
  }
  if (status >= 500 || type === 'api_error' || type === 'api_connection_error') {
    return { kind: 'unknown', errorClass: 'api_error', message };
  }
  if (status === 429 || code === 'rate_limit' || type === 'rate_limit_error') {
    return { kind: 'unknown', errorClass: 'rate_limited', message };
  }
  if (status === 409 || code === 'idempotency_key_in_use') {
    return { kind: 'unknown', errorClass: 'idempotency_in_use', message };
  }
  if (code === 'balance_insufficient') {
    return { kind: 'unknown', errorClass: 'balance_insufficient', message };
  }
  if (code === 'idempotency_error') {
    // Same key, different parameters — a code bug or mutated terms. Never retry blind.
    return { kind: 'failed', errorClass: 'idempotency_conflict', code, message };
  }
  if (code === 'charge_disputed') return { kind: 'failed', errorClass: 'charge_disputed', code, message };
  if (code === 'resource_missing') {
    return { kind: 'failed', errorClass: isCrossModeStripeMessage(message) ? 'cross_mode' : 'resource_missing', code, message };
  }
  if (type === 'invalid_request_error' || (status >= 400 && status < 500)) {
    return { kind: 'failed', errorClass: 'invalid_request', code: code || type || `http_${status}`, message };
  }
  return { kind: 'failed', errorClass: 'unknown_error', code: code || `http_${status}`, message };
}

/**
 * Resolve an ambiguous outcome from `GET /v1/refunds?payment_intent=…`.
 * `strict` (the unknown path) requires metadata.ops_action_id === actionId —
 * a refund created by another route must NOT be claimed as ours. The
 * charge_already_refunded path is non-strict: the money is back regardless of
 * who sent it, so any existing refund settles the action (ours preferred).
 */
export function findExistingRefund(
  list: { data?: StripeRefundObject[] } | null | undefined,
  actionId: string,
  strict: boolean,
): StripeRefundObject | null {
  const rows = Array.isArray(list?.data) ? list!.data! : [];
  const ours = rows.find((r) => r?.metadata?.ops_action_id === actionId) ?? null;
  if (ours) return ours;
  if (strict) return null;
  return rows.find((r) => typeof r?.id === 'string') ?? null;
}

export function providerResult(refund: StripeRefundObject): Record<string, unknown> {
  return {
    stripe_refund_id: refund.id ?? null,
    refund_status: refund.status ?? null,
    amount: typeof refund.amount === 'number' ? refund.amount : null,
    currency: refund.currency ?? null,
  };
}

/** HTTP status for the terminal response, by recorded state. */
export function httpStatusForState(state: OutcomeState): number {
  switch (state) {
    case 'succeeded':
    case 'succeeded_at_provider':
      return 200;
    case 'failed':
      return 422;
    case 'unknown':
      return 502;
  }
}

/**
 * Strip anything that looks like a Stripe key or bearer token from a message
 * before it is persisted or logged. Stripe error messages never include the
 * key, but a transport error may echo request headers.
 */
export function sanitizeErrorMessage(message: string): string {
  return String(message)
    .replace(/\b(sk|rk|pk)_(live|test)_[A-Za-z0-9]+/g, '[redacted]')
    .replace(/Bearer\s+[A-Za-z0-9._-]+/g, 'Bearer [redacted]')
    .slice(0, 500);
}
