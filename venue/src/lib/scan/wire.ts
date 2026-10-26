/**
 * ONE parse of the compact credential the buyer app shows as a QR:
 * `header.payload.signature`, typ `SNATCHIT-TICKET-CRED-V1`
 * (supabase/functions/credential-sign/credential.ts). This is the reference
 * decoder `decodeOfflineToken` from supabase/functions/_shared/offline-verify.ts
 * (SCANNER-CONTRACT-v1 step 0-wire), carried into venue/ because the app's
 * build root is venue/ and cannot import across it. tests/scan-wire.test.ts
 * proves the two decoders agree on every golden token in
 * tests/fixtures/scanner-contract-v1.json and on mutated ones, so this copy
 * cannot drift silently.
 *
 * Decoding is NOT verification. Nothing here checks a signature, a key or a
 * manifest; the decoded atom id is only the argument the server's admission
 * verb takes, and that verb is the authority (CONTRACTS.md C7). Whether the
 * signature is verified inside the wrapper path or by a verifier call first
 * is B's open answer; until then this is the "stubbed verify" A asked for,
 * and it never produces an admit on its own.
 */
export const CREDENTIAL_TYP = "SNATCHIT-TICKET-CRED-V1";
export const MAX_WIRE_TOKEN_LENGTH = 8192;
const KNOWN_ALGORITHMS: ReadonlySet<string> = new Set(["EdDSA", "ES256"]);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const B64URL_RE = /^[A-Za-z0-9_-]+$/;
const B64URL_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
const B64URL_REVERSE: Record<string, number> = (() => {
  const map: Record<string, number> = {};
  for (let i = 0; i < B64URL_ALPHABET.length; i++) map[B64URL_ALPHABET[i]] = i;
  return map;
})();

/** Strict unpadded base64url (RFC 4648 §5): no `=`, no whitespace, canonical trailing bits, length % 4 ≠ 1. */
function base64urlDecodeStrict(s: string): Uint8Array | null {
  if (s.length === 0 || s.length % 4 === 1 || !B64URL_RE.test(s)) return null;
  const out: number[] = [];
  let i = 0;
  for (; i + 4 <= s.length; i += 4) {
    const n = (B64URL_REVERSE[s[i]] << 18) | (B64URL_REVERSE[s[i + 1]] << 12) | (B64URL_REVERSE[s[i + 2]] << 6) | B64URL_REVERSE[s[i + 3]];
    out.push((n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff);
  }
  const rem = s.length - i;
  if (rem === 2) {
    const a = B64URL_REVERSE[s[i]],
      b = B64URL_REVERSE[s[i + 1]];
    if ((b & 0x0f) !== 0) return null;
    out.push(((a << 2) | (b >> 4)) & 0xff);
  } else if (rem === 3) {
    const a = B64URL_REVERSE[s[i]],
      b = B64URL_REVERSE[s[i + 1]],
      c = B64URL_REVERSE[s[i + 2]];
    if ((c & 0x03) !== 0) return null;
    out.push(((a << 2) | (b >> 4)) & 0xff, ((b << 4) | (c >> 2)) & 0xff);
  }
  return new Uint8Array(out);
}

function isPlainObjectWithExactKeys(v: unknown, keys: readonly string[]): v is Record<string, unknown> {
  if (!v || typeof v !== "object" || Array.isArray(v)) return false;
  const own = Object.keys(v as object).sort();
  const want = [...keys].sort();
  if (own.length !== want.length) return false;
  for (let i = 0; i < own.length; i++) if (own[i] !== want[i]) return false;
  return true;
}

function isNonNegativeInt(v: unknown): v is number {
  return typeof v === "number" && Number.isInteger(v) && v >= 0;
}

/** The claims a strictly decoded token carries. `typ` and `algorithm` are informational here (the verifier pins them). */
export type CredentialClaims = {
  keyId: string;
  typ: string;
  algorithm: string;
  atomId: string;
  sessionId: string;
  credentialVersion: number;
  /** unix seconds */
  exp: number;
  /** unix seconds */
  iat: number;
};

/**
 * Returns the fully derived claims, or `null` for ANY deviation — the caller
 * treats `null` as a malformed pass and never falls back to a looser parse.
 *   header  = exactly { alg: string, kid: uuid, typ: string }
 *   payload = exactly { atom: uuid, exp: int, iat: int, sess: uuid, ver: int }, iat ≤ exp
 *   sig     = 64 bytes when alg is a known algorithm
 */
export function decodeCredentialWire(wire: unknown): CredentialClaims | null {
  if (typeof wire !== "string" || wire.length === 0 || wire.length > MAX_WIRE_TOKEN_LENGTH) return null;
  const parts = wire.split(".");
  if (parts.length !== 3) return null;
  const [h, p, s] = parts;
  const hb = base64urlDecodeStrict(h);
  const pb = base64urlDecodeStrict(p);
  const sig = base64urlDecodeStrict(s);
  if (!hb || !pb || !sig) return null;
  let header: unknown;
  let payload: unknown;
  try {
    header = JSON.parse(new TextDecoder().decode(hb));
    payload = JSON.parse(new TextDecoder().decode(pb));
  } catch {
    return null;
  }
  if (!isPlainObjectWithExactKeys(header, ["alg", "kid", "typ"])) return null;
  if (!isPlainObjectWithExactKeys(payload, ["atom", "exp", "iat", "sess", "ver"])) return null;
  const alg = header.alg,
    kid = header.kid,
    typ = header.typ;
  const atom = payload.atom,
    exp = payload.exp,
    iat = payload.iat,
    sess = payload.sess,
    ver = payload.ver;
  if (typeof alg !== "string" || typeof kid !== "string" || typeof typ !== "string") return null;
  if (!UUID_RE.test(kid)) return null;
  if (typeof atom !== "string" || !UUID_RE.test(atom)) return null;
  if (typeof sess !== "string" || !UUID_RE.test(sess)) return null;
  if (!isNonNegativeInt(exp) || !isNonNegativeInt(iat) || !isNonNegativeInt(ver)) return null;
  if (iat > exp) return null;
  if (KNOWN_ALGORITHMS.has(alg) && sig.length !== 64) return null;
  return { keyId: kid, typ, algorithm: alg, atomId: atom, sessionId: sess, credentialVersion: ver, exp, iat };
}
