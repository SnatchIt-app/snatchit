/**
 * src/lib/push/deviceSecret.ts — the device secret that proves "same device"
 * to push-token registration (migration 128 client half, A-08d).
 *
 * CONTRACT (A, 2026-09-14, 128 @f7b31ad — NOT FROZEN, a second delta is
 * expected). 16–512 characters, any text encoding; the server stores only its
 * SHA-256. It is PER DEVICE, not per account: it MUST survive sign-out and
 * account switching, because proving the same physical device across an
 * account change is its entire purpose.
 *
 * THE STORED HASH IS NEVER REPLACED. An earlier revision let the owner's
 * registration overwrite it; A's adversarial review found that a HIGH-severity
 * regression (momentary session access could plant a secret and capture the
 * device permanently) and it was reverted. Consequences for this client:
 *  - a registration with a mismatched secret still returns `refreshed`, so
 *    the reply can never reveal a mismatch; only the missing-secret signal can;
 *  - if the Keychain loses the value, a fresh one is generated HERE and the
 *    hook runs the recovery in registerToken.ts — delete the row this device
 *    owns (RLS DELETE), then register — gated so it can never run
 *    speculatively. The client never "rotates".
 * Nothing clears it: account deletion keeps it so the next account on this
 * device can still rebind.
 *
 * NEVER LOGGED, never sent anywhere but the registration RPC, never derived
 * from anything guessable, never a constant. Generated from the device CSPRNG
 * — the same source the session store uses — and never Math.random. The store
 * is injected so the lifecycle is testable without the Keychain.
 */

export const DEVICE_SECRET_KEY = 'snatchit.push.device_secret.v1';

/** 32 random bytes → 43 base64url characters (server accepts 16–512). */
export const DEVICE_SECRET_BYTES = 32;
export const DEVICE_SECRET_LENGTH = 43;

export type RandomBytes = (n: number) => Uint8Array;

export interface SecretStore {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
}

const B64URL = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/** base64url without padding; no Buffer dependency (Hermes has none). */
export function toBase64Url(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  for (; i + 2 < bytes.length; i += 3) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += B64URL[(n >> 18) & 63] + B64URL[(n >> 12) & 63] + B64URL[(n >> 6) & 63] + B64URL[n & 63];
  }
  const rest = bytes.length - i;
  if (rest === 1) {
    const n = bytes[i] << 16;
    out += B64URL[(n >> 18) & 63] + B64URL[(n >> 12) & 63];
  } else if (rest === 2) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out += B64URL[(n >> 18) & 63] + B64URL[(n >> 12) & 63] + B64URL[(n >> 6) & 63];
  }
  return out;
}

export function generateDeviceSecret(random: RandomBytes): string {
  const bytes = random(DEVICE_SECRET_BYTES);
  if (!(bytes instanceof Uint8Array) || bytes.length !== DEVICE_SECRET_BYTES) {
    throw new Error('deviceSecret: RNG returned the wrong shape');
  }
  return toBase64Url(bytes);
}

/** A stored value that is not ours (truncated, corrupted, foreign) is replaced. */
export function isWellFormedSecret(v: string | null | undefined): v is string {
  return typeof v === 'string' && new RegExp(`^[A-Za-z0-9_-]{${DEVICE_SECRET_LENGTH}}$`).test(v);
}

export type SecretResult =
  | { ok: true; secret: string; created: boolean }
  | { ok: false; reason: 'store_unavailable' | 'rng_unavailable' };

/** Read the secret, creating it on first use. Never throws. */
export async function getOrCreateDeviceSecret(store: SecretStore, random: RandomBytes): Promise<SecretResult> {
  let existing: string | null;
  try {
    existing = await store.get(DEVICE_SECRET_KEY);
  } catch {
    return { ok: false, reason: 'store_unavailable' };
  }
  if (isWellFormedSecret(existing)) return { ok: true, secret: existing, created: false };

  let fresh: string;
  try {
    fresh = generateDeviceSecret(random);
  } catch {
    return { ok: false, reason: 'rng_unavailable' };
  }
  try {
    await store.set(DEVICE_SECRET_KEY, fresh);
  } catch {
    return { ok: false, reason: 'store_unavailable' };
  }
  return { ok: true, secret: fresh, created: true };
}
