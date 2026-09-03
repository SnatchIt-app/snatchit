/**
 * supabase/functions/connect-onboarding/index.ts
 *
 * ORGANIZATION Stripe Connect onboarding — the venue money-identity bind.
 * Specified at docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md §3.3 (:439-462,
 * summary matrix :1778). Designed by docs/phase2/_rulings/F_org_onboarding.md
 * (Part 3) and fenced by docs/phase2/_rulings/G_onboarding_security.md (§2 threat
 * table, §3 callback rules, §5.1 attach-vs-replace).
 *
 * ─── WHY THIS IS A SEPARATE FUNCTION, NOT A PARAMETER ON create-connect-account
 * The seller path derives its subject solely from auth.uid() (:119), hardcodes
 * business_type=individual (:204) and writes profiles.stripe_connect_id (:215).
 * Adding an org_id to it would create exactly one accident — a venue employee
 * taps "set up payouts", falls through to the individual arm, and the venue's
 * money is bound to that employee's personal Stripe account. Ruling F §3.2
 * forbids the shared door. THE TWO PATHS MUST NOT SHARE A DOOR.
 *
 * ─── WHAT IS REUSED FROM THE SELLER PATH (Ruling F §3.2 "what is reused")
 *   • _shared/stripe.ts             — the centrally pinned Stripe-Version.
 *   • the fail-closed rate limiter  — an RPC error is a 503, never a bypass.
 *   • HTTPS validation of redirect targets before any Stripe call.
 *   • the status_only probe shape   — re-read from Stripe, never trust a cache.
 *   • the error shape / CORS / security headers / Sentry discipline.
 *
 * ─── WHAT IS DELIBERATELY *NOT* REUSED
 *   • business_type=individual                  → 'company'. The org is the legal entity.
 *   • profiles.stripe_connect_id as the sink    → kernel.organization, via RPC only.
 *   • auth.uid() as the subject                 → the ORG, with an explicit role gate.
 *   • the stale-account SELF-HEAL RE-MINT (create-connect-account:239-261).
 *     Ruling G T-1: on the org plane a re-mint triggered by a Stripe error string
 *     is a *destination-replacement primitive* — it would swap the payee without
 *     org_owner, without aal2 step-up, without the cool-down and without the
 *     `org.payout_destination.change` audit row that kernel.set_org_payout_destination
 *     (085:1601-1662) exists to enforce. There is no re-mint arm here and none may
 *     be added: an account Stripe will not return is a 409 that routes the operator
 *     to the replacement verb, which carries those controls.
 *
 * ─── AUTH MODEL: CLASS A (edge spec §0, EA-1), with one Class B leg
 * kernel.set_org_connect_ref RAISES when auth.uid() is NULL (077:962-966) because
 * it stamps payout_destination_set_by — the SoD-1 operand that later bars the
 * setter from requesting the payout (087:428-431). A service-role connection has
 * no auth.uid(), so the bind MUST ride a client built from the CALLER'S OWN
 * Authorization header. The service-role calls are the rate limiter (unreachable
 * from `authenticated` by design), kernel.get_org_connect_ref — whose ONLY
 * protection is its grant, so its authority gate is the org-role check in this
 * function and it is never called before that check — and kernel.sync_org_connect_state,
 * which is service_role-EXEC-only precisely because it asserts Stripe's own state
 * and no human may be able to declare their org ready to sell (093:225-234).
 *
 * ─── THE ONE RULE THIS FILE EXISTS TO ENFORCE (Ruling G, threat G-1)
 * THE SERVER MINTS THE ACCOUNT. THE CALLER NEVER NAMES ONE.
 * The request body is parsed against a THREE-KEY ALLOW-LIST; anything else is a
 * 400. There is no field, no fallback and no error path by which a caller-supplied
 * string can become the value passed to kernel.set_org_connect_ref. The DB binder
 * validates its argument with a regex only (077:971-973), so this is the layer
 * where account provenance is actually established.
 *
 * ─── WRITTEN AGAINST MIGRATION 093 AS AUTHORED
 * docs/phase2/_impl/093_parts/30_connect_org.sql. Every RPC below is called at
 * its authored signature, and 093 CHANGED THE BIND'S PRECONDITIONS in ways this
 * file must anticipate rather than discover:
 *   • set_org_connect_ref (093:628) is now org_owner ONLY — org_finance may
 *     initiate and view but may NOT bind — requires an aal2 session, and
 *     narrows the org status gate to ('approved','active').
 *   • ALL THREE ARE CHECKED HERE, BEFORE THE ACCOUNT IS MINTED. Minting first
 *     and meeting the refusal at bind time would strand a live orphan Stripe
 *     account with no row pointing at it — the exact failure 093's own
 *     get_org_connect_state header calls out as the thing that verb prevents.
 *   • TWO READERS, NEVER INTERCHANGEABLE (defect RT-A-4). get_org_connect_state
 *     (093:985) is `authenticated` and returns `connect_account_last4` — state
 *     for humans. get_org_connect_ref (093:1081) is service_role ONLY and returns
 *     the acct_ id — ref for machines, and THE RESOLVE-BEFORE-CREATE OPERAND.
 *     Taking the id from the first verb is what made every bound org look
 *     unbound and mint a duplicate live account on every attempt past Stripe's
 *     24h idempotency window.
 *   • sync_org_connect_state (093:125) is FIVE arguments, service_role-only,
 *     and already carries out-of-order, cross-org and heartbeat-vs-transition
 *     semantics — none of which are re-implemented here.
 *   • THE TWO-KEY SEQUENCE (RT-A-3). stage_org_connect_ref (093:329) records the
 *     platform's provenance for a minted account under service_role; only then
 *     will set_org_connect_ref accept that identifier, and only from a human
 *     org_owner on an aal2 session. Staging without binding achieves nothing;
 *     binding without staging is `no_pending_connect_ref`. THIS FUNCTION IS THE
 *     ONLY PLACE BOTH CREDENTIALS MEET — that is the point, so the two clients
 *     must never be collapsed into one.
 *
 * Deploy with verify_jwt: true. Preconditions in docs/phase2/_impl/E1_connect_onboarding.md.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetch, stripeFetchRaw } from '../_shared/stripe.ts';

const SUPABASE_URL              = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SUPABASE_ANON_KEY         = Deno.env.get('SUPABASE_ANON_KEY')!;

const TAG = 'connect-onboarding';

// ── CORS origin whitelist ────────────────────────────────────────────────────
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

/**
 * Machine-readable failure. The dashboard renders operator copy from `code`
 * (Ruling F §3.6 prescribes distinct sentences per state); `error` is a safe
 * fallback string. NOTHING internal — no acct_ id, no capability names, no SQL
 * error text — crosses this boundary.
 */
function fail(
  req: Request,
  status: number,
  code: string,
  error: string,
  extra: Record<string, unknown> = {},
): Response {
  return json({ error, code, ...extra }, status, getResponseHeaders(req));
}

// ─────────────────────────────────────────────────────────────────────────────
// Redirect targets
//
// CALLER-SUPPLIED return_url / refresh_url ARE REFUSED. Edge spec §3.3 lists
// them in the request body; Ruling G §3 overrules it — a caller-chosen landing
// page is an open redirect that catches a mid-onboarding org owner, and the
// shipped seller path already treats these as constants
// (create-connect-account:98-99, validated :161-163). Env-configurable so the
// venue dashboard can move without a code change; host-pinned so a bad env var
// cannot silently point Stripe at somebody else's domain (Ruling G §3, the
// "confirm the return target is served by a surface under our control" caveat).
//
// These are venue-DASHBOARD routes, never snatchitapp.com/payout-return — that
// screen deep-links into the mobile profile tab and unconditionally claims
// success (app/payout-return.tsx:48-52), which Stripe's own documentation says
// return_url must never do.
// ─────────────────────────────────────────────────────────────────────────────
const RETURN_URL  = Deno.env.get('VENUE_CONNECT_RETURN_URL')
  ?? 'https://snatchitapp.com/dashboard/payments/connect/return';
const REFRESH_URL = Deno.env.get('VENUE_CONNECT_REFRESH_URL')
  ?? 'https://snatchitapp.com/dashboard/payments/connect/refresh';

const ALLOWED_REDIRECT_HOSTS = new Set(['snatchitapp.com', 'www.snatchitapp.com']);

