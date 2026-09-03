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
 *
 * PFA-PT-8 — ALGORITHM PINNING (migration 103)
 *   `kernel.signing_key.algorithm` is now a real, immutable, distributed
 *   column — `kernel.get_ticket_signing_context` returns it (no longer
 *   null). The token header's `alg` is INFORMATIONAL ONLY: verification
 *   AUTHORITY is the TRUSTED key's own `algorithm` (`TrustedKey.algorithm`
 *   below), resolved by `kid` from the trusted keyring, never from the
 *   token. `verifyToken` refuses (`alg_mismatch`) unless
 *   `token.header.alg === trustedKey.algorithm` — no fallback, no "try
 *   EdDSA then ES256". See `docs/phase2/_impl/KMSADAPTER.md`.
 *
 * ES256 SIGNATURE ENCODING
 *   AWS KMS (the sanctioned ES256 provider, `./kms.ts`) returns ECDSA
 *   signatures as ASN.1/DER `SEQUENCE{INTEGER r, INTEGER s}`. This wire
 *   format (and WebCrypto's ECDSA verify) uses raw `R||S`, 64 bytes.
 *   `derToRawEcdsaP256`/`rawToDerEcdsaP256` below do that conversion, pure
 *   and import-free like everything else here.
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
  /** `kernel.signing_key.algorithm` (migration 103, PFA-PT-8) — a real value
   *  as of `kernel.get_ticket_signing_context`'s post-103 shape. Only a
   *  missing/unrecognized value falls back to `DEFAULT_ALGORITHM`; never
   *  invent one when the context provides a real algorithm. */
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
// ES256 (ECDSA P-256) signature encoding — DER ⇄ raw. AWS KMS's `Sign` API
// (the sanctioned ES256 provider, `./kms.ts`) returns a DER-encoded
// `SEQUENCE{INTEGER r, INTEGER s}`; JWS/this module's wire format and
// WebCrypto's ECDSA verify both use raw `R||S`, 64 bytes (r and s each
// left-padded/trimmed to 32 bytes, big-endian, unsigned). Pure, import-free,
// like everything else here — DER parsing is just byte offsets, no crypto
// library needed. EdDSA (Ed25519) signatures are ALREADY raw 64 bytes and
// need no conversion (passthrough) — these two functions are ES256-only.
// ─────────────────────────────────────────────────────────────────────────

const P256_INTEGER_BYTES = 32;

/** Reads a DER definite-form length starting at `buf[offset]`. Returns the
 *  decoded length and the offset of the first content byte. Rejects, each
 *  with a DISTINCT message:
 *   - indefinite length (leading byte 0x80, BER-only, invalid DER);
 *   - a length field wider than 4 bytes (defensive bound — this parser only
 *     ever sees a tiny ECDSA signature, never anything needing that many
 *     length-bytes);
 *   - NON-MINIMAL long-form encoding — either a leading 0x00 length byte
 *     (padding that contributes nothing: the same value fits in fewer
 *     bytes) or a long-form length that ends up `< 0x80` (a value that
 *     should have used short form in the first place). DER requires the
 *     minimal encoding; both are the same defect, just at different byte
 *     positions, so both are checked, and both are rejected rather than
 *     silently accepted from untrusted input;
 *   - OUT-OF-RANGE — a syntactically well-formed (minimal) long-form length
 *     that is still larger than the buffer it is read from. Accumulated
 *     with plain arithmetic (`length * 256 + byte`), not `<<`/`|`, so a
 *     4-byte length near `2^31` cannot wrap into a negative 32-bit int and
 *     be misreported as something else — it is caught here, by value,
 *     with its own message, distinct from "non-minimal". */
function readDerLength(buf: Uint8Array, offset: number): { length: number; contentOffset: number } {
  if (offset >= buf.length) throw new Error('malformed_der: truncated length');
  const first = buf[offset];
  if (first < 0x80) {
    return { length: first, contentOffset: offset + 1 };
  }
  const numBytes = first & 0x7f;
  if (numBytes === 0) throw new Error('malformed_der: indefinite length (BER, not DER)');
  if (numBytes > 4) throw new Error('malformed_der: length field too large');
  if (offset + 1 + numBytes > buf.length) throw new Error('malformed_der: truncated long-form length');
  // A leading 0x00 length byte can never be part of a minimal encoding —
  // it contributes nothing but bulk (the value fits in `numBytes - 1`
  // bytes, or is 0, which must be short-form). Reject before accumulating.
  if (buf[offset + 1] === 0x00) {
    throw new Error('malformed_der: non-minimal length encoding (leading zero byte)');
  }
  let length = 0;
  for (let i = 0; i < numBytes; i++) {
    length = length * 256 + buf[offset + 1 + i]; // regular arithmetic — no 32-bit bitwise wraparound
  }
  // The OTHER non-minimality shape: a nonzero leading byte that still
  // resolves to a value that fits in short form (e.g. long-form `0x81 0x05`
  // encoding length 5, which should have been the single short-form byte
  // `0x05`). Distinct check from the leading-zero-byte one above — together
  // they cover every non-minimal long-form encoding this parser can see.
  if (length < 0x80) throw new Error('malformed_der: non-minimal length encoding');
  // OUT-OF-RANGE, not non-minimal: a syntactically minimal length that is
  // simply too large for the buffer it was read from. This parser only ever
  // reads AWS KMS's own `Sign` response (a `security`-class input already
  // — the caller fails closed regardless), so this is defense-in-depth, not
  // the primary gate.
  if (length > buf.length) throw new Error('malformed_der: length exceeds buffer size (out of range)');
  return { length, contentOffset: offset + 1 + numBytes };
}

/** Reads one DER `INTEGER` at `buf[offset]`. Rejects a negative integer (the
 *  content's first byte has its high bit set with no preceding sign-padding
 *  zero — for r/s, which must be positive, that is malformed input, not a
 *  value to silently reinterpret) and returns the RAW content bytes
 *  (including any legitimate leading 0x00 sign-padding — normalization to 32
 *  bytes happens in the caller). */
function readDerInteger(buf: Uint8Array, offset: number): { bytes: Uint8Array; nextOffset: number } {
  if (offset >= buf.length || buf[offset] !== 0x02) {
    throw new Error('malformed_der: expected INTEGER tag (0x02)');
  }
  const { length, contentOffset } = readDerLength(buf, offset + 1);
  if (length === 0) throw new Error('malformed_der: zero-length INTEGER');
  if (contentOffset + length > buf.length) throw new Error('malformed_der: truncated INTEGER content');
  const bytes = buf.slice(contentOffset, contentOffset + length);
  if (bytes[0] >= 0x80) {
    // No sign-padding zero preceding a high-bit-set first byte ⇒ DER would
    // interpret this as a NEGATIVE integer. r/s are always positive.
    throw new Error('malformed_der: negative integer');
  }
  return { bytes, nextOffset: contentOffset + length };
}

/** Left-pads/trims an unsigned big-endian integer's minimal bytes to exactly
 *  32 bytes (P-256 field element width). Rejects a value that does not fit
 *  (more than 32 significant bytes after stripping sign-padding zeros) —
 *  that is out of range for a P-256 r/s, not a value to truncate. */
function normalizeToP256Width(bytes: Uint8Array): Uint8Array {
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0x00) start++;
  const trimmed = bytes.slice(start);
  if (trimmed.length > P256_INTEGER_BYTES) {
    throw new Error('malformed_der: integer exceeds P-256 field width');
  }
  const out = new Uint8Array(P256_INTEGER_BYTES);
  out.set(trimmed, P256_INTEGER_BYTES - trimmed.length);
  return out;
}

