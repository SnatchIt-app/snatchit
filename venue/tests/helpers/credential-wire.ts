/** Test-only: assemble a SNATCHIT-TICKET-CRED-V1 compact token with an arbitrary (unverified) 64-byte signature. */
const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
export function b64url(bytes: Uint8Array): string {
  let out = "";
  let i = 0;
  for (; i + 3 <= bytes.length; i += 3) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63] + B64[(n >> 6) & 63] + B64[n & 63];
  }
  const rem = bytes.length - i;
  if (rem === 1) {
    const n = bytes[i] << 16;
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63];
  } else if (rem === 2) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63] + B64[(n >> 6) & 63];
  }
  return out.replace(/\+/g, "-").replace(/\//g, "_");
}
export const seg = (v: unknown) => b64url(new TextEncoder().encode(JSON.stringify(v)));
export const KID = "00000000-0000-4000-8000-0000000000b0";
export const SESS = "5e55e55e-0000-4000-8000-000000000001";
export const ATOM = "a70a70a7-0000-4000-8000-000000000001";
export const SIG64 = b64url(new Uint8Array(64).fill(7));
export function makeWire(o: { atom?: string; sess?: string; exp?: number; iat?: number; ver?: number; typ?: string; alg?: string; kid?: string; sig?: string; header?: unknown; payload?: unknown } = {}): string {
  const header = o.header ?? { alg: o.alg ?? "ES256", kid: o.kid ?? KID, typ: o.typ ?? "SNATCHIT-TICKET-CRED-V1" };
  const payload = o.payload ?? { atom: o.atom ?? ATOM, exp: o.exp ?? 1_800_000_000, iat: o.iat ?? 1_799_990_000, sess: o.sess ?? SESS, ver: o.ver ?? 1 };
  return `${seg(header)}.${seg(payload)}.${o.sig ?? SIG64}`;
}
