/**
 * supabase/functions/door-session/pure.ts
 * ═══════════════════════════════════════════════════════════════════════════
 * The PURE, IMPORT-FREE decision logic behind `door-session/index.ts` —
 * same pattern as `credential-sign/credential.ts` and
 * `credential-sign/kms-taxonomy.ts`: zero imports, no network, no
 * `crypto.subtle`, no Deno/Node-specific global, so it type-checks cleanly
 * under `npm run typecheck` AND can be imported directly by
 * `tests/door-session.test.ts`.
 *
 * ── WHY THIS FILE EXISTS (a deliberate, minimal addition to the brief's
 *    4-file list — flagged in KEDGES.md) ──────────────────────────────────
 * `index.ts` is Deno-only: a remote `serve` import and a `createClient` from
 * esm.sh, neither of which `tsc -p .` can resolve. The root `tsconfig.json`
 * excludes `supabase/functions` from its OWN root-file glob, but `tests/**`
 * is NOT excluded — so the moment a test imports ANYTHING from `index.ts`,
 * even indirectly, `tsc -p .` is forced to type-check the whole file and
 * fails on the unresolvable remote specifiers. `credential-sign` solved this
 * by splitting every unit-testable DECISION into `credential.ts` /
 * `kms-taxonomy.ts`, pure modules imported by both `index.ts` (Deno) and the
 * test (Node/vitest) — never the reverse. This file is that split for
 * `door-session`. It has no Deno-specific and no WebCrypto-specific code:
 * SHA-1 (RFC4122 UUIDv5, for the rate-limit principals) is hand-rolled in
 * plain JS below specifically so this module never needs `crypto.subtle` —
 * which is the other half of the trap `kms.ts`'s header documents
 * (`Uint8Array<ArrayBufferLike>` vs `BufferSource` strictness under a recent
 * `lib.dom.d.ts`). A generic SHA-256 helper (`sha256Hex`) is provided for
 * completeness/tests; it is NOT the token_hash algorithm (see below).
 *
 * ── WHAT THIS FILE DOES NOT DO ────────────────────────────────────────────
 * This module NEVER computes the door-session `token_hash`. Per the frozen
 * contract (EDGE spec §3.9a "Verification"; RPC §1.1d), the bearer header is
 * parsed here into `{door_session_id, secret}` and BOTH raw pieces are
 * forwarded to `kernel.assert_door_session`, which computes `token_hash` and
 * compares it constant-time, server-side, against the stored row — "so no
 * second implementation can drift from it and no plaintext leaves the DB
 * boundary." The AUTHORITATIVE token_hash contract is DB-owned and is
 * `md5('door_session:' || secret)` — written by `venue.mint_door_session`
 * (107) and recomputed by `kernel.assert_door_session` (086), which match
 * each other exactly. The edge deliberately carries NO token_hash
 * implementation, so none can drift from the DB.
 * ═══════════════════════════════════════════════════════════════════════════
 */

// ── Bearer parsing — `Authorization: DoorSession <door_session_id>.<secret>`
// (edge §3.9a). Malformed input returns null; NEVER throws. ────────────────

export interface ParsedDoorSessionBearer {
  doorSessionId: string;
  secret: string;
}

const BEARER_PREFIX = 'DoorSession ';

/**
 * Parses the door-session bearer header. Splits on the LAST '.' per the
 * frozen contract ("Split the header on the last '.'") — `door_session_id`
 * is a uuid (no dots) and `secret` is base64url (no dots either), but
 * splitting on the last dot is the spec's own robustness rule and is what
 * this function does, rather than assuming either half is dot-free.
 */
export function parseDoorSessionBearer(header: string | null | undefined): ParsedDoorSessionBearer | null {
  if (typeof header !== 'string') return null;
  if (!header.startsWith(BEARER_PREFIX)) return null;
  const rest = header.slice(BEARER_PREFIX.length);
  if (!rest) return null;

  const lastDot = rest.lastIndexOf('.');
  if (lastDot <= 0 || lastDot === rest.length - 1) return null; // no dot, dot leads, or dot trails

  const doorSessionId = rest.slice(0, lastDot);
  const secret = rest.slice(lastDot + 1);
  if (!doorSessionId || !secret) return null;
  if (/\s/.test(doorSessionId) || /\s/.test(secret)) return null; // no whitespace in either half
  if (doorSessionId.includes(' ') || secret.includes(' ')) return null;

  return { doorSessionId, secret };
}

// ── Path dispatch — one function, five paths (edge §3.9a). Tolerant of an
// optional function-name prefix (`/door-session/scan`) and a trailing
// slash, since the exact `req.url` pathname shape Supabase's edge runtime
// hands the handler is not something this module should assume. ──────────

