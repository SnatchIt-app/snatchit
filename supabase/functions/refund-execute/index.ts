// =============================================================================
// refund-execute — the server-side Stripe refund executor (owner ruling D3)
// =============================================================================
// THE DEFECT THIS CLOSES
//   Today a primary refund voids the buyer's ticket and returns NO money.
//   `kernel.refund_primary_order` (085:457) voids the atoms (085:593), moves
//   the order to `refunded`/`partially_refunded` (085:604) and INSERTs a
//   `kernel.refund` row born `pending` (085:599). Nothing then calls Stripe,
//   and `kernel.mark_refund_state` (085:1737) — the transition out of
//   `pending` — has ZERO callers repo-wide. The buyer loses the ticket, gets
//   nothing, and the `pending` row blocks their account deletion forever
//   (BP-12 arm 1, 085:249-262). This function is that missing caller.
//
// THE FROZEN SHAPE (NOT REDESIGNED HERE)
//   085:2144-2146 names the intended caller verbatim: *"the refund-execute
//   edge (as service_role, forwarding the platform JWT for the direct arm)"*,
//   and `refund_primary_order` sits in the `v_svc` (service_role) grant array,
//   deliberately absent from `v_auth`. Ruling D3
//   (`docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md:327`) ratifies
//   building it and says to extend the ONE proven Stripe refund path in this
//   repo — `enforce-transfer-expiry/index.ts:264` / `:387` — rather than
//   invent a new one. Same `POST /v1/refunds`, same deterministic
//   idempotency-key discipline, same "one failure never blocks the batch".
//
// THE INVARIANT
//   REFUND-ROW-DRIVEN. The payment is read out of `kernel.refund.payment_id`
//   inside the database. There is no request field for a payment, a
//   PaymentIntent or a charge, and a request that smuggles one is refused
//   (`assertNoClientPaymentReference`). That is what makes "incapable of
//   refunding the wrong payment or order" structural. It is also why event
//   cancellation needs no special case: `catalog.cancel_event` (088:1664,
//   :1721, :1779) inserts `kernel.refund` rows directly and they are executed
//   like any other.
//
// ORDER OF OPERATIONS (never reordered)
//   1. RPC first — the DB records the refund intent and voids atoms
//      atomically, under the payment lock, with the Σ-guard.
//   2. THEN Stripe, under `refund_<refund_id>`.
//   3. THEN `kernel.mark_refund_state` to record the `re_…`.
//   A crash at any point leaves a row a later sweep replays under the SAME
//   Stripe key. Replay is never re-pay.
//
// THE CREATE-ERROR RULE (the branch that decides whether a retry is safe)
//   If `POST /v1/refunds` itself errors there is NO `re_…` — nothing was left
//   with Stripe — so this function does NOT call `mark_refund_state` at all.
//   The row stays `pending` and the retry replays the same key. `failed` is
//   reserved for a refund Stripe ACCEPTED and then could not settle, which
//   carries a ref. 085's `refund_ref_pairing_ck` makes the wrong reading
//   unstorable. (`EDGE_FUNCTION_SPEC.md:552-556`.)
//
// TWO CLIENTS, ON PURPOSE (EA-1 / EA-3 B-ii)
//   • caller client (the caller's own JWT): `kernel.admin_refund`, the DIRECT
//     arm of `refund_primary_order`, and `kernel.record_money_denial` — all
//     read `auth.uid()`. `record_money_denial` is explicitly REVOKED from
//     service_role (085:2174), so a service-role call would write nothing on
//     the highest-value fraud signal in the system.
//   • service client (service_role): the DELEGATED arm of
//     `refund_primary_order` and `kernel.mark_refund_state`, which is
//     service_role-only with no human path by contract (085:1735-1737 header).
//
// NOT DEPLOYED IN THIS TRAIN (ruling D3). No Stripe object is created by
// authoring this file.
// =============================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetchRaw } from '../_shared/stripe.ts';
import {
  assertNoClientPaymentReference,
  buildRefundIdempotencyKey,
  classifyArm,
  classifyStateSyncError,
  classifyStripeRefundError,
  httpStatusForRpcError,
  isMoneyDenial,
  isUuid,
  planClaimedBatch,
  planReconcile,
  planRefund,
  planStateSync,
  type ClaimedRefund,
  type RefundExecutionContext,
  type RefundExecutionMode,
} from './executor.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const INTERNAL_CRON_SECRET = Deno.env.get('INTERNAL_CRON_SECRET') ?? '';

