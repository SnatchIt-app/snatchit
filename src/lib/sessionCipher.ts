/**
 * src/lib/sessionCipher.ts — the session blob cipher, three generations.
 *
 * Pure (aes-js, @noble/ciphers, crypto.getRandomValues) so it is testable as
 * behaviour. The storage adapter (sessionStore.ts) never touches primitives.
 *
 *   v3  `v3.` + hex(nonce, 24 B) + hex(ct || tag)   XChaCha20-Poly1305 (AEAD)
 *   v2  `v2.` + hex(iv, 16 B)   + hex(ct)           AES-256-CTR, IV per write
 *   legacy  bare hex                                AES-256-CTR, fixed Counter(1)
 *
 * ONLY v3 IS WRITTEN. v2 and legacy are read paths kept so a blob written by an
 * earlier build is never treated as unreadable — that path deletes the session,
 * which is the D5 symptom this branch removes — and each is re-encrypted to v3
 * by the store on its next write.
 *
 * WHY AN AEAD (review of 5a6e6ad). CTR is unauthenticated and malleable: a
 * writer to AsyncStorage can flip chosen plaintext bits or truncate the blob
 * and the reader cannot tell, and a wrong-key read yields plausible garbage
 * rather than a clean failure. Poly1305 makes tampering, truncation and a
 * wrong key all fail the same way: a thrown `undecryptable`. Nothing here is
 * composed by hand; the AEAD is the audited @noble/ciphers implementation, and
 * the nonce is drawn fresh per write, so a reused key never reuses a keystream.
 */

import * as aesjs from 'aes-js';
import { xchacha20poly1305 } from '@noble/ciphers/chacha.js';

export const BLOB_V3_PREFIX = 'v3.';
export const BLOB_V2_PREFIX = 'v2.';
const NONCE_BYTES = 24;
const IV_BYTES = 16;
const TAG_BYTES = 16;
const HEX = /^[0-9a-f]*$/;

export type BlobFormat = 'v3' | 'v2' | 'legacy';

/** The one failure the cipher reports: the blob cannot be authenticated/decoded. */
export class SessionCipherError extends Error {
  readonly kind = 'undecryptable' as const;
  constructor(detail: string) { super(`sessionCipher: undecryptable (${detail})`); }
}

const utf8 = { to: (s: string) => new TextEncoder().encode(s), from: (b: Uint8Array) => new TextDecoder('utf-8', { fatal: true }).decode(b) };
// aes-js returns plain Arrays from hex.toBytes; @noble/ciphers requires Uint8Array.
const hex = {
  fromBytes: (b: Uint8Array | number[]) => aesjs.utils.hex.fromBytes(b),
  toBytes: (h: string) => Uint8Array.from(aesjs.utils.hex.toBytes(h)),
};

export function randomBytes(n: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(n));
}

export function blobFormat(blob: string): BlobFormat {
  if (blob.startsWith(BLOB_V3_PREFIX)) return 'v3';
  if (blob.startsWith(BLOB_V2_PREFIX)) return 'v2';
  return 'legacy';
}

/** v3 — the only write path. */
export function encryptV3(key: Uint8Array, plaintext: string, nonce: Uint8Array = randomBytes(NONCE_BYTES)): string {
  if (key.length !== 32) throw new Error('sessionCipher: key must be 32 bytes');
  if (nonce.length !== NONCE_BYTES) throw new Error('sessionCipher: nonce must be 24 bytes');
  const ct = xchacha20poly1305(key, nonce).encrypt(utf8.to(plaintext));
  return BLOB_V3_PREFIX + hex.fromBytes(nonce) + hex.fromBytes(ct);
}

function decryptV3(key: Uint8Array, blob: string): string {
  const body = blob.slice(BLOB_V3_PREFIX.length);
  if (!HEX.test(body) || body.length % 2 !== 0) throw new SessionCipherError('v3 not hex');
  const bytes = hex.toBytes(body);
  if (bytes.length < NONCE_BYTES + TAG_BYTES) throw new SessionCipherError('v3 truncated');
  const nonce = bytes.slice(0, NONCE_BYTES);
  const ct = bytes.slice(NONCE_BYTES);
  try {
    return utf8.from(xchacha20poly1305(key, nonce).decrypt(ct));
  } catch {
    throw new SessionCipherError('v3 auth failed'); // wrong key, tamper, truncation — all here
  }
}

/** v2 — read only. Kept so blobs from the IV build stay readable. */
export function encryptV2ForTests(key: Uint8Array, plaintext: string, iv: Uint8Array = randomBytes(IV_BYTES)): string {
  const ct = new aesjs.ModeOfOperation.ctr(key, new aesjs.Counter(iv)).encrypt(utf8.to(plaintext));
  return BLOB_V2_PREFIX + hex.fromBytes(iv) + hex.fromBytes(ct);
}

function decryptV2(key: Uint8Array, blob: string): string {
  const body = blob.slice(BLOB_V2_PREFIX.length);
  if (!HEX.test(body) || body.length <= IV_BYTES * 2) throw new SessionCipherError('v2 malformed');
  const bytes = hex.toBytes(body);
  const pt = new aesjs.ModeOfOperation.ctr(key, new aesjs.Counter(bytes.slice(0, IV_BYTES))).decrypt(bytes.slice(IV_BYTES));
  try { return utf8.from(pt); } catch { throw new SessionCipherError('v2 not utf-8'); }
}

/** legacy — read only. Fixed Counter(1); exists nowhere on a write path. */
export function encryptLegacyForTests(key: Uint8Array, plaintext: string): string {
  return hex.fromBytes(new aesjs.ModeOfOperation.ctr(key, new aesjs.Counter(1)).encrypt(utf8.to(plaintext)));
}

function decryptLegacy(key: Uint8Array, blob: string): string {
  if (!HEX.test(blob) || blob.length === 0 || blob.length % 2 !== 0) throw new SessionCipherError('legacy not hex');
  const pt = new aesjs.ModeOfOperation.ctr(key, new aesjs.Counter(1)).decrypt(hex.toBytes(blob));
  try { return utf8.from(pt); } catch { throw new SessionCipherError('legacy not utf-8'); }
}

/**
 * Decrypt any generation. Throws SessionCipherError when the blob cannot be
 * authenticated or decoded; never returns garbage.
 */
export function decryptAny(key: Uint8Array, blob: string): { plaintext: string; format: BlobFormat } {
  const format = blobFormat(blob);
  const plaintext = format === 'v3' ? decryptV3(key, blob) : format === 'v2' ? decryptV2(key, blob) : decryptLegacy(key, blob);
  return { plaintext, format };
}
