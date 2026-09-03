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
  planRefund,
  planStateSync,
  planSweep,
  type RefundExecutionContext,
  type SweepCandidate,
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

async function executeOne(
  service: SupabaseClient,
  refundId: string,
  commandKey: string,
  expected: { order_id?: string | null },
): Promise<ExecuteOutcome> {
  if (!isUuid(refundId)) {
    return { refund_id: refundId, outcome: 'refused', code: 'malformed_refund_id', detail: refundId, http: 400 };
  }

  const loaded = await loadContext(service, refundId);
  if (!loaded.ok) {
    return { refund_id: refundId, outcome: 'refused', code: loaded.code, detail: loaded.detail, http: loaded.status };
  }
  const ctx = loaded.ctx;

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
  const refundObj = res.data as { id?: string; status?: string; failure_reason?: string };
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
    amount_minor: plan.amount_minor,
  });
  return { refund_id: refundId, outcome: last, stripe_refund_ref: refundObj.id ?? null, http: 200 };
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

      const limit = Number.isInteger(body.limit) ? Math.max(1, Math.min(body.limit as number, 100)) : 25;
      const { data, error } = await service.rpc('list_pending_refunds', { p_limit: limit });
      if (error) {
        const missing = error.code === 'PGRST202' || /could not find the function|does not exist/i.test(error.message);
        return json({
          error: missing ? 'context_rpc_missing' : 'sweep_read_failed',
          detail: missing
            ? `kernel.list_pending_refunds(int) is not deployed — see docs/phase2/_impl/E4_refund_executor.md §3`
            : error.message,
        }, missing ? 501 : 500, headers);
      }

      const rows = (data as { refunds?: SweepCandidate[] } | null)?.refunds ?? [];
      const ids = planSweep(rows, { limit });
      const results: ExecuteOutcome[] = [];
      // One failure NEVER blocks the batch (the enforce-transfer-expiry rule).
      for (const id of ids) {
        try {
          // `sweep:<uuid>` is 42 chars — inside the 64-char audit command-key
          // budget WITHOUT truncation. Truncating a key would collapse two
          // different refunds onto one audit identity.
          results.push(await executeOne(service, id, `sweep:${id}`, {}));
        } catch (err) {
          await captureException('refund-execute:sweep', err, { refund_id: id });
          results.push({ refund_id: id, outcome: 'stripe_error', code: 'unhandled', detail: String(err), retryable: true });
        }
      }
      const counts = results.reduce<Record<string, number>>((acc, r) => {
        acc[r.outcome] = (acc[r.outcome] ?? 0) + 1;
        return acc;
      }, {});
      console.log('[refund-execute] sweep complete:', { considered: rows.length, attempted: ids.length, counts });
      return json({ status: 'ok', attempted: ids.length, counts, results }, 200, headers);
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

      // PFA-23 arm selection is by command key alone (085:494-520).
      // DELEGATED (`req:<uuid>`) needs no auth.uid() → service client.
      // DIRECT needs is_platform() → the caller's client, which is the only
      // client carrying the platform identity. See executor.ts `classifyArm`
      // for why the direct arm currently returns 42501 with this grant set.
      const arm = classifyArm(commandKey);
      const rpcClient = arm === 'delegated' ? service : caller;
      const { data, error } = await rpcClient.rpc('refund_primary_order', {
        p_order_id: orderId,
        p_amount_minor: amountMinor,
        p_reason_code: reasonCode,
        p_command_key: commandKey,
      });

      if (error) {
        console.error('[refund-execute] refund_primary_order failed:', { arm, order_id: orderId, error: error.message });
        if (isMoneyDenial(error.message)) {
          await recordMoneyDenial(caller, 'order', orderId, error.message.slice(0, 120));
        }
        return json({ error: 'refund_primary_order_failed', arm, detail: error.message },
          httpStatusForRpcError(error.message), headers);
      }

      const result = data as { status?: string; refund_id?: string; voided?: number; consumed?: unknown };
      // `idempotency_replay` returns the SAME refund_id (085:484-487, :616-621)
      // — a duplicate request converges on one refund, never two.
      return json({
        status: result?.status ?? 'ok',
        arm,
        refund_id: result?.refund_id ?? null,
        atoms_voided: result?.voided ?? 0,
        consumed: result?.consumed ?? [],
        next: 'call action:execute with this refund_id',
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