/**
 * The one DB artifact this function needs that does NOT exist yet.
 *
 * `service_role` holds USAGE on the `kernel` schema (085:2095, PFA-21) and
 * EXECUTE on exactly six functions (085:2148-2156) — and NO table grants
 * ("No table/DML grants", 085:2093/2096). So the edge cannot SELECT
 * `kernel.refund` or `kernel.payment_native`, and the only refund reader that
 * exists, `kernel.list_org_refunds` (085:1487), is `authenticated`-only,
 * org-scoped, and deliberately returns `has_stripe_ref` as a BOOLEAN rather
 * than the reference (085:1512). There is therefore no path today from
 * `refund_id` to `stripe_payment_intent_id`.
 *
 * This function names the read it needs and FAILS CLOSED AND LOUD when it is
 * absent, rather than guessing a binding. The required shape is specified in
 * `docs/phase2/_impl/E4_refund_executor.md` §3 for owner ratification; it is
 * deliberately NOT authored as a migration here (the migration ledger is
 * 1:1 with the repo and this train applies nothing).
 */
const CONTEXT_RPC = 'get_refund_execution_context';

const ALLOWED_ORIGINS = ['https://snatchitapp.com', 'https://www.snatchitapp.com'];

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin') ?? '';
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };
}

function getSecurityHeaders(): Record<string, string> {
  return {
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'X-DNS-Prefetch-Control': 'off',
    'X-Download-Options': 'noopen',
    'X-Permitted-Cross-Domain-Policies': 'none',
    'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
  };
}

const responseHeaders = (req: Request) => ({ ...getCorsHeaders(req), ...getSecurityHeaders() });

function json(body: unknown, status: number, headers: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json' },
  });
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Clients
// ─────────────────────────────────────────────────────────────────────────────

/** service_role, kernel schema. The DELEGATED arm + mark_refund_state. */
function kernelServiceClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
    db: { schema: 'kernel' },
  });
}

/** The caller's own JWT, kernel schema. Everything that reads auth.uid(). */
function kernelCallerClient(authHeader: string): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
    db: { schema: 'kernel' },
  });
}

/** service_role, public schema. Rate limiting only. */
function publicServiceClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// The denial witness (EA-1 — caller's client, in its own request)
// ─────────────────────────────────────────────────────────────────────────────

