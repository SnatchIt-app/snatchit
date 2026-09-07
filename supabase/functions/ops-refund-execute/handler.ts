/**
 * ops-refund-execute/handler.ts — the executor flow, over injected adapters.
 *
 * Pure TypeScript: no Deno globals, no `serve`, no fetch, no supabase-js.
 * index.ts (Deno) builds the real adapters; tests/ops-refund-handler.test.ts
 * (vitest, Node) builds fakes. Everything that decides the ORDER of database
 * writes and Stripe calls lives here so that the ordering — the thing the
 * money depends on — is executable in CI without a Stripe account.
 *
 * THE FLOW
 *   claim (ops.executor_claim: state ∈ processing|unknown, enabled flag,
 *   approval hash, lease — one transaction)
 *     → refused                → 409 {reason}; NO Stripe call
 *     → already_refunded_local → record succeeded; 200; NO Stripe call
 *     → claimed
 *        → partial amount?     → record failed; 422; NO Stripe call
 *        → previously sent?    → GET /v1/refunds FIRST; adopt ours (validated)
 *                                 in any non-failed/non-canceled state; never
 *                                 POST again over a live refund
 *        → record processing   → if this write fails, NO Stripe call
 *        → POST /v1/refunds    → Idempotency-Key ops_action_<id>
 *        → classify the OBJECT → succeeded_at_provider | processing | failed | unknown
 *        → record outcome      → refused by a monotonic RPC = log + 409, never throw
 *
 * NEVER: mark success from an HTTP 2xx alone; adopt a refund whose PI /
 * amount / currency / ops_action_id differ from the claim; POST while a
 * refund with our metadata is pending/requires_action/succeeded; throw
 * past this function (every path returns a response).
 */

import {
  type OutcomeState,
  type RefundExpectation,
  type StripeRefundObject,
  buildOpsRefundIdempotencyKey,
  classifyRefundCreate,
  classifyRefundObject,
  findExistingRefund,
  findOurRefundUnvalidated,
  httpStatusForState,
  isUuid,
  planRefundBody,
  providerResult,
  refundMismatch,
  sanitizeErrorMessage,
} from './classify.ts';

// ─────────────────────────────────────────────────────────────────────────────
// Adapter contracts (index.ts implements them over supabase-js / _shared/stripe)
// ─────────────────────────────────────────────────────────────────────────────

/** Lease the claim RPC takes on the action; a crashed executor frees it by expiry. */
export const CLAIM_LEASE_SECONDS = 120;

export type ClaimRefusalReason =
  | 'disabled' | 'paused' | 'not_found' | 'wrong_type' | 'terminal' | 'not_executable'
  | 'approval_missing' | 'approval_stale' | 'claim_busy'
  | 'succeeded_at_provider' | 'already_refunded_locally'
  | 'payment_missing' | 'payment_not_refundable';

/** `ops.executor_claim(p_action_id, p_lease_seconds)` → jsonb, status = claimed. */
export interface ClaimedAction {
  status: 'claimed';
  action_id: string;
  payment_id: string;
  stripe_payment_intent_id: string;
  /** ALWAYS the full payment total (partials are rejected server-side). */
  amount_cents: number;
  /** `public.payments.total` — the handler refuses if amount_cents differs (defense in depth). */
  payment_total_cents: number;
  currency: string;
  reason_code: string | null;
  /** A prior attempt recorded `processing` with stripe_request_started_at, or attempt > 1. */
  previously_sent: boolean;
  provider_ref: string | null;
  attempt: number;
  /** Optional: `payments.stripe_livemode`; checked against deps.stripeKeyMode when both are present. */
  stripe_livemode?: boolean | null;
}

export interface ClaimRefused {
  status: 'refused';
  /** Any unlisted reason is still a refusal (409); the union documents the known set. */
  reason: ClaimRefusalReason | (string & {});
  detail?: string;
  /** Diagnostics the RPC may attach; passed through to the response, never acted on. */
  state?: string;
  claimed_until?: string;
}

export type ClaimResult = ClaimedAction | ClaimRefused;

/** States this executor records through `ops.record_action_outcome`. */
export type RecordableState = OutcomeState | 'processing';