export type DoorSessionRoute = 'mint' | 'refresh' | 'manifest_sync' | 'scan' | 'offline_batch';

export function dispatchDoorSessionRoute(pathname: string): DoorSessionRoute | null {
  const trimmed = pathname.replace(/\/+$/, '');
  if (trimmed.endsWith('/manifest/sync')) return 'manifest_sync';
  if (trimmed.endsWith('/offline-batch')) return 'offline_batch';
  if (trimmed.endsWith('/mint')) return 'mint';
  if (trimmed.endsWith('/refresh')) return 'refresh';
  if (trimmed.endsWith('/scan')) return 'scan';
  return null;
}

// ── Device-id cross-check (RPC §1.1d / §9.4 EDGE-4c) — `assert_door_session`
// returns the BOUND device id; the request's `device_id` is a cross-check
// only, never a source of truth. A mismatch is a hard refusal + Sentry event
// — this predicate is the pure half of that rule. ──────────────────────────

export function deviceIdsMatch(boundDeviceId: string, requestDeviceId: string): boolean {
  return boundDeviceId === requestDeviceId;
}

// ── "p_scan_meta.device_id is REJECTED, not deprecated" (RPC §9.4/§9.5,
// matrix X-5). Applies to `/scan`'s `scan_meta` and to every row of
// `/offline-batch`'s `batch` — both are scan-telemetry shapes under the same
// discipline. A plain `hasOwnProperty` check — presence is the violation,
// not the value (so `device_id: null` / `device_id: undefined` still count:
// a stale client sending the key at all must fail loudly). ────────────────

export function hasForbiddenDeviceIdField(meta: unknown): boolean {
  if (!meta || typeof meta !== 'object' || Array.isArray(meta)) return false;
  return Object.prototype.hasOwnProperty.call(meta, 'device_id');
}

export function batchContainsForbiddenDeviceId(batch: unknown): boolean {
  if (!Array.isArray(batch)) return false;
  return batch.some((row) => hasForbiddenDeviceIdField(row));
}

// ── Rate-limit derived principals (edge §3.9a "Rate limit"; RPC §1.1d
// `AUTHZ-H3a`(a)): `/mint` + `/refresh` share ONE principal —
// `uuidv5(NS_DOOR_PIN, venue_id || ':' || device_id_claim)` — because a
// re-mint is the same underlying operation the PIN-grinding budget must
// bound; every relay route uses `uuidv5(NS_DOOR_SESSION, door_session_id)`,
// a SEPARATE budget so relay traffic can never exhaust the PIN budget or
// vice versa. The frozen contract names the scheme (`uuidv5`) but not the
// two namespace UUID values — they are not specified anywhere in the
// PHASE_2_* spec set. The two constants below are this implementation's
// choice (flagged as a spec ambiguity in KEDGES.md); what matters for
// correctness is that they are FIXED and DISTINCT across mint and relay so
// the two budgets can never collide. ────────────────────────────────────

export const NS_DOOR_PIN = 'a3f1c2d4-5b6e-4f7a-8c9d-0e1f2a3b4c5d';
export const NS_DOOR_SESSION = 'b4e2d3c5-6a7f-4e8b-9d0c-1f2a3b4c5d6e';

export function doorPinRateLimitName(venueId: string, deviceIdClaim: string): string {
  return `${venueId}:${deviceIdClaim}`;
}

export function doorSessionRateLimitName(doorSessionId: string): string {
  return doorSessionId;
}

export function deriveDoorPinRateLimitPrincipal(venueId: string, deviceIdClaim: string): string {
  return uuidv5(NS_DOOR_PIN, doorPinRateLimitName(venueId, deviceIdClaim));
}

export function deriveDoorSessionRateLimitPrincipal(doorSessionId: string): string {
  return uuidv5(NS_DOOR_SESSION, doorSessionRateLimitName(doorSessionId));
}

// ── mint_door_session's PFA-26 park — "raises `precondition_failed:
// door_pin_kdf_unavailable … (PFA-26)` with ZERO mutation." The edge must
// surface this as a clean 503/`pin_unavailable`, never crash and never
// conflate it with a real precondition failure (wrong PIN, wrong device,
// wrong venue — all of which share ONE opaque error class per §9.6, and are
// NOT this code path). Pure string match on the RPC's error message. ─────

export function isDoorPinKdfUnavailable(errorMessage: string | null | undefined): boolean {
  if (!errorMessage) return false;
  return errorMessage.includes('door_pin_kdf_unavailable');
}