/** DER `SEQUENCE{INTEGER r, INTEGER s}` (AWS KMS's `Sign` output for
 *  `ECDSA_SHA_256`) → raw `R||S`, 64 bytes (JWS/WebCrypto wire format).
 *  Throws on any malformed input — wrong tag, over-long/under-long,
 *  trailing extra bytes, or a negative integer — a `security`-class defect
 *  (§ KMSADAPTER.md taxonomy), never a silent truncation. */
export function derToRawEcdsaP256(der: Uint8Array): Uint8Array {
  if (der.length < 8) throw new Error('malformed_der: too short to be a SEQUENCE of two INTEGERs');
  if (der[0] !== 0x30) throw new Error('malformed_der: expected SEQUENCE tag (0x30)');
  const seq = readDerLength(der, 1);
  if (seq.contentOffset + seq.length !== der.length) {
    throw new Error('malformed_der: SEQUENCE length does not match buffer (extra or missing bytes)');
  }
  const r = readDerInteger(der, seq.contentOffset);
  const s = readDerInteger(der, r.nextOffset);
  if (s.nextOffset !== der.length) {
    throw new Error('malformed_der: extra bytes after the second INTEGER');
  }
  const rRaw = normalizeToP256Width(r.bytes);
  const sRaw = normalizeToP256Width(s.bytes);
  const raw = new Uint8Array(64);
  raw.set(rRaw, 0);
  raw.set(sRaw, 32);
  return raw;
}

