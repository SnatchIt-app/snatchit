/**
 * supabase/functions/credential-sign/credential.ts
 * ═══════════════════════════════════════════════════════════════════════════
 * The PURE, IMPORT-FREE core of the ticket-credential signer (C33).
 *
 * WHY THIS FILE IS SEPARATE FROM `index.ts`
 *   Deno edge modules import over `https://…` URLs, which vitest cannot load.
 *   Every byte that ends up inside a KMS signature — and every check a
 *   verifier runs against one — lives here, with NO imports (not even Deno's
 *   std lib), so `tests/credential-sign.test.ts` can exercise it directly in
 *   Node. `index.ts` is the I/O shell: HTTP, auth, the Supabase client, the
 *   KMS provider adapter, Sentry. Same split as `payout-execute/executor.ts`
 *   vs its `index.ts`, and `refund-execute/executor.ts` vs its `index.ts`.
 *
 * WHAT THIS MODULE IS, EXACTLY
 *   The frozen contract (`docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md`
 *   §3.2, §5/C33) fixes the six signed claims — `atom_id, session_id,
 *   credential_version, key_id, issued_at, exp` — and leaves the WIRE
 *   ENCODING as "a compact signed token". This module IS that encoding,
 *   proposed here and filed as `PFA-PT-6` (pending owner signature) in
 *   `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md`:
 *
 *     token = b64url(protected_header) + "." + b64url(payload) + "." + b64url(signature)
 *
 *   protected_header (canonical JSON, sorted keys, no whitespace):
 *     { "alg": "EdDSA" | "ES256", "kid": <key_id, lowercase uuid>,
 *       "typ": "SNATCHIT-TICKET-CRED-V1" }
 *
 *   payload (canonical JSON, sorted keys, no whitespace):
 *     { "atom": <ticket_atom_id, lowercase uuid>, "exp": <unix seconds, int>,
 *       "iat": <unix seconds, int>, "sess": <session_id, lowercase uuid>,
 *       "ver": <credential_version, int> }
 *
 *   `key_id` rides the header as `kid`; the other five frozen claims are in
 *   the payload. NO floats, NO locale-formatted anything, NO mutable display
 *   fields (title, venue name, …) — only the six frozen, machine-checkable
 *   facts. This is deliberate: a display field would make two credentials for
 *   the SAME atom+version sign differently depending on when a title changed,
 *   which breaks the "business-level idempotency" argument (KCRYPTO report §4).
 *
 * DOMAIN SEPARATION — the `typ` claim
 *   `typ` sits INSIDE the protected header, which is part of the SIGNED bytes
 *   (`signedBytes = ASCII(headerB64 + "." + payloadB64)`). A signature minted
 *   over a ticket-credential header can therefore never be replayed as, say, a
 *   wallet-manifest or door-manifest token: changing `typ` changes the header
 *   bytes, which changes the signed bytes, which the signature no longer
 *   covers. See `tests/credential-sign.test.ts`'s domain-separation case for
 *   the constructed proof (forge a different `typ` header, reuse a genuine
 *   signature, watch it fail).
 *
 * WHAT THIS MODULE DOES NOT DO
 *   No network, no KMS, no Deno/Node-specific API (no `Buffer`, no `Deno.*`,
 *   no `btoa`/`atob` — base64url is hand-rolled so behaviour is identical in
 *   the Deno edge runtime and in vitest/Node). It signs NOTHING itself — it
 *   only builds the bytes a signer must sign (`buildCanonicalPayload`) and
 *   assembles/parses the compact token around a signature the CALLER supplies
 *   (`encodeToken`, `decodeTokenStructure`, `verifyToken`). The verifier's
 *   actual crypto primitive is INJECTED (`VerifyPrimitive`) so this module
 *   never needs to choose or import a crypto library, and the test can inject
 *   Node's Ed25519 while the real door/edge injects whatever the platform
 *   provides.
 *
 * STATELESS BY DESIGN (frozen model, EDGE_FUNCTION_SPEC §5.5)
 *   There is no dedup table and no "already signed" check here. Idempotency
 *   is a BUSINESS-LEVEL argument over `(atom_id, credential_version)`, not a
 *   byte-identical-signature guarantee (ECDSA-P256 is nondeterministic; even
 *   Ed25519's determinism is an implementation detail this module does not
 *   rely on). See KCRYPTO_credential_sign.md §4.
 */

// ─────────────────────────────────────────────────────────────────────────
// The domain separator + supported algorithms
// ─────────────────────────────────────────────────────────────────────────

