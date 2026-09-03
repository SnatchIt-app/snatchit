/**
 * refund-execute/executor.ts — pure, dependency-free refund execution logic.
 *
 * WHY THIS FILE EXISTS SEPARATELY
 *   Deno edge modules import over https, which vitest cannot load. Every
 *   decision that decides whether real money moves lives here, import-free,
 *   so `tests/refund-executor.test.ts` can exercise it directly. `index.ts`
 *   is the I/O shell: HTTP, auth, two Supabase clients, Stripe, Sentry.
 *   Same split as `_shared/payout-logic.ts` vs `_shared/payouts.ts`.
 *
 * WHAT THIS EXECUTOR IS
 *   The caller of `kernel.mark_refund_state` (085:1737), which until now had
 *   ZERO callers. Every `kernel.refund` row is born `pending` (085:599,
 *   085:706, 088:1664/1721/1779) and no transition out of `pending` was
 *   reachable — while the same transaction already voided the buyer's atoms
 *   (085:593) and moved the order to `refunded`/`partially_refunded`
 *   (085:604). The buyer lost the ticket and got nothing, and the `pending`
 *   row then blocked their account deletion forever (BP-12 arm 1, 085:249-262
 *   blocks on `status in ('pending','submitted')`).
 *
 * THE ONE INVARIANT EVERYTHING ELSE SERVES
 *   The executor is REFUND-ROW-DRIVEN, never order-driven and never
 *   client-parameter-driven. The payment it refunds is read out of
 *   `kernel.refund.payment_id` — a FK with `on delete restrict` (085:76) —
 *   inside the database. No caller can name a payment, a PaymentIntent or a
 *   charge; there is no request field for one, and `assertNoClientPaymentReference`
 *   refuses the request outright if one is smuggled in. That single fact is
 *   what makes "incapable of refunding the wrong payment or order" structural
 *   rather than aspirational.
 *
 *   Being refund-row-driven is also why event cancellation works with no
 *   special case: `catalog.cancel_event` (088:1664, :1721, :1779) inserts
 *   `kernel.refund` rows DIRECTLY — it never calls `refund_primary_order` —
 *   and those rows are picked up by refund_id like any other.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

export type RefundStatus = 'pending' | 'submitted' | 'succeeded' | 'failed';

/**
 * Everything the executor is allowed to know about one refund, assembled
 * SERVER-SIDE from `kernel.refund` ⋈ `kernel.payment_native` ⋈ `public.payments`.
 * Every field is DB-derived. Nothing here ever comes from the request body.
 */
export interface RefundExecutionContext {
  refund_id: string;
  /** kernel.refund.payment_id — the FK. The binding. */
  payment_id: string;
  /** kernel.payment_native.order_id (primary rail) — XOR with sale_id (085:56-58). */
  order_id: string | null;
  /** kernel.payment_native.sale_id (native resale rail) — XOR with order_id. */
  sale_id: string | null;
  amount_minor: number;
  currency: string;
  reason_code: string;
  status: RefundStatus;
  stripe_refund_ref: string | null;
  /** public.payments.total (minor units). The Σ-guard operand. */
  payment_total_minor: number;
  payment_status: string;
  stripe_payment_intent_id: string | null;
  /** migration 045. NULL = unclassified ⇒ fail closed. */
  stripe_livemode: boolean | null;
  /** Σ amount_minor of OTHER non-failed kernel.refund rows on this payment. */
  prior_non_failed_minor: number;
  /** Σ amount_minor of lost/charge_refunded kernel.dispute_native rows (088:1661). */
  disputed_minor: number;
}

export type RefundRefusalCode =
  | 'malformed_refund_id'
  | 'malformed_payment_id'
  | 'binding_subject_ambiguous'
  | 'binding_order_mismatch'
  | 'client_supplied_payment_reference'
  | 'unknown_refund_status'
  | 'impossible_pending_with_ref'
  | 'amount_not_positive'
  | 'payment_not_refundable'
  | 'no_payment_intent'
  | 'malformed_payment_intent'
  | 'payment_not_livemode'
  | 'payment_total_invalid'
  | 'amount_exceeds_payment_total'
  | 'amount_exceeds_headroom'
  | 'currency_unsupported';