/** Encodes one 32-byte unsigned big-endian integer as a minimal DER
 *  `INTEGER` (stripping leading zero bytes, then re-adding exactly one
 *  sign-padding 0x00 if the minimal form's first byte would otherwise be
 *  interpreted as negative). */
function encodeDerInteger(fieldBytes: Uint8Array): Uint8Array {
  let start = 0;
  while (start < fieldBytes.length - 1 && fieldBytes[start] === 0x00) start++;
  const trimmed = fieldBytes.slice(start);
  const needsPad = trimmed[0] >= 0x80;
  const content = needsPad ? new Uint8Array(trimmed.length + 1) : trimmed;
  if (needsPad) content.set(trimmed, 1); // content[0] stays 0x00
  if (content.length >= 0x80) {
    // Cannot happen for a 32-byte field element (max content is 33 bytes,
    // well under the short-form length limit of 127) — defensive only.
    throw new Error('malformed_raw: integer too large to length-encode in short form');
  }
  const out = new Uint8Array(2 + content.length);
  out[0] = 0x02;
  out[1] = content.length;
  out.set(content, 2);
  return out;
}

/** Raw `R||S`, 64 bytes → DER `SEQUENCE{INTEGER r, INTEGER s}` — the inverse
 *  of `derToRawEcdsaP256`. Used for the round-trip test proof and for any
 *  verify primitive that requires DER input (Node's `crypto.verify` accepts
 *  raw via `dsaEncoding: 'ieee-p1363'`, so this module PREFERS raw
 *  end-to-end and only builds DER where a caller explicitly needs it). */
export function rawToDerEcdsaP256(raw: Uint8Array): Uint8Array {
  if (raw.length !== 64) throw new Error('malformed_raw: expected exactly 64 bytes (32-byte r || 32-byte s)');
  const rDer = encodeDerInteger(raw.slice(0, 32));
  const sDer = encodeDerInteger(raw.slice(32, 64));
  const contentLength = rDer.length + sDer.length;
  if (contentLength >= 0x80) {
    throw new Error('malformed_raw: sequence content too large to length-encode in short form');
  }
  const out = new Uint8Array(2 + contentLength);
  out[0] = 0x30;
  out[1] = contentLength;
  out.set(rDer, 2);
  out.set(sDer, 2 + rDer.length);
  return out;
}

// ─────────────────────────────────────────────────────────────────────────
// Structural decode — no verification, just "is this shaped like a token".
// ─────────────────────────────────────────────────────────────────────────

/** The DECODED header, before algorithm validation — `alg` is `unknown`
 *  because a malicious/malformed token can put anything there (`"none"`,
 *  `"RS256"`, a number, missing entirely). `verifyToken` is what turns this
 *  into an authoritative `SigningAlgorithm` (or refuses). Structurally
 *  distinct from `ProtectedHeader`, which is what a HONEST BUILDER produces
 *  (`buildHeader`), where `alg` is always a real `SigningAlgorithm`. */
export interface DecodedHeader {
  alg: unknown;
  kid: string;
  typ: string;
}

export interface DecodedToken {
  headerB64: string;
  payloadB64: string;
  sigB64: string;
  header: DecodedHeader;
  payload: CredentialPayload;
  /** ASCII bytes of `headerB64 + "." + payloadB64`, recomputed from the
   *  token's OWN header/payload segments — this is what a tampered header or
   *  payload changes, which is exactly what makes tampering detectable. */
  signedBytes: Uint8Array;
  signatureBytes: Uint8Array;
}

