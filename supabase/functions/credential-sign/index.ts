/**
 * supabase/functions/credential-sign/index.ts
 * ═══════════════════════════════════════════════════════════════════════════
 * `credential-sign` — mints the cacheable signed ticket credential (C33).
 *
 * Frozen contract: `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §3.2, §5.
 * Wire encoding proposed here as `PFA-PT-6`:
 *   `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md`.
 * Implementation notes: `docs/phase2/_impl/KCRYPTO_credential_sign.md`.
 * The pure token builder/verifier this file signs through: `./credential.ts`.
 *
 * Deploy posture: POST + OPTIONS, `verify_jwt: true`.
 *
 * ── NOT DEPLOYED ────────────────────────────────────────────────────────────
 * Authoring this file creates no KMS key, calls no KMS, and signs no
 * credential. Train boundary (TRAIN_BRIEF.md): no production, no deploy, no
 * KMS, no signing key, no secret — DARK code only. The `KmsSigner` this file
 * wires up throws `kms_provider_unconfigured` unconditionally; selecting a
 * real AWS KMS / GCP KMS / CloudHSM adapter is a ceremony-time decision made
 * by ANOTHER change, never here (§2.1 below).
 *
 * ── WHAT THIS FUNCTION IS ────────────────────────────────────────────────────
 * A THIN shell around `kernel.get_ticket_signing_context` (migration 102,
 * authored concurrently by DB-IMPL against the same DESIGN_102.md §1.1). The
 * database is the ONLY authority for "is this caller the owner, is the atom
 * alive, which key is pinned, what is the version, what is the TTL" — this
 * file does not re-derive any of those facts. It adds exactly the two things
 * the database cannot do: talk to KMS, and assemble the compact signed token.
 *
 * ── C33 NON-EXPOSURE (the constraint this file is built to hold under) ─────
 * The private signing key never appears here. `kernel.signing_key.kms_handle_ref`
 * is an opaque handle (an ARN, not key material) — it crosses this file only
 * to be passed to `KmsSigner.sign`, and it is NEVER logged, NEVER put in a
 * response body, NEVER put in a Sentry `extra`. `logOutcome` below is typed
 * (`CredentialSignLogFields`, from `credential.ts`) so there is no field to
 * accidentally put it in.
 *
 * ── §2.4 "THE SIGNER SIGNS ONE TYPE ONLY" (proof B — no arbitrary-bytes path) ─
 * The request body carries exactly `{ ticket_atom_id }`. The bytes handed to
 * `KmsSigner.sign` are `buildCanonicalPayload(ctx).signedBytes`, built ENTIRELY
 * from the DB-returned `ctx` — there is no code path from the request body (or
 * any other client input) into the signed bytes. The `kms_handle_ref` /
 * `key_id` passed to the signer are `ctx.kms_handle_ref` / the resolved header
 * `kid` — both come from the DB's OWN resolution of the atom's PINNED
 * `signing_key_id` (kernel.tickets.signing_key_id, set at issue/transfer).
 * There is no request field for a key id, and a client-supplied one (if ever
 * added to the body) is ignored — the RPC does not accept one.
 * ═══════════════════════════════════════════════════════════════════════════
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException, captureMessage } from '../_shared/sentry.ts';
import {
  buildCanonicalPayload,
  buildCredentialSignLogLine,
  encodeToken,
  type TicketSigningContext,
} from './credential.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// ── CORS + security headers (house style, copied shape from primary-checkout) ─
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

// ── Logging — NEVER the token, the payload, or any key material. The field
// set is fixed by `CredentialSignLogFields` (credential.ts), so there is no
// field to smuggle a secret into. ───────────────────────────────────────────
function logOutcome(atomId: string | null, credentialVersion: number | null, keyId: string | null, outcome: string) {
  console.log(buildCredentialSignLogLine({ atom_id: atomId, credential_version: credentialVersion, key_id: keyId, outcome }));
}

// ── Rate limit — fail CLOSED (spec §3.2 "Rate limit": 30 per 60s) ──────────
type RateLimitResult = 'allowed' | 'over_limit' | 'error';

async function checkRateLimit(
  service: ReturnType<typeof createClient>,
  userId: string,
): Promise<RateLimitResult> {
  try {
    const { data, error } = await service.rpc('check_rate_limit', {
      p_user_id: userId,
      p_action: 'credential-sign',
      p_max: 30,
      p_window_seconds: 60,
    });
    if (error) {
      console.warn('credential-sign: rate limit RPC error (failing closed):', error.message);
      return 'error';
    }
    return data === true ? 'allowed' : 'over_limit';
  } catch (err) {
    console.warn('credential-sign: rate limit check threw (failing closed):', err);
    return 'error';
  }
}

// ── Body ─────────────────────────────────────────────────────────────────
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function parseBody(body: unknown): { ok: true; ticketAtomId: string } | { ok: false; error: string } {
  if (!body || typeof body !== 'object') return { ok: false, error: 'Body must be a JSON object' };
  const b = body as Record<string, unknown>;
  if (typeof b.ticket_atom_id !== 'string' || !UUID_RE.test(b.ticket_atom_id)) {
    return { ok: false, error: 'ticket_atom_id must be a uuid' };
  }
  // NOTE: a client-supplied `credential_version` or `key_id`, if ever sent,
  // is ignored by construction — nothing below reads any body field but
  // `ticket_atom_id` (spec §3.2: "No version or key id from the client").
  return { ok: true, ticketAtomId: b.ticket_atom_id };
}

// ── `kernel.get_ticket_signing_context`'s `{status:'ok', …}` shape ─────────
// (DESIGN_102.md §1.1). Read defensively — a malformed response is a 500, not
// a crash and not a silently-accepted partial context.
interface SigningContextOk {
  status: 'ok';
  ticket_atom_id: string;
  session_id: string;
  credential_version: number;
  key_id: string;
  kms_handle_ref: string;
  public_key: string;
  algorithm: string | null;
  not_before: string;
  not_after: string | null;
  issued_at: string;
  ttl_seconds: number;
  exp: string;
  domain: string;
}
interface SigningContextRefused {
  status: 'refused';
  code: string;
}
type SigningContextResponse = SigningContextOk | SigningContextRefused;

function isSigningContextOk(v: unknown): v is SigningContextOk {
  if (!v || typeof v !== 'object') return false;
  const r = v as Record<string, unknown>;
  return (
    r.status === 'ok' &&
    typeof r.ticket_atom_id === 'string' &&
    typeof r.session_id === 'string' &&
    typeof r.credential_version === 'number' &&
    typeof r.key_id === 'string' &&
    typeof r.kms_handle_ref === 'string' &&
    typeof r.issued_at === 'string' &&
    typeof r.exp === 'string' &&
    typeof r.ttl_seconds === 'number'
  );
}

function isSigningContextRefused(v: unknown): v is SigningContextRefused {
  if (!v || typeof v !== 'object') return false;
  const r = v as Record<string, unknown>;
  return r.status === 'refused' && typeof r.code === 'string';
}

// ── Refusal-code → HTTP mapping (spec §3.2 "Failure") ──────────────────────
function mapRefusalCode(code: string): { status: number; body: Record<string, unknown>; sentry: 'message' | 'exception' | null } {
  switch (code) {
    case 'not_owner':
      // Fraud signal (spec: "Sentry: capture … owner-mismatch spikes").
      return { status: 403, body: { error: 'You do not own this ticket.', code: 'not_owner' }, sentry: 'message' };
    case 'atom_terminal':
      return { status: 409, body: { error: 'This ticket is no longer active.', code: 'atom_terminal' }, sentry: null };
    case 'signing_key_unavailable':
      // Ops-critical: an event with issued atoms but no active/in-window key.
      return {
        status: 500,
        body: { error: 'Ticket credentials are temporarily unavailable. Please try again shortly.', code: 'signing_key_unavailable' },
        sentry: 'exception',
      };
    default:
      // Defensive: an unrecognized refusal code from the DB is a defect, not
      // a case to guess at — fail closed, alert, never expose the raw code.
      return {
        status: 500,
        body: { error: 'Ticket credentials are temporarily unavailable. Please try again shortly.', code: 'signing_context_unrecognized' },
        sentry: 'exception',
      };
  }
}

// ── KMS provider adapter — a ceremony-time choice, NOT made here ───────────
// (spec §5.3, §5.7; DESIGN_102.md §2.1: "do NOT hardcode a provider or call
// any KMS"). The real AWS KMS / GCP KMS / CloudHSM adapter is selected when
// this train's boundary lifts; this default throws unconditionally so the
// code path is complete and testable in SHAPE without ever being able to
// reach a live signer.
interface KmsSigner {
  sign(kmsHandleRef: string, bytes: Uint8Array, algorithm: string): Promise<Uint8Array>;
}

class UnconfiguredKmsSigner implements KmsSigner {
  // deno-lint-ignore require-await
  async sign(_kmsHandleRef: string, _bytes: Uint8Array, _algorithm: string): Promise<Uint8Array> {
    throw new Error('kms_provider_unconfigured');
  }
}

const kmsSigner: KmsSigner = new UnconfiguredKmsSigner();

/** `kms_provider_unconfigured` is a permanent config error (500, alert — this
 *  deploy has no signer wired in at all). Anything else surfacing from a real
 *  adapter's transient failure modes (throttling, timeout, temporary
 *  unavailability) is a 503 the client should retry (spec §3.2 "KMS down:
 *  503"). */