/**
 * A redirect target must be https, on a host we control, and CARRY NO STATE.
 *
 * The no-query/no-fragment rule is the enforcement of Ruling G §3's requirement
 * that "the return and refresh handlers MUST treat every URL-borne value as
 * decoration". If we never put state in the URL, no handler can be tempted to
 * read it — the same discipline app/payout-return.tsx:33-39 already keeps by
 * reading nothing at all. Status is re-derived server-side, from the caller's
 * session and a live Stripe read, on the way back in.
 */
function isSafeRedirect(raw: string): boolean {
  try {
    const u = new URL(raw);
    return u.protocol === 'https:'
      && ALLOWED_REDIRECT_HOSTS.has(u.hostname)
      && u.search === ''
      && u.hash === '';
  } catch {
    return false;
  }
}

// ── Rate limiting — fail CLOSED (create-connect-account:70-93) ───────────────
type RateLimitResult = 'allowed' | 'over_limit' | 'error';

/**
 * 5 per 600s. Edge spec §3.3 says `check_rate_limit(user, 'connect-onboarding',
 * 5, 60)`; this is the STRICTER window that the shipped seller path uses
 * (create-connect-account:131), so it can never exceed the spec's ceiling.
 * Binding an org's money identity is a once-per-lifetime act — five attempts in
 * ten minutes is already generous, and the tighter bucket is the fail-safe
 * direction for a money-binding endpoint.
 */
async function checkRateLimit(
  service: ReturnType<typeof createClient>,
  userId: string,
): Promise<RateLimitResult> {
  try {
    const { data, error } = await service.rpc('check_rate_limit', {
      p_user_id:        userId,
      p_action:         'connect-onboarding',
      p_max:            5,
      p_window_seconds: 600,
    });
    if (error) {
      console.warn(`[${TAG}] rate limit RPC error (failing closed):`, error.message);
      return 'error';
    }
    return data === true ? 'allowed' : 'over_limit';
  } catch (err) {
    console.warn(`[${TAG}] rate limit check threw (failing closed):`, err);
    return 'error';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Request body — ALLOW-LIST, not deny-list.
//
// Three keys exist. Anything else is a 400 with no further processing. An
// allow-list is checkable by inspection: a reviewer can prove, by reading these
// twenty lines, that no request value reaches Stripe or the binder. A deny-list
// of "fields that look like an account" could not be proved at all.
//
// `command_key` is ACCEPTED FOR SPEC COMPATIBILITY (§3.3) AND THEN IGNORED. The
// bind key is derived from the org id below, because a caller-chosen dedupe
// token lets a client defeat its own replay protection, and because "no request
// body value reaches the account binding" is easier to keep absolutely than
// approximately.
// ─────────────────────────────────────────────────────────────────────────────
const BODY_KEYS = new Set(['org_id', 'status_only', 'command_key']);
const UUID_RE   = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type ParsedBody =
  | { ok: true;  orgId: string; statusOnly: boolean }
  | { ok: false; code: string; message: string };

function parseBody(raw: unknown): ParsedBody {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    return { ok: false, code: 'invalid_body', message: 'Request body must be a JSON object.' };
  }
  const body = raw as Record<string, unknown>;

  for (const key of Object.keys(body)) {
    if (!BODY_KEYS.has(key)) {
      // Named explicitly so a client that tries to pass an account id gets a
      // 400 and a log line, rather than silently having it dropped.
      return {
        ok: false,
        code: 'unexpected_field',
        message: `Unsupported field: ${key}. This endpoint never accepts a Stripe account identifier.`,
      };
    }
  }

  const orgId = body.org_id;
  if (typeof orgId !== 'string' || !UUID_RE.test(orgId)) {
    return { ok: false, code: 'invalid_org_id', message: 'org_id must be a uuid.' };
  }

  const statusOnlyRaw = body.status_only;
  if (statusOnlyRaw !== undefined && typeof statusOnlyRaw !== 'boolean') {
    return { ok: false, code: 'invalid_status_only', message: 'status_only must be a boolean.' };
  }

  return { ok: true, orgId, statusOnly: statusOnlyRaw === true };
}

// ─────────────────────────────────────────────────────────────────────────────
// Kernel RPC wrappers. Every one of these rides the CALLER's JWT — the RPC is
// the authority, the edge only carries the question (edge spec §3.3: "the edge
// passes the org id; the RPC decides").
// ─────────────────────────────────────────────────────────────────────────────

type KernelClient = ReturnType<typeof createClient>;

function callerClient(authHeader: string): KernelClient {
  // Anon key + the caller's Authorization: PostgREST runs this as
  // `authenticated` with a real auth.uid(). The service key would make every
  // kernel money RPC raise 42501 — deliberately (077:962-966, 085:1614-1617).
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth:   { autoRefreshToken: false, persistSession: false },
    db:     { schema: 'kernel' },
  });
}

/** THE ENDPOINT gate: Ruling F §3.4 gives INITIATE, RECONNECT and VIEW to
 *  org_owner + org_finance. No venue role, ever — a venue_manager is an employee
 *  of a site, not an officer of the legal entity, and letting one onboard is
 *  precisely how venue money ends up in a personal account.
 *
 *  THE BIND gate is NARROWER: 093:658 dropped org_finance from
 *  set_org_connect_ref, so naming the payee is org_owner only (SoD-1). Finance
 *  still passes this gate, views status, and starts the flow — it is refused at
 *  step 8(b), BEFORE anything is minted. Roles are single-valued with NO
 *  inheritance (077:150), so every name is listed explicitly at both gates. */
const ONBOARDING_ROLES = ['org_owner', 'org_finance'];

/** `null` = could not evaluate. The caller treats that as 503, never as allow.
 *  The role set is a parameter because 093 split the two authorities: the wider
 *  pair may reach this endpoint, only org_owner may bind. */
async function hasOrgRole(
  caller: KernelClient,
  orgId: string,
  roles: string[],
): Promise<boolean | null> {
  try {
    const { data, error } = await caller.rpc('has_org_role', {
      p_org_id: orgId,
      p_roles:  roles,
    });
    if (error) {
      console.warn(`[${TAG}] has_org_role error (failing closed):`, error.message);
      return null;
    }
    return data === true;
  } catch (err) {
    console.warn(`[${TAG}] has_org_role threw (failing closed):`, err);
    return null;
  }
}

/**
 * kernel.get_org_connect_state (093:981) — the resolve-before-create operand.
 *
 * `authenticated`-only, caller-JWT bound, org_owner/org_finance. It exists
 * because stripe_connect_account_ref is readable by NEITHER role that could ask:
 * `authenticated` is revoked down to (org_id, display_name, status)
 * (077:133-138) and service_role holds USAGE only on the kernel schema
 * (085:2092-2095). An unbound org returns `connect_bound = false`, NOT a
 * not-found — this is the normal first call, so there is no not_found arm to map.
 *
 * IT RETURNS LAST 4, NEVER THE acct_ ID (G §6.1, CRM_EXPORT_SPEC:285). The mint
 * path is therefore the only path that ever holds an account id: see RECONNECT
 * GAP at the bound-org branch in the handler.
 *
 * It also does NOT return legal_name or display_name — deliberately minimal —
 * which is why createOrgAccount below prefills nothing.
 */
type OrgConnectState = {
  orgStatus:        string | null;
  connectBound:     boolean;
  /** Presence of 093's `connect_account_ref` sentinel — a bound/unbound signal
   *  only. NEVER an identifier and never forwarded anywhere. */
  refKeyPresent:    boolean;
  accountLast4:     string | null;
  transfersActive:  boolean;
  stateSyncedAt:    string | null;
};

/** 093:1253. The literal this verb returns for a BOUND org in place of the id.
 *  Handing it to Stripe earns an immediate 400 — a loud, harmless failure that
 *  replaces the silent orphan-account outcome — but it must never get that far,
 *  so it is refused explicitly at the resolve. */
const CONNECT_REF_SENTINEL = 'masked:call_kernel.get_org_connect_ref';

type StateResult =
  | { ok: true;  state: OrgConnectState }
  | { ok: false; status: number; code: string; message: string };