/** Structural only — `alg` may be ANY JSON value, or ABSENT ENTIRELY
 *  (`v.alg` reads as `undefined` either way); it is treated as `unknown` on
 *  purpose so `verifyToken` can distinguish "missing alg" and "alg: 'none'"
 *  from a valid `SigningAlgorithm` and refuse BOTH the same way
 *  (`unsupported_alg`), rather than a missing `alg` key making the whole
 *  header structurally invalid (`malformed_token`) while a present-but-wrong
 *  one is `unsupported_alg` — that split would leak which malformation an
 *  attacker sent. `kid`/`typ` are still required strings — those drive
 *  actual lookups/decoding and a missing one IS genuinely malformed. */
function isDecodedHeader(value: unknown): value is DecodedHeader {
  if (!value || typeof value !== 'object') return false;
  const v = value as Record<string, unknown>;
  return typeof v.kid === 'string' && typeof v.typ === 'string';
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

/** Hard cap on the ACCEPTED token length, checked before any parsing work
 *  (base64 decode, JSON.parse) runs. A real ticket credential — three short
 *  base64url segments, `{alg,kid,typ}` header + `{atom,exp,iat,sess,ver}`
 *  payload + a 64-96 byte signature — is a few hundred bytes; 8192 leaves
 *  generous headroom while bounding the parsing work ANY caller of
 *  `decodeTokenStructure`/`verifyToken` does on attacker-controlled input,
 *  in the one function every caller goes through, rather than leaving the
 *  DoS bound as an unstated caller obligation. */
export const MAX_TOKEN_LENGTH = 8192;

export function decodeTokenStructure(token: string): DecodedToken | null {
  if (typeof token !== 'string' || token.length === 0) return null;
  if (token.length > MAX_TOKEN_LENGTH) return null;
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
  if (!isDecodedHeader(header) || !isCredentialPayload(payload)) return null;

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

/**
 * A TRUSTED key, resolved by `kid` against the keyring (M1, the
 * `kernel.signing_key` projection) — NEVER a key (or its algorithm) carried
 * inside the token itself. `algorithm` is the ONLY value `verifyToken` trusts
 * to pick the verify primitive (PFA-PT-8, migration 103): the token header's
 * `alg` is checked AGAINST it, never used to select it.
 *
 * `not_before`/`not_after`/`status` are accepted for forward compatibility
 * with an M1 resolver that projects the full `kernel.signing_key` row, but
 * `verifyToken` does not read them (key-window/revocation admissibility is a
 * door/M1 concern, not this pure authenticity check — same split as
 * `credential_version`/`session_id` below).
 */
export interface TrustedKey {
  public_key: string;
  algorithm: SigningAlgorithm;
  not_before?: string | number | Date;
  not_after?: string | number | Date | null;
  status?: string;
}

/** Resolves `kid` → `TrustedKey` (or `null`/`undefined` for an unknown/
 *  untrusted `kid`) against the TRUSTED keyring. The shape of
 *  `TrustedKey.public_key` is whatever `verifyPrimitive` expects (base64
 *  SPKI DER in the vitest suite; the edge/door's own convention in
 *  production — this module does not care). */
export type TrustedKeyResolver = (kid: string) => TrustedKey | null | undefined | Promise<TrustedKey | null | undefined>;

export type VerifyPrimitive = (
  publicKey: string,
  message: Uint8Array,
  signature: Uint8Array,
  alg: SigningAlgorithm,
) => boolean | Promise<boolean>;

export type VerifyReason =
  | 'ok'
  | 'malformed_token'
  | 'wrong_typ'
  | 'unknown_kid'
  | 'unsupported_alg'
  | 'alg_mismatch'
  | 'signature_invalid'
  | 'expired';

export interface VerifyResult {
  authentic: boolean;
  reason: VerifyReason;
}

/**
 * Pure verification: structure → header-alg shape check → key resolution by
 * `kid` → ALGORITHM PIN (PFA-PT-8) → signature → expiry. Does NOT check
 * `credential_version` currency (that is M2/live, §5.4.3 conjunct 3b.iii — a
 * door/live-read concern, not this module's) and does NOT check `session_id`
 * binding (§5.4.3 check 3 — also a door concern). This function proves
 * AUTHENTICITY, not ADMISSIBILITY — exactly the split the frozen spec draws
 * (§5.4.3: "Signature authenticity ≠ current admissibility").
 *
 * PFA-PT-8 — the header's `alg` is INFORMATIONAL ONLY. Verification
 * AUTHORITY is `trustedKey.algorithm`, resolved from the TRUSTED keyring by
 * `kid`. `token.header.alg` must equal it EXACTLY or verification refuses
 * with `alg_mismatch` — no fallback, no "try EdDSA then ES256", no
 * key-type-confusion path where a wrong-algorithm primitive is ever invoked.
 *
 * DOMAIN SEPARATION, ENFORCED (not just claimed): `header.typ` must equal
 * `DOMAIN` exactly, checked FIRST — before the alg-shape check, before any
 * key resolution — or refuse `wrong_typ`. The file-header comment's domain-
 * separation argument ("changing typ changes the signed bytes, so a forged
 * typ breaks the signature") only defends against FORGERY. It does nothing
 * against REPLAY of a genuinely-signed DIFFERENT-typ credential (e.g. a
 * wallet/door manifest) whose payload happens to shape-match
 * `{atom,exp,iat,sess,ver}` — that token's signature is real and would
 * otherwise verify here. This explicit equality check is what actually
 * closes that gap; the signed-bytes argument alone does not.
 */
export async function verifyToken(
  token: string,
  resolveTrustedKey: TrustedKeyResolver,
  nowSeconds: number,
  verifyPrimitive: VerifyPrimitive,
): Promise<VerifyResult> {
  const decoded = decodeTokenStructure(token);
  if (!decoded) return { authentic: false, reason: 'malformed_token' };

  // ENFORCED domain separation (see doc above) — a genuinely-signed token
  // for a DIFFERENT typ (wallet manifest, door manifest, …) is refused here,
  // before anything else, even if its payload shape-matches a ticket
  // credential and its signature is perfectly valid.
  if (decoded.header.typ !== DOMAIN) {
    return { authentic: false, reason: 'wrong_typ' };
  }

  // `alg: 'none'`, an unrecognized alg, or a missing alg are ALL rejected
  // here, uniformly, as `unsupported_alg` — before any key resolution, so a
  // garbage `alg` never triggers a `kid` lookup.
  const headerAlg = decoded.header.alg;
  if (!isSigningAlgorithm(headerAlg)) {
    return { authentic: false, reason: 'unsupported_alg' };
  }

  const trustedKey = await resolveTrustedKey(decoded.header.kid);
  if (!trustedKey) return { authentic: false, reason: 'unknown_kid' };

  // THE PIN: the trusted key's own algorithm is authority. The header's alg
  // (already known to be a real SigningAlgorithm, above) must match it
  // exactly, or refuse — no fallback between algorithms, ever.
  if (!isSigningAlgorithm(trustedKey.algorithm) || headerAlg !== trustedKey.algorithm) {
    return { authentic: false, reason: 'alg_mismatch' };
  }

  const signatureOk = await verifyPrimitive(
    trustedKey.public_key,
    decoded.signedBytes,
    decoded.signatureBytes,
    trustedKey.algorithm,
  );
  if (!signatureOk) return { authentic: false, reason: 'signature_invalid' };

  if (decoded.payload.exp <= nowSeconds) return { authentic: false, reason: 'expired' };

  return { authentic: true, reason: 'ok' };
}

/**
 * SIGN-AFTER-VERIFY (index.ts §9) — the one function the KMS-signing path
 * calls to prove its own output before ever returning a credential. Verifies
 * `signatureBytes` against `publicKey`/`algorithm` over the EXACT
 * `canonical.signedBytes` — the SAME bytes handed to `KmsSigner.sign`, not a
 * re-decoded token (a decode/re-encode round trip could theoretically mask a
 * framing bug; this checks the literal bytes that were signed). A `false`
 * result means: wrong KMS handle, wrong key version, wrong algorithm, or
 * DER/raw encoding drift — index.ts treats it as `signing_unhealthy` and
 * returns NO credential (fail closed, never retried).
 */
export async function verifyCanonicalSignature(
  canonical: CanonicalCredential,
  signatureBytes: Uint8Array,
  publicKey: string,
  algorithm: SigningAlgorithm,
  verifyPrimitive: VerifyPrimitive,
): Promise<boolean> {
  return verifyPrimitive(publicKey, canonical.signedBytes, signatureBytes, algorithm);
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
