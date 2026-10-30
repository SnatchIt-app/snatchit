/**
 * The trusted keyring for the staff-path scanner: `kernel.signing_key`'s public projection
 * (083:114 + 103:95: key_id, scope, event_id, venue_id, public_key, algorithm, status, not_before,
 * not_after; SELECT to authenticated, policy kernel_signing_key_sel_public). Row adapter and public-key
 * normalizer carried verbatim from supabase/functions/_shared/offline-verify.ts (`m1EntryFromWire`,
 * `m1FromWire`, `normalizeSpkiPublicKey`): ANY malformed row ⇒ no keyring (a partially trusted keyring
 * is worse than none), duplicate key_id ⇒ none, `not_after` NULL ⇒ no upper bound.
 */
export type TrustedKey = {
  key_id: string;
  scope: "global" | "per_event" | "per_venue";
  event_id: string | null;
  venue_id: string | null;
  /** PEM or bare base64 SPKI, verbatim; normalized before any primitive runs. */
  public_key: string;
  algorithm: string;
  /** unix seconds */
  not_before: number;
  /** unix seconds; +Infinity = no upper bound */
  not_after: number;
  status: string;
};
export type Keyring = Record<string, TrustedKey>;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const KNOWN_ALGORITHMS: ReadonlySet<string> = new Set(["EdDSA", "ES256"]);

function unixSecondsFromWire(v: unknown, nullMeans: number | null): number | null {
  if (v === null || v === undefined) return nullMeans;
  if (typeof v === "number" && Number.isFinite(v)) return Math.trunc(v);
  if (typeof v === "string") {
    const ms = Date.parse(v);
    return Number.isFinite(ms) ? Math.floor(ms / 1000) : null;
  }
  return null;
}

export function trustedKeyFromRow(row: unknown): TrustedKey | null {
  if (!row || typeof row !== "object") return null;
  const r = row as Record<string, unknown>;
  if (typeof r.key_id !== "string" || !UUID_RE.test(r.key_id)) return null;
  if (r.scope !== "global" && r.scope !== "per_event" && r.scope !== "per_venue") return null;
  if (typeof r.public_key !== "string" || r.public_key.length === 0) return null;
  if (typeof r.algorithm !== "string") return null;
  if (typeof r.status !== "string") return null;
  const nb = unixSecondsFromWire(r.not_before, null);
  const na = unixSecondsFromWire(r.not_after, Number.POSITIVE_INFINITY);
  if (nb === null || na === null) return null;
  return { key_id: r.key_id, scope: r.scope, event_id: typeof r.event_id === "string" ? r.event_id : null, venue_id: typeof r.venue_id === "string" ? r.venue_id : null, public_key: r.public_key, algorithm: r.algorithm, not_before: nb, not_after: na, status: r.status };
}

export function keyringFromRows(rows: unknown): Keyring | null {
  if (!Array.isArray(rows)) return null;
  const out: Keyring = {};
  for (const row of rows) {
    const e = trustedKeyFromRow(row);
    if (!e || out[e.key_id]) return null;
    out[e.key_id] = e;
  }
  return out;
}

const B64_STD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const B64_STD_REVERSE: Record<string, number> = (() => {
  const map: Record<string, number> = {};
  for (let i = 0; i < B64_STD.length; i++) map[B64_STD[i]] = i;
  return map;
})();
const SPKI_PREFIX_P256_UNCOMPRESSED: readonly number[] = [0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00];
const SPKI_PREFIX_ED25519: readonly number[] = [0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00];
const SPKI_LENGTH: Record<string, number> = { ES256: 91, EdDSA: 44 };
const PEM_PUBLIC_KEY_RE = /^-----BEGIN PUBLIC KEY-----(?:\r?\n)([A-Za-z0-9+/=\r\n]+?)(?:\r?\n)-----END PUBLIC KEY-----$/;
const BARE_BASE64_RE = /^[A-Za-z0-9+/]+={0,2}$/;