async function getOrgConnectState(caller: KernelClient, orgId: string): Promise<StateResult> {
  let data: unknown;
  let error: { message?: string; code?: string } | null = null;
  try {
    const res = await caller.rpc('get_org_connect_state', { p_org_id: orgId });
    data  = res.data;
    error = res.error as { message?: string; code?: string } | null;
  } catch (err) {
    console.error(`[${TAG}] get_org_connect_state threw:`, err);
    return {
      ok: false, status: 503, code: 'connect_state_unavailable',
      message: 'Payment settings are temporarily unavailable. Please try again shortly.',
    };
  }

  if (error) {
    const msg = error.message ?? '';
    // 42501 — the RPC re-checked authority and refused. Report it as a role
    // failure, not as an outage: a caller demoted between our check and this
    // call must see 403, and this is one of the places that re-check happens.
    if (/insufficient_privilege|42501/i.test(msg)) {
      return {
        ok: false, status: 403, code: 'forbidden',
        message: 'You do not have permission to manage payments for this organization.',
      };
    }
    // Anything else — including PGRST202 while 093 is unapplied — is an
    // AMBIGUITY, and an ambiguity about whether an account already exists must
    // never resolve to "create one".
    console.error(`[${TAG}] get_org_connect_state error (failing closed):`, msg);
    return {
      ok: false, status: 503, code: 'connect_state_unavailable',
      message: 'Payment settings are temporarily unavailable. Please try again shortly.',
    };
  }

  const row = (data ?? {}) as Record<string, unknown>;

  // connect_bound is the authored operand. It is read strictly — anything other
  // than an explicit `false` for an org with a last4 present would be a shape
  // change, and guessing on this field is guessing about whether to mint.
  if (typeof row.connect_bound !== 'boolean') {
    console.error(`[${TAG}] get_org_connect_state returned no connect_bound for org ${orgId}`);
    return {
      ok: false, status: 503, code: 'connect_state_unavailable',
      message: 'Payment settings are temporarily unavailable. Please try again shortly.',
    };
  }

  // 093:1251-1253 — the anti-footgun key. It is non-null whenever the org is
  // bound, so `if (!connect_account_ref) mint()` short-circuits correctly. It is
  // the SENTINEL, never an identifier: it is captured here only as a third
  // independent bound/unbound signal for the cross-check, and MUST NOT reach
  // Stripe. CONNECT_REF_SENTINEL below is the guard that proves it never does.
  const refKey = typeof row.connect_account_ref === 'string' ? row.connect_account_ref : null;

  return {
    ok: true,
    state: {
      orgStatus:       typeof row.org_status === 'string' ? row.org_status : null,
      connectBound:    row.connect_bound,
      refKeyPresent:   refKey !== null,
      accountLast4:    typeof row.connect_account_last4 === 'string' ? row.connect_account_last4 : null,
      transfersActive: row.connect_transfers_active === true,
      stateSyncedAt:   typeof row.connect_state_synced_at === 'string' ? row.connect_state_synced_at : null,
    },
  };
}

/**
 * kernel.get_org_connect_ref (093:1081) — THE MACHINE READER. FULL IDENTIFIER.
 *
 * THIS IS THE RESOLVE-BEFORE-CREATE OPERAND. Reading it off get_org_connect_state
 * instead was defect RT-A-4: that verb returns connect_account_last4 and never
 * the id, so the id came back `undefined`, every bound org reported
 * `not_connected`, and the create path ran for organizations that already had an
 * account. Stripe's idempotency key masks that for 24h; past the window every
 * attempt mints ANOTHER live connected account bound to nothing. The two verbs
 * must never be merged and neither may be substituted for the other:
 *
 *   STATE-FOR-HUMANS  get_org_connect_state  ->  last4      `authenticated`
 *   REF-FOR-MACHINES  get_org_connect_ref    ->  acct_ id   service_role ONLY
 *
 * CALLED WITH THE SERVICE CLIENT, NEVER THE CALLER'S. It carries no has_org_role
 * check by design — that predicate tests auth.uid(), which is NULL on a machine
 * session, so adding one could only ever refuse. ITS PROTECTION IS ITS GRANT
 * (093:1100-1102) AND THE AUTHORITY GATE FOR IT LIVES HERE: it is only ever
 * called after the caller has been authenticated and proven to hold an org money
 * role. DO NOT MOVE THIS CALL ABOVE THAT CHECK.
 *
 * Returns NULL for an unbound org — the normal first call — and never raises.
 */
type RefResult =
  | { ok: true;  ref: string | null }
  | { ok: false; status: number; code: string; message: string };

async function getOrgConnectRef(orgId: string): Promise<RefResult> {
  let data: unknown;
  let error: { message?: string; code?: string } | null = null;
  try {
    const kernelService = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
      db:   { schema: 'kernel' },
    });
    const res = await kernelService.rpc('get_org_connect_ref', { p_org_id: orgId });
    data  = res.data;
    error = res.error as { message?: string; code?: string } | null;
  } catch (err) {
    console.error(`[${TAG}] get_org_connect_ref threw org=${orgId}:`, err);
    await captureException(TAG, err, { org_id: orgId, stage: 'get_org_connect_ref' });
    return {
      ok: false, status: 503, code: 'connect_state_unavailable',
      message: 'Payment settings are temporarily unavailable. Please try again shortly.',
    };
  }

  if (error) {
    // A missing verb or a signature drift here is the RT-A-4 shape again, so it
    // is alarmed on rather than degraded past. NEVER fall through to "assume
    // unbound" — that is exactly the branch that mints a duplicate account.
    console.error(`[${TAG}] get_org_connect_ref failed org=${orgId}: ${error.message ?? ''}`);
    await captureException(TAG, new Error(`get_org_connect_ref: ${error.message ?? 'unknown'}`), {
      org_id: orgId, stage: 'get_org_connect_ref', hint: 'migration 093 slice 30 section 7 applied?',
    });
    return {
      ok: false, status: 503, code: 'connect_state_unavailable',
      message: 'Payment settings are temporarily unavailable. Please try again shortly.',
    };
  }

  if (data === null || data === undefined) return { ok: true, ref: null };

  if (typeof data !== 'string' || !/^acct_[A-Za-z0-9]+$/.test(data)) {
    console.error(`[${TAG}] get_org_connect_ref returned a malformed ref for org=${orgId}`);
    await captureException(TAG, new Error('malformed connect ref from get_org_connect_ref'), {
      org_id: orgId, stage: 'get_org_connect_ref',
    });
    return {
      ok: false, status: 500, code: 'malformed_account_ref',
      message: 'Payment settings could not be read. Support has been notified.',
    };
  }
  return { ok: true, ref: data };
}

/**
 * The `aal` claim, decoded from the already-VERIFIED caller token.
 *
 * PRE-FLIGHT ONLY. auth.getUser() has already verified the signature by the time
 * this runs; we decode the payload solely so that a session without a step-up is
 * refused BEFORE a Stripe account is minted for it. set_org_connect_ref
 * (093:665-672) reads request.jwt.claims itself and remains the authority —
 * this can only ever refuse earlier, never permit.
 *
 * Absent claim ⇒ null ⇒ refused, matching AUTHZ-M4: an absent claim can never be
 * evaluated as satisfied.
 */
function readAalClaim(token: string): string | null {
  try {
    const payload = token.split('.')[1];
    if (!payload) return null;
    const b64 = payload.replace(/-/g, '+').replace(/_/g, '/');
    const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4);
    const claims = JSON.parse(atob(padded)) as Record<string, unknown>;
    return typeof claims.aal === 'string' ? claims.aal : null;
  } catch {
    return null;
  }
}

/**
 * The denial witness (085:1567-1596). EXEC to `authenticated` only — never
 * service_role — because the actor must be a real auth.uid() and nothing else
 * may set it. Best-effort: a refusal that cannot be logged is still a refusal.
 * Ruling G §6.1 records `payout.destination` + `organization` as the reusable
 * arm for a bind denial.
 */
