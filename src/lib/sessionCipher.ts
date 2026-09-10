/**
 * src/lib/sessionCipher.ts — AES-256-CTR for the session blob, IV per write.
 *
 * Pure (aes-js + crypto.getRandomValues only) so it is testable as behaviour.
 *
 * WHY THE IV. a050125 made the storage key stable to close a torn-write hazard,
 * but the counter was a fixed `Counter(1)`. Stable key + fixed counter = the same
 * keystream for every write, and two session blobs then satisfy
 * C1 XOR C2 = P1 XOR P2 — with JSON scaffolding and the JWT header identical on
 * every write, that leaks token material to anyone holding two generations of
 * the blob, Keychain untouched. Each write now draws a random 16-byte IV that
 * seeds the counter and travels with the blob, so keystreams never repeat
 * under a reused key. The key stays stable, so key and blob still cannot
 * disagree.
 *
 * FORMAT. `v2.` + hex(iv, 32 chars) + hex(ciphertext). Blobs written before this
 * change carry no prefix and no IV; they are decrypted with `Counter(1)` exactly
 * as before, and re-encrypted into v2 on the next write. A legacy blob must never
 * read as "cannot decrypt", because that path deletes the session — the D5
 * symptom this branch exists to remove.
 */

import * as aesjs from 'aes-js';

export const BLOB_V2_PREFIX = 'v2.';
const IV_BYTES = 16;
const IV_HEX = IV_BYTES * 2;

export function randomIv(): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(IV_BYTES));
}

export function isV2Blob(blob: string): boolean {
  return blob.startsWith(BLOB_V2_PREFIX) && blob.length > BLOB_V2_PREFIX.length + IV_HEX;
}

export function encryptV2(key: Uint8Array, plaintext: string, iv: Uint8Array = randomIv()): string {
  if (iv.length !== IV_BYTES) throw new Error('sessionCipher: iv must be 16 bytes');
  const cipher = new aesjs.ModeOfOperation.ctr(key, new aesjs.Counter(iv));
  const ct = cipher.encrypt(aesjs.utils.utf8.toBytes(plaintext));
  return BLOB_V2_PREFIX + aesjs.utils.hex.fromBytes(iv) + aesjs.utils.hex.fromBytes(ct);
}

/** Legacy (pre-IV) format: bare hex, fixed Counter(1). Read-only; never written. */
export function decryptLegacy(key: Uint8Array, blobHex: string): string {
  const cipher = new aesjs.ModeOfOperation.ctr(key, new aesjs.Counter(1));
  return aesjs.utils.utf8.fromBytes(cipher.decrypt(aesjs.utils.hex.toBytes(blobHex)));
}

export function decryptAny(key: Uint8Array, blob: string): { plaintext: string; legacy: boolean } {
  if (isV2Blob(blob)) {
    const body = blob.slice(BLOB_V2_PREFIX.length);
    const iv = aesjs.utils.hex.toBytes(body.slice(0, IV_HEX));
    const ct = aesjs.utils.hex.toBytes(body.slice(IV_HEX));
    const cipher = new aesjs.ModeOfOperation.ctr(key, new aesjs.Counter(iv));
    return { plaintext: aesjs.utils.utf8.fromBytes(cipher.decrypt(ct)), legacy: false };
  }
  return { plaintext: decryptLegacy(key, blob), legacy: true };
}
