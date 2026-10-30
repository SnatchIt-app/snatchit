import { base64DecodeStrict, normalizeSpkiPublicKey, type Keyring, type TrustedKey } from "@/lib/scan/keys";
import { CREDENTIAL_TYP, decodeCredentialWire, type CredentialClaims } from "@/lib/scan/wire";

/**
 * B's TICKET-CREDENTIAL-CONTRACT-v1 §3, the scanner-side verification order, evaluated exactly as the
 * reference `offlineVerify` (supabase/functions/_shared/offline-verify.ts) evaluates its first conjuncts:
 * decode → typ → algorithm whitelist → kid in the trusted keyring → key status / window → algorithm pin
 * → public-key normalization → signature over the exact signed bytes → session binding → expiry with the
 * reference tolerance (2 × 30 s). Everything after that (atom state, version, resale, first-in-wins) is
 * the server's (§4), reached only with a token that passed here. tests/scan-verify.test.ts runs every
 * golden vector of SCANNER-CONTRACT-v1 through this with the fixture's real keys and WebCrypto.
 *
 * This is usability and honest-staff defence (B §3), not the security boundary; it can only refuse.
 */
export const DEFAULT_TIME_BUCKET_SECONDS = 30;
const KNOWN_ALGORITHMS: ReadonlySet<string> = new Set(["EdDSA", "ES256"]);

export type VerifyReason = "malformed_token" | "wrong_typ" | "unsupported_alg" | "unknown_key" | "key_scope" | "key_revoked" | "key_window" | "alg_mismatch" | "malformed_public_key" | "signature_invalid" | "wrong_session" | "expired";
export type VerifyResult = { ok: true; claims: CredentialClaims } | { ok: false; reason: VerifyReason; claims: CredentialClaims | null };

/** `Verify(publicKey, message, signature, algorithm)`: canonical SPKI DER (standard base64) → boolean. Async for WebCrypto. */
export type VerifyPrimitive = (publicKeyDerB64: string, message: Uint8Array, signature: Uint8Array, algorithm: string) => Promise<boolean>;

export type VerifyContext = { keyring: Keyring; boundSessionId: string; scanVenueId: string; scanEventId: string; nowSeconds: number; verify: VerifyPrimitive; timeBucketSeconds?: number };

/**
 * E-F10 — key scope. RLS on `kernel.signing_key` is deliberately row-universal (083:117-123, PFA-16), so
 * the keyring a door reads carries EVERY venue's keys, not just its own. Nothing downstream re-checks
 * scope either: `record_scan` is told an atom and a session, not which key vouched for them. So without
 * this, a `per_venue` key issued to venue A verifies a pass presented at venue B, and a `per_event` key
 * verifies a pass for another event — the key is genuinely trusted, just not for THIS door.
 *
 * A key is accepted only when its scope names this door: `global` always; `per_venue` when its venue is
 * the route's venue; `per_event` when its event is the one the bound session belongs to. Anything else,
 * including a scoped key whose id is NULL or an unrecognised scope, is refused. Fail closed.
 *
 * Preventive today — production holds one `global` key — which is the only moment it is cheap to add.
 */
export function keyInScope(key: TrustedKey, scanVenueId: string, scanEventId: string): boolean {
  const matches = (keyId: string | null, routeId: string): boolean =>
    typeof keyId === "string" && keyId.length > 0 && routeId.length > 0 && keyId.toLowerCase() === routeId.toLowerCase();
  if (key.scope === "global") return true;
  if (key.scope === "per_venue") return matches(key.venue_id, scanVenueId);
  if (key.scope === "per_event") return matches(key.event_id, scanEventId);
  return false;
}

export async function verifyCredential(wire: unknown, ctx: VerifyContext): Promise<VerifyResult> {
  const token = decodeCredentialWire(wire);
  if (!token) return { ok: false, reason: "malformed_token", claims: null };
  const refuse = (reason: VerifyReason): VerifyResult => ({ ok: false, reason, claims: token });
  const toleranceSeconds = 2 * (ctx.timeBucketSeconds ?? DEFAULT_TIME_BUCKET_SECONDS);
  if (token.typ !== CREDENTIAL_TYP) return refuse("wrong_typ");
  if (!KNOWN_ALGORITHMS.has(token.algorithm)) return refuse("unsupported_alg");
  const key = ctx.keyring[token.keyId];
  if (!key) return refuse("unknown_key");
  // E-F10: trusted by the keyring is not the same as trusted for THIS door.
  if (!keyInScope(key, ctx.scanVenueId, ctx.scanEventId)) return refuse("key_scope");
  if (key.status === "revoked") return refuse("key_revoked");
  if (ctx.nowSeconds < key.not_before || ctx.nowSeconds > key.not_after) return refuse("key_window");
  if (!KNOWN_ALGORITHMS.has(key.algorithm) || token.algorithm !== key.algorithm) return refuse("alg_mismatch");
  const canonical = normalizeSpkiPublicKey(key.public_key, key.algorithm);
  if (canonical === null) return refuse("malformed_public_key");
  let signatureOk = false;
  try {
    signatureOk = await ctx.verify(canonical, token.claims, token.sig, key.algorithm);
  } catch {
    signatureOk = false;
  }
  if (!signatureOk) return refuse("signature_invalid");
  if (token.sessionId !== ctx.boundSessionId.toLowerCase()) return refuse("wrong_session");
  if (ctx.nowSeconds > token.exp + toleranceSeconds) return refuse("expired");
  return { ok: true, claims: token };
}

/** The WebCrypto primitive: ES256 = ECDSA P-256 / SHA-256 over raw R||S; EdDSA = Ed25519. Any failure is `false`. */
export const webcryptoVerify: VerifyPrimitive = async (publicKeyDerB64, message, signature, algorithm) => {
  const der = base64DecodeStrict(publicKeyDerB64);
  if (!der || signature.length !== 64) return false;
  const subtle = globalThis.crypto?.subtle;
  if (!subtle) return false;
  const keyData = der.buffer.slice(der.byteOffset, der.byteOffset + der.byteLength) as ArrayBuffer;
  const msg = message.buffer.slice(message.byteOffset, message.byteOffset + message.byteLength) as ArrayBuffer;
  const sig = signature.buffer.slice(signature.byteOffset, signature.byteOffset + signature.byteLength) as ArrayBuffer;
  if (algorithm === "ES256") {
    const key = await subtle.importKey("spki", keyData, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
    return subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, sig, msg);
  }
  if (algorithm === "EdDSA") {
    const key = await subtle.importKey("spki", keyData, { name: "Ed25519" }, false, ["verify"]);
    return subtle.verify({ name: "Ed25519" }, key, sig, msg);
  }
  return false;
};