async function recordDenial(caller: KernelClient, orgId: string, code: string): Promise<void> {
  try {
    const { error } = await caller.rpc('record_money_denial', {
      p_action:       'payout.destination',
      p_subject_kind: 'organization',
      p_subject_id:   orgId,
      p_error_code:   code,
    });
    if (error) console.warn(`[${TAG}] record_money_denial failed:`, error.message);
  } catch (err) {
    console.warn(`[${TAG}] record_money_denial threw:`, err);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stripe
// ─────────────────────────────────────────────────────────────────────────────

/** Everything this platform needs to know about a connected account, derived
 *  from a LIVE retrieve — never from a cached row and never from a webhook's
 *  embedded snapshot (Stripe's own guidance: retrieve by data.object.id). */
type ConnectSnapshot = {
  accountId:            string;
  transfersActive:      boolean;
  payoutsEnabled:       boolean;
  detailsSubmitted:     boolean;
  requirementsDue:      boolean;
  pendingVerification:  boolean;
  disabledReason:       string | null;
  requirementsDeadline: string | null;
};

type ConnectStatus =
  | 'not_connected'
  | 'onboarding_required'
  | 'pending_verification'
  | 'restricted'
  | 'ready';

/**
 * `transfers === 'active'` is THE readiness predicate, and it is not a new one:
 * _shared/payouts.ts:96-98 already gates every seller payout on exactly this and
 * nothing else. charges_enabled/payouts_enabled are account-level rollups that
 * can disagree with the capability in both directions — gate the specific money
 * movement on the specific capability.
 *
 * Order is deliberate. `ready` wins over outstanding requirements: an account
 * with transfers active and paperwork pending is one Stripe will still accept
 * transfers to, so the product warns loudly and gates NOTHING (Ruling F §3.6.2).
 * Taking a live on-sale event down over a paperwork item is a self-inflicted
 * outage; `requirements_due` is returned alongside so the banner can still fire.
 */
function deriveStatus(s: ConnectSnapshot): ConnectStatus {
  if (s.transfersActive) return 'ready';
  if (s.disabledReason)  return 'restricted';
  if (s.pendingVerification && !s.requirementsDue) return 'pending_verification';
  return 'onboarding_required';
}

type AccountReadResult =
  | { ok: true;  snapshot: ConnectSnapshot }
  | { ok: false; kind: 'unusable' | 'transient'; detail: string };

async function readAccount(accountId: string): Promise<AccountReadResult> {
  const probe = await stripeFetchRaw(`/accounts/${accountId}`);
  const body  = probe.data as Record<string, unknown>;

  if (!probe.ok) {
    const err     = (body?.error ?? {}) as Record<string, unknown>;
    const code    = typeof err.code === 'string' ? err.code : '';
    const message = typeof err.message === 'string' ? err.message : `HTTP ${probe.status}`;
    // Classify on Stripe's own error code first and only fall back to the
    // message when it is absent — create-connect-account:244 matches on message
    // text alone, which is fragile and, on this plane, would be the trigger of a
    // destination change (Ruling G T-1). Here the classification decides only
    // 409-vs-503; NEITHER branch re-mints.
    const unusable =
      probe.status === 404 ||
      code === 'resource_missing' ||
      code === 'account_invalid' ||
      /test\s?mode|testmode|no such account/i.test(message);
    return { ok: false, kind: unusable ? 'unusable' : 'transient', detail: message };
  }

  const caps = (body?.capabilities ?? {}) as Record<string, unknown>;
  const req  = (body?.requirements ?? {}) as Record<string, unknown>;
  const currentlyDue        = Array.isArray(req.currently_due) ? req.currently_due : [];
  const pendingVerification = Array.isArray(req.pending_verification) ? req.pending_verification : [];
  const deadline            = typeof req.current_deadline === 'number' ? req.current_deadline : null;

  return {
    ok: true,
    snapshot: {
      accountId,
      transfersActive:      caps.transfers === 'active',
      payoutsEnabled:       body?.payouts_enabled === true,
      detailsSubmitted:     body?.details_submitted === true,
      requirementsDue:      currentlyDue.length > 0,
      pendingVerification:  pendingVerification.length > 0,
      disabledReason:       typeof req.disabled_reason === 'string' ? req.disabled_reason : null,
      requirementsDeadline: deadline === null ? null : new Date(deadline * 1000).toISOString(),
    },
  };
}

/**
 * Mint the org's connected account. THE ONLY PLACE AN ACCOUNT IS CREATED, and
 * every argument is server-derived: the org id came from a validated uuid, the
 * names came from kernel.organization via the read RPC. Nothing here can be
 * reached from the request body.
 *
 * Shape is fixed by Ruling F §3.2 and several of these are IMMUTABLE once set:
 *   type=express      — controller.stripe_dashboard.type cannot be changed
 *                       without re-onboarding; Stripe runs verification and all
 *                       future compliance updates, and login_links already work.
 *   country=US        — requesting any capability at creation LOCKS the country.
 *   business_type=company — the org is the legal entity. This is the line the
 *                       hard constraint is drawn on.
 *   capabilities[transfers] ONLY — NOT card_payments. Under the Ruling A money
 *                       model the platform is merchant of record and pays the org
 *                       by POST /v1/transfers, so transfers is all that is needed.
 *                       Requesting card_payments would make the VENUE merchant of
 *                       record, drag in the whole merchant KYC + website
 *                       verification set, and COUPLE THE TWO CAPABILITIES — if
 *                       either goes inactive, Stripe disables both.
 *   metadata[org_id]  — the webhook's fallback join and the only thing that makes
 *                       the account self-describing in the Stripe dashboard.
 *
 * NOTHING IS PREFILLED, and that is now a consequence of the schema rather than
 * a preference. Ruling F §3.2 suggests company[name] <- legal_name and
 * business_profile[name] <- display_name to reduce prompts, but 093's
 * get_org_connect_state (:981) returns neither: legal_name is not client-
 * readable at all (077:120-123) and the verb is minimal by design. Prefill is a
 * prompt-reduction nicety; widening a money-path read verb to serve one would be
 * a poor trade, so Stripe collects both during hosted onboarding.
 * company.address, any Person, any individual field and external_accounts stay
 * absent for the original reason — prefilling them disables Stripe's networked
 * onboarding, which is how a venue group with several orgs reuses one verified
 * legal entity.
 *
 * No `email` is sent. The seller path attaches the caller's auth email
 * (create-connect-account:210); on this plane that would stamp an employee's
 * personal address onto the venue's money identity and would follow them out of
 * the door. Stripe collects the business email during hosted onboarding.
 */
async function createOrgAccount(orgId: string): Promise<string> {
  const params: Record<string, string> = {
    'type':                                  'express',
    'country':                               'US',
    'business_type':                         'company',
    'capabilities[transfers][requested]':    'true',
    'business_profile[product_description]': 'Live event ticketing sold through Snatch It',
    'metadata[org_id]':                      orgId,
    // An explicit discriminator so the webhook's org arm never has to infer the
    // plane from the absence of a profiles match (stripe-webhook:837 currently
    // matches profiles only, and an org account silently matches zero rows).
    'metadata[snatchit_plane]':              'organization',
  };

  // Deterministic key (edge spec §3.3): a retry — a double tap, a client
  // timeout, two dashboard tabs — REPLAYS the first account instead of minting
  // a second. This is what makes "one Stripe account per organization" hold
  // under concurrency; the DB's partial UNIQUE index (077:124-126) is the
  // backstop, not the primary control.
  const created = await stripeFetch<{ id?: string }>('/accounts', {
    method:         'POST',
    body:           params,
    idempotencyKey: `connect_org_${orgId}`,
  });

  const id = created?.id;
  if (typeof id !== 'string' || !/^acct_[A-Za-z0-9]+$/.test(id)) {
    throw new Error('Stripe returned no usable account id');
  }
  return id;
}

// ─────────────────────────────────────────────────────────────────────────────
// Stage, then bind — THE TWO-KEY SEQUENCE
// ─────────────────────────────────────────────────────────────────────────────

type StageOutcome =
  | { ok: true;  replay: boolean }
  | { ok: false; status: number; code: string; message: string };

/**
 * kernel.stage_org_connect_ref (093:329) — THE PROVENANCE WRITER. Step 4 of 6.
 *
 * WHAT IT IS: the platform's record that IT minted this account for THIS org.
 * set_org_connect_ref then refuses any identifier that is not the staged one —
 * an allowlist of exactly one value, written by a credential a browser session
 * never holds. This is what makes "the caller may not supply an arbitrary
 * acct_" TRUE rather than advisory: the cross-plane refusal is a blocklist and
 * cannot catch an attacker's own fresh Stripe account (the red team bound
 * `acct_ORPHANATTACKER` straight through it). Closes RT-A-3.
 *
 * SERVICE_ROLE CLIENT, AND THAT IS THE WHOLE CONTROL. If `authenticated` could
 * reach this verb, an attacker would stage their own account and then bind it —
 * writing the answer before taking the test. Its grant (093:408-410) is its only
 * protection, exactly like get_org_connect_ref.
 *
 * THE TWO-KEY PROPERTY THIS FUNCTION EXISTS TO COMPLETE — do not collapse these
 * onto one client, however tempting the shared code looks:
 *   • STAGING needs service_role — a machine credential;
 *   • BINDING needs a human org_owner on an aal2 session and REFUSES a
 *     service_role connection outright (093:850-856).
 * Neither credential alone can bind. A leaked service key can stage a ref and
 * get no further; a compromised org_owner can bind only what the platform
 * already minted for that org. This edge is the only place both halves meet.
 *
 * NOT RE-IMPLEMENTED HERE, because the verb already owns it: the cross-plane
 * refusal (earliest of all, so a personal seller account is refused BEFORE a
 * human is sent to Stripe); the already-bound-to-another-org refusal; and
 * overwrite-safe idempotency (re-staging the same ref is noop_replay, a
 * different one replaces the pending value).
 *
 * FAILURE IS FATAL TO THE REQUEST, not best-effort. Skipping or losing this step
 * means the bind cannot succeed at all (`no_pending_connect_ref`), so a swallowed
 * error here would produce a live Stripe account that can never be bound — the
 * orphan outcome, reached by a different road.
 */
async function stageConnectRef(orgId: string, accountRef: string): Promise<StageOutcome> {
  let data: unknown;
  let error: { message?: string; code?: string } | null = null;
  try {
    const kernelService = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
      db:   { schema: 'kernel' },
    });
    const res = await kernelService.rpc('stage_org_connect_ref', {
      p_org_id:              orgId,
      p_connect_account_ref: accountRef,
      // Deterministic in the value being staged, so a retry of the same stage is
      // byte-identical and a re-mint stages under its own key.
      p_command_key:         `connect_org_stage_${orgId}_${accountRef}`,
    });
    data  = res.data;
    error = res.error as { message?: string; code?: string } | null;
  } catch (err) {
    console.error(`[${TAG}] stage_org_connect_ref threw org=${orgId}:`, err);
    await captureException(TAG, err, { org_id: orgId, stage: 'stage_org_connect_ref' });
    return {
      ok: false, status: 503, code: 'stage_unavailable',
      message: 'Could not start your payment setup. Please try again shortly.',
    };
  }

  if (error) {
    const msg  = error.message ?? '';
    const code = error.code ?? '';

    // The account belongs to the individual seller plane (or its archive). The
    // verb runs this EARLIEST, which is why it now fires before the operator is
    // sent to Stripe instead of after. Unreachable for an account minted seconds
    // ago on the org plane — so if it fires, our own minting path produced an id
    // that already lives on the individual plane, which is an integrity alarm.
    if (/account_not_platform_minted_for_org/i.test(msg)) {
      console.error(`[${TAG}] stage refused, cross-plane org=${orgId}: ${msg}`);
      await captureException(TAG, new Error(`stage cross-plane refusal: ${msg}`), {
        org_id: orgId, stage: 'stage_org_connect_ref',
      });
      return {
        ok: false, status: 409, code: 'cross_plane_refusal',
        message: 'That payment account cannot be used for an organization.',
      };
    }
    if (/conflict_locked/i.test(msg)) {
      return {
        ok: false, status: 409, code: 'conflict_locked',
        message: 'That payment account is already in use by another organization.',
      };
    }
    if (/not_found/i.test(msg) || code === 'P0002') {
      return { ok: false, status: 404, code: 'org_not_found', message: 'Organization not found.' };
    }
    if (/malformed_account_ref/i.test(msg)) {
      console.error(`[${TAG}] stage rejected our own minted ref org=${orgId}`);
      await captureException(TAG, new Error('stage_org_connect_ref: malformed_account_ref'), {
        org_id: orgId, stage: 'stage_org_connect_ref',
      });
      return {
        ok: false, status: 500, code: 'malformed_account_ref',
        message: 'Payment setup could not be recorded. Support has been notified.',
      };
    }
    // Includes PGRST202 while slice 30 §2b is unapplied. Fail closed and alarm:
    // silently continuing to the bind would burn a live Stripe account.
    console.error(`[${TAG}] stage_org_connect_ref failed org=${orgId}: ${msg}`);
    await captureException(TAG, new Error(`stage_org_connect_ref: ${msg}`), {
      org_id: orgId, stage: 'stage_org_connect_ref', hint: 'migration 093 slice 30 section 2b applied?',
    });
    return {
      ok: false, status: 502, code: 'stage_failed',
      message: 'Could not start your payment setup. Please try again shortly.',
    };
  }

  const status = (data as { status?: string } | null)?.status ?? 'ok';
  return { ok: true, replay: status === 'noop_replay' };
}