export type RefundPlan =
  | {
      kind: 'stripe_create';
      idempotency_key: string;
      /** Exactly the form body for POST /v1/refunds. */
      body: Record<string, string>;
      payment_intent: string;
      amount_minor: number;
    }
  | {
      kind: 'noop_replay';
      reason: 'already_submitted' | 'already_succeeded' | 'already_failed';
      stripe_refund_ref: string | null;
    }
  | {
      kind: 'refuse';
      code: RefundRefusalCode;
      detail: string;
      /** false ⇒ a worker must NOT keep retrying this row. */
      retryable: boolean;
    };

const NIL_UUID = '00000000-0000-0000-0000-000000000000';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Stripe PaymentIntent ids. `pi_` in live and test alike. */
const PI_RE = /^pi_[A-Za-z0-9]+$/;
/** Stripe Refund ids. */
const RE_RE = /^re_[A-Za-z0-9]+$/;

export function isUuid(v: unknown): v is string {
  return typeof v === 'string' && UUID_RE.test(v) && v !== NIL_UUID;
}

// ─────────────────────────────────────────────────────────────────────────────
// Stripe idempotency key
// ─────────────────────────────────────────────────────────────────────────────

/**
 * `refund_<refund_id>` — the key the edge spec froze
 * (`PHASE_2_EDGE_FUNCTION_SPEC.md:559-560`).
 *
 * Derived from the refund row's OWN primary key, so it is reconstructible by
 * any retry from any worker with no shared state, and two attempts on the same
 * refund can never mint two Stripe Refund objects. It is deliberately NOT
 * derived from the order, the command key or the request: a delegated key is
 * single-use (085:496) and a command key is caller-supplied, while `refund_id`
 * is minted by Postgres under the payment lock.
 */
export function buildRefundIdempotencyKey(refundId: string): string {
  if (!isUuid(refundId)) {
    throw new Error(`refund-execute: refusing to build an idempotency key from a non-uuid refund id: ${String(refundId)}`);
  }
  return `refund_${refundId}`;
}

// ─────────────────────────────────────────────────────────────────────────────
// The request-side guard: the caller may NEVER name the money
// ─────────────────────────────────────────────────────────────────────────────

const FORBIDDEN_REQUEST_KEYS = [
  'payment_id',
  'payment_intent',
  'stripe_payment_intent_id',
  'charge',
  'charge_id',
  'stripe_charge_id',
  'stripe_refund_ref',
  'stripe_refund_id',
  'destination',
] as const;

/**
 * Defence in depth for the property that matters most. The executor resolves
 * the payment from the refund row; a request that also tries to name one is a
 * confused-deputy attempt, so it is refused rather than ignored — ignoring it
 * would let a future refactor start reading it.
 */