/** `ops.record_action_outcome(...)` → jsonb. `refused` = the RPC is monotonic and kept its state. */
export type RecordOutcomeResult =
  | { status: 'ok'; action_id?: string; state?: string }
  | { status: 'idempotent_replay'; state?: string }
  | { status: 'refused'; reason: string; state?: string };

export interface OpsDb {
  claim(actionId: string, leaseSeconds: number): Promise<ClaimResult>;
  recordOutcome(
    actionId: string,
    state: RecordableState,
    result: Record<string, unknown> | null,
    error: string | null,
    providerRef: string | null,
  ): Promise<RecordOutcomeResult>;
}

/** Shape of `_shared/stripe.ts#stripeFetchRaw`. `data` is Stripe's parsed JSON body. */
export interface StripeTransportResult {
  ok: boolean;
  status: number;
  data: unknown;
}

export interface StripeListResult {
  ok: boolean;
  status?: number;
  data: StripeRefundObject[];
  error?: string;
}

export interface StripeApi {
  /** POST /v1/refunds. May throw on transport failure (treated as unknown). */
  createRefund(body: Record<string, string>, idempotencyKey: string): Promise<StripeTransportResult>;
  /** GET /v1/refunds?payment_intent=… (limit 100). May throw on transport failure. */
  listRefunds(paymentIntent: string): Promise<StripeListResult>;
}

export interface Logger {
  info(event: string, fields?: Record<string, unknown>): void;
  warn(event: string, fields?: Record<string, unknown>): void;
  error(event: string, fields?: Record<string, unknown>): void;
}

export interface Deps {
  db: OpsDb;
  stripe: StripeApi;
  now: () => Date;
  log: Logger;
  /** Optional pager (Sentry). Called for failed/unknown/unrecorded outcomes. Never awaited-throwing. */
  alert?: (event: string, message: string, ctx: Record<string, unknown>) => Promise<void> | void;
  /** Optional live/test mode of the configured key; validated against claim.stripe_livemode when both exist. */
  stripeKeyMode?: 'live' | 'test' | null;
}

export interface Caller {
  userId: string;
  role: string;
  aal: string;
}

export interface RefundExecutionInput {
  actionId: string;
  caller: Caller;
}

