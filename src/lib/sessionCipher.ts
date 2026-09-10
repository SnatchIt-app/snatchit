/**
 * src/lib/sessionCipher.ts — the session blob cipher, three generations.
 *
 * Pure (aes-js, @noble/ciphers) so it is testable as behaviour, and proven under
 * the Hermes engine by scripts/hermes/run-session-smoke.sh. NO RUNTIME GLOBAL IS
 * READ: not `crypto` (Hermes has none — build 14 crashed on it), not
 * `TextDecoder` (Hermes has TextEncoder but not TextDecoder — the first Hermes
 * smoke found a ReferenceError inside decrypt being misreported as an auth
 * failure, which would have deleted a valid session). Randomness is injected;
 * UTF-8 is a strict pure codec below.
 *
 *   v3  `v3.` + hex(nonce, 24 B) + hex(ct || tag)   XChaCha20-Poly1305 (AEAD)
 *   v2  `v2.` + hex(iv, 16 B)   + hex(ct)           AES-256-CTR, IV per write
 *   legacy  bare hex                                AES-256-CTR, fixed Counter(1)
 *
 * ONLY v3 IS WRITTEN. v2 and legacy are read paths kept so a blob from an earlier
 * build is never treated as unreadable — that path deletes the session, the D5
 * symptom this branch removes — and each is re-encrypted to v3 on its next write.
 *
 * Poly1305 makes tampering, truncation and a wrong key fail identically: a thrown
 * `undecryptable`. Only the AEAD call sits inside the catch that produces it, so
 * a programming error (a missing global, a bug) propagates as itself and the
 * store keeps the ciphertext instead of clearing it.
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

export type RandomBytes = (n: number) => Uint8Array;

export class RandomnessUnavailable extends Error {
  constructor(detail = 'no randomness source was wired') {
    super(`sessionCipher: ${detail}. Hermes has no crypto global; the app entry must import ` +
          `'react-native-get-random-values' before any module that reaches the session cipher.`);
  }
}

/**
 * The only randomness entry point. Callers supply `random` from an audited
 * device source (the native binding wires react-native-get-random-values).
 * Falls back to a WebCrypto global only where one already exists (Node, web);
 * otherwise fails closed instead of reaching an undefined global.
 */
export function randomBytes(n: number, random?: RandomBytes): Uint8Array {
  if (random) {
    const out = random(n);
    if (!(out instanceof Uint8Array) || out.length !== n) throw new RandomnessUnavailable();
    return out;
  }
  const g = (globalThis as { crypto?: { getRandomValues?: (a: Uint8Array) => Uint8Array } }).crypto;
  if (g && typeof g.getRandomValues === 'function') return g.getRandomValues(new Uint8Array(n));
  throw new RandomnessUnavailable();
}

/** Strict pure UTF-8: no TextEncoder/TextDecoder, invalid input throws. */
export const utf8 = {
  to(s: string): Uint8Array {
    const out: number[] = [];
    for (let i = 0; i < s.length; i++) {
      let cp = s.charCodeAt(i);
      if (cp >= 0xd800 && cp <= 0xdbff && i + 1 < s.length) {
        const lo = s.charCodeAt(i + 1);
        if (lo >= 0xdc00 && lo <= 0xdfff) { cp = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00); i++; }
      }
      if (cp < 0x80) out.push(cp);
      else if (cp < 0x800) out.push(0xc0 | (cp >> 6), 0x80 | (cp & 0x3f));
      else if (cp < 0x10000) out.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
      else out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
    }
    return Uint8Array.from(out);
  },
  from(b: Uint8Array): string {
    let s = '';
    let i = 0;
    const cont = (k: number): number => {
      const x = b[k];
      if (x === undefined || (x & 0xc0) !== 0x80) throw new SessionCipherError('not utf-8');
      return x & 0x3f;
    };
    while (i < b.length) {
      const c = b[i];
      let cp: number;
      let n: number;
      if (c < 0x80) { cp = c; n = 1; }
      else if ((c & 0xe0) === 0xc0) { cp = ((c & 0x1f) << 6) | cont(i + 1); n = 2; if (cp < 0x80) throw new SessionCipherError('not utf-8'); }
      else if ((c & 0xf0) === 0xe0) { cp = ((c & 0x0f) << 12) | (cont(i + 1) << 6) | cont(i + 2); n = 3; if (cp < 0x800 || (cp >= 0xd800 && cp <= 0xdfff)) throw new SessionCipherError('not utf-8'); }
      else if ((c & 0xf8) === 0xf0) { cp = ((c & 0x07) << 18) | (cont(i + 1) << 12) | (cont(i + 2) << 6) | cont(i + 3); n = 4; if (cp < 0x10000 || cp > 0x10ffff) throw new SessionCipherError('not utf-8'); }
      else throw new SessionCipherError('not utf-8');
      s += String.fromCodePoint(cp);
      i += n;
    }
    return s;
  },
};

// aes-js returns plain Arrays from hex.toBytes; @noble/ciphers requires Uint8Array.
const hex = {
  fromBytes: (b: Uint8Array | number[]) => aesjs.utils.hex.fromBytes(b),
  toBytes: (h: string) => Uint8Array.from(aesjs.utils.hex.toBytes(h)),
};

export function blobFormat(blob: string): BlobFormat {
  if (blob.startsWith(BLOB_V3_PREFIX)) return 'v3';
  if (blob.startsWith(BLOB_V2_PREFIX)) return 'v2';
  return 'legacy';
}

/** v3 — the only write path. The nonce MUST come from `randomBytes(24, random)`. */
export function encryptV3(key: Uint8Array, plaintext: string, nonce: Uint8Array): string {
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
  let pt: Uint8Array;
  try {
    pt = xchacha20poly1305(key, nonce).decrypt(ct); // ONLY the AEAD is inside the try
  } catch {
    throw new SessionCipherError('v3 auth failed');  // wrong key, tamper, truncation — all here
  }
  return utf8.from(pt);                                // strict; throws its own undecryptable
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
  return utf8.from(pt);
}

/** legacy — read only. Fixed Counter(1); exists nowhere on a write path. */
export function encryptLegacyForTests(key: Uint8Array, plaintext: string): string {
  return hex.fromBytes(new aesjs.ModeOfOperation.ctr(key, new aesjs.Counter(1)).encrypt(utf8.to(plaintext)));
}

function decryptLegacy(key: Uint8Array, blob: string): string {
  if (!HEX.test(blob) || blob.length === 0 || blob.length % 2 !== 0) throw new SessionCipherError('legacy not hex');
  const pt = new aesjs.ModeOfOperation.ctr(key, new aesjs.Counter(1)).decrypt(hex.toBytes(blob));
  return utf8.from(pt);
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