// ─────────────────────────────────────────────────────────────────────────────
// The bind
// ─────────────────────────────────────────────────────────────────────────────

type BindOutcome =
  | { ok: true;  replay: boolean }
  | { ok: false; status: number; code: string; message: string };

/**
 * kernel.set_org_connect_ref (077:948-1013), through the CALLER's JWT.
 *
 * This call is the second, authoritative authority check and the reason the
 * whole function is Class A. The RPC:
 *   • raises 42501 when auth.uid() is NULL (077:962-966) — service_role cannot bind;
 *   • re-reads has_org_role LIVE (077:967) — never from a JWT claim, so a role
 *     lost while the operator was inside Stripe's flow cannot complete a bind
 *     (Ruling G, threat G-9);
 *   • returns `noop_replay` for the same id (077:985-990) — replay-safe;
 *   • raises `destination_already_set` for a DIFFERENT id (077:991-993) — bind-once;
 *   • stamps payout_destination_set_by = the caller, the SoD-1 operand;
 *   • writes the `org.connect_ref.bind` admin_audit row (077:1005-1009).
 *
 * The command key is derived, never accepted. Deterministic per org means a
 * retried request is byte-identical.
 */
async function bindConnectRef(
  caller: KernelClient,
  orgId: string,
  accountId: string,
): Promise<BindOutcome> {
  let data: unknown;
  let error: { message?: string } | null = null;
  try {
    const res = await caller.rpc('set_org_connect_ref', {
      p_org_id:             orgId,
      p_connect_account_id: accountId,
      p_command_key:        `connect_org_bind_${orgId}`,
    });
    data  = res.data;
    error = res.error as { message?: string } | null;
  } catch (err) {
    console.error(`[${TAG}] set_org_connect_ref threw:`, err);
    return {
      ok: false, status: 503, code: 'bind_unavailable',
      message: 'Could not save your payment setup. Please try again shortly.',
    };
  }

  if (error) {
    const msg = error.message ?? '';
    if (/destination_already_set/i.test(msg)) {
      return {
        ok: false, status: 409, code: 'destination_already_set',
        message: 'This organization already has a payout destination. Changing it is a separate, owner-only action.',
      };
    }
    if (/conflict_locked/i.test(msg)) {
      return {
        ok: false, status: 409, code: 'conflict_locked',
        message: 'That payment account is already in use by another organization.',
      };
    }
    if (/org_not_bindable/i.test(msg)) {
      return {
        ok: false, status: 409, code: 'org_not_bindable',
        message: 'This organization cannot set up payments until it has been approved.',
      };
    }
    // ---- RT-A-3 provenance (093:906-914) --------------------------------
    // Nothing staged. This is exactly what an attacker calling the RPC directly
    // as `authenticated` gets, and it is also what THIS function would get if
    // step 7c were ever removed. Alarm on it: from here it means the stage call
    // succeeded and the pending row then vanished, which is not a user error.
    if (/no_pending_connect_ref/i.test(msg)) {
      console.error(`[${TAG}] bind refused: nothing staged org=${orgId}`);
      await captureException(TAG, new Error('set_org_connect_ref: no_pending_connect_ref after staging'), {
        org_id: orgId, stage: 'set_org_connect_ref',
      });
      return {
        ok: false, status: 409, code: 'no_pending_connect_ref',
        message: 'Payment setup could not be completed. Start setup again from your dashboard.',
      };
    }
    // Staged one value, bound another. Unreachable from this function — it binds
    // the identifier it just staged — so this is either a concurrent re-mint or
    // a direct RPC attempt with an invented account.
    if (/connect_ref_not_platform_minted/i.test(msg)) {
      console.error(`[${TAG}] bind refused: identifier not platform-minted org=${orgId}`);
      await captureException(TAG, new Error('set_org_connect_ref: connect_ref_not_platform_minted'), {
        org_id: orgId, stage: 'set_org_connect_ref',
      });
      return {
        ok: false, status: 409, code: 'connect_ref_not_platform_minted',
        message: 'Payment setup could not be completed. Start setup again from your dashboard.',
      };
    }
    // ---- end provenance --------------------------------------------------
    // The cross-plane refusal (G-1), which the bind keeps as a second line
    // behind stage_org_connect_ref's earlier one.
    if (/account_not_platform_minted_for_org/i.test(msg)) {
      return {
        ok: false, status: 409, code: 'cross_plane_refusal',
        message: 'That payment account cannot be used for an organization.',
      };
    }
    // 093:665-672. Both are pre-flighted before minting, so reaching them here
    // means the session changed mid-request. Fail closed either way.
    if (/step_up_unavailable/i.test(msg)) {
      return {
        ok: false, status: 403, code: 'step_up_unavailable',
        message: 'Your session cannot be verified for this action. Sign in again and retry.',
      };
    }
    if (/step_up_required/i.test(msg)) {
      return {
        ok: false, status: 403, code: 'step_up_required',
        message: 'Confirm your identity with two-factor authentication to set up payouts.',
      };
    }
    if (/insufficient_privilege|42501/i.test(msg)) {
      return {
        ok: false, status: 403, code: 'forbidden',
        message: 'You do not have permission to manage payments for this organization.',
      };
    }
    if (/not_found/i.test(msg)) {
      return { ok: false, status: 404, code: 'org_not_found', message: 'Organization not found.' };
    }
    console.error(`[${TAG}] set_org_connect_ref error:`, msg);
    return {
      ok: false, status: 500, code: 'bind_failed',
      message: 'Could not save your payment setup. Support has been notified.',
    };
  }

  const status = (data as { status?: string } | null)?.status ?? 'ok';
  return { ok: true, replay: status === 'noop_replay' };
}

