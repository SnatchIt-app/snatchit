/**
 * ops-refund-execute/classify.ts — pure decision logic for the console refund
 * executor. No Deno globals, no I/O: this module is imported by the edge
 * (index.ts) AND by the root vitest suite (tests/ops-refund-classify.test.ts),
 * the same split `refund-execute/executor.ts` uses.
 *
 * Everything that decides WHAT to send to Stripe and HOW to read what came
 * back lives here so it can be tested deterministically; handler.ts runs the
 * flow over injected adapters and index.ts is the Deno shell around both.
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
//
// Since migration 118 the AUTHORITATIVE gate is `ops.executor_claim` (state,
// enabled flag, approval hash, lease — all evaluated in one transaction).
// These row-level checks are kept as the documented, testable mirror of that
// contract; handler.ts does not load ops.action / public.payments itself.
// ─────────────────────────────────────────────────────────────────────────────

/** States `ops.executor_claim` will hand to the executor. `succeeded_at_provider`
 *  is NOT retryable: the money moved; only the webhook / detector may close it. */
export const RETRYABLE_ACTION_STATES = ['processing', 'unknown'] as const;

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
      code: action.state === 'succeeded' ? 'already_succeeded'
          : action.state === 'succeeded_at_provider' ? 'succeeded_at_provider'
          : 'not_executable',
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
 * FULL REFUNDS ONLY. The local model has no refunded-amount column:
 * `payments.status` is the whole ledger and the `charge.refunded` webhook
 * flips it to `refunded` unconditionally, so a partial refund would be
 * recorded locally as a full one. `ops.executor_claim` rejects partials
 * server-side; `runRefundExecution` refuses them again (defense in depth).
 *
 * `amount` is sent EXPLICITLY (= the payment total) rather than relying on
 * Stripe's omit-means-full semantics: if the charge was partially refunded by
 * another route, omitting `amount` would refund only the remainder and mint a
 * refund object whose facts differ from the action. Sending the full amount
 * makes Stripe refuse (`amount_too_large` → failed) instead of creating money
 * movement the ledger cannot account for.
 */
