/**
 * supabase/functions/delete-account/index.ts
 *
 * THE OR-17 CUTOVER (edge spec §1.8a; DELETION_STATE_MACHINE_SPEC §5; 077
 * release-train artifact — recorded in POST_FREEZE_AMENDMENTS.md "077
 * RELEASE-TRAIN GATE"). From the same release train that applies migration 077:
 *
 *   - The physical-delete orchestration is RETIRED. This function is now a
 *     thin Class A caller (EA-1: the RPC client is built from the caller's own
 *     Authorization header) of kernel.request_account_deletion — the
 *     always-accepts entry into DELETION_PENDING (RPC §20.17.1).
 *   - The PR #28-era request-time 409s are RETIRED: an active transfer becomes
 *     blocker BP-7 inside kernel.sweep_deletion_pending; the dispute 409 lifts
 *     (16d) because the tombstone terminal never clears that column.
 *   - auth.admin.deleteUser is called by NOTHING. Erasure is the DB sweep's
 *     tombstone terminal (ODR-16); no CASCADE physical delete ever runs.
 *   - A second action exposes kernel.withdraw_account_deletion (§20.17.2), so
 *     a pending request is reversible until the grace window elapses.
 *
 * Client compatibility: the deployed mobile build POSTs with an empty body and
 * expects { success: true }. An empty body maps to action='request' and the
 * response keeps `success: true`, so already-shipped clients cut over to the
 * tombstone flow with no app update.
 *
 * DEPLOYMENT PRECONDITIONS (release train, in order — see the Phase-2
 * production runbook):
 *   1. Migrations 076..092 applied (kernel.request_account_deletion exists).
 *   2. The project's PostgREST exposed schemas include `kernel`
 *      (Dashboard → API → db_schemas), or the .schema('kernel') calls 404.
 * Deploying THIS body before those two steps would break account deletion;
 * deploying 077 without this body is the recorded compliance outage.
 *
 * Storage note: no storage object is deleted at request time — a pending
 * request is withdrawable, and the terminal storage step is a separate
 * engineering cell of the release train (DSM §4.5: storage is the edge
 * layer's step at the tombstone, not at the request).
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

const ALLOWED_ORIGINS = [
  'https://snatchitapp.com',
  'https://www.snatchitapp.com',
];

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

function getResponseHeaders(req: Request): Record<string, string> {
  return { ...getCorsHeaders(req), ...getSecurityHeaders() };
}

function json(body: unknown, status: number, headers: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json' },
  });
}

// Fail-CLOSED rate limiting via the service client (EA-2: the limiter takes no
// authority from the caller and is unreachable from `authenticated`).
type RateLimitResult = 'allowed' | 'over_limit' | 'error';

async function checkRateLimit(
  service: ReturnType<typeof createClient>,
  userId: string,
): Promise<RateLimitResult> {
  try {
    const { data, error } = await service.rpc('check_rate_limit', {
      p_user_id: userId,
      p_action: 'delete_account',
      p_max: 5,
      p_window_seconds: 3600,
    });
    if (error) return 'error';
    return data === true ? 'allowed' : 'over_limit';
  } catch {
    return 'error';
  }
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: getResponseHeaders(req) });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405, getResponseHeaders(req));
  }

  try {
    // EA-7: Class A — a missing caller Authorization header fails closed.
    const authHeader = req.headers.get('authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return json({ error: 'Missing authorization' }, 401, getResponseHeaders(req));
    }

    const service = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: { user }, error: userErr } = await service.auth.getUser(
      authHeader.replace('Bearer ', ''),
    );
    if (userErr || !user) {
      return json({ error: 'Invalid or expired token' }, 401, getResponseHeaders(req));
    }

    const limit = await checkRateLimit(service, user.id);
    if (limit === 'over_limit') {
      return json({ error: 'Too many requests. Please try again later.' }, 429, getResponseHeaders(req));
    }
    if (limit === 'error') {
      return json({ error: 'Service temporarily unavailable.' }, 503, getResponseHeaders(req));
    }

    let action = 'request';
    try {
      const body = await req.json();
      if (body && typeof body.action === 'string') action = body.action;
    } catch {
      /* empty body = request (deployed-client compatibility) */
    }
    if (action !== 'request' && action !== 'withdraw') {
      return json({ error: "action must be 'request' or 'withdraw'" }, 400, getResponseHeaders(req));
    }

    // EA-1: the kernel RPC derives its subject from auth.uid() — the client
    // MUST carry the caller's own JWT, never the service key.
    const caller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
      db: { schema: 'kernel' },
    });

    const fn = action === 'request' ? 'request_account_deletion' : 'withdraw_account_deletion';
    const commandKey = `edge-${action}-${crypto.randomUUID()}`;
    const { data, error } = await caller.rpc(fn, { p_command_key: commandKey });

    if (error) {
      console.error(`[delete-account] ${fn} error:`, error.message);
      await captureException('delete-account', new Error(`${fn}: ${error.message}`));
      return json({
        error: action === 'request'
          ? 'Failed to submit your deletion request. Please try again or contact support.'
          : 'Failed to withdraw your deletion request. Please try again or contact support.',
      }, 500, getResponseHeaders(req));
    }

    const status = (data as { status?: string } | null)?.status ?? 'ok';
    console.log(`[delete-account] ${fn} for ${user.id}: ${status}`);
    return json({
      success: true,
      action,
      status,
      deletion_state: action === 'request' ? 'DELETION_PENDING' : 'ACTIVE',
    }, 200, getResponseHeaders(req));
  } catch (err) {
    await captureException('delete-account', err);
    return json({ error: 'Internal server error' }, 500, getResponseHeaders(req));
  }
});