/**
 * kernel.sync_org_connect_state (093:121) — the mirror write.
 *
 * SIGNATURE IS EXACTLY FIVE ARGUMENTS, in this order:
 *   (p_org_id uuid, p_connect_account_ref text, p_transfers_active boolean,
 *    p_observed_at timestamptz, p_command_key text)
 * service_role EXEC only (093:231); `authenticated` is revoked, and rightly —
 * a human who could call this could declare their own org ready to sell.
 *
 * SEMANTICS THAT COME FOR FREE AND ARE NOT RE-IMPLEMENTED HERE:
 *   • both selectors are accepted; the ref wins, p_org_id is the metadata
 *     fallback. We pass both because we have both;
 *   • an account that is not the org's bound destination is REFUSED with
 *     `conflict_locked` — the stale-callback guard, in the database;
 *   • an observation no newer than the recorded one returns `noop_replay`
 *     rather than raising, so redelivery and double-taps are free;
 *   • an unchanged fact stamps freshness WITHOUT writing an audit row, so
 *     calling this on every poll cannot bury a capability loss in heartbeat
 *     noise. That is why p_observed_at is the RETRIEVE instant and not now().
 *
 * THIS FAILURE IS NOT SWALLOWED. connect_transfers_active is the operand of the
 * G1 on-sale gate and the G2 checkout gate: "the mirror did not persist" is
 * "this organization cannot take money and nothing said so". A console.warn on
 * that path is indistinguishable from success in every log search anyone would
 * actually run. Every outcome below is therefore console.error + Sentry, and the
 * caller turns it into a non-2xx. Retrying is free — the Stripe idempotency key
 * replays the account, set_org_connect_ref returns noop_replay, and this verb is
 * idempotent on an unchanged fact.
 */
type MirrorResult =
  | { ok: true;  status: string }
  | { ok: false; status: number; code: string; message: string };

async function syncMirror(
  orgId: string,
  accountRef: string,
  transfersActive: boolean,
  observedAt: string,
): Promise<MirrorResult> {
  let data: unknown;
  let error: { message?: string; code?: string } | null = null;
  try {
    // Built here rather than reusing the handler's service client because the
    // kernel schema has to be selected at construction time — the house pattern
    // (delete-account:154-158). This is the ONLY service-role RPC in this file,
    // and it is correct precisely because the writer has no human path.
    const kernelService = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
      db:   { schema: 'kernel' },
    });
    const res = await kernelService.rpc('sync_org_connect_state', {
      p_org_id:             orgId,
      p_connect_account_ref: accountRef,
      p_transfers_active:   transfersActive,
      p_observed_at:        observedAt,
      p_command_key:        `connect_sync_${orgId}_${observedAt}`,
    });
    data  = res.data;
    error = res.error as { message?: string; code?: string } | null;
  } catch (err) {
    console.error(`[${TAG}] sync_org_connect_state threw org=${orgId}:`, err);
    await captureException(TAG, err, { org_id: orgId, stage: 'sync_org_connect_state' });
    return {
      ok: false, status: 503, code: 'state_writer_unavailable',
      message: 'Your payment setup was saved, but its status could not be recorded. Please retry.',
    };
  }

  if (error) {
    const msg  = error.message ?? '';
    const code = error.code ?? '';
    // PGRST202 — no function matching that name and signature. This is the
    // shape that would otherwise fail silently forever, so it is called out by
    // name and alarmed on rather than folded into a generic branch.
    if (code === 'PGRST202' || /could not find the function|does not exist/i.test(msg)) {
      console.error(`[${TAG}] sync_org_connect_state MISSING OR SIGNATURE MISMATCH org=${orgId}: ${msg}`);
      await captureException(TAG, new Error(`sync_org_connect_state unavailable: ${msg}`), {
        org_id: orgId, stage: 'sync_org_connect_state', hint: 'migration 093 part 30 applied?',
      });
      return {
        ok: false, status: 503, code: 'state_writer_unavailable',
        message: 'Your payment setup was saved, but its status could not be recorded. Please retry.',
      };
    }
    // The account we just minted is not this org's bound destination. Something
    // rebound underneath us; the mirror must NOT be forced.
    if (/conflict_locked/i.test(msg)) {
      console.error(`[${TAG}] sync refused, account not bound to org=${orgId}: ${msg}`);
      await captureException(TAG, new Error(`sync_org_connect_state conflict_locked: ${msg}`), {
        org_id: orgId, stage: 'sync_org_connect_state',
      });
      return {
        ok: false, status: 409, code: 'conflict_locked',
        message: 'This organization\'s payout destination changed during setup. Reload and try again.',
      };
    }
    console.error(`[${TAG}] sync_org_connect_state failed org=${orgId}: ${msg}`);
    await captureException(TAG, new Error(`sync_org_connect_state: ${msg}`), {
      org_id: orgId, stage: 'sync_org_connect_state',
    });
    return {
      ok: false, status: 502, code: 'state_not_persisted',
      message: 'Your payment setup was saved, but its status could not be recorded. Please retry.',
    };
  }

  return { ok: true, status: (data as { status?: string } | null)?.status ?? 'ok' };
}

/** Ruling G §6.1 / dashboard §1194: the full acct_ id never leaves the trust
 *  boundary. The dashboard shows a masked ref; the client has no use for the
 *  whole id because it can never send one back. */
function maskAccount(accountId: string): string {
  return accountId.slice(-4);
}

