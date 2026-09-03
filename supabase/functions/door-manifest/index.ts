/**
 * supabase/functions/door-manifest/index.ts
 * ═══════════════════════════════════════════════════════════════════════════
 * `door-manifest` — KMS-sign the M2 ticket manifest, for parity with M1
 * (`credential-sign`). **OPTIONAL** per the frozen contract: the door's own
 * manifest fetch already has a home at `door-session`'s `/manifest/sync`
 * (verify_jwt: false, gated on `kernel.assert_door_session`); this function
 * exists only to add a KMS signature over the digest for a **staff** caller
 * who wants the signed artifact directly.
 *
 * Frozen contract: `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §3.9b.
 * `venue.get_door_manifest` result shape: RPC contracts §20.6.1.
 * KMS adapter (reused, not copied): `../credential-sign/kms.ts` /
 * `../credential-sign/kms-taxonomy.ts` (`KmsSigner` / `UnconfiguredKmsSigner`
 * / `AwsKmsSigner`).
 *
 * ── ONE route, ONE auth model, ONE verify_jwt value (`SPEC CORRECTION
 *    EDGE-2`) ─────────────────────────────────────────────────────────────
 * `verify_jwt: true`. **Class A (EA-1).** A `venue_scanner` / `venue_manager`
 * staff JWT. `venue.get_door_manifest` authorizes on
 * `has_venue_role(venue, ['venue_scanner','venue_manager'])` — a
 * caller-identity predicate — so the RPC call rides the CALLER's own
 * `Authorization` header (never service_role for that call). The PIN/door-
 * session route this section originally specified is DELETED, not split
 * (§3.9b `EDGE-2`): it would have reintroduced the "provisioning, not
 * possession" gate `AUTHZ-H3` closed, one section after closing it, and
 * `door-session`'s `/manifest/sync` already serves that traffic.
 *
 * ── DARK / NOT DEPLOYED — KMS is always UnconfiguredKmsSigner here ───────
 * Authoring this file creates no KMS key, calls no KMS, and signs no
 * manifest. `KMS_PROVIDER` defaults to unset → `UnconfiguredKmsSigner`
 * (`kms-taxonomy.ts`), which throws `kms_provider_unconfigured`
 * unconditionally — surfaced below as a clean 500/`kms_unconfigured`, never
 * a crash. Selecting `KMS_PROVIDER=aws` with real AWS credentials on a
 * deployed edge is a ceremony-time operator decision made by another
 * change, never here (mirrors `credential-sign/index.ts`'s own posture and
 * its `selectKmsSigner`).
 *
 * ── "Deterministic over the digest, so re-signing is free" ───────────────
 * No stored signature, no unsigned window: every call re-fetches the
 * manifest and re-signs its digest object fresh. ("Deterministic" here
 * means the OPERATION is idempotent in effect — the same digest is always
 * validly signable, so caching a signature buys nothing — not that ECDSA
 * (ES256, AWS KMS's only offered algorithm — `kms.ts`) produces
 * bit-identical signature bytes across calls; it does not, by construction
 * of the algorithm. Flagged in `docs/phase2/_impl/KEDGES.md`.)
 *
 * ── Data minimization ──────────────────────────────────────────────────────
 * The response passes through only what `get_door_manifest` returns, plus
 * the signature. `get_door_manifest` already excludes `public_key`/identity
 * (PFA-24) — this file adds nothing beyond that. Log lines carry only
 * non-secret selectors (`session_id`, `manifest_id`, `outcome`) — never a
 * key handle, never PII, never signature bytes.
 * ═══════════════════════════════════════════════════════════════════════════
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { AwsKmsSigner, KmsSignError, UnconfiguredKmsSigner, type KmsErrorClass, type KmsSigner } from '../credential-sign/kms.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
// Declared per the frozen secrets list (§3.9b). Not used by any call in this
// handler today — every DB read here is caller-identity (`has_venue_role`),
// never service_role. Kept read (not removed) so a future addition (an
// audit-log write, a rate-limit table keyed differently, etc.) does not need
// a new secret wired in.
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
void SUPABASE_SERVICE_ROLE_KEY;

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

// ── Logging — never a key handle, signature bytes, or PII. ────────────────
function logOutcome(sessionId: string | null, manifestId: string | null, outcome: string) {
  console.log(JSON.stringify({ fn: 'door-manifest', session_id: sessionId, manifest_id: manifestId, outcome }));
}

// ── Rate limit — fail CLOSED. Not literally specified by §3.9b (which names
// no limiter for this route), added per the brief's general
// "rate-limit-fail-closed" shell requirement and this repo's house style
// (`credential-sign` uses 30/60 on the same Class-A/staff-JWT shape). Keyed
// on the caller's `auth.uid()` — a real identity exists on this path,
// unlike `door-session`. ────────────────────────────────────────────────
type RateLimitResult = 'allowed' | 'over_limit' | 'error';

async function checkRateLimit(service: SupabaseClient, userId: string): Promise<RateLimitResult> {
  try {
    const { data, error } = await service.rpc('check_rate_limit', {
      p_user_id: userId,
      p_action: 'door-manifest',
      p_max: 30,
      p_window_seconds: 60,
    });
    if (error) {
      console.warn('door-manifest: rate limit RPC error (failing closed):', error.message);
      return 'error';
    }
    return data === true ? 'allowed' : 'over_limit';
  } catch (err) {
    console.warn('door-manifest: rate limit check threw (failing closed):', err);
    return 'error';
  }
}

// ── Body ─────────────────────────────────────────────────────────────────
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface RequestBody {
  session_id: string;
  since_delta_seq: number | null;
}
function parseBody(body: unknown): { ok: true; value: RequestBody } | { ok: false; error: string } {
  if (!body || typeof body !== 'object') return { ok: false, error: 'Body must be a JSON object' };
  const b = body as Record<string, unknown>;
  if (typeof b.session_id !== 'string' || !UUID_RE.test(b.session_id)) {
    return { ok: false, error: 'session_id must be a uuid' };
  }
  if (b.since_delta_seq !== undefined && b.since_delta_seq !== null && typeof b.since_delta_seq !== 'number') {
    return { ok: false, error: 'since_delta_seq must be a number when present' };
  }
  return { ok: true, value: { session_id: b.session_id, since_delta_seq: (b.since_delta_seq as number | null) ?? null } };
}

// ── `venue.get_door_manifest`'s reconciled result shape (RPC §20.6.1). Read
// defensively — a malformed response is a 500, not a crash. ───────────────
interface DoorManifestOpen {
  open: true;
  manifest_id: string;
  manifest_version: number;
  session_id: string;
  opened_at: string;
  not_after: string;
  manifest_digest: string;
  max_delta_seq: number;
  entries: unknown[];
  deltas: unknown[];
}
interface DoorManifestClosed {
  open: false;
  status: 'no_open_manifest';
  entries: unknown[];
  deltas: unknown[];
}
type DoorManifestResponse = DoorManifestOpen | DoorManifestClosed;

function isDoorManifestOpen(v: unknown): v is DoorManifestOpen {
  if (!v || typeof v !== 'object') return false;
  const r = v as Record<string, unknown>;
  return (
    r.open === true &&
    typeof r.manifest_id === 'string' &&
    typeof r.manifest_version === 'number' &&
    typeof r.session_id === 'string' &&
    typeof r.not_after === 'string' &&
    typeof r.manifest_digest === 'string'
  );
}

// ── KMS provider adapter — a ceremony-time choice, NOT made here. Identical
// selection logic to `credential-sign/index.ts`. ──────────────────────────
function selectKmsSigner(): KmsSigner {
  const provider = Deno.env.get('KMS_PROVIDER') ?? '';
  if (provider === 'aws') {
    const region = Deno.env.get('AWS_REGION') || Deno.env.get('KMS_REGION') || undefined;
    const roleArn = Deno.env.get('KMS_SIGNER_ROLE_ARN') || undefined;
    return new AwsKmsSigner(region, roleArn);
  }
  return new UnconfiguredKmsSigner();
}
const kmsSigner: KmsSigner = selectKmsSigner();

// The KMS handle for the M2 manifest signing key. UNLIKE M1 (per-atom
// pinned via `kernel.signing_key`, resolved by `get_ticket_signing_context`)
// there is no RPC in the frozen contract that resolves a manifest-signing
// key/handle/algorithm — `§3.9b` names no such lookup and no such env var.
// `INFERENCE`, flagged here and in KEDGES.md: this file reads a
// `DOOR_MANIFEST_KMS_HANDLE_REF` env var (default empty) and signs with
// ES256 (AWS KMS's only offered algorithm — `kms.ts`'s file header). Both
// are inert while `KMS_PROVIDER` is unset (`UnconfiguredKmsSigner` throws
// before either value is read), so this inference has zero live effect
// until an owner ceremony both selects `aws` AND resolves this gap.
const DOOR_MANIFEST_KMS_HANDLE_REF = Deno.env.get('DOOR_MANIFEST_KMS_HANDLE_REF') ?? '';
const DOOR_MANIFEST_SIGNING_ALGORITHM: 'ES256' = 'ES256';

// ── KMS error taxonomy (mirrors credential-sign/index.ts's classifyKmsError)
interface KmsErrorClassification {
  status: 500 | 503;
  retryAfterSeconds: number | null;
  taxonomy: KmsErrorClass;
}
function classifyKmsError(err: unknown): KmsErrorClassification {
  if (err instanceof KmsSignError) {
    if (err.errorClass === 'transient') return { status: 503, retryAfterSeconds: 5, taxonomy: 'transient' };
    return { status: 500, retryAfterSeconds: null, taxonomy: err.errorClass };
  }
  const message = err instanceof Error ? err.message : String(err);
  if (message === 'kms_provider_unconfigured') {
    return { status: 500, retryAfterSeconds: null, taxonomy: 'permanent' };
  }
  if (/throttl|unavailable|timeout|timed out|temporarily|too many requests|5\d\d/i.test(message)) {
    return { status: 503, retryAfterSeconds: 5, taxonomy: 'transient' };
  }
  return { status: 500, retryAfterSeconds: null, taxonomy: 'permanent' };
}

// ── Canonical bytes for the signed digest object. Fixed key order (object
// literal insertion order, never re-sorted at runtime) so the same manifest
// state always produces the same bytes handed to the signer. ─────────────
function canonicalManifestDigestBytes(open: DoorManifestOpen): Uint8Array {
  const canonical = {
    manifest_id: open.manifest_id,
    manifest_version: open.manifest_version,
    session_id: open.session_id,
    not_after: open.not_after,
    manifest_digest: open.manifest_digest,
  };
  return new TextEncoder().encode(JSON.stringify(canonical));
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
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
    // ── 1. Authentication — verify_jwt: true already ran gateway-side;
    // this re-derives the caller so we have a principal to rate-limit and
    // log against, same pattern as credential-sign/index.ts. ─────────────
    const authHeader = req.headers.get('authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return json({ error: 'Missing or invalid Authorization header' }, 401, H);
    }

    const service = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: { user }, error: userErr } = await service.auth.getUser(authHeader.replace('Bearer ', ''));
    if (userErr || !user) {
      return json({ error: 'Invalid or expired token' }, 401, H);
    }

    // ── 2. Rate limit — fail CLOSED. ────────────────────────────────────
    const rl = await checkRateLimit(service, user.id);
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
    const { session_id, since_delta_seq } = parsed.value;

    // ── 4. `venue.get_door_manifest` — CALLER-IDENTITY (has_venue_role),
    // rides the forwarded Authorization header, never service_role. ──────
    const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
      db: { schema: 'venue' },
    });

    const { data: manifestData, error: manifestErr } = await callerClient.rpc('get_door_manifest', {
      p_session_id: session_id,
      p_since_delta_seq: since_delta_seq,
    });

    if (manifestErr) {
      // has_venue_role denial or any other RPC-level failure — opaque,
      // never distinguishes "no role" from "no such session" beyond what
      // the RPC itself returns.
      if (manifestErr.code === '42501' || manifestErr.message?.includes('insufficient_privilege')) {
        logOutcome(session_id, null, 'refused');
        return json({ error: 'You are not authorized to view this manifest.', code: 'insufficient_privilege' }, 403, H);
      }
      await captureException('door-manifest', new Error(manifestErr.message), { session_id });
      logOutcome(session_id, null, 'manifest_rpc_error');
      return json({ error: 'Manifest is temporarily unavailable. Please try again shortly.' }, 500, H);
    }

    const manifest = manifestData as DoorManifestResponse;

    if (!isDoorManifestOpen(manifest)) {
      // No open episode — a legitimate state (§20.6.1: "{ open: false,
      // status: 'no_open_manifest' }"), not an error. Nothing to sign.
      logOutcome(session_id, null, 'no_open_manifest');
      return json({ manifest, signature: null }, 200, H);
    }

    // ── 5. KMS-sign the digest object (§3.9b). ──────────────────────────
    let signatureBytes: Uint8Array;
    try {
      signatureBytes = await kmsSigner.sign(
        DOOR_MANIFEST_KMS_HANDLE_REF,
        canonicalManifestDigestBytes(manifest),
        DOOR_MANIFEST_SIGNING_ALGORITHM,
      );
    } catch (kmsErr) {
      const { status, retryAfterSeconds, taxonomy } = classifyKmsError(kmsErr);
      await captureException('door-manifest', kmsErr, { session_id, manifest_id: manifest.manifest_id, kms_error_class: taxonomy });
      logOutcome(session_id, manifest.manifest_id, `kms_sign_failed_${taxonomy}`);
      const headers = retryAfterSeconds !== null ? { ...H, 'Retry-After': String(retryAfterSeconds) } : H;
      const code = taxonomy === 'transient' ? 'kms_unavailable' : taxonomy === 'security' ? 'kms_security_error' : 'kms_unconfigured';
      return json(
        { error: 'The signed manifest is temporarily unavailable. Please try again shortly.', code },
        status,
        headers,
      );
    }

    // ── 6. Response — pass through only what `get_door_manifest` returned,
    // plus the signature. No key handle, no public key, nothing beyond
    // what the RPC already excludes (PFA-24: no identity column). ────────
    logOutcome(session_id, manifest.manifest_id, 'signed');
    return json(
      {
        manifest,
        signature: {
          value: bytesToBase64(signatureBytes),
          algorithm: DOOR_MANIFEST_SIGNING_ALGORITHM,
        },
      },
      200,
      H,
    );
  } catch (err) {
    await captureException('door-manifest', err);
    logOutcome(null, null, 'unhandled_error');
    return json({ error: 'An unexpected error occurred. Please try again.' }, 500, H);
  }
});
