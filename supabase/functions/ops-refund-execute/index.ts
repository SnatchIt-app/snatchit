// =============================================================================
// ops-refund-execute — the money leg of an APPROVED console refund
// (docs/admin-console/DESIGN_AND_EXECUTION_PLAN.md §2 decision 8)
// =============================================================================
// WHAT THIS IS
//   `ops.execute_action('refund_execute', …)` → second-founder approval →
//   `ops.action_dispatch` leaves the action in state `processing`. Nothing in
//   Postgres talks to Stripe. This function is the handoff target.
//
//   This file is the DENO SHELL only: HTTP, auth, rate limit, and the real
//   adapters (supabase-js → ops.executor_claim / ops.record_action_outcome;
//   _shared/stripe.ts → POST/GET /v1/refunds). The flow itself —
//   claim → list-before-POST → POST → classify the OBJECT → record — is
//   `runRefundExecution` in handler.ts, which has no Deno dependency and is
//   executed by the root vitest suite (tests/ops-refund-handler.test.ts).
//
// THE INVARIANT
//   ACTION-ROW-DRIVEN. The ONLY client input is `action_id`. Payment,
//   PaymentIntent, amount and reason come out of `ops.executor_claim`, which
//   evaluates state, the enabled flag, the approval hash and the lease in one
//   transaction. A body that names any of them is refused
//   (`assertNoClientPaymentReference`).
//
// WHO MAY CALL
//   A founder JWT: `ops.whoami()` (executed AS the caller) must return
//   role = platform_admin and aal = aal2. The service client only ever runs
//   after that gate. Hidden navigation is not security; the DB is the wall.
//
// LOCAL STATE
//   This function does NOT write public.payments. `payments.status` →
//   'refunded' is set by the `charge.refunded` handler in stripe-webhook,
//   exactly as for a Dashboard refund. See README.md for the state machine.
//
// DEPLOYMENT PRECONDITIONS (owner steps, not performed by this file):
//   1. Migrations 115 + 118 applied; `ops` in PostgREST exposed schemas.
//   2. Deployed with verify_jwt ON; then `refund_execute_enabled` flipped.
// =============================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetchRaw } from '../_shared/stripe.ts';
import { type StripeRefundObject, sanitizeErrorMessage, stripeKeyMode, validateRequest } from './classify.ts';
import {
  type ClaimResult,
  type Deps,
  type Logger,
  type OpsDb,
  type RecordOutcomeResult,
  type StripeApi,
  runRefundExecution,
} from './handler.ts';

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

/** service_role. Token verification, executor_claim, record_action_outcome. */
function serviceClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Adapters — the only I/O the handler is allowed to perform
// ─────────────────────────────────────────────────────────────────────────────

function opsDb(service: SupabaseClient): OpsDb {
  return {
    async claim(actionId, leaseSeconds) {
      const { data, error } = await service.schema('ops').rpc('executor_claim', {
        p_action_id:     actionId,
        p_lease_seconds: leaseSeconds,
      });
      if (error) throw new Error(`executor_claim: ${error.message}`);
      return data as ClaimResult;
    },
    async recordOutcome(actionId, state, result, error, providerRef) {
      const { data, error: rpcErr } = await service.schema('ops').rpc('record_action_outcome', {
        p_action_id:    actionId,
        p_state:        state,
        p_result:       result,
        p_error:        error,
        p_provider_ref: providerRef,
      });
      if (rpcErr) throw new Error(`record_action_outcome: ${rpcErr.message}`);
      return data as RecordOutcomeResult;
    },
  };
}

const stripeApi: StripeApi = {
  createRefund(body, idempotencyKey) {
    return stripeFetchRaw('/refunds', { method: 'POST', idempotencyKey, body });
  },
  async listRefunds(paymentIntent) {
    const res = await stripeFetchRaw(
      `/refunds?payment_intent=${encodeURIComponent(paymentIntent)}&limit=100`,
      { method: 'GET' },
    );
    if (!res.ok) {
      const err = (res.data as { error?: { message?: string } } | null)?.error;
      return { ok: false, status: res.status, data: [], error: sanitizeErrorMessage(err?.message ?? `HTTP ${res.status}`) };
    }
    const rows = (res.data as { data?: StripeRefundObject[] } | null)?.data;
    return { ok: true, status: res.status, data: Array.isArray(rows) ? rows : [] };
  },
};

const logger: Logger = {
  info:  (event, fields) => console.log(JSON.stringify({ fn: FN, level: 'info',  event, ...fields })),
  warn:  (event, fields) => console.warn(JSON.stringify({ fn: FN, level: 'warn',  event, ...fields })),
  error: (event, fields) => console.error(JSON.stringify({ fn: FN, level: 'error', event, ...fields })),
};

// ─────────────────────────────────────────────────────────────────────────────
// HTTP shell
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

    // ── 6. The executor (claim → reconcile → POST → classify → record) ─────
    const deps: Deps = {
      db: opsDb(service),
      stripe: stripeApi,
      now: () => new Date(),
      log: logger,
      alert: (event, message, ctx) => captureException(event, new Error(message), ctx),
      stripeKeyMode: STRIPE_KEY_MODE,
    };
    const out = await runRefundExecution(
      { actionId, caller: { userId: user.id, role: identity.role, aal: identity.aal } },
      deps,
    );
    return json(out.body, out.http, headers);
  } catch (err) {
    await captureException(FN, err, { action_id: actionId });
    return json({ error: 'Internal server error' }, 500, headers);
  }
});