export function assertNoClientPaymentReference(
  body: Record<string, unknown> | null | undefined,
): { ok: true } | { ok: false; code: 'client_supplied_payment_reference'; detail: string } {
  if (!body || typeof body !== 'object') return { ok: true };
  for (const k of FORBIDDEN_REQUEST_KEYS) {
    if (Object.prototype.hasOwnProperty.call(body, k) && body[k] != null) {
      return {
        ok: false,
        code: 'client_supplied_payment_reference',
        detail: `the caller may not name the money: '${k}' is resolved from kernel.refund.payment_id, never from the request`,
      };
    }
  }
  return { ok: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// The plan: what (if anything) to send to Stripe
// ─────────────────────────────────────────────────────────────────────────────

const refuse = (code: RefundRefusalCode, detail: string, retryable = false): RefundPlan =>
  ({ kind: 'refuse', code, detail, retryable });

/**
 * Decide, from DB-derived facts alone, whether this refund row may be sent to
 * Stripe — and if so, exactly what to send.
 *
 * `expected.order_id` is the CALLER's assertion about which order it believes
 * it is refunding. It is never used to find the payment; it is only used to
 * REFUSE when the caller's belief and the database disagree. An operator who
 * pastes the wrong refund id gets a refusal, not someone else's refund.
 */
export function planRefund(
  ctx: RefundExecutionContext,
  expected: { order_id?: string | null } = {},
): RefundPlan {
  // ── 1. identity ──────────────────────────────────────────────────────────
  if (!isUuid(ctx.refund_id)) return refuse('malformed_refund_id', `refund_id=${String(ctx.refund_id)}`);
  if (!isUuid(ctx.payment_id)) return refuse('malformed_payment_id', `payment_id=${String(ctx.payment_id)}`);

  // ── 2. binding ───────────────────────────────────────────────────────────
  // kernel.payment_native's XOR (085:56-58) must hold in the assembled context;
  // a row that satisfies neither/both means the join was wrong, and a wrong
  // join is exactly how you refund the wrong order.
  const hasOrder = ctx.order_id != null;
  const hasSale = ctx.sale_id != null;
  if (hasOrder === hasSale) {
    return refuse(
      'binding_subject_ambiguous',
      `payment ${ctx.payment_id} resolves to order=${String(ctx.order_id)} sale=${String(ctx.sale_id)} — the payment_native XOR does not hold`,
    );
  }
  if (expected.order_id != null && expected.order_id !== ctx.order_id) {
    return refuse(
      'binding_order_mismatch',
      `caller asserted order ${expected.order_id}; refund ${ctx.refund_id} binds to order ${String(ctx.order_id)}`,
    );
  }

  // ── 3. state ─────────────────────────────────────────────────────────────
  switch (ctx.status) {
    case 'submitted':
      return { kind: 'noop_replay', reason: 'already_submitted', stripe_refund_ref: ctx.stripe_refund_ref };
    case 'succeeded':
      return { kind: 'noop_replay', reason: 'already_succeeded', stripe_refund_ref: ctx.stripe_refund_ref };
    case 'failed':
      return { kind: 'noop_replay', reason: 'already_failed', stripe_refund_ref: ctx.stripe_refund_ref };
    case 'pending':
      break;
    default:
      return refuse('unknown_refund_status', `status=${String(ctx.status)}`);
  }
  // 085's `refund_ref_pairing_ck` makes this unstorable; if we ever see it the
  // row is corrupt and must not drive a Stripe call.
  if (ctx.stripe_refund_ref != null) {
    return refuse('impossible_pending_with_ref', `refund ${ctx.refund_id} is pending but carries ${ctx.stripe_refund_ref}`);
  }

  // ── 4. money ─────────────────────────────────────────────────────────────
  if (!Number.isInteger(ctx.amount_minor) || ctx.amount_minor <= 0) {
    return refuse('amount_not_positive', `amount_minor=${String(ctx.amount_minor)}`);
  }
  if (ctx.payment_status !== 'succeeded' && ctx.payment_status !== 'refunded') {
    return refuse('payment_not_refundable', `public.payments.status=${ctx.payment_status}`);
  }
  if (!ctx.stripe_payment_intent_id) {
    return refuse('no_payment_intent', `payment ${ctx.payment_id} carries no stripe_payment_intent_id`);
  }
  if (!PI_RE.test(ctx.stripe_payment_intent_id)) {
    return refuse('malformed_payment_intent', `stripe_payment_intent_id=${ctx.stripe_payment_intent_id}`);
  }
  // MODE BOUNDARY — the same rule enforce-transfer-expiry's self-heal applies:
  // a live key cannot see a test-mode PaymentIntent, and NULL (unclassified,
  // migration 045) fails closed.
  if (ctx.stripe_livemode !== true) {
    return refuse('payment_not_livemode', `stripe_livemode=${String(ctx.stripe_livemode)}`);
  }
  if (!Number.isInteger(ctx.payment_total_minor) || ctx.payment_total_minor <= 0) {
    return refuse('payment_total_invalid', `total=${String(ctx.payment_total_minor)}`);
  }
  if (ctx.amount_minor > ctx.payment_total_minor) {
    return refuse('amount_exceeds_payment_total', `${ctx.amount_minor} > ${ctx.payment_total_minor}`);
  }
  // The Σ-guard, mirrored client-side. The RPC already enforced it under the
  // payment lock (085:545) — this re-check catches a row whose headroom was
  // consumed by a chargeback or a second refund AFTER the intent was recorded
  // but BEFORE the executor ran, which is precisely the window a queued job
  // sits in.
  const consumed = ctx.prior_non_failed_minor + ctx.disputed_minor;
  if (!Number.isInteger(ctx.prior_non_failed_minor) || ctx.prior_non_failed_minor < 0
      || !Number.isInteger(ctx.disputed_minor) || ctx.disputed_minor < 0) {
    return refuse('payment_total_invalid', `prior=${String(ctx.prior_non_failed_minor)} disputed=${String(ctx.disputed_minor)}`);
  }
  if (consumed + ctx.amount_minor > ctx.payment_total_minor) {
    return refuse(
      'amount_exceeds_headroom',
      `prior ${ctx.prior_non_failed_minor} + disputed ${ctx.disputed_minor} + this ${ctx.amount_minor} > total ${ctx.payment_total_minor}`,
    );
  }
  if ((ctx.currency ?? '').toUpperCase() !== 'USD') {
    return refuse('currency_unsupported', `currency=${String(ctx.currency)}`);
  }

  // ── 5. the call ──────────────────────────────────────────────────────────
  // `amount` is sent even for a full refund, deliberately. Stripe binds the
  // request parameters to the idempotency key: a replay that has somehow
  // mutated the amount comes back as `idempotency_error` instead of quietly
  // doing something different. Omitting `amount` would forfeit that check.
  const body: Record<string, string> = {
    'payment_intent': ctx.stripe_payment_intent_id,
    'amount': String(ctx.amount_minor),
    'metadata[refund_id]': ctx.refund_id,
    'metadata[payment_id]': ctx.payment_id,
    'metadata[reason]': ctx.reason_code,
    'metadata[source]': 'refund-execute',
  };
  if (ctx.order_id) body['metadata[order_id]'] = ctx.order_id;
  if (ctx.sale_id) body['metadata[sale_id]'] = ctx.sale_id;

  return {
    kind: 'stripe_create',
    idempotency_key: buildRefundIdempotencyKey(ctx.refund_id),
    body,
    payment_intent: ctx.stripe_payment_intent_id,
    amount_minor: ctx.amount_minor,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Stripe error classification
// ─────────────────────────────────────────────────────────────────────────────

export type RefundErrorClass =
  | 'network'
  | 'rate_limited'
  | 'api_error'
  | 'idempotency_in_use'
  | 'idempotency_conflict'
  | 'charge_already_refunded'
  | 'charge_disputed'
  | 'resource_missing'
  | 'balance_insufficient'
  | 'invalid_request'
  | 'unknown';

export interface RefundErrorVerdict {
  class: RefundErrorClass;
  /** May a worker retry this row on a later tick? */
  retryable: boolean;
  /** Should this page a human via Sentry? */
  page: boolean;
  /**
   * ALWAYS false. A `create` error means there is no `re_…` — nothing was left
   * with Stripe — so the row must stay `pending` and NOTHING may be written
   * through mark_refund_state. `failed` is reserved for a refund Stripe
   * ACCEPTED and then could not settle, which carries a ref
   * (085:1762-1764; spec `:552-556`; the `refund_ref_pairing_ck` at 085:93
   * makes the wrong reading unstorable).
   */
  writesState: false;
}

export function classifyStripeRefundError(
  input: { status?: number; error?: { type?: string; code?: string; message?: string } } | Error,
): RefundErrorVerdict {
  const base = { writesState: false as const };
  if (input instanceof Error) {
    // Thrown before any HTTP response existed: DNS, TLS, socket, abort/timeout.
    return { ...base, class: 'network', retryable: true, page: false };
  }
  const status = input.status ?? 0;
  const code = input.error?.code ?? '';
  const type = input.error?.type ?? '';

  if (code === 'idempotency_error') {
    // Same key, different parameters. This is a CODE BUG or a mutated amount —
    // the wrong-refund guard tripping at Stripe. Never retry it blind.
    return { ...base, class: 'idempotency_conflict', retryable: false, page: true };
  }
  if (status === 409 || code === 'idempotency_key_in_use') {
    return { ...base, class: 'idempotency_in_use', retryable: true, page: false };
  }
  if (code === 'charge_already_refunded') {
    // The money may already be back by another route (Dashboard, the legacy
    // expiry sweep, a chargeback). Reconciliation, not a retry.
    return { ...base, class: 'charge_already_refunded', retryable: false, page: true };
  }
  if (code === 'charge_disputed') {
    // A disputed charge cannot be refunded — the dispute rail owns the money.
    return { ...base, class: 'charge_disputed', retryable: false, page: true };
  }
  if (code === 'resource_missing') {
    // The PaymentIntent does not exist for this key. A binding or mode fault.
    return { ...base, class: 'resource_missing', retryable: false, page: true };
  }
  if (code === 'balance_insufficient') {
    // Operational, not terminal — the same class the payout rail already treats
    // as "retry later, do not page" (`_shared/payout-logic.ts`).
    return { ...base, class: 'balance_insufficient', retryable: true, page: false };
  }
  if (status === 429 || code === 'rate_limit' || type === 'rate_limit_error') {
    return { ...base, class: 'rate_limited', retryable: true, page: false };
  }
  if (status >= 500 || type === 'api_error' || type === 'api_connection_error') {
    return { ...base, class: 'api_error', retryable: true, page: false };
  }
  if (type === 'invalid_request_error' || (status >= 400 && status < 500)) {
    return { ...base, class: 'invalid_request', retryable: false, page: true };
  }
  return { ...base, class: 'unknown', retryable: false, page: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// The callback plan: kernel.mark_refund_state
// ─────────────────────────────────────────────────────────────────────────────

export interface StateSyncStep {
  new_status: 'submitted' | 'succeeded' | 'failed';
  stripe_refund_ref: string;
  failure_code: string | null;
}

export type StateSyncPlan =
  | { kind: 'sync'; steps: StateSyncStep[] }
  | { kind: 'refuse'; code: 'malformed_stripe_refund_ref' | 'unknown_stripe_refund_status'; detail: string };

/**
 * Turn the Stripe Refund object into the ordered `kernel.mark_refund_state`
 * calls that make it true in our ledger.
 *
 * `submitted` is ALWAYS step 1 and is written before anything else, so the
 * write-once `stripe_refund_ref` lands even if the process dies immediately
 * after. The RPC is forward-only pending→submitted→succeeded|failed
 * (085:1757-1761), so a terminal can never be reached without it.
 *
 * DEVIATION FROM THE LETTER OF THE EDGE SPEC, DELIBERATE AND FLAGGED:
 * `EDGE_FUNCTION_SPEC.md:539-541` assigns `succeeded` to a `charge.refunded`
 * webhook branch. That branch does not exist (`stripe-webhook/index.ts:705-734`
 * only touches legacy `public.payments`) and this train may not modify it. A
 * refund parked at `submitted` still blocks the buyer's account deletion
 * (BP-12 arm 1, 085:249-262 blocks on `pending`/`submitted`), so stopping at
 * `submitted` would close only half the defect. When Stripe's OWN returned
 * object says `status: 'succeeded'` that is a fact, not an inference, so it is
 * recorded. The webhook branch, when it is written, converges on the same row
 * via `noop_replay` (085:1752-1755).
 */
export function planStateSync(
  stripeRefund: { id?: unknown; status?: unknown; failure_reason?: unknown },
): StateSyncPlan {
  const id = stripeRefund?.id;
  if (typeof id !== 'string' || !RE_RE.test(id)) {
    return { kind: 'refuse', code: 'malformed_stripe_refund_ref', detail: `id=${String(id)}` };
  }
  const submitted: StateSyncStep = { new_status: 'submitted', stripe_refund_ref: id, failure_code: null };
  const status = typeof stripeRefund.status === 'string' ? stripeRefund.status : '';

  switch (status) {
    case 'succeeded':
      return { kind: 'sync', steps: [submitted, { new_status: 'succeeded', stripe_refund_ref: id, failure_code: null }] };
    case 'failed':
      return {
        kind: 'sync',
        steps: [submitted, {
          new_status: 'failed',
          stripe_refund_ref: id,
          // 085:1769-1771 makes failure_code mandatory for `failed`.
          failure_code: typeof stripeRefund.failure_reason === 'string' && stripeRefund.failure_reason.length > 0
            ? stripeRefund.failure_reason
            : 'stripe_refund_failed',
        }],
      };
    case 'canceled':
      return {
        kind: 'sync',
        steps: [submitted, { new_status: 'failed', stripe_refund_ref: id, failure_code: 'refund_canceled' }],
      };
    case 'pending':
    case 'requires_action':
      // Stripe accepted it but has not settled it. Record the ref and stop;
      // the terminal belongs to whoever observes it next.
      return { kind: 'sync', steps: [submitted] };
    default:
      // Unknown status: still record `submitted` so the ref is never lost —
      // losing it is how you end up unable to prove a refund exists.
      return { kind: 'sync', steps: [submitted] };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The sweep
// ─────────────────────────────────────────────────────────────────────────────

export interface SweepCandidate {
  refund_id: string;
  created_at: string;
  status: RefundStatus;
}

/**
 * The worker's work list: oldest-first, deduped, bounded, `pending` only.
 *
 * This is the leg that makes every dangerous interleaving converge —
 * Stripe-succeeded-then-DB-failed, DB-failed-then-worker-retry, a crash
 * between `refund_primary_order` and the Stripe call, and the N `pending`
 * rows `catalog.cancel_event` leaves behind. Each one replays the SAME
 * `refund_<id>` key, so replay never means re-pay.
 */
export function planSweep(rows: SweepCandidate[], opts: { limit?: number } = {}): string[] {
  const limit = Math.max(1, Math.min(opts.limit ?? 25, 100));
  const seen = new Set<string>();
  return rows
    .filter((r) => r.status === 'pending' && isUuid(r.refund_id))
    .slice()
    .sort((a, b) => (a.created_at < b.created_at ? -1 : a.created_at > b.created_at ? 1 : 0))
    .filter((r) => (seen.has(r.refund_id) ? false : (seen.add(r.refund_id), true)))
    .slice(0, limit)
    .map((r) => r.refund_id);
}

// ─────────────────────────────────────────────────────────────────────────────
// mark_refund_state error classification
// ─────────────────────────────────────────────────────────────────────────────

export interface StateSyncVerdict {
  /**
   * `converged`  — another actor already advanced this row past the step we
   *                tried to write. The refund is recorded; we are the loser of
   *                a benign race. NOT an error and NOT retryable: retrying it
   *                forever is how a worker turns a healthy race into a hot loop.
   * `conflict`   — the row disagrees with us in a way that means something is
   *                genuinely wrong (two different Stripe refs on one row, a
   *                missing row, a malformed argument). Page a human.
   * `retry`      — transport/DB unavailability. The money already moved, so the
   *                next sweep tick must replay and finish the callback.
   */
  kind: 'converged' | 'conflict' | 'retry';
  page: boolean;
}

export function classifyStateSyncError(message: string): StateSyncVerdict {
  // 085:1757-1761 — the row is already at or past this state. Because the
  // Stripe key is deterministic per refund_id, whoever got there first used the
  // same key and therefore holds the same `re_…`.
  if (/refund_state_backwards/.test(message)) return { kind: 'converged', page: false };
  // 085:1766-1768 — two DIFFERENT refs on one refund row. Real incident.
  if (/conflict_locked/.test(message)) return { kind: 'conflict', page: true };
  if (/not_found/.test(message)) return { kind: 'conflict', page: true };
  if (/invalid_input/.test(message)) return { kind: 'conflict', page: true };
  return { kind: 'retry', page: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// Authority routing (PFA-23)
// ─────────────────────────────────────────────────────────────────────────────

export type RefundArm = 'delegated' | 'direct';

/**
 * `kernel.refund_primary_order`'s two authority arms are selected by the
 * command key alone (085:494-520): `req:<uuid>` is DELEGATED and binds to an
 * already-approved `kernel.approval_request`; anything else is DIRECT and
 * requires `is_platform([platform_support, platform_admin])`, i.e. `auth.uid()`.
 *
 * WHICH CLIENT EACH ARM NEEDS, AND WHY THE DIRECT ARM IS CURRENTLY UNREACHABLE:
 *   `refund_primary_order` is granted to `service_role` ONLY (085:2148-2156,
 *   the `v_svc` array) and explicitly NOT to `authenticated` (085:2129-2130:
 *   *"refund_primary_order is NOT here — PFA-23 makes it EXEC DEF"*).
 *   PostgREST derives the database role from the JWT it verifies, so one
 *   request is either `service_role` (and `auth.uid()` is NULL, failing
 *   `is_platform`) or `authenticated` (and EXECUTE is denied). "As service_role,
 *   forwarding the platform JWT" has no single-client implementation with this
 *   grant set. The DELEGATED arm needs no `auth.uid()` and is therefore the arm
 *   that works today — which is also the safer default, since dual control is
 *   already enforced upstream by request/approve.
 *
 *   The DIRECT arm is still routed (on the caller's own client, which is the
 *   only client that carries the platform identity) so that the resulting
 *   `42501` is a precise, logged, denial-witnessed refusal instead of a silent
 *   nothing. See `docs/phase2/_impl/E4_refund_executor.md` §7.
 */
export function classifyArm(commandKey: string): RefundArm {
  return commandKey.startsWith('req:') ? 'delegated' : 'direct';
}

/** The four money-denial codes the edge spec routes to `record_money_denial`. */
export function isMoneyDenial(message: string): boolean {
  return /insufficient_privilege|sod_violation|step_up_required|step_up_unavailable/.test(message);
}

/** Map a Postgres RPC error onto an HTTP status, per the edge spec's failure table. */
export function httpStatusForRpcError(message: string): number {
  if (/insufficient_privilege|sod_violation|step_up_required|step_up_unavailable/.test(message)) return 403;
  if (/not_found/.test(message)) return 404;
  if (/precondition_failed|conflict_locked|state_conflict|custody_moved|frozen|policy_violation/.test(message)) return 409;
  if (/invalid_input/.test(message)) return 400;
  return 500;
}