function classifyKmsError(err: unknown): { status: 500 | 503; retryAfterSeconds: number | null } {
  const message = err instanceof Error ? err.message : String(err);
  if (message === 'kms_provider_unconfigured') return { status: 500, retryAfterSeconds: null };
  if (/throttl|unavailable|timeout|timed out|temporarily|too many requests/i.test(message)) {
    return { status: 503, retryAfterSeconds: 5 };
  }
  return { status: 500, retryAfterSeconds: null };
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
    // ── 1. Authentication (actor is server-derived from the JWT, never a body field)
    const authHeader = req.headers.get('authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return json({ error: 'Missing or invalid Authorization header' }, 401, H);
    }

    const service = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: { user }, error: userErr } = await service.auth.getUser(authHeader.replace('Bearer ', ''));
    if (userErr || !user) {
      return json({ error: 'Invalid or expired token' }, 401, H);
    }
    const ownerId = user.id;

    // ── 2. Rate limit — fail CLOSED (503 on limiter fault, 429 over limit) ──
    const rl = await checkRateLimit(service, ownerId);
    if (rl === 'error') {
      return json({ error: 'Service temporarily unavailable. Please try again shortly.' }, 503, { ...H, 'Retry-After': '30' });
    }
    if (rl === 'over_limit') {
      return json({ error: 'Too many requests. Please try again later.' }, 429, { ...H, 'Retry-After': '60' });
    }

    // ── 3. Body ──────────────────────────────────────────────────────────
    let rawBody: unknown;
    try {
      rawBody = await req.json();
    } catch {
      return json({ error: 'Body must be valid JSON' }, 400, H);
    }
    const parsed = parseBody(rawBody);
    if (!parsed.ok) return json({ error: parsed.error }, 400, H);
    const { ticketAtomId } = parsed;

    // ── 4. The DB authority — `kernel.get_ticket_signing_context`. Called
    // AS THE OWNER (the user's own JWT forwarded, anon key), never as
    // service_role: the RPC is `authenticated`-granted and its body reads
    // `auth.uid()` for the ownership check (DESIGN_102.md §1.1) — the edge
    // does not, and must not, pick the owner itself.
    const kernelCaller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
      db: { schema: 'kernel' },
    });

    const { data: ctxData, error: ctxErr } = await kernelCaller.rpc('get_ticket_signing_context', {
      p_ticket_atom_id: ticketAtomId,
    });
    if (ctxErr) {
      await captureException('credential-sign', new Error(ctxErr.message), { atom_id: ticketAtomId });
      logOutcome(ticketAtomId, null, null, 'signing_context_rpc_error');
      return json({ error: 'Ticket credentials are temporarily unavailable. Please try again shortly.' }, 500, H);
    }

    const response = ctxData as SigningContextResponse;

    if (isSigningContextRefused(response)) {
      const mapped = mapRefusalCode(response.code);
      if (mapped.sentry === 'message') {
        await captureMessage('credential-sign', `refused:${response.code}`, 'warning', { atom_id: ticketAtomId, owner_id: ownerId });
      } else if (mapped.sentry === 'exception') {
        await captureException('credential-sign', new Error(`refused:${response.code}`), { atom_id: ticketAtomId });
      }
      logOutcome(ticketAtomId, null, null, `refused_${response.code}`);
      return json(mapped.body, mapped.status, H);
    }

    if (!isSigningContextOk(response)) {
      await captureException('credential-sign', new Error('signing_context_malformed'), { atom_id: ticketAtomId });
      logOutcome(ticketAtomId, null, null, 'signing_context_malformed');
      return json({ error: 'Ticket credentials are temporarily unavailable. Please try again shortly.' }, 500, H);
    }

    // ── 5. Build the canonical payload — entirely from the DB context, never
    // from the request body (proof B, §2.4 above). ─────────────────────────
    const ctx: TicketSigningContext = {
      ticket_atom_id: response.ticket_atom_id,
      session_id: response.session_id,
      credential_version: response.credential_version,
      key_id: response.key_id,
      algorithm: response.algorithm,
      issued_at: response.issued_at,
      exp: response.exp,
    };
    const canonical = buildCanonicalPayload(ctx);

    // ── 6. Sign via KMS (the provider adapter — see UnconfiguredKmsSigner above)
    let signatureBytes: Uint8Array;
    try {
      signatureBytes = await kmsSigner.sign(response.kms_handle_ref, canonical.signedBytes, canonical.header.alg);
    } catch (kmsErr) {
      const { status, retryAfterSeconds } = classifyKmsError(kmsErr);
      await captureException('credential-sign', kmsErr, { atom_id: ticketAtomId, key_id: response.key_id });
      logOutcome(ticketAtomId, response.credential_version, response.key_id, 'kms_sign_failed');
      const headers = retryAfterSeconds !== null ? { ...H, 'Retry-After': String(retryAfterSeconds) } : H;
      return json(
        { error: 'Ticket credentials are temporarily unavailable. Please try again shortly.', code: status === 503 ? 'kms_unavailable' : 'kms_unconfigured' },
        status,
        headers,
      );
    }

    const token = encodeToken(canonical.headerB64, canonical.payloadB64, signatureBytes);

    // ── 7. Response (spec §3.2). `not_after` is the CREDENTIAL's own expiry
    // (== the signed `exp` claim, restated as a timestamp for client
    // convenience) — distinct from `ctx.not_after`, which is the SIGNING
    // KEY's validity window and is never surfaced to the client (see
    // KCRYPTO_credential_sign.md §2 for the interpretation note). ─────────
    logOutcome(ticketAtomId, response.credential_version, response.key_id, 'signed');
    return json(
      {
        token,
        credential_version: response.credential_version,
        signing_key_id: response.key_id,
        not_after: response.exp,
        ttl_seconds: response.ttl_seconds,
      },
      200,
      H,
    );
  } catch (err) {
    await captureException('credential-sign', err);
    logOutcome(null, null, null, 'unhandled_error');
    return json({ error: 'An unexpected error occurred. Please try again.' }, 500, H);
  }
});
