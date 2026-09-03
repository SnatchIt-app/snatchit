/**
 * supabase/functions/door-session/index.ts
 * ═══════════════════════════════════════════════════════════════════════════
 * `door-session` — mint + validate the loginless door session (the door's
 * only gate).
 *
 * Frozen contract: `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §3.9a.
 * RPC contracts:   `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md`
 *                    §1.1d (`kernel.assert_door_session`), §9.4
 *                    (`venue.record_scan`), §9.5
 *                    (`venue.reconcile_offline_scans`), §9.6
 *                    (`venue.mint_door_session`).
 * Parked RPC:      `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md`
 *                    PFA-26 — `mint_door_session` currently RAISES
 *                    `precondition_failed: door_pin_kdf_unavailable … (PFA-26)`
 *                    with ZERO mutation on every call, until a ratified
 *                    slow-KDF mechanism un-parks it. `assert_door_session`
 *                    itself stays live, but with no PIN un-parked there is
 *                    no way to mint a session, so it never sees a live row.
 * Pure helper module: `./pure.ts` — bearer parsing, path dispatch, the
 *   device-id cross-check, the forbidden-`device_id` scan-meta rule, the
 *   rate-limit derived principals (`uuidv5`), and the token_hash wire
 *   contract, all import-free and unit-tested in `tests/door-session.test.ts`.
 *
 * ── DARK / NOT DEPLOYED ────────────────────────────────────────────────────
 * Authoring this file deploys nothing, calls no live door-session row (none
 * can exist while PFA-26 is parked), and makes no production traffic. Every
 * branch below is written to the FULL frozen contract — including the
 * success paths that PFA-26 currently makes unreachable — so this file does
 * not need a second pass when the KDF un-parks. See
 * `docs/phase2/_impl/KEDGES.md` for what was verified and what remains
 * genuinely untestable until then.
 *
 * ── verify_jwt: false — Class B (B-iii), TWO credentials in sequence ──────
 * There is no `auth.uid()` anywhere on this path (by design — role model
 * §7.2/§7.3). The `venue.door_pin` PROVISIONS (presented once, at
 * `/mint`/`/refresh`); the door session token — `Authorization: DoorSession
 * <door_session_id>.<secret>` — POSSESSES and is the only gate on every
 * relay call. `kernel.assert_door_session` is that gate; this file never
 * re-implements its constant-time compare or its dummy-compare-on-unknown-id
 * anti-enumeration behavior — both live in the DB, "so no second
 * implementation can drift from it and no plaintext leaves the DB boundary"
 * (edge §3.9a).
 *
 * ── EA-6 / EDGE-4c — the returned device id is the ONLY device id ─────────
 * Every relay handler's first DB call is `kernel.assert_door_session`, and
 * its RETURN VALUE — never `req` body, never a cache, never the previous
 * call — is what gets passed to `record_scan` / `reconcile_offline_scans` as
 * `p_actor_device_id`. The body's `device_id` is used ONLY as an input to
 * `assert_door_session` itself (part of its own WHERE match) and as a
 * defense-in-depth cross-check against the returned value afterward; a
 * mismatch is a hard, opaque 401 plus a Sentry event, because that shape is
 * an attack, not a client bug.
 *
 * ── Data minimization ──────────────────────────────────────────────────────
 * Every handler passes through only what the wrapped RPC returns. Nothing
 * here adds buyer name/email/phone/demographics/price/payout/Stripe/Connect
 * ids. Log lines carry only non-secret selectors (`door_session_id` — the
 * uuid PK, explicitly loggable per §3.9a — `session_id`, `venue_id`,
 * `route`, `outcome`); the PIN, the secret, the full bearer header, and any
 * KMS/RPC internals are never logged, in any stage, any error path, or any
 * Sentry `extra`.
 * ═══════════════════════════════════════════════════════════════════════════
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException, captureMessage } from '../_shared/sentry.ts';
import {
  batchContainsForbiddenDeviceId,
  deriveDoorPinRateLimitPrincipal,
  deriveDoorSessionRateLimitPrincipal,
  deviceIdsMatch,
  dispatchDoorSessionRoute,
  doorPinRateLimitName,
  hasForbiddenDeviceIdField,
  isAssertDoorSessionAuthFailure,
  isDoorPinKdfUnavailable,
  parseDoorSessionBearer,
  type DoorSessionRoute,
} from './pure.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// ── CORS + security headers (house style, copied shape from credential-sign)
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

function getResponseHeaders(req: Request): Record<string, string> {
  return { ...getCorsHeaders(req), ...getSecurityHeaders() };
}

function json(body: unknown, status: number, headers: Record<string, string>): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...headers, 'Content-Type': 'application/json' } });
}

// ── Logging — NEVER the PIN, the secret, the token, or PII. The field set is
// fixed so there is no field to smuggle a secret into. `door_session_id` is
// the non-secret selector (the row PK) and is explicitly loggable per
// §3.9a. ─────────────────────────────────────────────────────────────────
interface DoorSessionLogFields {
  route: string;
  door_session_id: string | null;
  session_id: string | null;
  venue_id: string | null;
  outcome: string;
}
function logOutcome(fields: DoorSessionLogFields) {
  console.log(JSON.stringify({ fn: 'door-session', ...fields }));
}

// ── The generic, opaque relay-auth failure body. §3.9a: "Unknown id · wrong
// secret · expired · revoked · session mismatch · unknown device return the
// same status, the same body, and the same timing budget." This function
// does not attempt to equalize wall-clock timing itself (that discipline is
// `assert_door_session`'s, DB-side, per the file header) — it only ensures
// every one of these outcomes maps to the SAME response shape. ────────────
function opaqueAuthFailure(headers: Record<string, string>): Response {
  return json({ error: 'Unauthorized', code: 'door_session_invalid' }, 401, headers);
}

// ── The generic, opaque mint/refresh failure body (§9.6: "insufficient_
// privilege(42501) — one opaque class for every precondition"). Distinct
// wording from the relay failure above so client-side handling can tell
// "your PIN/device/session combination doesn't work" from "your session
// token doesn't work" — the FROZEN contract only requires that within each
// class every failure look alike; it says nothing about the two classes
// looking alike as each other, and the two are different credentials on
// different routes reached by different clients (a person typing a PIN vs
// a device replaying a stored token). ─────────────────────────────────────
function opaqueMintFailure(headers: Record<string, string>): Response {
  return json({ error: 'Unable to establish a door session.', code: 'door_session_unavailable' }, 401, headers);
}

// ── Rate limit — fail CLOSED. Two SEPARATE principals/budgets (§3.9a):
// `/mint` + `/refresh` share `uuidv5(NS_DOOR_PIN, venue_id||':'||device_id)`
// at 5/60 (both are the same underlying re-mint operation, so PIN grinding
// cannot be laundered through `/refresh`); every relay route uses
// `uuidv5(NS_DOOR_SESSION, door_session_id)` at 60/60, per route action, so
// relay traffic can never exhaust the PIN budget or vice versa. ───────────
type RateLimitResult = 'allowed' | 'over_limit' | 'error';

async function checkRateLimit(
  service: SupabaseClient,
  principal: string,
  action: string,
  max: number,
  windowSeconds: number,
): Promise<RateLimitResult> {
  try {
    const { data, error } = await service.rpc('check_rate_limit', {
      p_user_id: principal,
      p_action: action,
      p_max: max,
      p_window_seconds: windowSeconds,
    });
    if (error) {
      console.warn('door-session: rate limit RPC error (failing closed):', error.message);
      return 'error';
    }
    return data === true ? 'allowed' : 'over_limit';
  } catch (err) {
    console.warn('door-session: rate limit check threw (failing closed):', err);
    return 'error';
  }
}

function rateLimitedResponse(result: 'error' | 'over_limit', headers: Record<string, string>): Response {
  if (result === 'error') {
    return json({ error: 'Service temporarily unavailable. Please try again shortly.' }, 503, { ...headers, 'Retry-After': '30' });
  }
  return json({ error: 'Too many requests. Please try again later.' }, 429, { ...headers, 'Retry-After': '60' });
}

// ── Body validation ─────────────────────────────────────────────────────
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isUuid(v: unknown): v is string {
  return typeof v === 'string' && UUID_RE.test(v);
}

interface MintBody {
  venue_id: string;
  session_id: string;
  device_id: string;
  pin: string;
  command_key: string;
}
function parseMintBody(body: unknown): { ok: true; value: MintBody } | { ok: false; error: string } {
  if (!body || typeof body !== 'object') return { ok: false, error: 'Body must be a JSON object' };
  const b = body as Record<string, unknown>;
  if (!isUuid(b.venue_id)) return { ok: false, error: 'venue_id must be a uuid' };
  if (!isUuid(b.session_id)) return { ok: false, error: 'session_id must be a uuid' };
  if (!isUuid(b.device_id)) return { ok: false, error: 'device_id must be a uuid' };
  if (typeof b.pin !== 'string' || b.pin.length === 0) return { ok: false, error: 'pin is required' };
  if (typeof b.command_key !== 'string' || b.command_key.length === 0) return { ok: false, error: 'command_key is required' };
  return { ok: true, value: { venue_id: b.venue_id, session_id: b.session_id, device_id: b.device_id, pin: b.pin, command_key: b.command_key } };
}

interface RelayBodyBase {
  session_id: string;
  device_id: string;
}
function parseRelayBodyBase(body: unknown): { ok: true; value: RelayBodyBase; raw: Record<string, unknown> } | { ok: false; error: string } {
  if (!body || typeof body !== 'object') return { ok: false, error: 'Body must be a JSON object' };
  const b = body as Record<string, unknown>;
  if (!isUuid(b.session_id)) return { ok: false, error: 'session_id must be a uuid' };
  if (!isUuid(b.device_id)) return { ok: false, error: 'device_id must be a uuid' };
  return { ok: true, value: { session_id: b.session_id, device_id: b.device_id }, raw: b };
}

// ── Supabase clients — service_role only. There is no caller JWT on this
// path (verify_jwt: false, no auth.uid() anywhere) — every RPC call below
// is made AS service_role, deliberately, per §3.9a / RPC §1.1d/§9.4-§9.6. ──
function serviceClient(schema: 'venue' | 'kernel'): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
    db: { schema },
  });
}
function serviceClientPublic(): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

// ── `/mint` and `/refresh` — both call `venue.mint_door_session` a second
// time; there is no `venue.refresh_door_session` and none is contracted
// (RPC §1.1d `AUTHZ-H3a`(b)). Same rate-limit principal AND action for both
// routes — a re-mint is the same operation the PIN budget must bound, so
// `/refresh` cannot be a limiter-free path to unlimited session life. ─────
async function handleMintOrRefresh(req: Request, headers: Record<string, string>): Promise<Response> {
  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    return json({ error: 'Body must be valid JSON' }, 400, headers);
  }
  const parsed = parseMintBody(rawBody);
  if (!parsed.ok) return json({ error: parsed.error }, 400, headers);
  const { venue_id, session_id, device_id, pin, command_key } = parsed.value;

  const publicSvc = serviceClientPublic();
  const principal = deriveDoorPinRateLimitPrincipal(venue_id, device_id);
  const rl = await checkRateLimit(publicSvc, principal, 'door-pin:mint', 5, 60);
  if (rl !== 'allowed') {
    logOutcome({ route: 'mint', door_session_id: null, session_id, venue_id, outcome: `rate_limited_${rl}` });
    return rateLimitedResponse(rl, headers);
  }

  const venueSvc = serviceClient('venue');
  const { data, error } = await venueSvc.rpc('mint_door_session', {
    p_venue_id: venue_id,
    p_session_id: session_id,
    p_device_id_claim: device_id,
    p_pin: pin,
    p_command_key: command_key,
  });

  if (error) {
    if (isDoorPinKdfUnavailable(error.message)) {
      // PFA-26: parked fail-closed, ZERO mutation. Clean 503, never a crash.
      logOutcome({ route: 'mint', door_session_id: null, session_id, venue_id, outcome: 'pin_unavailable' });
      return json(
        { error: 'Door PIN sessions are temporarily unavailable.', code: 'pin_unavailable' },
        503,
        { ...headers, 'Retry-After': '300' },
      );
    }
    if (isAssertDoorSessionAuthFailure(error.code ?? null, error.message ?? null)) {
      // §9.6: one opaque class for every precondition failure (wrong PIN,
      // wrong device, wrong venue, wrong session — never distinguished).
      logOutcome({ route: 'mint', door_session_id: null, session_id, venue_id, outcome: 'refused' });
      return opaqueMintFailure(headers);
    }
    await captureException('door-session', new Error(error.message), { route: 'mint', session_id, venue_id });
    logOutcome({ route: 'mint', door_session_id: null, session_id, venue_id, outcome: 'mint_rpc_error' });
    return json({ error: 'Door sessions are temporarily unavailable. Please try again shortly.' }, 500, headers);
  }

  const response = data as
    | { status: 'ok'; door_session_id: string; secret: string; expires_at: string; bound_device_id?: string; bound_session_id?: string }
    | { status: 'noop_replay'; door_session_id: string; expires_at?: string }
    | null
    | undefined;

  if (!response || typeof response !== 'object' || typeof response.door_session_id !== 'string') {
    await captureException('door-session', new Error('mint_response_malformed'), { route: 'mint', session_id, venue_id });
    logOutcome({ route: 'mint', door_session_id: null, session_id, venue_id, outcome: 'mint_response_malformed' });
    return json({ error: 'Door sessions are temporarily unavailable. Please try again shortly.' }, 500, headers);
  }

  if (response.status === 'noop_replay') {
    // §9.6: "A replay returns { status: 'noop_replay' } and the ORIGINAL
    // door_session_id — but NOT the secret, which was returned once and is
    // unrecoverable by construction." A client that lost the secret must
    // re-mint with a fresh command_key; it cannot recover this session.
    logOutcome({ route: 'mint', door_session_id: response.door_session_id, session_id, venue_id, outcome: 'idempotency_replay' });
    return json(
      { door_session_id: response.door_session_id, expires_at: response.expires_at ?? null, replayed: true },
      200,
      headers,
    );
  }

  // Success — the secret is returned ONCE and never re-returned by any route.
  logOutcome({ route: 'mint', door_session_id: response.door_session_id, session_id, venue_id, outcome: 'minted' });
  return json({ door_session_id: response.door_session_id, secret: response.secret, expires_at: response.expires_at }, 200, headers);
}

// ── Every relay route's shared preamble: parse bearer → rate limit →
// `assert_door_session` → cross-check the returned device id. Returns the
// BOUND `(device_id, event_session_id)` pair on success, or a Response to
// send back immediately on any failure. Structural gate (§3.9a): every
// relay handler's FIRST DB call is `assert_door_session` — this function is
// that gate, shared so no relay handler below can reach its RPC without it.
// ─────────────────────────────────────────────────────────────────────────
interface RelayAdmission {
  boundDeviceId: string;
  boundSessionId: string;
}
async function admitRelayCall(
  req: Request,
  route: DoorSessionRoute,
  bodySessionId: string,
  bodyDeviceId: string,
  headers: Record<string, string>,
): Promise<{ ok: true; admission: RelayAdmission } | { ok: false; response: Response }> {
  const parsedBearer = parseDoorSessionBearer(req.headers.get('authorization'));
  if (!parsedBearer) {
    logOutcome({ route, door_session_id: null, session_id: bodySessionId, venue_id: null, outcome: 'missing_or_malformed_bearer' });
    return { ok: false, response: opaqueAuthFailure(headers) };
  }
  const { doorSessionId, secret } = parsedBearer;

  const publicSvc = serviceClientPublic();
  const principal = deriveDoorSessionRateLimitPrincipal(doorSessionId);
  const rl = await checkRateLimit(publicSvc, principal, `door-session:${route}`, 60, 60);
  if (rl !== 'allowed') {
    logOutcome({ route, door_session_id: doorSessionId, session_id: bodySessionId, venue_id: null, outcome: `rate_limited_${rl}` });
    return { ok: false, response: rateLimitedResponse(rl, headers) };
  }

  const kernelSvc = serviceClient('kernel');
  const { data, error } = await kernelSvc.rpc('assert_door_session', {
    p_device_id: bodyDeviceId,
    p_session_id: bodySessionId,
    p_door_session_id: doorSessionId,
    p_session_token: secret,
  });

  if (error) {
    if (isAssertDoorSessionAuthFailure(error.code ?? null, error.message ?? null)) {
      logOutcome({ route, door_session_id: doorSessionId, session_id: bodySessionId, venue_id: null, outcome: 'assert_refused' });
      return { ok: false, response: opaqueAuthFailure(headers) };
    }
    await captureException('door-session', new Error(error.message), { route, door_session_id: doorSessionId });
    logOutcome({ route, door_session_id: doorSessionId, session_id: bodySessionId, venue_id: null, outcome: 'assert_rpc_error' });
    return { ok: false, response: json({ error: 'Door sessions are temporarily unavailable. Please try again shortly.' }, 500, headers) };
  }

  // `assert_door_session` returns `(device_id, event_session_id)` — accept
  // either a single-row object or a one-element array (PostgREST may wrap a
  // scalar/composite RPC result either way depending on how it is declared;
  // this function never guesses beyond that).
  const row = Array.isArray(data) ? data[0] : data;
  const boundDeviceId = row && typeof row === 'object' ? (row as Record<string, unknown>).device_id : undefined;
  const boundSessionId = row && typeof row === 'object' ? (row as Record<string, unknown>).event_session_id : undefined;

  if (typeof boundDeviceId !== 'string' || typeof boundSessionId !== 'string') {
    await captureException('door-session', new Error('assert_door_session_response_malformed'), { route, door_session_id: doorSessionId });
    logOutcome({ route, door_session_id: doorSessionId, session_id: bodySessionId, venue_id: null, outcome: 'assert_response_malformed' });
    return { ok: false, response: json({ error: 'Door sessions are temporarily unavailable. Please try again shortly.' }, 500, headers) };
  }

  // EDGE-4c / EA-6: the returned device id is licensed; the body's is a
  // cross-check only. A mismatch here means `assert_door_session` accepted
  // a call whose bound row disagrees with the request's own claim — under
  // §1.1d clause 1 that should already be impossible (device_id is part of
  // the row match), so seeing it at all is an attack signal, not a client
  // bug, and is treated with the SAME opaque response as an unknown id.
  if (!deviceIdsMatch(boundDeviceId, bodyDeviceId)) {
    await captureMessage('door-session', 'device_id_cross_check_mismatch', 'warning', {
      route,
      door_session_id: doorSessionId,
    });
    logOutcome({ route, door_session_id: doorSessionId, session_id: bodySessionId, venue_id: null, outcome: 'device_id_mismatch' });
    return { ok: false, response: opaqueAuthFailure(headers) };
  }

  logOutcome({ route, door_session_id: doorSessionId, session_id: boundSessionId, venue_id: null, outcome: 'admitted' });
  return { ok: true, admission: { boundDeviceId, boundSessionId } };
}

// ── `/manifest/sync` — assert → `venue.get_door_manifest`. Pass through
// only what the RPC returns (data minimization). ───────────────────────────
async function handleManifestSync(req: Request, headers: Record<string, string>): Promise<Response> {
  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    return json({ error: 'Body must be valid JSON' }, 400, headers);
  }
  const base = parseRelayBodyBase(rawBody);
  if (!base.ok) return json({ error: base.error }, 400, headers);
  const { session_id, device_id } = base.value;
  const sinceDeltaSeq = base.raw.since_delta_seq;
  if (sinceDeltaSeq !== undefined && sinceDeltaSeq !== null && typeof sinceDeltaSeq !== 'number') {
    return json({ error: 'since_delta_seq must be a number when present' }, 400, headers);
  }

  const admission = await admitRelayCall(req, 'manifest_sync', session_id, device_id, headers);
  if (!admission.ok) return admission.response;

  const venueSvc = serviceClient('venue');
  const { data, error } = await venueSvc.rpc('get_door_manifest', {
    p_session_id: admission.admission.boundSessionId,
    p_since_delta_seq: sinceDeltaSeq ?? null,
  });

  if (error) {
    await captureException('door-session', new Error(error.message), { route: 'manifest_sync', session_id: admission.admission.boundSessionId });
    logOutcome({ route: 'manifest_sync', door_session_id: null, session_id: admission.admission.boundSessionId, venue_id: null, outcome: 'manifest_rpc_error' });
    return json({ error: 'Manifest sync is temporarily unavailable. Please try again shortly.' }, 500, headers);
  }

  logOutcome({ route: 'manifest_sync', door_session_id: null, session_id: admission.admission.boundSessionId, venue_id: null, outcome: 'synced' });
  return json(data, 200, headers);
}

// ── `/scan` — assert → `venue.record_scan`. `p_scan_meta.device_id` is
// REJECTED, not ignored (RPC §9.4, matrix X-5). ────────────────────────────
async function handleScan(req: Request, headers: Record<string, string>): Promise<Response> {
  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    return json({ error: 'Body must be valid JSON' }, 400, headers);
  }
  const base = parseRelayBodyBase(rawBody);
  if (!base.ok) return json({ error: base.error }, 400, headers);
  const { session_id, device_id } = base.value;
  const atomId = base.raw.atom_id;
  const scanMeta = base.raw.scan_meta;
  const commandKey = base.raw.command_key;

  if (!isUuid(atomId)) return json({ error: 'atom_id must be a uuid' }, 400, headers);
  if (typeof commandKey !== 'string' || commandKey.length === 0) return json({ error: 'command_key is required' }, 400, headers);
  if (hasForbiddenDeviceIdField(scanMeta)) {
    return json({ error: 'scan_meta.device_id is not accepted; device identity is derived server-side.', code: 'invalid_input' }, 400, headers);
  }

  const admission = await admitRelayCall(req, 'scan', session_id, device_id, headers);
  if (!admission.ok) return admission.response;

  const venueSvc = serviceClient('venue');
  const { data, error } = await venueSvc.rpc('record_scan', {
    p_atom_id: atomId,
    p_session_id: admission.admission.boundSessionId,
    p_actor_device_id: admission.admission.boundDeviceId,
    p_scan_meta: scanMeta ?? {},
    p_command_key: commandKey,
  });

  if (error) {
    await captureException('door-session', new Error(error.message), { route: 'scan', session_id: admission.admission.boundSessionId });
    logOutcome({ route: 'scan', door_session_id: null, session_id: admission.admission.boundSessionId, venue_id: null, outcome: 'scan_rpc_error' });
    return json({ error: 'Scan is temporarily unavailable. Please try again shortly.' }, 500, headers);
  }

  logOutcome({ route: 'scan', door_session_id: null, session_id: admission.admission.boundSessionId, venue_id: null, outcome: 'scanned' });
  return json(data, 200, headers);
}

// ── `/offline-batch` — assert → `venue.reconcile_offline_scans`. Every row
// of `batch` is checked for a forbidden `device_id` field, same rule as
// `/scan`. ──────────────────────────────────────────────────────────────
async function handleOfflineBatch(req: Request, headers: Record<string, string>): Promise<Response> {
  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    return json({ error: 'Body must be valid JSON' }, 400, headers);
  }
  const base = parseRelayBodyBase(rawBody);
  if (!base.ok) return json({ error: base.error }, 400, headers);
  const { session_id, device_id } = base.value;
  const batch = base.raw.batch;
  const commandKey = base.raw.command_key;

  if (!Array.isArray(batch)) return json({ error: 'batch must be an array' }, 400, headers);
  if (typeof commandKey !== 'string' || commandKey.length === 0) return json({ error: 'command_key is required' }, 400, headers);
  if (batchContainsForbiddenDeviceId(batch)) {
    return json({ error: 'batch rows may not carry device_id; device identity is derived server-side.', code: 'invalid_input' }, 400, headers);
  }

  const admission = await admitRelayCall(req, 'offline_batch', session_id, device_id, headers);
  if (!admission.ok) return admission.response;

  const venueSvc = serviceClient('venue');
  const { data, error } = await venueSvc.rpc('reconcile_offline_scans', {
    p_session_id: admission.admission.boundSessionId,
    p_actor_device_id: admission.admission.boundDeviceId,
    p_batch: batch,
    p_command_key: commandKey,
  });

  if (error) {
    await captureException('door-session', new Error(error.message), { route: 'offline_batch', session_id: admission.admission.boundSessionId });
    logOutcome({ route: 'offline_batch', door_session_id: null, session_id: admission.admission.boundSessionId, venue_id: null, outcome: 'offline_batch_rpc_error' });
    return json({ error: 'Offline reconciliation is temporarily unavailable. Please try again shortly.' }, 500, headers);
  }

  logOutcome({ route: 'offline_batch', door_session_id: null, session_id: admission.admission.boundSessionId, venue_id: null, outcome: 'reconciled' });
  return json(data, 200, headers);
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: getResponseHeaders(req) });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405, getResponseHeaders(req));
  }

  const H = getResponseHeaders(req);

  try {
    const pathname = new URL(req.url).pathname;
    const route = dispatchDoorSessionRoute(pathname);
    if (!route) {
      return json({ error: 'Not found' }, 404, H);
    }

    switch (route) {
      case 'mint':
      case 'refresh':
        return await handleMintOrRefresh(req, H);
      case 'manifest_sync':
        return await handleManifestSync(req, H);
      case 'scan':
        return await handleScan(req, H);
      case 'offline_batch':
        return await handleOfflineBatch(req, H);
    }
  } catch (err) {
    await captureException('door-session', err);
    logOutcome({ route: 'unknown', door_session_id: null, session_id: null, venue_id: null, outcome: 'unhandled_error' });
    return json({ error: 'An unexpected error occurred. Please try again.' }, 500, H);
  }
});