export function base64DecodeStrict(b64: string): Uint8Array | null {
  if (b64.length === 0 || b64.length % 4 !== 0 || !BARE_BASE64_RE.test(b64)) return null;
  const pad = b64.endsWith("==") ? 2 : b64.endsWith("=") ? 1 : 0;
  const firstPad = b64.indexOf("=");
  if (firstPad !== -1 && firstPad !== b64.length - pad) return null;
  const out: number[] = [];
  for (let i = 0; i < b64.length; i += 4) {
    const c2 = b64[i + 2];
    const c3 = b64[i + 3];
    const n0 = B64_STD_REVERSE[b64[i]];
    const n1 = B64_STD_REVERSE[b64[i + 1]];
    const n2 = c2 === "=" ? 0 : B64_STD_REVERSE[c2];
    const n3 = c3 === "=" ? 0 : B64_STD_REVERSE[c3];
    if (n0 === undefined || n1 === undefined || n2 === undefined || n3 === undefined) return null;
    out.push(((n0 << 2) | (n1 >> 4)) & 0xff);
    if (c2 !== "=") out.push(((n1 << 4) | (n2 >> 2)) & 0xff);
    if (c3 !== "=") out.push(((n2 << 6) | n3) & 0xff);
  }
  if (pad === 1 && (B64_STD_REVERSE[b64[b64.length - 2]] & 0x03) !== 0) return null;
  if (pad === 2 && (B64_STD_REVERSE[b64[b64.length - 3]] & 0x0f) !== 0) return null;
  return new Uint8Array(out);
}

function base64EncodeStd(bytes: Uint8Array): string {
  let out = "";
  let i = 0;
  for (; i + 3 <= bytes.length; i += 3) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += B64_STD[(n >> 18) & 63] + B64_STD[(n >> 12) & 63] + B64_STD[(n >> 6) & 63] + B64_STD[n & 63];
  }
  const remaining = bytes.length - i;
  if (remaining === 1) {
    const n = bytes[i] << 16;
    out += B64_STD[(n >> 18) & 63] + B64_STD[(n >> 12) & 63] + "==";
  } else if (remaining === 2) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out += B64_STD[(n >> 18) & 63] + B64_STD[(n >> 12) & 63] + B64_STD[(n >> 6) & 63] + "=";
  }
  return out;
}

/** PEM or bare SPKI base64 → canonical bare SPKI DER (standard base64) of the pinned algorithm's exact shape, or null. */
export function normalizeSpkiPublicKey(input: unknown, algorithm: string): string | null {
  if (typeof input !== "string") return null;
  const text = input.replace(/^[\t\r\n ]+|[\t\r\n ]+$/g, "");
  if (text.length === 0 || text.length > 4096) return null;
  if (text.indexOf("PRIVATE KEY") !== -1) return null;
  let b64: string;
  if (text.startsWith("-----")) {
    const m = PEM_PUBLIC_KEY_RE.exec(text);
    if (!m) return null;
    b64 = m[1].replace(/\r?\n/g, "");
  } else {
    b64 = text;
  }
  const bytes = base64DecodeStrict(b64);
  if (!bytes || bytes.length < 4) return null;
  if (bytes[0] !== 0x30) return null;
  let len: number;
  let hdr: number;
  if (bytes[1] < 0x80) {
    len = bytes[1];
    hdr = 2;
  } else if (bytes[1] === 0x81) {
    len = bytes[2];
    hdr = 3;
  } else if (bytes[1] === 0x82) {
    len = (bytes[2] << 8) | bytes[3];
    hdr = 4;
  } else return null;
  if (hdr + len !== bytes.length) return null;
  if (!KNOWN_ALGORITHMS.has(algorithm)) return null;
  if (bytes.length !== SPKI_LENGTH[algorithm]) return null;
  const prefix = algorithm === "ES256" ? SPKI_PREFIX_P256_UNCOMPRESSED : SPKI_PREFIX_ED25519;
  for (let i = 0; i < prefix.length; i++) if (bytes[i] !== prefix[i]) return null;
  if (algorithm === "ES256" && bytes[prefix.length] !== 0x04) return null;
  return base64EncodeStd(bytes);
}