// ── `kernel.assert_door_session` — RPC §1.1d: "One class, deliberately:
// `insufficient_privilege(42501)` … `not_found` is never returned." Pure
// classifier so index.ts never has to special-case a Postgres error code by
// hand at more than one call site. ─────────────────────────────────────────

export function isAssertDoorSessionAuthFailure(errorCode: string | null | undefined, errorMessage: string | null | undefined): boolean {
  if (errorCode === '42501') return true;
  if (errorMessage && errorMessage.includes('insufficient_privilege')) return true;
  return false;
}

// ─────────────────────────────────────────────────────────────────────────
// UTF-8 encoding — hand-rolled (no `TextEncoder` dependency) so this module
// makes no assumption about which globals a given tsc `lib` setting exposes.
// ─────────────────────────────────────────────────────────────────────────

function utf8Bytes(str: string): number[] {
  const bytes: number[] = [];
  for (let i = 0; i < str.length; i++) {
    let codePoint = str.codePointAt(i)!;
    if (codePoint > 0xffff) i++; // consumed a surrogate pair
    if (codePoint < 0x80) {
      bytes.push(codePoint);
    } else if (codePoint < 0x800) {
      bytes.push(0xc0 | (codePoint >> 6), 0x80 | (codePoint & 0x3f));
    } else if (codePoint < 0x10000) {
      bytes.push(0xe0 | (codePoint >> 12), 0x80 | ((codePoint >> 6) & 0x3f), 0x80 | (codePoint & 0x3f));
    } else {
      bytes.push(
        0xf0 | (codePoint >> 18),
        0x80 | ((codePoint >> 12) & 0x3f),
        0x80 | ((codePoint >> 6) & 0x3f),
        0x80 | (codePoint & 0x3f),
      );
    }
  }
  return bytes;
}

function bytesToHex(bytes: number[]): string {
  return bytes.map((b) => (b & 0xff).toString(16).padStart(2, '0')).join('');
}

// ─────────────────────────────────────────────────────────────────────────
// SHA-256 — hand-rolled, standard FIPS 180-4 construction. No `crypto`
// import of any kind (WebCrypto or Node's `node:crypto`) — this file stays
// import-free so it can never trip the `.ts`-extension / `BufferSource`
// traps `kms.ts`'s header documents. Used only by `computeTokenHash` (see
// the file header for why `index.ts` never actually calls it).
// ─────────────────────────────────────────────────────────────────────────

const SHA256_K = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

function rotr32(x: number, n: number): number {
  return ((x >>> n) | (x << (32 - n))) >>> 0;
}