/** The `typ` claim. Every other credential type in this system (wallet
 *  manifest, door manifest, refund receipt, …) MUST use a different `typ` —
 *  that is the entire domain-separation mechanism. Do not reuse this value
 *  for anything that is not a ticket credential. */
export const DOMAIN = 'SNATCHIT-TICKET-CRED-V1';

export type SigningAlgorithm = 'EdDSA' | 'ES256';

/** Ed25519 preferred (EDGE_FUNCTION_SPEC §5.1/§5.3). Used when the signing
 *  context does not carry a resolvable `algorithm` (kernel.signing_key has no
 *  `algorithm` column as of migration 083 — the provider/edge decides). */
export const DEFAULT_ALGORITHM: SigningAlgorithm = 'EdDSA';

function isSigningAlgorithm(value: unknown): value is SigningAlgorithm {
  return value === 'EdDSA' || value === 'ES256';
}

// ─────────────────────────────────────────────────────────────────────────
// The signing context — exactly `kernel.get_ticket_signing_context`'s
// `status: 'ok'` shape (DESIGN_102.md §1.1). This module reads it; it never
// re-derives any of it.
// ─────────────────────────────────────────────────────────────────────────

export interface TicketSigningContext {
  ticket_atom_id: string;
  session_id: string;
  credential_version: number;
  key_id: string;
  /** From `kernel.signing_key` if ever modeled; today always absent/null —
   *  `DEFAULT_ALGORITHM` applies. Never invent a value here. */
  algorithm?: string | null;
  /** A timestamptz from Postgres arrives as an ISO-8601 string over jsonb; a
   *  `Date` or a pre-computed unix-seconds `number` are also accepted (the
   *  latter mainly for test fixtures — see `toUnixSeconds`). */
  issued_at: string | number | Date;
  exp: string | number | Date;
}

// ─────────────────────────────────────────────────────────────────────────
// base64url — hand-rolled, no `Buffer`, no `btoa`/`atob`. Works identically
// under Deno and Node so the edge and the vitest suite exercise the same code.
// ─────────────────────────────────────────────────────────────────────────

const B64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const B64_REVERSE: Record<string, number> = (() => {
  const map: Record<string, number> = {};
  for (let i = 0; i < B64_ALPHABET.length; i++) map[B64_ALPHABET[i]] = i;
  return map;
})();

/** Standard base64, then made URL-safe and unpadded (RFC 4648 §5). */
export function base64urlEncode(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  for (; i + 3 <= bytes.length; i += 3) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += B64_ALPHABET[(n >> 18) & 63] + B64_ALPHABET[(n >> 12) & 63]
         + B64_ALPHABET[(n >> 6) & 63] + B64_ALPHABET[n & 63];
  }
  const remaining = bytes.length - i;
  if (remaining === 1) {
    const n = bytes[i] << 16;
    out += B64_ALPHABET[(n >> 18) & 63] + B64_ALPHABET[(n >> 12) & 63];
  } else if (remaining === 2) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out += B64_ALPHABET[(n >> 18) & 63] + B64_ALPHABET[(n >> 12) & 63] + B64_ALPHABET[(n >> 6) & 63];
  }
  return out.replace(/\+/g, '-').replace(/\//g, '_');
}

export function base64urlDecode(input: string): Uint8Array {
  const b64 = input.replace(/-/g, '+').replace(/_/g, '/');
  const cleanLen = b64.length - (b64.length % 4 === 0 ? 0 : 0); // no-op, kept for clarity
  const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4);
  const bytes: number[] = [];
  for (let i = 0; i < padded.length; i += 4) {
    const c0 = padded[i];
    const c1 = padded[i + 1];
    const c2 = padded[i + 2];
    const c3 = padded[i + 3];
    const n0 = B64_REVERSE[c0];
    const n1 = B64_REVERSE[c1];
    if (n0 === undefined || n1 === undefined) throw new Error('base64url: invalid character');
    bytes.push(((n0 << 2) | (n1 >> 4)) & 0xff);
    if (c2 !== '=' && c2 !== undefined) {
      const n2 = B64_REVERSE[c2];
      if (n2 === undefined) throw new Error('base64url: invalid character');
      bytes.push(((n1 << 4) | (n2 >> 2)) & 0xff);
      if (c3 !== '=' && c3 !== undefined) {
        const n3 = B64_REVERSE[c3];
        if (n3 === undefined) throw new Error('base64url: invalid character');
        bytes.push(((n2 << 6) | n3) & 0xff);
      }
    }
  }
  void cleanLen;
  return new Uint8Array(bytes);
}

// ─────────────────────────────────────────────────────────────────────────
// Canonical JSON — sorted keys, no whitespace, recursive. Deterministic
// regardless of the insertion order of the object literal that built it.
// ─────────────────────────────────────────────────────────────────────────