export interface RefundExecutionResponse {
  http: number;
  body: Record<string, unknown>;
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

type Outcome = {
  state: RecordableState;
  result: Record<string, unknown> | null;
  error: string | null;
  providerRef: string | null;
  message: string;
};

const noopLog: Logger = { info() {}, warn() {}, error() {} };

function errMessage(err: unknown): string {
  return sanitizeErrorMessage(err instanceof Error ? err.message : String(err));
}

/** recordOutcome that never throws: a thrown adapter error becomes {status:'error'}. */
async function safeRecord(
  deps: Deps,
  actionId: string,
  o: Omit<Outcome, 'message'>,
): Promise<RecordOutcomeResult | { status: 'error'; message: string }> {
  try {
    const r = await deps.db.recordOutcome(actionId, o.state, o.result, o.error, o.providerRef);
    if (!r || typeof r !== 'object' || typeof (r as { status?: unknown }).status !== 'string') {
      return { status: 'error', message: 'record_action_outcome returned no status' };
    }
    return r;
  } catch (err) {
    return { status: 'error', message: errMessage(err) };
  }
}

/** Map a validated refund object (created or adopted) onto the action state machine. */
function outcomeFromRefund(
  refund: StripeRefundObject,
  expected: RefundExpectation,
  extra: Record<string, unknown>,
): Outcome {
  const verdict = classifyRefundObject(refund, expected);
  const base = { ...providerResult(refund), ...extra };
  const id = typeof refund.id === 'string' ? refund.id : null;
  switch (verdict) {
    case 'succeeded':
      return {
        state: 'succeeded_at_provider', result: base, error: null, providerRef: id,
        message: 'refund succeeded at Stripe; local payment state follows via charge.refunded webhook',
      };
    case 'pending':
    case 'requires_action':
      return {
        state: 'processing',
        result: {
          ...base,
          provider_ref: id,
          needs_action: verdict === 'requires_action',
          ...(refund.next_action ? { next_action: refund.next_action } : {}),
        },
        error: null,
        providerRef: id,
        message: verdict === 'requires_action'
          ? 'refund requires customer action at Stripe; in flight, not success'
          : 'refund pending at Stripe; in flight, not success',
      };
    case 'failed':
    case 'canceled':
      return {
        state: 'failed',
        result: { ...base, failure_reason: refund.failure_reason ?? verdict },
        error: `refund ${verdict}${refund.failure_reason ? `: ${sanitizeErrorMessage(refund.failure_reason)}` : ''}`,
        providerRef: id,
        message: `Stripe reports the refund ${verdict}; a new action is required`,
      };
    case 'mismatch':
      return {
        state: 'unknown',
        result: { ...base, mismatch: refundMismatch(refund, expected) },
        error: 'refund object does not match the claimed action (see result.mismatch)',
        providerRef: null,
        message: 'a refund exists at Stripe but its facts differ from the action; human reconciliation required',
      };
    case 'unknown':
    default:
      return {
        state: 'unknown',
        result: base,
        error: `unrecognised refund status: ${sanitizeErrorMessage(String(refund.status))}`,
        providerRef: id,
        message: 'Stripe returned a refund in an unrecognised status; human reconciliation required',
      };
  }
}

/**
 * GET /v1/refunds and adopt OUR refund if one exists. Returns:
 *   {kind:'adopted', outcome}   a validated refund with our metadata (any status)
 *   {kind:'mismatch', outcome}  a refund carries our metadata but its facts differ
 *   {kind:'none'}               nothing with our metadata on the intent
 *   {kind:'unavailable', outcome} the list itself failed — we cannot see
 */
async function reconcileAtProvider(
  deps: Deps,
  expected: RefundExpectation,
  extra: Record<string, unknown>,
): Promise<
  | { kind: 'adopted' | 'mismatch' | 'unavailable'; outcome: Outcome }
  | { kind: 'none' }
> {
  let list: StripeListResult;
  try {
    list = await deps.stripe.listRefunds(expected.paymentIntent);
  } catch (err) {
    list = { ok: false, data: [], error: errMessage(err) };
  }
  if (!list.ok || !Array.isArray(list.data)) {
    return {
      kind: 'unavailable',
      outcome: {
        state: 'unknown',
        result: { ...extra, reconcile: 'list_failed', list_status: list.status ?? null },
        error: sanitizeErrorMessage(list.error ?? `GET /v1/refunds → ${list.status ?? 'transport error'}`),
        providerRef: null,
        message: 'could not list refunds at Stripe; outcome unresolved, retry is safe',
      },
    };
  }
  const ours = findExistingRefund({ data: list.data }, expected);
  if (ours) return { kind: 'adopted', outcome: outcomeFromRefund(ours, expected, { ...extra, adopted_existing_refund: true }) };
  const tainted = findOurRefundUnvalidated({ data: list.data }, expected.actionId);
  if (tainted) return { kind: 'mismatch', outcome: outcomeFromRefund(tainted, expected, { ...extra, adopted_existing_refund: false }) };
  return { kind: 'none' };
}

function respond(actionId: string, o: Outcome, extra: Record<string, unknown> = {}): RefundExecutionResponse {
  return {
    http: httpStatusForState(o.state),
    body: {
      action_id: actionId,
      state: o.state,
      ...(o.providerRef ? { provider_ref: o.providerRef } : {}),
      message: o.message,
      ...extra,
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// The executor
// ─────────────────────────────────────────────────────────────────────────────

export async function runRefundExecution(
  input: RefundExecutionInput,
  deps: Deps,
): Promise<RefundExecutionResponse> {
  const log = deps.log ?? noopLog;
  const actionId = input.actionId;
  const ctx = { action_id: actionId, caller: input.caller?.userId ?? null };
  try {
    return await execute(input, deps, log, ctx);
  } catch (err) {
    // Last line of defence: a bug must still produce a response, never a crash
    // that leaves the wrapper guessing. No money-moving call happens after
    // this point.
    const message = errMessage(err);
    log.error('ops-refund-execute.internal_error', { ...ctx, message });
    await page(deps, 'ops-refund-execute:internal', message, ctx);
    return { http: 500, body: { action_id: actionId, error: 'internal_error', message } };
  }
}

async function page(deps: Deps, event: string, message: string, ctx: Record<string, unknown>): Promise<void> {
  if (!deps.alert) return;
  try { await deps.alert(event, sanitizeErrorMessage(message), ctx); } catch { /* paging must never break the flow */ }
}

async function execute(
  input: RefundExecutionInput,
  deps: Deps,
  log: Logger,
  ctx: Record<string, unknown>,
): Promise<RefundExecutionResponse> {
  const actionId = input.actionId;
  if (!isUuid(actionId)) {
    return { http: 400, body: { error: 'invalid_input', detail: 'action_id must be a uuid' } };
  }

  // ── 1. Claim — the ONLY gate; evaluated in the database in one transaction ──
  const claim = await deps.db.claim(actionId, CLAIM_LEASE_SECONDS);

  if (!claim || typeof claim !== 'object' || (claim.status !== 'claimed' && claim.status !== 'refused')) {
    log.error('ops-refund-execute.claim_invalid', { ...ctx, claim });
    return { http: 500, body: { action_id: actionId, error: 'claim_invalid', message: 'executor_claim returned an unrecognised payload' } };
  }

  if (claim.status === 'refused') {
    if (claim.reason === 'already_refunded_locally') {
      // The webhook (or another route) already settled the local row. Nothing
      // to send to Stripe; close the action idempotently.
      const rec = await safeRecord(deps, actionId, {
        state: 'succeeded', result: { note: 'already refunded locally' }, error: null, providerRef: null,
      });
      if (rec.status === 'error') {
        return { http: 500, body: { action_id: actionId, error: 'outcome_unrecordable', detail: rec.message } };
      }
      if (rec.status === 'refused') {
        log.warn('ops-refund-execute.outcome_refused', { ...ctx, state: 'succeeded', reason: rec.reason });
      }
      return { http: 200, body: { action_id: actionId, state: 'succeeded', message: 'already refunded locally' } };
    }
    log.info('ops-refund-execute.claim_refused', { ...ctx, reason: claim.reason, state: claim.state ?? null });
    return {
      http: 409,
      body: {
        action_id: actionId,
        error: 'claim_refused',
        reason: claim.reason,
        ...(claim.state ? { state: claim.state } : {}),
        ...(claim.claimed_until ? { claimed_until: claim.claimed_until } : {}),
        ...(claim.detail ? { detail: claim.detail } : {}),
      },
    };
  }

  // ── 2. Validate what we were handed (defense in depth on the claim payload) ──
  const pi = claim.stripe_payment_intent_id;
  const amount = claim.amount_cents;
  const total = claim.payment_total_cents;
  const currency = typeof claim.currency === 'string' ? claim.currency.toLowerCase() : '';
  if (
    claim.action_id !== actionId ||
    typeof pi !== 'string' || !/^pi_[A-Za-z0-9]+$/.test(pi) ||
    !Number.isInteger(amount) || amount <= 0 ||
    !Number.isInteger(total) || total <= 0 ||
    currency !== 'usd' ||
    !isUuid(claim.payment_id)
  ) {
    log.error('ops-refund-execute.claim_invalid', { ...ctx, fields: Object.keys(claim) });
    return { http: 500, body: { action_id: actionId, error: 'claim_invalid', message: 'executor_claim payload failed validation; nothing sent to Stripe' } };
  }

  if (amount !== total) {
    // Partial refunds are unsupported: the local model has no refunded-amount
    // column and `charge.refunded` marks the payment fully refunded.
    const o: Outcome = {
      state: 'failed',
      result: { refused: 'partial_refund_unsupported', amount_cents: amount, payment_total_cents: total },
      error: 'partial refunds are not supported: amount_cents must equal the payment total',
      providerRef: null,
      message: 'partial refund refused; only full refunds can be accounted for locally',
    };
    const rec = await safeRecord(deps, actionId, o);
    log.error('ops-refund-execute.partial_refused', { ...ctx, amount, total, record: rec.status });
    return respond(actionId, o);
  }

  if (deps.stripeKeyMode != null && typeof claim.stripe_livemode === 'boolean'
      && (deps.stripeKeyMode === 'live') !== claim.stripe_livemode) {
    const o: Outcome = {
      state: 'failed',
      result: { mode_check: 'cross_mode' },
      error: `payment row is ${claim.stripe_livemode ? 'live' : 'test'} but the configured Stripe key is ${deps.stripeKeyMode}`,
      providerRef: null,
      message: 'live/test mode mismatch between the payment row and the Stripe key; nothing sent',
    };
    await safeRecord(deps, actionId, o);
    await page(deps, 'ops-refund-execute:mode-guard', o.error!, ctx);
    return respond(actionId, o);
  }

  const expected: RefundExpectation = { actionId, paymentIntent: pi, amountCents: amount, currency: 'usd' };
  const attempt = Number.isInteger(claim.attempt) ? claim.attempt : 1;
  const priorRef = typeof claim.provider_ref === 'string' && claim.provider_ref.length > 0 ? claim.provider_ref : null;
  const mustReconcile = claim.previously_sent === true || priorRef !== null || attempt > 1;

  // ── 3. Aged retry: look before any POST ────────────────────────────────────
  if (mustReconcile) {
    log.info('ops-refund-execute.reconcile_first', { ...ctx, attempt, prior_ref: priorRef });
    const r = await reconcileAtProvider(deps, expected, { attempt, resolved_by: 'list_before_post' });
    if (r.kind !== 'none') {
      return await finish(deps, log, ctx, actionId, r.outcome);
    }
    if (priorRef !== null) {
      // We hold a re_ id that Stripe does not list on this intent. Facts
      // disagree; never POST over that.
      const o: Outcome = {
        state: 'unknown',
        result: { attempt, reconcile: 'provider_ref_not_listed', prior_provider_ref: priorRef },
        error: 'recorded provider_ref is not listed on the PaymentIntent',
        providerRef: null,
        message: 'a refund id is recorded but Stripe does not list it on this PaymentIntent; human reconciliation required',
      };
      return await finish(deps, log, ctx, actionId, o);
    }
    // Sent before but nothing carries our metadata: either the POST never
    // reached Stripe or the object is not yet visible. The idempotency key
    // makes the POST below a replay-or-create-once, never a second refund.
  }

  // ── 4. Mark the attempt BEFORE money can move — no record, no Stripe ─────
  const started = await safeRecord(deps, actionId, {
    state: 'processing',
    result: { stripe_request_started_at: deps.now().toISOString(), attempt, partial: false },
    error: null,
    providerRef: null,
  });
  if (started.status === 'error') {
    log.error('ops-refund-execute.processing_unrecordable', { ...ctx, message: started.message });
    return { http: 500, body: { action_id: actionId, error: 'outcome_unrecordable', detail: started.message } };
  }
  if (started.status === 'refused') {
    // The action moved under us (a late callback landed, or it was closed).
    // Do NOT touch Stripe on a row the database no longer considers ours.
    log.warn('ops-refund-execute.processing_refused', { ...ctx, reason: started.reason });
    return { http: 409, body: { action_id: actionId, error: 'outcome_refused', reason: started.reason, message: 'action state changed before the Stripe call; nothing sent' } };
  }

  // ── 5. POST /v1/refunds ────────────────────────────────────────────────────
  const body = planRefundBody({
    actionId, paymentId: claim.payment_id, paymentIntent: pi, amountCents: amount, reasonCode: claim.reason_code,
  });
  const idempotencyKey = buildOpsRefundIdempotencyKey(actionId);
  log.info('ops-refund-execute.issuing', { ...ctx, payment_id: claim.payment_id, attempt });

  let res: StripeTransportResult | Error;
  try {
    res = await deps.stripe.createRefund(body, idempotencyKey);
  } catch (err) {
    res = err instanceof Error ? err : new Error(String(err));
  }
  const verdict = classifyRefundCreate(res);

  // ── 6. Classify the OBJECT, never the HTTP status ─────────────────────────
  let outcome: Outcome;
  switch (verdict.kind) {
    case 'created': {
      outcome = outcomeFromRefund(verdict.refund, expected, { attempt });
      break;
    }
    case 'already_refunded': {
      const r = await reconcileAtProvider(deps, expected, { attempt, resolved_after: 'charge_already_refunded' });
      outcome = r.kind !== 'none' ? r.outcome : {
        state: 'failed',
        result: { attempt, stripe_error_class: 'charge_already_refunded' },
        error: `${verdict.code}: ${verdict.message}`,
        providerRef: null,
        message: 'Stripe reports the charge already refunded by another route; no refund carries this action\'s metadata. The charge.refunded webhook settles the payment; this action is closed',
      };
      break;
    }
    case 'failed': {
      outcome = {
        state: 'failed',
        result: { attempt, stripe_error_class: verdict.errorClass, stripe_error_code: verdict.code },
        error: `${verdict.code}: ${verdict.message}`,
        providerRef: null,
        message: `Stripe refused the refund (${verdict.errorClass})`,
      };
      break;
    }
    case 'unknown':
    default: {
      // Stripe MAY hold a refund. Resolve strictly by our own metadata.
      const r = await reconcileAtProvider(deps, expected, { attempt, resolved_after: verdict.errorClass });
      outcome = r.kind !== 'none' ? r.outcome : {
        state: 'unknown',
        result: { attempt, stripe_error_class: verdict.errorClass },
        error: sanitizeErrorMessage(verdict.message),
        providerRef: null,
        message: 'Stripe outcome unresolved; retry is safe (same idempotency key, list-before-POST)',
      };
      break;
    }
  }

  return await finish(deps, log, ctx, actionId, outcome);
}

/** Record the outcome and shape the response. Money may have moved by now: never throw. */
async function finish(
  deps: Deps,
  log: Logger,
  ctx: Record<string, unknown>,
  actionId: string,
  o: Outcome,
): Promise<RefundExecutionResponse> {
  const rec = await safeRecord(deps, actionId, o);

  if (rec.status === 'error') {
    // Stripe answered and the ledger did not follow. Page with the ref; the
    // next attempt reconciles by list (previously_sent) — never a second POST.
    log.error('ops-refund-execute.outcome_unrecorded', { ...ctx, state: o.state, provider_ref: o.providerRef, message: rec.message });
    await page(deps, 'ops-refund-execute:outcome-unrecorded', rec.message, { ...ctx, state: o.state, provider_ref: o.providerRef, financial_operation: 'refund' });
    return {
      http: 500,
      body: {
        action_id: actionId,
        state: o.state,
        ...(o.providerRef ? { provider_ref: o.providerRef } : {}),
        error: 'outcome_unrecorded',
        message: 'Stripe outcome known but ops.record_action_outcome failed; retry reconciles by list',
      },
    };
  }

  if (rec.status === 'refused') {
    // Monotonic RPC kept a more authoritative state (a late callback after a
    // terminal state, or a different provider_ref). The database wins; log it.
    log.warn('ops-refund-execute.outcome_refused', { ...ctx, attempted_state: o.state, provider_ref: o.providerRef, reason: rec.reason });
    return {
      http: 409,
      body: {
        action_id: actionId,
        error: 'outcome_refused',
        reason: rec.reason,
        attempted_state: o.state,
        ...(o.providerRef ? { provider_ref: o.providerRef } : {}),
        ...(rec.state ? { state: rec.state } : {}),
        message: 'the action already holds a more authoritative outcome; nothing changed',
      },
    };
  }

  if (o.state === 'failed' || o.state === 'unknown') {
    log.error('ops-refund-execute.outcome', { ...ctx, state: o.state, error: o.error });
    await page(deps, 'ops-refund-execute:stripe', `${o.state}: ${o.error ?? o.message}`, { ...ctx, state: o.state, provider_ref: o.providerRef, financial_operation: 'refund' });
  } else {
    log.info('ops-refund-execute.outcome', { ...ctx, state: o.state, provider_ref: o.providerRef });
  }
  return respond(actionId, o);
}
