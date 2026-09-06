// =============================================================================
// ops-refund-execute — the money leg of an APPROVED console refund
// (docs/admin-console/DESIGN_AND_EXECUTION_PLAN.md §2 decision 8)
// =============================================================================
// WHAT THIS IS
//   `ops.execute_action('refund_execute', …)` → second-founder approval →
//   `ops.action_dispatch` leaves the action in state `processing` with
//   result {handoff:'ops-refund-execute', stripe_payment_intent_id,
//   amount_cents}. Nothing in Postgres talks to Stripe. This function is the
//   handoff target: it re-verifies the caller and the action, issues
//   `POST /v1/refunds` under the deterministic key `ops_action_<action_id>`,
//   and reports back through `ops.record_action_outcome` (service_role only).
//
// THE INVARIANT
//   ACTION-ROW-DRIVEN. The ONLY client input is `action_id`. Payment,
//   PaymentIntent, amount and reason are read from `ops.action` and
//   `public.payments` inside the database; a body that names any of them is
//   refused (`assertNoClientPaymentReference`, mirroring refund-execute).
//
// WHO MAY CALL
//   A founder JWT: `ops.whoami()` (executed AS the caller) must return
//   role = platform_admin and aal = aal2. The service client only ever runs
//   after that gate, and the action must additionally carry an `approved`
//   ops.approval row. Hidden navigation is not security; the DB is the wall.
//
// LOCAL STATE
//   This function does NOT write public.payments. `payments.status` →
//   'refunded' (and stripe_refund_id) is set by the existing
//   `charge.refunded` handler in stripe-webhook/index.ts, exactly as for a
//   Dashboard refund. Hence the action rests at `succeeded_at_provider` until
//   the webhook lands; the reconciliation detector (117) tracks the gap.
//
// FAILURE / RETRY SEMANTICS (see README.md)
//   2xx                → succeeded_at_provider (provider_ref = re_…)        200
//   definite 4xx       → failed (terminal; Stripe code + message, no key)   422
//   charge_already_refunded → list refunds; adopt existing → s_at_provider 200
//   transport/5xx/429/409-in-use → list refunds by metadata.ops_action_id;
//                        found → succeeded_at_provider, else `unknown`      502
//   `unknown` is retryable from the console under the SAME idempotency key,
//   so a retry can only replay — never mint a second refund.
//
// DEPLOYMENT PRECONDITIONS (owner steps, not performed by this file):
//   1. Migration 115 applied; `ops` in PostgREST exposed schemas.
//   2. service_role can SELECT ops.action / ops.approval (see README).
//   3. Deployed with verify_jwt ON; then `refund_execute_enabled` flipped.
// =============================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetchRaw } from '../_shared/stripe.ts';
import {
  type ActionRow,
  type ApprovalRow,
  type OutcomeState,
  type PaymentRow,
  type StripeRefundObject,
  buildOpsRefundIdempotencyKey,
  checkActionPreconditions,
  checkPaymentPreconditions,
  classifyRefundCreate,
  findExistingRefund,
  httpStatusForState,
  planRefundBody,
  providerResult,
  sanitizeErrorMessage,
  stripeKeyMode,
  validateRequest,
} from './classify.ts';

const FN = 'ops-refund-execute';

const SUPABASE_URL              = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SUPABASE_ANON_KEY         = Deno.env.get('SUPABASE_ANON_KEY')!;
// Read ONLY to derive live/test mode from the prefix. The transport in
// _shared/stripe.ts owns the header; the key value is never logged or returned.
const STRIPE_KEY_MODE = stripeKeyMode(Deno.env.get('STRIPE_SECRET_KEY'));

// Optional: the console's origin for browser-originated calls. The Next
// proxy is expected to call server-to-server, so no default origin is open.
const CONSOLE_ORIGIN = Deno.env.get('OPS_CONSOLE_ORIGIN') ?? '';

// ─────────────────────────────────────────────────────────────────────────────
// Response plumbing (same shape as delete-account / refund-execute)
// ─────────────────────────────────────────────────────────────────────────────

function responseHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin') ?? '';
  const cors: Record<string, string> = CONSOLE_ORIGIN && origin === CONSOLE_ORIGIN
    ? {
        'Access-Control-Allow-Origin': CONSOLE_ORIGIN,
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
        'Vary': 'Origin',
      }
    : {};
  return {
    ...cors,
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Cache-Control': 'no-store',
    'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
  };
}

function json(body: unknown, status: number, headers: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json' },
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Clients
// ─────────────────────────────────────────────────────────────────────────────

/** The caller's own JWT. Everything that must see auth.uid()/aal (whoami). */
function callerClient(authHeader: string): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/** service_role. Token verification, ops.action/approval reads, outcome RPC. */
function serviceClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Outcome recording — the ONLY database write this function performs
// ─────────────────────────────────────────────────────────────────────────────

async function recordOutcome(
  service: SupabaseClient,
  actionId: string,
  state: OutcomeState | 'processing',
  result: Record<string, unknown> | null,
  error: string | null,
  providerRef: string | null,
): Promise<{ ok: true } | { ok: false; message: string }> {
  const { error: rpcErr } = await service.schema('ops').rpc('record_action_outcome', {
    p_action_id:    actionId,
    p_state:        state,
    p_result:       result,
    p_error:        error,
    p_provider_ref: providerRef,
  });
  if (rpcErr) return { ok: false, message: rpcErr.message };
  return { ok: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// Stripe lookups
// ─────────────────────────────────────────────────────────────────────────────

async function listRefundsForIntent(paymentIntent: string): Promise<{ data?: StripeRefundObject[] } | null> {
  try {
    const res = await stripeFetchRaw(
      `/refunds?payment_intent=${encodeURIComponent(paymentIntent)}&limit=10`,
      { method: 'GET' },
    );
    if (!res.ok) return null;
    return res.data as { data?: StripeRefundObject[] };
  } catch {
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Handler
// ─────────────────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  const headers = responseHeaders(req);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405, headers);

  // ── 1. Auth header (fail closed) ──────────────────────────────────────────
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice('Bearer '.length) : '';
  if (token.length === 0) {
    return json({ error: 'Missing or invalid Authorization header' }, 401, headers);
  }

  // ── 2. Body: action_id and nothing else ───────────────────────────────────
  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return json({ error: 'invalid_input', detail: 'body must be JSON' }, 400, headers);
  }
  const request = validateRequest(raw);
  if (!request.ok) return json({ error: request.code, detail: request.detail }, 400, headers);
  const actionId = request.action_id;

  try {
    const service = serviceClient();

    // ── 3. Token is a real, live session ────────────────────────────────────
    const { data: { user }, error: userErr } = await service.auth.getUser(token);
    if (userErr || !user) return json({ error: 'Invalid or expired token' }, 401, headers);

    // ── 4. Operator gate, evaluated IN THE DATABASE as the caller ──────────
    //    ops.whoami raises 42501 for non-operators; we additionally require
    //    the platform_admin role and an aal2 (TOTP) session.
    const { data: who, error: whoErr } = await callerClient(authHeader).schema('ops').rpc('whoami');
    if (whoErr) {
      return json({ error: 'forbidden', detail: 'operator role required' }, 403, headers);
    }
    const identity = (who ?? {}) as { user_id?: string; role?: string; aal?: string };
    if (identity.user_id !== user.id || identity.role !== 'platform_admin') {
      return json({ error: 'forbidden', detail: 'platform_admin required' }, 403, headers);
    }
    if (identity.aal !== 'aal2') {
      return json({ error: 'forbidden', detail: 'step_up_required: aal2 session required' }, 403, headers);
    }

    // ── 5. Fail-closed throughput limiter (neighbour convention) ──────────
    const { data: rl, error: rlErr } = await service.rpc('check_rate_limit', {
      p_user_id: user.id, p_action: FN, p_max: 10, p_window_seconds: 60,
    });
    if (rlErr || rl !== true) {
      return json({ error: rlErr ? 'rate_limit_unavailable' : 'rate_limited' }, 429, headers);
    }

    // ── 6. The action and its approval ─────────────────────────────────────
    const { data: action, error: actErr } = await service
      .schema('ops')
      .from('action')
      .select('id, action_type, subject_kind, subject_id, state, params, result, approval_id')
      .eq('id', actionId)
      .maybeSingle();
    if (actErr) {
      // Most likely cause: service_role lacks SELECT on ops.action (README §grants).
      await captureException(`${FN}:load-action`, new Error(actErr.message), { action_id: actionId });
      return json({ error: 'action_unreadable', detail: 'could not read ops.action; see function logs' }, 500, headers);
    }

    const { data: approvals, error: apprErr } = await service
      .schema('ops')
      .from('approval')
      .select('id, state')
      .eq('action_id', actionId)
      .eq('state', 'approved');
    if (apprErr) {
      await captureException(`${FN}:load-approval`, new Error(apprErr.message), { action_id: actionId });
      return json({ error: 'approval_unreadable', detail: 'could not read ops.approval; see function logs' }, 500, headers);
    }

    const pre = checkActionPreconditions(action as ActionRow | null, approvals as ApprovalRow[] | null);
    if (!pre.ok) {
      return json({ action_id: actionId, error: pre.code, message: pre.detail }, 409, headers);
    }
    const act = action as ActionRow;

    // ── 7. The payment (by action.subject_id — never from the request) ─────
    const { data: payment, error: payErr } = await service
      .from('payments')
      .select('id, status, total, stripe_payment_intent_id, stripe_livemode')
      .eq('id', act.subject_id!)
      .maybeSingle();
    if (payErr) {
      await captureException(`${FN}:load-payment`, new Error(payErr.message), { action_id: actionId });
      return json({ error: 'payment_unreadable' }, 500, headers);
    }

    const pv = checkPaymentPreconditions(payment as PaymentRow | null, STRIPE_KEY_MODE);
    if (!pv.ok) {
      if (pv.code === 'cross_mode' || pv.code === 'row_mode_unclassified') {
        // Data-integrity fault: terminal for this action, and page it.
        await recordOutcome(service, actionId, 'failed', { mode_check: pv.code }, pv.detail, null);
        await captureException(`${FN}:mode-guard`, new Error(`${pv.code}: ${pv.detail}`), {
          action_id: actionId, payment_id: act.subject_id, financial_operation: 'refund',
        });
        return json({ action_id: actionId, state: 'failed', message: pv.detail }, 422, headers);
      }
      return json({ action_id: actionId, error: pv.code, message: pv.detail }, 409, headers);
    }

    if (pv.kind === 'already_refunded_locally') {
      // The webhook (or another route) already settled the local row. Nothing
      // to send to Stripe; close the action idempotently.
      const rec = await recordOutcome(service, actionId, 'succeeded', { note: 'already refunded locally' }, null, null);
      if (!rec.ok) return json({ error: 'outcome_unrecordable', detail: rec.message }, 500, headers);
      return json({ action_id: actionId, state: 'succeeded', message: 'already refunded locally' }, 200, headers);
    }

    const pay = payment as PaymentRow;
    const body = planRefundBody({
      actionId,
      paymentId: pay.id,
      paymentIntent: pv.payment_intent,
      paymentTotal: pay.total,
      amountCents: act.result?.amount_cents,
      reasonCode:  act.params?.reason_code,
    });
    const idempotencyKey = buildOpsRefundIdempotencyKey(actionId);

    // ── 8. Mark the attempt BEFORE money can move ──────────────────────────
    //    If we cannot record, we do not call Stripe.
    const started = await recordOutcome(
      service, actionId, 'processing',
      { stripe_request_started_at: new Date().toISOString(), partial: 'amount' in body },
      null, null,
    );
    if (!started.ok) {
      return json({ error: 'outcome_unrecordable', detail: started.message }, 500, headers);
    }

    console.log(JSON.stringify({ fn: FN, msg: 'issuing Stripe refund', action_id: actionId, payment_id: pay.id, partial: 'amount' in body }));

    // ── 9. POST /v1/refunds ────────────────────────────────────────────────
    let res: { ok: boolean; status: number; data: unknown } | Error;
    try {
      res = await stripeFetchRaw('/refunds', { method: 'POST', idempotencyKey, body });
    } catch (err) {
      res = err instanceof Error ? err : new Error(String(err));
    }
    const verdict = classifyRefundCreate(res);

    // ── 10. Map the verdict onto the action state machine ─────────────────
    let state: OutcomeState;
    let result: Record<string, unknown> | null = null;
    let error: string | null = null;
    let providerRef: string | null = null;
    let message: string;

    switch (verdict.kind) {
      case 'created': {
        state = 'succeeded_at_provider';
        result = providerResult(verdict.refund);
        providerRef = verdict.refund.id ?? null;
        message = 'refund created at Stripe; local payment state follows via charge.refunded webhook';
        break;
      }
      case 'already_refunded': {
        const existing = findExistingRefund(await listRefundsForIntent(pv.payment_intent), actionId, false);
        if (existing) {
          state = 'succeeded_at_provider';
          result = { ...providerResult(existing), adopted_existing_refund: true };
          providerRef = existing.id ?? null;
          message = 'charge was already refunded at Stripe; adopted the existing refund';
        } else {
          state = 'failed';
          result = { stripe_error_class: 'charge_already_refunded' };
          error = `${verdict.code}: ${verdict.message}`;
          message = 'Stripe reports the charge already refunded but no refund object was listed; human reconciliation required';
        }
        break;
      }
      case 'failed': {
        state = 'failed';
        result = { stripe_error_class: verdict.errorClass, stripe_error_code: verdict.code };
        error = `${verdict.code}: ${verdict.message}`;
        message = `Stripe refused the refund (${verdict.errorClass})`;
        break;
      }
      case 'unknown': {
        // Stripe MAY hold a refund. Resolve strictly by our own metadata.
        const ours = findExistingRefund(await listRefundsForIntent(pv.payment_intent), actionId, true);
        if (ours) {
          state = 'succeeded_at_provider';
          result = { ...providerResult(ours), resolved_after: verdict.errorClass };
          providerRef = ours.id ?? null;
          message = 'refund found at Stripe after a transport error; recorded as succeeded_at_provider';
        } else {
          state = 'unknown';
          result = { stripe_error_class: verdict.errorClass };
          error = sanitizeErrorMessage(verdict.message);
          message = 'Stripe outcome unresolved; retry is safe (same idempotency key)';
        }
        break;
      }
    }

    const rec = await recordOutcome(service, actionId, state, result, error, providerRef);
    if (!rec.ok) {
      // Money may have moved and we could not say so. Page loudly with the ref.
      await captureException(`${FN}:unrecordable-outcome`, new Error(rec.message), {
        action_id: actionId, state, provider_ref: providerRef, financial_operation: 'refund',
      });
      return json({ action_id: actionId, state, provider_ref: providerRef ?? undefined,
                    error: 'outcome_unrecordable', message: 'Stripe outcome known but ops.record_action_outcome failed' }, 500, headers);
    }

    if (state === 'failed' || state === 'unknown') {
      await captureException(`${FN}:stripe`, new Error(`${state}: ${error ?? message}`), {
        action_id: actionId, payment_id: pay.id, state, financial_operation: 'refund',
      });
    } else {
      console.log(JSON.stringify({ fn: FN, msg: 'outcome recorded', action_id: actionId, state, provider_ref: providerRef }));
    }

    return json(
      { action_id: actionId, state, ...(providerRef ? { provider_ref: providerRef } : {}), message },
      httpStatusForState(state),
      headers,
    );
  } catch (err) {
    await captureException(FN, err, { action_id: actionId });
    return json({ error: 'Internal server error' }, 500, headers);
  }
});
