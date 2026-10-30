/**
 * tests/session-cipher.test.ts — the session cipher as behaviour.
 * v3 (XChaCha20-Poly1305) is the only write path; v2 and legacy are read paths.
 */

import { describe, expect, it } from 'vitest';
import * as aesjs from 'aes-js';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { blobFormat, decryptAny, encryptLegacyForTests, encryptV2ForTests, encryptV3, randomBytes, RandomnessUnavailable, SessionCipherError } from '../src/lib/sessionCipher';
import { randomBytes as nodeRandom } from 'node:crypto';

const rng = (n: number) => new Uint8Array(nodeRandom(n));
const nonce = () => randomBytes(24, rng);

const KEY = new Uint8Array(32).map((_, i) => (i * 7 + 3) & 0xff);
const P1 = '{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.aaaa","refresh_token":"r1"}';
const P2 = '{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.bbbb","refresh_token":"r2"}';

describe('v3 is authenticated', () => {
  it('round-trips and reports its format', () => {
    const b = encryptV3(KEY, P1, nonce());
    expect(blobFormat(b)).toBe('v3');
    expect(decryptAny(KEY, b)).toEqual({ plaintext: P1, format: 'v3' });
  });
  it('two writes differ (fresh nonce each time)', () => {
    expect(encryptV3(KEY, P1, nonce())).not.toBe(encryptV3(KEY, P1, nonce()));
  });
  it('a flipped bit, a truncation, a wrong key and non-hex all throw undecryptable', () => {
    const b = encryptV3(KEY, P1, nonce());
    const flipped = b.slice(0, -2) + (b.slice(-2) === '00' ? '01' : '00');
    for (const bad of [flipped, b.slice(0, 60), 'v3.zz', 'v3.' + 'ab'.repeat(30)]) {
      expect(() => decryptAny(KEY, bad)).toThrow(SessionCipherError);
    }
    const other = new Uint8Array(32).fill(9);
    expect(() => decryptAny(other, b)).toThrow(SessionCipherError);
  });
  it('rejects a bad key or nonce length instead of silently truncating', () => {
    expect(() => encryptV3(new Uint8Array(16), P1, nonce())).toThrow();
    expect(() => encryptV3(KEY, P1, new Uint8Array(12))).toThrow();
  });
});

describe('randomness is injected, never a global', () => {
  it('a missing source fails closed with a typed error, not a ReferenceError', () => {
    const saved = (globalThis as { crypto?: unknown }).crypto;
    delete (globalThis as { crypto?: unknown }).crypto; // simulate Hermes: no crypto global
    try {
      expect(() => randomBytes(24)).toThrow(RandomnessUnavailable);
      expect(randomBytes(24, rng)).toHaveLength(24);
    } finally { (globalThis as { crypto?: unknown }).crypto = saved; }
  });
  it('a source returning the wrong shape is rejected', () => {
    expect(() => randomBytes(24, () => new Uint8Array(3))).toThrow(RandomnessUnavailable);
  });
});

describe('older generations still read', () => {
  it('legacy fixed-counter blob decrypts and is labelled legacy', () => {
    expect(decryptAny(KEY, encryptLegacyForTests(KEY, P1))).toEqual({ plaintext: P1, format: 'legacy' });
  });
  it('v2 IV blob decrypts and is labelled v2', () => {
    expect(decryptAny(KEY, encryptV2ForTests(KEY, P2))).toEqual({ plaintext: P2, format: 'v2' });
  });
  it('the fixed-counter construction is the one that leaked — kept only as evidence', () => {
    const fixed = (p: string) => new aesjs.ModeOfOperation.ctr(KEY, new aesjs.Counter(1)).encrypt(new TextEncoder().encode(p));
    const xor = (a: Uint8Array, b: Uint8Array) => Array.from(a, (x, i) => x ^ b[i]).join(',');
    const p1 = new TextEncoder().encode(P1), p2 = new TextEncoder().encode(P2);
    expect(xor(fixed(P1), fixed(P2))).toBe(xor(p1, p2));
  });
});

describe('write path', () => {
  it('only v3 is written by the store; Counter(1) survives solely in the legacy read path', () => {
    const store = readFileSync(resolve(__dirname, '..', 'src/lib/sessionStore.ts'), 'utf8');
    expect(store).toContain('encryptV3(');
    expect(store).not.toMatch(/encryptV2|Counter\(/);
    const cipher = readFileSync(resolve(__dirname, '..', 'src/lib/sessionCipher.ts'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    const legacy = cipher.slice(cipher.indexOf('function decryptLegacy'), cipher.indexOf('export function decryptAny'));
    expect(legacy).toContain('Counter(1)');
  });
});