function snapshotPayload(orgId: string, s: ConnectSnapshot) {
  return {
    status:                 deriveStatus(s),
    org_id:                 orgId,
    connect_account_last4:  maskAccount(s.accountId),
    transfers_active:       s.transfersActive,
    payouts_enabled:        s.payoutsEnabled,
    details_submitted:      s.detailsSubmitted,
    requirements_due:       s.requirementsDue,
    disabled_reason:        s.disabledReason,
    requirements_deadline:  s.requirementsDeadline,
    checked_at:             new Date().toISOString(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: getResponseHeaders(req) });
  }
  if (req.method !== 'POST') {
    return fail(req, 405, 'method_not_allowed', 'Method not allowed');
  }

  let orgId = '';
  try {
    // ── 1. Authenticated caller. Anonymous is refused before anything else. ──
    const authHeader = req.headers.get('authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return fail(req, 401, 'unauthenticated', 'Missing authorization');
    }

    const service = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: { user }, error: userErr } = await service.auth.getUser(
      authHeader.replace('Bearer ', ''),
    );
    if (userErr || !user) {
      return fail(req, 401, 'unauthenticated', 'Invalid or expired token');
    }

    // ── 2. Body: allow-list, then shape. ─────────────────────────────────────
    let rawBody: unknown;
    try {
      rawBody = await req.json();
    } catch {
      return fail(req, 400, 'invalid_body', 'Request body must be a JSON object.');
    }
    const parsed = parseBody(rawBody);
    if (!parsed.ok) {
      console.warn(`[${TAG}] rejected body from ${user.id}: ${parsed.code}`);
      return fail(req, 400, parsed.code, parsed.message);
    }
    orgId = parsed.orgId;
    const { statusOnly } = parsed;

    const caller = callerClient(authHeader);

    // ── 3. AUTHORITY, BEFORE ANYTHING IS CREATED. ────────────────────────────
    // Ahead of the rate limiter on purpose: the role read is the cheaper and
    // more selective gate, and nothing — not a limiter bucket, not a Stripe
    // object, not a log line with an org id in it — should be spent on a caller
    // who has no standing in this organization. The org id came from the body;
    // the ANSWER is computed in the database against auth.uid(), so a forged
    // org_id buys nothing.
    const authorized = await hasOrgRole(caller, orgId, ONBOARDING_ROLES);
    if (authorized === null) {
      return fail(req, 503, 'authority_unavailable',
        'Could not verify your permissions. Please try again shortly.');
    }
    if (!authorized) {
      await recordDenial(caller, orgId, 'org_role_required');
      console.warn(`[${TAG}] role denied user=${user.id} org=${orgId}`);
      return fail(req, 403, 'forbidden',
        'You do not have permission to manage payments for this organization.');
    }

    // ── 4. Rate limit — mutating calls only. ─────────────────────────────────
    // status_only is exempt because the dashboard fires it on mount, focus and
    // foreground (the seller path's :126-130 reasoning); limiting it would make
    // a venue's own status screen throttle itself.
    if (!statusOnly) {
      const rl = await checkRateLimit(service, user.id);
      if (rl === 'error') {
        return json(
          { error: 'Service temporarily unavailable. Please try again shortly.', code: 'rate_limit_unavailable' },
          503,
          { ...getResponseHeaders(req), 'Retry-After': '30' },
        );
      }
      if (rl === 'over_limit') {
        await recordDenial(caller, orgId, 'rate_limited');
        return json(
          { error: 'Too many requests. Please try again later.', code: 'rate_limited' },
          429,
          { ...getResponseHeaders(req), 'Retry-After': '600' },
        );
      }
    }

    // ── 5. RESOLVE BEFORE CREATE. ────────────────────────────────────────────
    // TWO READS, DELIBERATELY, AND THEY ARE NOT INTERCHANGEABLE (RT-A-4).
    //   • get_org_connect_state — human-facing: org_status, last4, mirror. Also
    //     a SECOND live authority check, inside the RPC.
    //   • get_org_connect_ref   — machine-facing: the full acct_ id, service_role
    //     only. THIS is the resolve operand. Reading the id from the first verb
    //     is what made every bound org look unbound and mint duplicates.
    const stateRes = await getOrgConnectState(caller, orgId);
    if (!stateRes.ok) {
      if (stateRes.status === 403) await recordDenial(caller, orgId, 'org_role_required');
      return fail(req, stateRes.status, stateRes.code, stateRes.message);
    }
    const st = stateRes.state;

    // Only reached after the caller is authenticated AND holds an org money
    // role: the grant is this verb's only protection, so its authority gate is
    // step 3 above. Never hoist this call.
    const refRes = await getOrgConnectRef(orgId);
    if (!refRes.ok) {
      return fail(req, refRes.status, refRes.code, refRes.message);
    }
    let accountId = refRes.ref;

    // Belt-and-braces on the sentinel. The resolve never reads an id off the
    // human verb, so this cannot fire — but if 093's masking ever regressed and
    // the sentinel reached this variable, sending it to Stripe would be a 400
    // and, worse, `!accountId` would be false for an unbound org. Refuse it by
    // name rather than relying on the acct_ regex to catch it.
    if (accountId === CONNECT_REF_SENTINEL) {
      console.error(`[${TAG}] sentinel reached the resolve operand org=${orgId}`);
      await captureException(TAG, new Error('connect ref sentinel reached the resolve operand'), {
        org_id: orgId,
      });
      return fail(req, 500, 'malformed_account_ref',
        'Payment settings could not be read. Support has been notified.');
    }

    // THREE independent bound/unbound signals now exist: the machine verb's id,
    // the human verb's `connect_bound` boolean, and its `connect_account_ref`
    // sentinel. They read the same column through different doors, so they must
    // agree. If they do not, we do not know whether this org has an account —
    // the single question that decides whether to mint. Fail closed and alarm;
    // never pick a winner.
    const refPresent = accountId !== null;
    if (refPresent !== st.connectBound || refPresent !== st.refKeyPresent) {
      console.error(`[${TAG}] connect state disagreement org=${orgId} ref_present=${refPresent} connect_bound=${st.connectBound} ref_key=${st.refKeyPresent}`);
      await captureException(TAG, new Error('get_org_connect_ref / get_org_connect_state disagree'), {
        org_id: orgId, ref_present: refPresent, connect_bound: st.connectBound, ref_key_present: st.refKeyPresent,
      });
      return fail(req, 503, 'connect_state_unavailable',
        'Payment settings are temporarily unavailable. Please try again shortly.');
    }

    // ── 6. UNBOUND + probe: report and stop. No Stripe call, no write. ───────
    // org_finance reaches this too — viewing is theirs even though binding is not.
    if (!accountId && statusOnly) {
      return json(
        { status: 'not_connected', org_id: orgId, checked_at: new Date().toISOString() },
        200,
        getResponseHeaders(req),
      );
    }

    // ── 7. MINT + BIND — only when the org genuinely has no account. ─────────
    //
    // RECONNECT does not pass through here, and must not. F §3.4: resuming an
    // abandoned or expired flow is org_owner + org_finance and carries NO
    // step-up and NO cool-down, because it does not change the destination.
    // Requiring an owner with aal2 to re-enter a half-finished flow would leave
    // a venue disabled and accruing money whenever the owner is unreachable —
    // a self-inflicted outage with no fraud benefit. Every gate below is
    // therefore inside the "no account yet" branch.
    let justMinted = false;
    if (!accountId) {
      // ── 7a. PRE-MINT REFUSALS. ────────────────────────────────────────────
      // Every precondition set_org_connect_ref (093:632) will apply, applied
      // FIRST. Minting and then meeting the refusal leaves a live Stripe account
      // with no row pointing at it — 093's own get_org_connect_state header
      // names that as the failure it exists to prevent. The DB stays
      // authoritative; we only ever refuse earlier than it would.

      // org status — narrowed by 093 to approved/active. Approval precedes the
      // payee, which also stops a fraudster starting the probation clock before
      // review (G-6).
      if (st.orgStatus !== 'approved' && st.orgStatus !== 'active') {
        await recordDenial(caller, orgId, 'org_not_bindable');
        return fail(req, 409, 'org_not_bindable',
          'This organization cannot set up payments until it has been approved.');
      }

      // org_owner ONLY — 093 dropped org_finance from the BIND. Finance keeps
      // initiate-and-view (hence the wider gate at step 3) but SoD-1 reserves
      // naming the payee to the owner. Without this an org_finance would mint
      // and then be refused, orphaning the account.
      const isOwner = await hasOrgRole(caller, orgId, ['org_owner']);
      if (isOwner === null) {
        return fail(req, 503, 'authority_unavailable',
          'Could not verify your permissions. Please try again shortly.');
      }
      if (!isOwner) {
        await recordDenial(caller, orgId, 'bind_requires_owner');
        return fail(req, 403, 'bind_requires_owner',
          'Only an organization owner can set up the payout destination.');
      }

      // aal2 — fail closed on an absent claim (AUTHZ-M4).
      const aal = readAalClaim(authHeader.replace('Bearer ', ''));
      if (aal === null) {
        await recordDenial(caller, orgId, 'step_up_unavailable');
        return fail(req, 403, 'step_up_unavailable',
          'Your session cannot be verified for this action. Sign in again and retry.');
      }
      if (aal !== 'aal2') {
        await recordDenial(caller, orgId, 'step_up_required');
        return fail(req, 403, 'step_up_required',
          'Confirm your identity with two-factor authentication to set up payouts.');
      }

      // An account we cannot send the operator into is an account that should
      // not exist.
      if (!isSafeRedirect(RETURN_URL) || !isSafeRedirect(REFRESH_URL)) {
        console.error(`[${TAG}] refusing to onboard: unsafe redirect config`, { RETURN_URL, REFRESH_URL });
        await captureException(TAG, new Error('unsafe Connect redirect configuration'), { org_id: orgId });
        return fail(req, 500, 'misconfigured',
          'Payment setup is temporarily unavailable. Support has been notified.');
      }

      // ── 7b. MINT. ─────────────────────────────────────────────────────────
      accountId  = await createOrgAccount(orgId);
      justMinted = true;
      console.log(`[${TAG}] minted org account org=${orgId} last4=${maskAccount(accountId)}`);

      // ── 7c. STAGE THE PROVENANCE RECORD — service_role. ──────────────────
      // Between the mint and the bind, and the order is load-bearing: §4
      // refuses with `no_pending_connect_ref` if nothing is staged, and the
      // pending value is CONSUMED by a successful bind so it can never be
      // replayed into a later re-point. Fatal on failure — a live Stripe
      // account that cannot be bound is the orphan outcome by another road.
      const staged = await stageConnectRef(orgId, accountId);
      if (!staged.ok) {
        console.error(`[${TAG}] staging failed after mint org=${orgId} last4=${maskAccount(accountId)} code=${staged.code}`);
        await recordDenial(caller, orgId, staged.code);
        return fail(req, staged.status, staged.code, staged.message);
      }
      console.log(`[${TAG}] staged org=${orgId} last4=${maskAccount(accountId)} replay=${staged.replay}`);

      // ── 7d. BIND, on the caller's JWT (SoD-1). ────────────────────────────
      const bound = await bindConnectRef(caller, orgId, accountId);
      if (!bound.ok) {
        // The org already points somewhere else — so the account just minted is
        // an orphan. WE DO NOT DELETE IT AND WE DO NOT REBIND: an
        // error-triggered destination swap is exactly the primitive Ruling G T-1
        // warns about, and deletion is irreversible. The orphan is inert (never
        // bound, never a transfer destination, no balance) and is reported for
        // reconciliation. With the resolve above working, this is reachable only
        // by a genuine race — concurrent requests replay the same idempotency
        // key and land on noop_replay.
        if (bound.code === 'destination_already_set' || bound.code === 'conflict_locked') {
          console.error(`[${TAG}] ORPHAN Stripe account minted org=${orgId} last4=${maskAccount(accountId)} reason=${bound.code}`);
          await captureException(TAG, new Error(`orphan connect account: ${bound.code}`), {
            org_id: orgId, orphan_last4: maskAccount(accountId),
          });
        }
        await recordDenial(caller, orgId, bound.code);
        return fail(req, bound.status, bound.code, bound.message);
      }
      console.log(`[${TAG}] bound org=${orgId} replay=${bound.replay}`);
    }

    // ── 8. Re-derive state from STRIPE, by id. ───────────────────────────────
    // Never from the create response, never from the mirror, never from anything
    // the browser carried back. This is the whole answer to the stale-callback
    // problem: the return URL holds no state because the state is recomputed
    // here every time — for a reconnect exactly as for a first onboarding.
    //
    // observedAt is captured BEFORE the retrieve because it is what
    // sync_org_connect_state stores as the observation instant; a later
    // observation must never be able to look older than this one.
    const observedAt = new Date().toISOString();
    const read = await readAccount(accountId);
    if (!read.ok) {
      if (read.kind === 'unusable' && !justMinted) {
        // A BOUND account Stripe will not return. The seller path re-mints here
        // (create-connect-account:239-261). On the org plane that would be a
        // silent payee replacement with no org_owner, no step-up, no cool-down
        // and no `org.payout_destination.change` audit row — Ruling G T-1. FAIL
        // CLOSED and route the operator to the replacement verb, which has
        // those controls. There is no re-mint arm and none may be added.
        console.error(`[${TAG}] bound account unusable org=${orgId} last4=${maskAccount(accountId)}: ${read.detail}`);
        await captureException(TAG, new Error(`bound connect account unusable: ${read.detail}`), {
          org_id: orgId, account_last4: maskAccount(accountId),
        });
        if (!statusOnly) await recordDenial(caller, orgId, 'destination_unusable');
        return fail(req, 409, 'destination_unusable',
          'This organization\'s payment account can no longer be reached. Contact support to change your payout destination.');
      }
      console.error(`[${TAG}] Stripe account read failed org=${orgId} (kind=${read.kind}): ${read.detail}`);
      return json(
        { error: 'Could not reach Stripe. Please try again shortly.', code: 'stripe_unavailable' },
        503,
        { ...getResponseHeaders(req), 'Retry-After': '15' },
      );
    }
    const snapshot = read.snapshot;

    // ── 9. status_only: report and stop. NO WRITE OF ANY KIND. ───────────────
    // This is now the TRUE bound state — a live Stripe read of the org's real
    // account, not a mirror and not "not_connected". The probe is a pure
    // function of (org, Stripe), so a replayed return — refresh, back button,
    // link previewer — is a harmless no-op.
    if (statusOnly) {
      return json(snapshotPayload(orgId, snapshot), 200, getResponseHeaders(req));
    }

    // ── 10. Mirror the capability for the SQL-side gates. NOT best effort. ───
    // connect_transfers_active is the operand of the G1 on-sale gate and the G2
    // checkout gate. If this did not land, the honest answer is a non-2xx — not
    // a 200 with a link and a warning nobody reads. Retrying the whole request
    // is safe: every step is idempotent.
    const mirrored = await syncMirror(orgId, accountId, snapshot.transfersActive, observedAt);
    if (!mirrored.ok) {
      return json(
        {
          ...snapshotPayload(orgId, snapshot),
          error: mirrored.message,
          code:  mirrored.code,
          // The bind COMMITTED (or was already in place). Say so, so a client
          // never reads this as "nothing happened" and a retry is understood as
          // a resume.
          bound: true,
        },
        mirrored.status,
        getResponseHeaders(req),
      );
    }

    // ── 12. The link. ────────────────────────────────────────────────────────
    // NO IDEMPOTENCY KEY on either call, deliberately: Account Links are
    // single-use and expire in minutes, and login links are one-shot. Replaying
    // a burned link under a deterministic key would hand the operator a dead URL
    // — the one place in this file where a fresh result is the correct result.
    if (!isSafeRedirect(RETURN_URL) || !isSafeRedirect(REFRESH_URL)) {
      console.error(`[${TAG}] unsafe redirect config at link time`, { RETURN_URL, REFRESH_URL });
      return fail(req, 500, 'misconfigured',
        'Payment setup is temporarily unavailable. Support has been notified.');
    }

    let url: unknown;
    if (snapshot.detailsSubmitted && snapshot.transfersActive) {
      // Onboarding is done. Express accounts CANNOT be given an
      // `account_update` Account Link — Stripe refuses that type for accounts
      // with Stripe-hosted dashboard access — so the self-service surface is the
      // Express Dashboard login link, exactly as the seller path already does
      // (create-connect-account:310).
      const loginLink = await stripeFetch<{ url?: string }>(`/accounts/${accountId}/login_links`, {
        method: 'POST',
        body:   {},
      });
      url = loginLink?.url;
    } else {
      const accountLink = await stripeFetch<{ url?: string }>('/account_links', {
        method: 'POST',
        body: {
          'account':                    accountId,
          'refresh_url':                REFRESH_URL,
          'return_url':                 RETURN_URL,
          'type':                       'account_onboarding',
          // A venue holds money across a whole season. Collecting everything
          // Stripe will eventually want, now, avoids a mid-season interruption
          // that would pause payouts during a run of shows.
          'collection_options[fields]': 'eventually_due',
        },
      });
      url = accountLink?.url;
    }

    if (typeof url !== 'string' || !url.startsWith('https://')) {
      console.error(`[${TAG}] Stripe returned an unusable link for org=${orgId}`);
      return json(
        { ...snapshotPayload(orgId, snapshot), error: 'Unable to generate a payment setup link. Please try again.', code: 'link_unavailable' },
        502,
        getResponseHeaders(req),
      );
    }

    console.log(`[${TAG}] link issued org=${orgId} status=${deriveStatus(snapshot)} mirror=${mirrored.status}`);
    return json({ ...snapshotPayload(orgId, snapshot), url }, 200, getResponseHeaders(req));
  } catch (err) {
    const message    = err instanceof Error ? err.message : '';
    const isAuthErr  = /authorization|token/i.test(message);
    if (!isAuthErr) {
      await captureException(TAG, err, { org_id: orgId });
    } else {
      console.error(`[${TAG}] auth error:`, message);
    }
    return fail(
      req,
      isAuthErr ? 401 : 500,
      isAuthErr ? 'unauthenticated' : 'internal_error',
      isAuthErr ? 'Invalid or expired token' : 'Internal server error',
    );
  }
});