async function recordMoneyDenial(
  caller: SupabaseClient,
  subjectKind: 'order' | 'payment' | 'approval_request',
  subjectId: string | null,
  errorCode: string,
): Promise<void> {
  if (!subjectId || !isUuid(subjectId)) return;
  try {
    const { error } = await caller.rpc('record_money_denial', {
      p_action: 'refund.execute',
      p_subject_kind: subjectKind,
      p_subject_id: subjectId,
      p_error_code: errorCode.slice(0, 120),
    });
    if (error) console.warn('[refund-execute] record_money_denial failed:', error.message);
  } catch (err) {
    console.warn('[refund-execute] record_money_denial threw:', String(err));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Context read
// ─────────────────────────────────────────────────────────────────────────────

type ContextResult =
  | { ok: true; ctx: RefundExecutionContext }
  | { ok: false; status: number; code: string; detail: string };

async function loadContext(service: SupabaseClient, refundId: string): Promise<ContextResult> {
  const { data, error } = await service.rpc(CONTEXT_RPC, { p_refund_id: refundId });
  if (error) {
    // PGRST202 = function not found in the exposed schema cache.
    const missing = error.code === 'PGRST202' || /could not find the function|does not exist/i.test(error.message);
    return {
      ok: false,
      status: missing ? 501 : httpStatusForRpcError(error.message),
      code: missing ? 'context_rpc_missing' : 'context_read_failed',
      detail: missing
        ? `kernel.${CONTEXT_RPC}(uuid) is not deployed. service_role holds USAGE on kernel but NO table grants (085:2093-2096), so the executor cannot resolve refund_id → payment_id → stripe_payment_intent_id without it. See docs/phase2/_impl/E4_refund_executor.md §3.`
        : error.message,
    };
  }
  if (!data || typeof data !== 'object') {
    return { ok: false, status: 404, code: 'refund_not_found', detail: `refund ${refundId}` };
  }
  return { ok: true, ctx: data as RefundExecutionContext };
}

// ─────────────────────────────────────────────────────────────────────────────
// Execute ONE refund row. The whole money path lives here.
// ─────────────────────────────────────────────────────────────────────────────

export type ExecuteOutcome = {
  refund_id: string;
  outcome:
    | 'submitted'
    | 'succeeded'
    | 'failed'
    | 'noop_replay'
    | 'refused'
    | 'stripe_error'
    | 'state_sync_deferred';
  stripe_refund_ref?: string | null;
  code?: string;
  detail?: string;
  retryable?: boolean;
  http?: number;
};

/**
 * Record what Stripe's OWN Refund object says. Shared by both execution modes,
 * because the truth is identical whether the object came back from a create, a
 * deduped replay of one, a fetch by ref, or a search of the PaymentIntent: it
 * is one Stripe Refund, and `mark_refund_state` is forward-only, write-once on
 * the ref, and `noop_replay` on an identical terminal (085:1737-1789). Calling
 * this twice with the same object is therefore always safe.
 */
async function applyStateSync(
  service: SupabaseClient,
  refundId: string,
  commandKey: string,
  ctx: RefundExecutionContext,
  stripeRefund: unknown,
): Promise<ExecuteOutcome> {
  const refundObj = stripeRefund as { id?: string; status?: string; failure_reason?: string };
  const syncPlan = planStateSync(refundObj);
  if (syncPlan.kind === 'refuse') {
    // Stripe answered 2xx with something we cannot record. Money moved and we
    // cannot prove it — page immediately, leave the row `pending` so the sweep
    // retries (the same key returns the same object).
    await captureException('refund-execute:unrecordable-refund', new Error(`${syncPlan.code}: ${syncPlan.detail}`), {
      refund_id: refundId, payment_id: ctx.payment_id,
    });
    return { refund_id: refundId, outcome: 'state_sync_deferred', code: syncPlan.code, detail: syncPlan.detail, retryable: true, http: 500 };
  }

  let last: ExecuteOutcome['outcome'] = 'state_sync_deferred';
  for (const step of syncPlan.steps) {
    const { error } = await service.rpc('mark_refund_state', {
      p_refund_id: refundId,
      p_new_status: step.new_status,
      p_stripe_refund_ref: step.stripe_refund_ref,
      p_failure_code: step.failure_code,
      p_command_key: commandKey,
    });
    if (error) {
      // MONEY MOVED, DB WRITE FAILED — the dangerous case. Do not retry inline
      // and do not compensate. The row stays where it is; the next sweep tick
      // replays the SAME Stripe key, gets the SAME `re_…` back, and re-runs
      // this callback. `mark_refund_state` is forward-only and returns
      // `noop_replay` on an identical terminal (085:1752-1755), so convergence
      // is guaranteed and double-refund is impossible.
      const verdict = classifyStateSyncError(error.message);
      console.error('[refund-execute] mark_refund_state did not apply:', {
        refund_id: refundId,
        stripe_refund_ref: step.stripe_refund_ref,
        target: step.new_status,
        verdict: verdict.kind,
        error: error.message,
      });
      if (verdict.page) {
        await captureException('refund-execute:state-sync', new Error(`mark_refund_state(${step.new_status}): ${error.message}`), {
          refund_id: refundId,
          payment_id: ctx.payment_id,
          stripe_refund_ref: step.stripe_refund_ref,
        });
      }
      if (verdict.kind === 'converged') {
        // A concurrent worker already advanced this row past us with the same
        // deterministic key, so the same `re_…`. Nothing to do and nothing to
        // retry — treating this as a failure is how a healthy race becomes a
        // hot loop against Stripe.
        return {
          refund_id: refundId,
          outcome: 'noop_replay',
          code: 'converged_elsewhere',
          detail: error.message,
          stripe_refund_ref: step.stripe_refund_ref,
          retryable: false,
          http: 200,
        };
      }
      return {
        refund_id: refundId,
        outcome: 'state_sync_deferred',
        code: verdict.kind === 'conflict' ? 'state_sync_conflict' : 'mark_refund_state_failed',
        detail: error.message,
        stripe_refund_ref: step.stripe_refund_ref,
        retryable: verdict.kind === 'retry',
        http: 500,
      };
    }
    last = step.new_status;
  }

  console.log('[refund-execute] refund complete:', {
    refund_id: refundId,
    stripe_refund_ref: refundObj.id,
    final_state: last,
  });
  return { refund_id: refundId, outcome: last, stripe_refund_ref: refundObj.id ?? null, http: 200 };
}

/**
 * Establish, then act. Never create before establishing.
 *
 * Two shapes, both decided by `planReconcile`:
 *   fetch_ref          the row already names its Stripe Refund (every
 *                      `submitted` row does — refund_ref_pairing_ck, 085:93).
 *                      GET it and sync. This is the leg that finishes E4 §5
 *                      case 4's stranded row, which nothing could reach before
 *                      and which keeps BP-12 blocking the buyer's account
 *                      deletion (085:249-262) for as long as it stands.
 *   search_then_create a `pending` row whose key has expired. Search the
 *                      PaymentIntent's refunds for the `metadata[refund_id]`
 *                      this function always writes. Found ⇒ sync it, no second
 *                      refund. Not found ⇒ nothing was ever created, so the
 *                      create is safe. Ambiguous (more pages than we read) ⇒
 *                      REFUSE and page a human; guessing here spends money.
 */
async function reconcileOne(
  service: SupabaseClient,
  refundId: string,
  commandKey: string,
  ctx: RefundExecutionContext,
): Promise<ExecuteOutcome> {
  const plan = planReconcile(ctx);

  if (plan.kind === 'refuse') {
    await captureException('refund-execute:reconcile-refusal', new Error(`${plan.code}: ${plan.detail}`), {
      refund_id: refundId, payment_id: ctx.payment_id,
    });
    return { refund_id: refundId, outcome: 'refused', code: plan.code, detail: plan.detail, retryable: plan.retryable, http: 409 };
  }
  if (plan.kind === 'noop_replay') {
    return { refund_id: refundId, outcome: 'noop_replay', code: plan.reason, stripe_refund_ref: plan.stripe_refund_ref, http: 200 };
  }

  if (plan.kind === 'fetch_ref') {
    let res: { ok: boolean; status: number; data: unknown };
    try {
      res = await stripeFetchRaw(`/refunds/${encodeURIComponent(plan.stripe_refund_ref)}`, { method: 'GET' });
    } catch (err) {
      return { refund_id: refundId, outcome: 'stripe_error', code: 'network', detail: String(err), retryable: true, http: 502 };
    }
    if (!res.ok) {
      // A ref we hold that Stripe does not know is a reconciliation incident,
      // not a retry: we must never respond to it by creating a replacement.
      await captureException('refund-execute:reconcile-fetch', new Error(`GET /refunds/${plan.stripe_refund_ref} → ${res.status}`), {
        refund_id: refundId, payment_id: ctx.payment_id,
      });
      return { refund_id: refundId, outcome: 'stripe_error', code: 'resource_missing', detail: `HTTP ${res.status}`, retryable: false, http: 409 };
    }
    return await applyStateSync(service, refundId, commandKey, ctx, res.data);
  }

  // search_then_create
  let list: { ok: boolean; status: number; data: unknown };
  try {
    list = await stripeFetchRaw(`/refunds?payment_intent=${encodeURIComponent(plan.payment_intent)}&limit=100`, { method: 'GET' });
  } catch (err) {
    return { refund_id: refundId, outcome: 'stripe_error', code: 'network', detail: String(err), retryable: true, http: 502 };
  }
  if (!list.ok) {
    return { refund_id: refundId, outcome: 'stripe_error', code: 'api_error', detail: `HTTP ${list.status}`, retryable: true, http: 503 };
  }

  const body = list.data as { data?: Array<{ id?: string; status?: string; failure_reason?: string; metadata?: Record<string, string> }>; has_more?: boolean };
  const rows = Array.isArray(body?.data) ? body.data : [];
  const match = rows.find((r) => r?.metadata?.refund_id === plan.metadata_refund_id);

  if (match) {
    console.log('[refund-execute] reconcile found an existing Stripe refund — NOT creating a second:', {
      refund_id: refundId, stripe_refund_ref: match.id,
    });
    return await applyStateSync(service, refundId, commandKey, ctx, match);
  }
  if (body?.has_more === true) {
    // We did not see the whole set, so "not found" is not established.
    await captureException('refund-execute:reconcile-ambiguous', new Error(`>100 refunds on ${plan.payment_intent}; existence not established`), {
      refund_id: refundId, payment_id: ctx.payment_id,
    });
    return { refund_id: refundId, outcome: 'refused', code: 'reconcile_ambiguous', detail: 'more refunds on this PaymentIntent than one page — human reconciliation required', retryable: false, http: 409 };
  }

  // Established: nothing exists for this refund_id. Creating is safe, and it
  // still goes out under the deterministic key so a concurrent worker converges.
  console.log('[refund-execute] reconcile established no Stripe refund exists — creating:', { refund_id: refundId });
  let res: { ok: boolean; status: number; data: unknown };
  try {
    res = await stripeFetchRaw('/refunds', { method: 'POST', idempotencyKey: plan.create.idempotency_key, body: plan.create.body });
  } catch (err) {
    const verdict = classifyStripeRefundError(err instanceof Error ? err : new Error(String(err)));
    return { refund_id: refundId, outcome: 'stripe_error', code: verdict.class, detail: String(err), retryable: verdict.retryable, http: 502 };
  }
  if (!res.ok) {
    const verdict = classifyStripeRefundError({
      status: res.status,
      error: (res.data as { error?: { type?: string; code?: string; message?: string } })?.error,
    });
    return { refund_id: refundId, outcome: 'stripe_error', code: verdict.class, detail: `HTTP ${res.status}`, retryable: verdict.retryable, http: verdict.retryable ? 503 : 409 };
  }
  return await applyStateSync(service, refundId, commandKey, ctx, res.data);
}

async function executeOne(
  service: SupabaseClient,
  refundId: string,
  commandKey: string,
  expected: { order_id?: string | null },
  /**
   * DB-ISSUED, never worker-chosen (093 slice 10i). 'create' means the row's
   * Stripe idempotency key is still a valid dedup token; 'reconcile' means it
   * is not, and the worker must establish what exists at Stripe before it may
   * create anything. `action: execute` defaults to 'create' because a
   * hand-driven single execution is, by construction, the key's first use.
   */
  mode: RefundExecutionMode = 'create',
): Promise<ExecuteOutcome> {
  if (!isUuid(refundId)) {
    return { refund_id: refundId, outcome: 'refused', code: 'malformed_refund_id', detail: refundId, http: 400 };
  }

  const loaded = await loadContext(service, refundId);
  if (!loaded.ok) {
    return { refund_id: refundId, outcome: 'refused', code: loaded.code, detail: loaded.detail, http: loaded.status };
  }
  const ctx = loaded.ctx;

  // ── RECONCILE. The branch that exists because Stripe forgets. ───────────
  // Stripe retains an idempotency key's result for 24 HOURS. E4 §5 cases
  // 2/3/13 all recover by replaying `refund_<refund_id>` and relying on the
  // ORIGINAL object coming back — true inside that window and false outside
  // it, where the identical request creates a SECOND, REAL refund. The
  // database decides which side of the window a row is on; this branch is
  // what the worker runs when the answer is "not safe to create blind".
  if (mode === 'reconcile') {
    return await reconcileOne(service, refundId, commandKey, ctx);
  }

  // ── The binding gate. Nothing reaches Stripe without passing this. ───────
  const plan = planRefund(ctx, expected);

  if (plan.kind === 'refuse') {
    console.warn('[refund-execute] refused:', { refund_id: refundId, code: plan.code, detail: plan.detail });
    if (!plan.retryable) {
      // A refusal on the binding itself is the alarm, not the noise.
      await captureException('refund-execute:binding-refusal', new Error(`${plan.code}: ${plan.detail}`), {
        refund_id: refundId,
        payment_id: ctx.payment_id,
        order_id: ctx.order_id ?? undefined,
      });
    }
    return {
      refund_id: refundId,
      outcome: 'refused',
      code: plan.code,
      detail: plan.detail,
      retryable: plan.retryable,
      http: 409,
    };
  }

  if (plan.kind === 'noop_replay') {
    // Application-level idempotency: a re-delivered job is a no-op.
    console.log('[refund-execute] noop replay:', { refund_id: refundId, reason: plan.reason });
    return {
      refund_id: refundId,
      outcome: 'noop_replay',
      code: plan.reason,
      stripe_refund_ref: plan.stripe_refund_ref,
      http: 200,
    };
  }

  // ── Stripe. Deterministic key derived from the refund id. ────────────────
  console.log('[refund-execute] issuing Stripe refund:', {
    refund_id: refundId,
    payment_id: ctx.payment_id,
    order_id: ctx.order_id,
    amount_minor: plan.amount_minor,
    idempotency_key: plan.idempotency_key,
  });

  let res: { ok: boolean; status: number; data: unknown };
  try {
    res = await stripeFetchRaw('/refunds', {
      method: 'POST',
      idempotencyKey: plan.idempotency_key,
      body: plan.body,
    });
  } catch (err) {
    // No HTTP response: DNS/TLS/socket/abort. Stripe MAY have created the
    // refund. We write NOTHING — the row stays `pending` and the next sweep
    // replays the SAME key, which returns the SAME object. Replay, not re-pay.
    const verdict = classifyStripeRefundError(err instanceof Error ? err : new Error(String(err)));
    console.error('[refund-execute] Stripe transport failure — row left pending for replay:', {
      refund_id: refundId, class: verdict.class,
    });
    return {
      refund_id: refundId,
      outcome: 'stripe_error',
      code: verdict.class,
      detail: String(err),
      retryable: verdict.retryable,
      http: 502,
    };
  }

  if (!res.ok) {
    const verdict = classifyStripeRefundError({
      status: res.status,
      error: (res.data as { error?: { type?: string; code?: string; message?: string } })?.error,
    });
    const stripeErr = (res.data as { error?: { code?: string; message?: string } })?.error;
    console.error('[refund-execute] Stripe refund create failed:', {
      refund_id: refundId,
      status: res.status,
      class: verdict.class,
      code: stripeErr?.code,
      retryable: verdict.retryable,
    });
    if (verdict.page) {
      await captureException('refund-execute:stripe', new Error(`${verdict.class}: ${stripeErr?.message ?? res.status}`), {
        refund_id: refundId,
        payment_id: ctx.payment_id,
        stripe_code: stripeErr?.code ?? '',
      });
    }
    // verdict.writesState is always false — see executor.ts.
    return {
      refund_id: refundId,
      outcome: 'stripe_error',
      code: verdict.class,
      detail: stripeErr?.message ?? `HTTP ${res.status}`,
      retryable: verdict.retryable,
      http: verdict.retryable ? 503 : 409,
    };
  }

  // ── The callback. From here on money HAS moved. ──────────────────────────
  return await applyStateSync(service, refundId, commandKey, ctx, res.data);
}

// ─────────────────────────────────────────────────────────────────────────────
// Handler
// ─────────────────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  const headers = responseHeaders(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405, headers);

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice('Bearer '.length) : '';

  let body: Record<string, unknown> = {};
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    body = {};
  }

  // ── The wrong-payment guard, applied to the REQUEST before anything else ──
  const clean = assertNoClientPaymentReference(body);
  if (!clean.ok) {
    console.warn('[refund-execute] rejected request naming the money:', clean.detail);
    return json({ error: clean.code, detail: clean.detail }, 400, headers);
  }

  const action = typeof body.action === 'string' ? body.action : '';
  const commandKey = typeof body.command_key === 'string' && body.command_key.length > 0
    ? body.command_key
    : `refund-execute:${crypto.randomUUID()}`;
  // The command key lands in the immutable audit; 088:1622 documents the shape.
  if (!/^[A-Za-z0-9._:-]{1,64}$/.test(commandKey)) {
    return json({ error: 'invalid_input', detail: 'command_key must be 1-64 chars of [A-Za-z0-9._:-]' }, 400, headers);
  }

  const service = kernelServiceClient();

  try {
    // ═══ MACHINE PATH — the sweep ═══════════════════════════════════════════
    // Cron-triggered, no human actor. This is the leg that drains every
    // `pending` row: the ones `catalog.cancel_event` inserted, and the ones a
    // crashed or half-failed earlier attempt left behind.
    if (action === 'sweep') {
      const cronOk = INTERNAL_CRON_SECRET.length > 0 && constantTimeEqual(token, INTERNAL_CRON_SECRET);
      const svcOk = SUPABASE_SERVICE_ROLE_KEY.length > 0 && constantTimeEqual(token, SUPABASE_SERVICE_ROLE_KEY);
      if (!cronOk && !svcOk) return json({ error: 'Unauthorized' }, 401, headers);

      // THE WORK LIST IS A LEASED CLAIM, NOT A LIST (093 slice 10i). The
      // database chooses which refunds are eligible, orders them oldest-money-
      // first, bounds the batch, hands each row to exactly ONE worker for a
      // bounded lease, and decides per row whether the Stripe idempotency key
      // is still a valid dedup token. Both parameters are throughput only and
      // are CLAMPED server-side; neither can name a refund, a payment, an
      // amount or a destination. See docs/phase2/_impl/H1_refund_architecture.md.
      const limit = Number.isInteger(body.limit) ? (body.limit as number) : 25;
      const leaseSeconds = Number.isInteger(body.lease_seconds) ? (body.lease_seconds as number) : 900;
      const { data, error } = await service.rpc('claim_refunds_for_execution', {
        p_limit: limit,
        p_lease_seconds: leaseSeconds,
      });
      if (error) {
        const missing = error.code === 'PGRST202' || /could not find the function|does not exist/i.test(error.message);
        return json({
          error: missing ? 'claim_rpc_missing' : 'sweep_claim_failed',
          detail: missing
            ? `kernel.claim_refunds_for_execution(int, int) is not deployed — 093 slice 10i; see docs/phase2/_impl/H1_refund_architecture.md §4`
            : error.message,
        }, missing ? 501 : 500, headers);
      }

      const claimed = planClaimedBatch((data as { refunds?: ClaimedRefund[] } | null)?.refunds);
      const results: ExecuteOutcome[] = [];
      // One failure NEVER blocks the batch (the enforce-transfer-expiry rule).
      for (const row of claimed) {
        try {
          // The command key is the DATABASE's (`refund.execute:<uuid>`, 42
          // chars — inside the 64-char audit budget with no truncation).
          // Truncating or minting one would collapse two different refunds
          // onto one audit identity.
          results.push(await executeOne(service, row.refund_id, row.command_key, {}, row.execution_mode));
        } catch (err) {
          await captureException('refund-execute:sweep', err, { refund_id: row.refund_id });
          results.push({ refund_id: row.refund_id, outcome: 'stripe_error', code: 'unhandled', detail: String(err), retryable: true });
        }
      }
      const counts = results.reduce<Record<string, number>>((acc, r) => {
        acc[r.outcome] = (acc[r.outcome] ?? 0) + 1;
        return acc;
      }, {});
      console.log('[refund-execute] sweep complete:', { claimed: claimed.length, counts });
      return json({ status: 'ok', attempted: claimed.length, counts, results }, 200, headers);
    }

    // ═══ HUMAN PATHS — a platform/operator JWT is mandatory ══════════════════
    if (!authHeader.startsWith('Bearer ') || token.length === 0) {
      return json({ error: 'Missing or invalid Authorization header' }, 401, headers);
    }
    const caller = kernelCallerClient(authHeader);
    const publicSvc = publicServiceClient();

    const { data: { user }, error: userErr } = await createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
      .auth.getUser(token);
    if (userErr || !user) return json({ error: 'Invalid or expired token' }, 401, headers);

    // Fail-closed throughput limiter (spec §3.5). This is a THROUGHPUT limit,
    // not a value limit — the value control is the RPC's cumulative support cap
    // (085:549-563) and the Σ-guard, not this.
    const { data: rl, error: rlErr } = await publicSvc.rpc('check_rate_limit', {
      p_user_id: user.id, p_action: 'refund-execute', p_max: 10, p_window_seconds: 60,
    });
    if (rlErr || rl !== true) {
      return json({ error: rlErr ? 'rate_limit_unavailable' : 'rate_limited' }, 429, headers);
    }

    // ── action: record — create the refund intent in the DB ────────────────
    if (action === 'record') {
      const orderId = typeof body.order_id === 'string' ? body.order_id : null;
      const amountMinor = typeof body.amount_minor === 'number' ? body.amount_minor : null;
      const reasonCode = typeof body.reason_code === 'string' ? body.reason_code : '';
      if (!isUuid(orderId ?? '')) return json({ error: 'invalid_input', detail: 'order_id must be a uuid' }, 400, headers);
      if (!Number.isInteger(amountMinor) || (amountMinor as number) <= 0) {
        return json({ error: 'invalid_input', detail: 'amount_minor must be a positive integer' }, 400, headers);
      }

      // ── PFA-23 ARM SELECTION, CORRECTED (H1_refund_architecture.md §5) ──
      // The arm is chosen by command key alone (085:494-520), but the CALLER
      // differs, and the earlier routing was unreachable:
      //
      //   DELEGATED (`req:<uuid>`) reads no auth.uid(), so it runs on the
      //   service client against `kernel.refund_primary_order` — exactly the
      //   caller PFA-23's ruling names.
      //
      //   DIRECT does NOT go to `refund_primary_order`. Its authority branch
      //   requires `kernel.is_platform(...)`, i.e. `auth.uid()`, while EXECUTE
      //   is service_role-only (085:2129-2130, 085:2152). PostgREST derives ONE
      //   database role per request, so that request is either service_role
      //   (auth.uid() NULL ⇒ is_platform fails) or authenticated (EXECUTE
      //   denied). It is unreachable in both directions, and no caller shape
      //   fixes it.
      //
      //   The platform's authority is NOT missing: `kernel.request_order_refund`
      //   (085:850) IS granted to `authenticated`, is SECURITY DEFINER, carries
      //   the caller's `auth.uid()`, evaluates the SAME `is_platform` predicates
      //   and the SAME platform_support cap, and — for platform_admin /
      //   platform_risk / an in-cap platform_support — sets `v_execute := true`
      //   and calls `refund_primary_order` definer→definer under a delegated
      //   key bound to an auto-approved witness record (085:995-1036). Suite
      //   149 D2 asserts it returns `status: 'executed'`. So the direct branch
      //   is DEFINER-INTERNAL, not an edge-callable arm, and this is the door.
      const arm = classifyArm(commandKey);
      const atomIdsForRecord = Array.isArray(body.atom_ids) ? (body.atom_ids as string[]) : [];
      if (arm === 'direct' && !atomIdsForRecord.every((a) => isUuid(a))) {
        return json({ error: 'invalid_input', detail: 'atom_ids must all be uuids' }, 400, headers);
      }

      const { data, error } = arm === 'delegated'
        ? await service.rpc('refund_primary_order', {
            p_order_id: orderId,
            p_amount_minor: amountMinor,
            p_reason_code: reasonCode,
            p_command_key: commandKey,
          })
        : await caller.rpc('request_order_refund', {
            p_order_id: orderId,
            p_atom_ids: atomIdsForRecord,
            p_amount_minor: amountMinor,
            p_reason_code: reasonCode,
            p_command_key: commandKey,
          });

      if (error) {
        console.error('[refund-execute] refund record failed:', { arm, order_id: orderId, error: error.message });
        if (isMoneyDenial(error.message)) {
          await recordMoneyDenial(caller, 'order', orderId, error.message.slice(0, 120));
        }
        return json({ error: arm === 'delegated' ? 'refund_primary_order_failed' : 'request_order_refund_failed', arm, detail: error.message },
          httpStatusForRpcError(error.message), headers);
      }

      // `request_order_refund` answers 'executed' (auto-exec tier), 'parked'
      // (dual control — a second human must approve) or 'idempotency_replay';
      // only the first mints a refund row that `action: execute` can drive.
      const result = data as { status?: string; refund_id?: string; request_id?: string; voided?: number; consumed?: unknown };
      // `idempotency_replay` returns the SAME refund_id (085:484-487, :616-621)
      // — a duplicate request converges on one refund, never two.
      return json({
        status: result?.status ?? 'ok',
        arm,
        refund_id: result?.refund_id ?? null,
        request_id: result?.request_id ?? null,
        atoms_voided: result?.voided ?? 0,
        consumed: result?.consumed ?? [],
        next: result?.refund_id
          ? 'call action:execute with this refund_id'
          : 'parked for dual control — a second approver calls kernel.approve_refund_request',
      }, 200, headers);
    }

    // ── action: admin_refund — the payment-scoped break-glass ──────────────
    // `kernel.admin_refund` IS granted to `authenticated` (085:2137) so this
    // arm runs entirely on the caller's own client. It is the sanctioned
    // destination for `custody_moved` (085:574).
    if (action === 'admin_refund') {
      const paymentSubject = typeof body.subject_payment_id === 'string' ? body.subject_payment_id : null;
      const atomIds = Array.isArray(body.atom_ids) ? (body.atom_ids as string[]) : [];
      const amountMinor = typeof body.amount_minor === 'number' ? body.amount_minor : null;
      const reasonCode = typeof body.reason_code === 'string' ? body.reason_code : '';
      if (!isUuid(paymentSubject ?? '')) {
        return json({ error: 'invalid_input', detail: 'subject_payment_id must be a uuid' }, 400, headers);
      }
      if (!atomIds.every((a) => isUuid(a))) {
        return json({ error: 'invalid_input', detail: 'atom_ids must all be uuids' }, 400, headers);
      }
      const { data, error } = await caller.rpc('admin_refund', {
        p_payment_id: paymentSubject,
        p_atom_ids: atomIds,
        p_amount_minor: amountMinor,
        p_reason_code: reasonCode,
        p_command_key: commandKey,
      });
      if (error) {
        if (isMoneyDenial(error.message)) {
          await recordMoneyDenial(caller, 'payment', paymentSubject, error.message.slice(0, 120));
        }
        return json({ error: 'admin_refund_failed', detail: error.message },
          httpStatusForRpcError(error.message), headers);
      }
      const result = data as { status?: string; refund_id?: string };
      return json({
        status: result?.status ?? 'ok',
        refund_id: result?.refund_id ?? null,
        next: 'call action:execute with this refund_id',
      }, 200, headers);
    }

    // ── action: execute — the money leg ────────────────────────────────────
    if (action === 'execute') {
      const refundId = typeof body.refund_id === 'string' ? body.refund_id : '';
      if (!isUuid(refundId)) return json({ error: 'invalid_input', detail: 'refund_id must be a uuid' }, 400, headers);
      // `expected_order_id` is the caller's ASSERTION, used only to refuse a
      // mismatch. It never selects the payment.
      const expectedOrderId = typeof body.expected_order_id === 'string' ? body.expected_order_id : null;

      const outcome = await executeOne(service, refundId, commandKey, { order_id: expectedOrderId });
      const status = outcome.http ?? (outcome.outcome === 'refused' ? 409 : 200);
      return json({ status: outcome.outcome, ...outcome }, status, headers);
    }

    return json({ error: "action must be 'record' | 'admin_refund' | 'execute' | 'sweep'" }, 400, headers);
  } catch (err) {
    await captureException('refund-execute', err);
    return json({ error: 'Internal server error' }, 500, headers);
  }
});

// Exported for the vitest protocol suite (Deno-only imports keep this module
// unloadable there, so the tests target ./executor.ts; this export exists so a
// future Deno-side integration test can drive the same function).
export { buildRefundIdempotencyKey, executeOne };