export function planRefundBody(input: {
  actionId: string;
  paymentId: string;
  paymentIntent: string;
  amountCents: number;
  reasonCode: unknown;
}): Record<string, string> {
  if (!Number.isInteger(input.amountCents) || input.amountCents <= 0) {
    throw new Error('ops-refund-execute: refusing to plan a refund without a positive integer amount');
  }
  return {
    payment_intent: input.paymentIntent,
    amount: String(input.amountCents),
    reason: mapStripeReason(input.reasonCode),
    'metadata[ops_action_id]': input.actionId,
    'metadata[payment_id]': input.paymentId,
    'metadata[source]': 'ops-refund-execute',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Outcome classification
// ─────────────────────────────────────────────────────────────────────────────

export type OutcomeState = 'succeeded' | 'succeeded_at_provider' | 'failed' | 'unknown';

export interface StripeRefundObject {
  id?: string;
  /** pending | requires_action | succeeded | failed | canceled */
  status?: string;
  amount?: number;
  currency?: string;
  /** Stripe returns the id, or the expanded object when `expand[]` asks for it. */
  payment_intent?: string | { id?: string } | null;
  charge?: string | { id?: string } | null;
  failure_reason?: string | null;
  next_action?: Record<string, unknown> | null;
  metadata?: Record<string, string>;
}

/** What the claimed action says the refund MUST look like. */
export interface RefundExpectation {
  actionId: string;
  paymentIntent: string;
  amountCents: number;
  currency: string;
}

export type RefundObjectVerdict =
  | 'succeeded' | 'pending' | 'requires_action' | 'failed' | 'canceled' | 'mismatch' | 'unknown';

export type RefundMismatch = Record<string, { expected: unknown; actual: unknown }>;

function stripeId(v: string | { id?: string } | null | undefined): string | null {
  if (typeof v === 'string') return v;
  if (v && typeof v === 'object' && typeof v.id === 'string') return v.id;
  return null;
}

/**
 * Identity check for ANY refund object the executor acts on — created or
 * adopted. A refund whose facts differ from the action (other PI, other
 * amount, other currency, other/no ops_action_id) is never ours to record as
 * success, whatever its status. Returns null when every fact matches.
 */
export function refundMismatch(
  refund: StripeRefundObject | null | undefined,
  expected: RefundExpectation,
): RefundMismatch | null {
  const mm: RefundMismatch = {};
  if (!refund || typeof refund !== 'object') {
    return { object: { expected: 'refund', actual: refund === null ? null : typeof refund } };
  }
  const pi = stripeId(refund.payment_intent);
  if (pi !== expected.paymentIntent) mm.payment_intent = { expected: expected.paymentIntent, actual: pi };
  if (refund.amount !== expected.amountCents) mm.amount = { expected: expected.amountCents, actual: refund.amount ?? null };
  const cur = typeof refund.currency === 'string' ? refund.currency.toLowerCase() : null;
  if (cur !== expected.currency.toLowerCase()) mm.currency = { expected: expected.currency.toLowerCase(), actual: cur };
  const meta = refund.metadata?.ops_action_id ?? null;
  if (meta !== expected.actionId) mm.ops_action_id = { expected: expected.actionId, actual: meta };
  return Object.keys(mm).length === 0 ? null : mm;
}

/**
 * Classifies the refund OBJECT, not the HTTP status that carried it. A 2xx
 * from `POST /v1/refunds` (or a listed refund) can be pending,
 * requires_action, failed or canceled — only `succeeded` is success.
 * Identity is checked first: a mismatching object is `mismatch` regardless
 * of its status.
 */
export function classifyRefundObject(
  refund: StripeRefundObject | null | undefined,
  expected: RefundExpectation,
): RefundObjectVerdict {
  if (refundMismatch(refund, expected) !== null) return 'mismatch';
  switch (refund!.status) {
    case 'succeeded':       return 'succeeded';
    case 'pending':         return 'pending';
    case 'requires_action': return 'requires_action';
    case 'failed':          return 'failed';
    case 'canceled':        return 'canceled';
    default:                return 'unknown';
  }
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
 *   • 2xx                                   → created (Stripe holds an object; its
 *                                             STATUS decides — see classifyRefundObject)
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
 * Returns ONLY a refund that (a) carries `metadata.ops_action_id ===
 * expected.actionId` and (b) passes `refundMismatch` (PI, amount, currency).
 * A refund created by another route (Dashboard, refund-execute) is never
 * adopted: the money may be back, but it is not THIS action's money leg and
 * the `charge.refunded` webhook settles the local row on its own.
 *
 * When several of our refunds exist (should not happen — one key per
 * action) the live/succeeded one is preferred over failed/canceled ones so
 * a retry never overlooks a refund that is still in flight.
 */
export function findExistingRefund(
  list: { data?: StripeRefundObject[] } | null | undefined,
  expected: RefundExpectation,
): StripeRefundObject | null {
  const rows = Array.isArray(list?.data) ? list!.data! : [];
  const ours = rows.filter((r) =>
    r?.metadata?.ops_action_id === expected.actionId && refundMismatch(r, expected) === null);
  if (ours.length === 0) return null;
  const rank = (r: StripeRefundObject) =>
    r.status === 'succeeded' ? 0 : r.status === 'pending' || r.status === 'requires_action' ? 1 : 2;
  return ours.slice().sort((a, b) => rank(a) - rank(b))[0];
}

/** Any refund on the intent that carries our metadata, validated or not (diagnostics only). */
export function findOurRefundUnvalidated(
  list: { data?: StripeRefundObject[] } | null | undefined,
  actionId: string,
): StripeRefundObject | null {
  const rows = Array.isArray(list?.data) ? list!.data! : [];
  return rows.find((r) => r?.metadata?.ops_action_id === actionId) ?? null;
}

export function providerResult(refund: StripeRefundObject): Record<string, unknown> {
  return {
    stripe_refund_id: refund.id ?? null,
    refund_status: refund.status ?? null,
    amount: typeof refund.amount === 'number' ? refund.amount : null,
    currency: refund.currency ?? null,
    charge: stripeId(refund.charge),
    payment_intent: stripeId(refund.payment_intent),
  };
}

/** HTTP status for the response, by recorded state. `processing` = refund in flight at Stripe. */
export function httpStatusForState(state: OutcomeState | 'processing'): number {
  switch (state) {
    case 'succeeded':
    case 'succeeded_at_provider':
      return 200;
    case 'processing':
      return 202;
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