function sha256(messageBytes: number[]): number[] {
  let h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
  let h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

  const bitLen = messageBytes.length * 8;
  const padded = messageBytes.slice();
  padded.push(0x80);
  while (padded.length % 64 !== 56) padded.push(0);
  for (let i = 0; i < 4; i++) padded.push(0); // high 32 bits of length (assumes < 2^32 bits of input)
  for (let i = 3; i >= 0; i--) padded.push((bitLen >>> (i * 8)) & 0xff);

  for (let chunkStart = 0; chunkStart < padded.length; chunkStart += 64) {
    const w = new Array<number>(64).fill(0);
    for (let i = 0; i < 16; i++) {
      const o = chunkStart + i * 4;
      w[i] = ((padded[o] << 24) | (padded[o + 1] << 16) | (padded[o + 2] << 8) | padded[o + 3]) >>> 0;
    }
    for (let i = 16; i < 64; i++) {
      const s0 = rotr32(w[i - 15], 7) ^ rotr32(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = rotr32(w[i - 2], 17) ^ rotr32(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }

    let [a, b, c, d, e, f, g, h] = [h0, h1, h2, h3, h4, h5, h6, h7];
    for (let i = 0; i < 64; i++) {
      const S1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25);
      const ch = (e & f) ^ (~e & g);
      const temp1 = (h + S1 + ch + SHA256_K[i] + w[i]) >>> 0;
      const S0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const temp2 = (S0 + maj) >>> 0;
      h = g; g = f; f = e; e = (d + temp1) >>> 0;
      d = c; c = b; b = a; a = (temp1 + temp2) >>> 0;
    }

    h0 = (h0 + a) >>> 0; h1 = (h1 + b) >>> 0; h2 = (h2 + c) >>> 0; h3 = (h3 + d) >>> 0;
    h4 = (h4 + e) >>> 0; h5 = (h5 + f) >>> 0; h6 = (h6 + g) >>> 0; h7 = (h7 + h) >>> 0;
  }

  const out: number[] = [];
  for (const word of [h0, h1, h2, h3, h4, h5, h6, h7]) {
    out.push((word >>> 24) & 0xff, (word >>> 16) & 0xff, (word >>> 8) & 0xff, word & 0xff);
  }
  return out;
}

/** A GENERIC SHA-256 hex helper. NOTE: this is NOT the door-session token_hash
 *  algorithm — that contract is DB-owned and is `md5('door_session:' || secret)`
 *  (venue.mint_door_session 107 / kernel.assert_door_session 086). The edge
 *  computes no token_hash at all (see the file header); this helper exists only
 *  as a self-contained hash utility with NIST-vector tests. */
export function sha256Hex(input: string): string {
  return bytesToHex(sha256(utf8Bytes(input)));
}

// ─────────────────────────────────────────────────────────────────────────
// SHA-1 + RFC4122 UUIDv5 — hand-rolled for the same import-free reason as
// SHA-256 above. Used for the rate-limit derived principals
// (`deriveDoorPinRateLimitPrincipal` / `deriveDoorSessionRateLimitPrincipal`)
// — `check_rate_limit`'s first parameter is a `uuid` (migration 021), and
// the frozen contract names the derivation scheme as `uuidv5(NS, name)`.
// ─────────────────────────────────────────────────────────────────────────

function rotl32(x: number, n: number): number {
  return ((x << n) | (x >>> (32 - n))) >>> 0;
}

function sha1(messageBytes: number[]): number[] {
  let h0 = 0x67452301, h1 = 0xefcdab89, h2 = 0x98badcfe, h3 = 0x10325476, h4 = 0xc3d2e1f0;

  const bitLen = messageBytes.length * 8;
  const padded = messageBytes.slice();
  padded.push(0x80);
  while (padded.length % 64 !== 56) padded.push(0);
  for (let i = 0; i < 4; i++) padded.push(0); // high 32 bits of length
  for (let i = 3; i >= 0; i--) padded.push((bitLen >>> (i * 8)) & 0xff);

  for (let chunkStart = 0; chunkStart < padded.length; chunkStart += 64) {
    const w = new Array<number>(80).fill(0);
    for (let i = 0; i < 16; i++) {
      const o = chunkStart + i * 4;
      w[i] = ((padded[o] << 24) | (padded[o + 1] << 16) | (padded[o + 2] << 8) | padded[o + 3]) >>> 0;
    }
    for (let i = 16; i < 80; i++) {
      w[i] = rotl32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }

    let [a, b, c, d, e] = [h0, h1, h2, h3, h4];
    for (let i = 0; i < 80; i++) {
      let f: number, k: number;
      if (i < 20) { f = (b & c) | (~b & d); k = 0x5a827999; }
      else if (i < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
      else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
      else { f = b ^ c ^ d; k = 0xca62c1d6; }

      const temp = (rotl32(a, 5) + f + e + k + w[i]) >>> 0;
      e = d; d = c; c = rotl32(b, 30); b = a; a = temp;
    }

    h0 = (h0 + a) >>> 0; h1 = (h1 + b) >>> 0; h2 = (h2 + c) >>> 0; h3 = (h3 + d) >>> 0; h4 = (h4 + e) >>> 0;
  }

  const out: number[] = [];
  for (const word of [h0, h1, h2, h3, h4]) {
    out.push((word >>> 24) & 0xff, (word >>> 16) & 0xff, (word >>> 8) & 0xff, word & 0xff);
  }
  return out;
}

function uuidStringToBytes(uuid: string): number[] {
  const hex = uuid.replace(/-/g, '');
  const bytes: number[] = [];
  for (let i = 0; i < hex.length; i += 2) bytes.push(parseInt(hex.slice(i, i + 2), 16));
  return bytes;
}

function bytesToUuidString(bytes: number[]): string {
  const hex = bytesToHex(bytes);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

/** RFC4122 UUIDv5 (namespace + name, SHA-1-based). Deterministic: the same
 *  `(namespace, name)` pair always produces the same uuid; different inputs
 *  produce different uuids with overwhelming probability. Validated in
 *  `tests/door-session.test.ts` against the RFC4122 Appendix B / Wikipedia
 *  worked example (DNS namespace + `"python.org"`) as an independent
 *  correctness check of this hand-rolled SHA-1, separate from this
 *  system's own `NS_DOOR_PIN`/`NS_DOOR_SESSION` constants. */
export function uuidv5(namespace: string, name: string): string {
  const nsBytes = uuidStringToBytes(namespace);
  const nameBytes = utf8Bytes(name);
  const digest = sha1(nsBytes.concat(nameBytes));
  const bytes = digest.slice(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
  return bytesToUuidString(bytes);
}