export function canonicalJSONStringify(value: unknown): string {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJSONStringify).join(',')}]`;
  }
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  const parts = keys.map((k) => `${JSON.stringify(k)}:${canonicalJSONStringify(record[k])}`);
  return `{${parts.join(',')}}`;
}

// ─────────────────────────────────────────────────────────────────────────
// Timestamps — unix-second integers only (no floats, per the frozen shape).
// ─────────────────────────────────────────────────────────────────────────

export function toUnixSeconds(value: string | number | Date): number {
  if (value instanceof Date) {
    if (Number.isNaN(value.getTime())) throw new Error('toUnixSeconds: invalid Date');
    return Math.floor(value.getTime() / 1000);
  }
  if (typeof value === 'number') {
    // Test fixtures and pre-derived contexts pass already-unix-seconds
    // integers; truncate defensively rather than accept a float claim.
    return Math.trunc(value);
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) throw new Error(`toUnixSeconds: invalid timestamp "${value}"`);
  return Math.floor(parsed.getTime() / 1000);
}

function normalizeUuid(id: string): string {
  return id.trim().toLowerCase();
}

// ─────────────────────────────────────────────────────────────────────────
// The protected header + payload shapes, and the builders.
// ─────────────────────────────────────────────────────────────────────────

export interface ProtectedHeader {
  alg: SigningAlgorithm;
  kid: string;
  typ: string;
}

export interface CredentialPayload {
  atom: string;
  exp: number;
  iat: number;
  sess: string;
  ver: number;
}

export interface CanonicalCredential {
  header: ProtectedHeader;
  payload: CredentialPayload;
  headerB64: string;
  payloadB64: string;
  /** `headerB64 + "." + payloadB64` — what a signer signs and a verifier re-derives. */
  signingInput: string;
  /** ASCII bytes of `signingInput` — pass this to `KMS.sign`. */
  signedBytes: Uint8Array;
}

export function buildHeader(ctx: TicketSigningContext): ProtectedHeader {
  const alg = isSigningAlgorithm(ctx.algorithm) ? ctx.algorithm : DEFAULT_ALGORITHM;
  return { alg, kid: normalizeUuid(ctx.key_id), typ: DOMAIN };
}

export function buildPayload(ctx: TicketSigningContext): CredentialPayload {
  return {
    atom: normalizeUuid(ctx.ticket_atom_id),
    exp: toUnixSeconds(ctx.exp),
    iat: toUnixSeconds(ctx.issued_at),
    sess: normalizeUuid(ctx.session_id),
    ver: Math.trunc(ctx.credential_version),
  };
}

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

/** The one function KMS-signing code calls: builds the exact bytes to sign. */
export function buildCanonicalPayload(ctx: TicketSigningContext): CanonicalCredential {
  const header = buildHeader(ctx);
  const payload = buildPayload(ctx);
  const headerB64 = base64urlEncode(textEncoder.encode(canonicalJSONStringify(header)));
  const payloadB64 = base64urlEncode(textEncoder.encode(canonicalJSONStringify(payload)));
  const signingInput = `${headerB64}.${payloadB64}`;
  return { header, payload, headerB64, payloadB64, signingInput, signedBytes: textEncoder.encode(signingInput) };
}

/** Assembles the compact token around a signature the caller produced
 *  (KMS in the edge; a test keypair in vitest). */
export function encodeToken(headerB64: string, payloadB64: string, signatureBytes: Uint8Array): string {
  return `${headerB64}.${payloadB64}.${base64urlEncode(signatureBytes)}`;
}

// ─────────────────────────────────────────────────────────────────────────
// Structural decode — no verification, just "is this shaped like a token".
// ─────────────────────────────────────────────────────────────────────────

export interface DecodedToken {
  headerB64: string;
  payloadB64: string;
  sigB64: string;
  header: ProtectedHeader;
  payload: CredentialPayload;
  /** ASCII bytes of `headerB64 + "." + payloadB64`, recomputed from the
   *  token's OWN header/payload segments — this is what a tampered header or
   *  payload changes, which is exactly what makes tampering detectable. */
  signedBytes: Uint8Array;
  signatureBytes: Uint8Array;
}

function isProtectedHeader(value: unknown): value is ProtectedHeader {
  if (!value || typeof value !== 'object') return false;
  const v = value as Record<string, unknown>;
  return typeof v.alg === 'string' && typeof v.kid === 'string' && typeof v.typ === 'string';
}

function isCredentialPayload(value: unknown): value is CredentialPayload {
  if (!value || typeof value !== 'object') return false;
  const v = value as Record<string, unknown>;
  return (
    typeof v.atom === 'string' &&
    typeof v.exp === 'number' &&
    typeof v.iat === 'number' &&
    typeof v.sess === 'string' &&
    typeof v.ver === 'number'
  );
}

export function decodeTokenStructure(token: string): DecodedToken | null {
  if (typeof token !== 'string' || token.length === 0) return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [headerB64, payloadB64, sigB64] = parts;
  if (!headerB64 || !payloadB64 || !sigB64) return null;

  let header: unknown;
  let payload: unknown;
  let signatureBytes: Uint8Array;
  try {
    header = JSON.parse(textDecoder.decode(base64urlDecode(headerB64)));
    payload = JSON.parse(textDecoder.decode(base64urlDecode(payloadB64)));
    signatureBytes = base64urlDecode(sigB64);
  } catch {
    return null;
  }
  if (!isProtectedHeader(header) || !isCredentialPayload(payload)) return null;

  return {
    headerB64,
    payloadB64,
    sigB64,
    header,
    payload,
    signedBytes: textEncoder.encode(`${headerB64}.${payloadB64}`),
    signatureBytes,
  };
}

// ─────────────────────────────────────────────────────────────────────────
// Verification — pure. The crypto primitive is INJECTED so this module never
// imports a crypto library; the caller supplies whatever the runtime offers.
// ─────────────────────────────────────────────────────────────────────────

/** Resolves a public key by `kid` against a TRUSTED keyring (M1, the
 *  `kernel.signing_key` projection) — NEVER a key carried inside the token
 *  itself. Return `null`/`undefined` for an unknown/untrusted `kid`. The
 *  shape of the returned key string is whatever `verifyPrimitive` expects
 *  (base64 SPKI DER in the vitest suite; the edge/door's own convention in
 *  production — this module does not care). */
export type PublicKeyResolver = (kid: string) => string | null | undefined | Promise<string | null | undefined>;

export type VerifyPrimitive = (
  publicKey: string,
  message: Uint8Array,
  signature: Uint8Array,
  alg: SigningAlgorithm,
) => boolean | Promise<boolean>;

export type VerifyReason =
  | 'ok'
  | 'malformed_token'
  | 'unknown_kid'
  | 'unsupported_alg'
  | 'signature_invalid'
  | 'expired';

export interface VerifyResult {
  authentic: boolean;
  reason: VerifyReason;
}

/**
 * Pure verification: structure → key resolution by `kid` → alg check →
 * signature → expiry. Does NOT check `credential_version` currency (that is
 * M2/live, §5.4.3 conjunct 3b.iii — a door/live-read concern, not this
 * module's) and does NOT check `session_id` binding (§5.4.3 check 3 — also a
 * door concern). This function proves AUTHENTICITY, not ADMISSIBILITY —
 * exactly the split the frozen spec draws (§5.4.3: "Signature authenticity ≠
 * current admissibility").
 */
export async function verifyToken(
  token: string,
  resolvePublicKeyByKid: PublicKeyResolver,
  nowSeconds: number,
  verifyPrimitive: VerifyPrimitive,
): Promise<VerifyResult> {
  const decoded = decodeTokenStructure(token);
  if (!decoded) return { authentic: false, reason: 'malformed_token' };

  if (!isSigningAlgorithm(decoded.header.alg)) {
    return { authentic: false, reason: 'unsupported_alg' };
  }

  const publicKey = await resolvePublicKeyByKid(decoded.header.kid);
  if (!publicKey) return { authentic: false, reason: 'unknown_kid' };

  const signatureOk = await verifyPrimitive(publicKey, decoded.signedBytes, decoded.signatureBytes, decoded.header.alg);
  if (!signatureOk) return { authentic: false, reason: 'signature_invalid' };

  if (decoded.payload.exp <= nowSeconds) return { authentic: false, reason: 'expired' };

  return { authentic: true, reason: 'ok' };
}

// ─────────────────────────────────────────────────────────────────────────
// Log-line shape — a pure, testable artifact so the "never log the token,
// payload, or key material" rule (EDGE_FUNCTION_SPEC §3.2 "Logging") is
// enforced both by the TYPE (these four fields are all `CredentialSignLogFields`
// admits) and by a runtime shape assertion in the test suite.
// ─────────────────────────────────────────────────────────────────────────

export interface CredentialSignLogFields {
  atom_id: string | null;
  credential_version: number | null;
  key_id: string | null;
  outcome: string;
}

const LOG_TAG = 'credential-sign';

export function buildCredentialSignLogLine(fields: CredentialSignLogFields): string {
  return JSON.stringify({ tag: LOG_TAG, ...fields });
}
