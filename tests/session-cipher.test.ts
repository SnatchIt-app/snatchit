/**
 * tests/session-cipher.test.ts — keystream never reused; legacy blobs still read.
 *
 * Review of a050125 (Claude A): a stable key with a fixed Counter(1) reuses the
 * keystream, so C1 XOR C2 = P1 XOR P2 across two session writes. These tests
 * exercise the cipher as behaviour, not source text.
 */

import { describe, expect, it } from 'vitest';
import * as aesjs from 'aes-js';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { BLOB_V2_PREFIX, decryptAny, decryptLegacy, encryptV2, isV2Blob } from '../src/lib/sessionCipher';

const KEY = new Uint8Array(32).map((_, i) => (i * 7 + 3) & 0xff);
const P1 = '{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.aaaa","refresh_token":"r1"}';
const P2 = '{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.bbbb","refresh_token":"r2"}';
const hex = aesjs.utils.hex;
const xor = (a: Uint8Array, b: Uint8Array) => a.map((x, i) => x ^ b[i]);
const body = (blob: string) => hex.toBytes(blob.slice(BLOB_V2_PREFIX.length + 32));

describe('(a) same plaintext, same key, two writes', () => {
  it('produce different ciphertexts', () => {
    expect(encryptV2(KEY, P1)).not.toBe(encryptV2(KEY, P1));
  });
});

describe('(b) keystream is not reused', () => {
  it('XOR of two ciphertexts does not equal XOR of the plaintexts', () => {
    const c1 = body(encryptV2(KEY, P1)), c2 = body(encryptV2(KEY, P2));
    const p1 = aesjs.utils.utf8.toBytes(P1), p2 = aesjs.utils.utf8.toBytes(P2);
    expect(hex.fromBytes(xor(c1, c2))).not.toBe(hex.fromBytes(xor(p1, p2)));
  });

  it('the old construction DID leak this way (the regression being closed)', () => {
    const fixed = (p: string) => new aesjs.ModeOfOperation.ctr(KEY, new aesjs.Counter(1)).encrypt(aesjs.utils.utf8.toBytes(p));
    const p1 = aesjs.utils.utf8.toBytes(P1), p2 = aesjs.utils.utf8.toBytes(P2);
    expect(hex.fromBytes(xor(fixed(P1), fixed(P2)))).toBe(hex.fromBytes(xor(p1, p2)));
  });
});

describe('(c) legacy no-IV blob', () => {
  const legacy = hex.fromBytes(new aesjs.ModeOfOperation.ctr(KEY, new aesjs.Counter(1)).encrypt(aesjs.utils.utf8.toBytes(P1)));
  it('is recognised as legacy and still decrypts — never "cannot decrypt"', () => {
    expect(isV2Blob(legacy)).toBe(false);
    expect(decryptLegacy(KEY, legacy)).toBe(P1);
    expect(decryptAny(KEY, legacy)).toEqual({ plaintext: P1, legacy: true });
  });
  it('the adapter re-encrypts a legacy blob on read instead of deleting it', () => {
    const src = readFileSync(resolve(__dirname, '..', 'src/lib/secureStorage.ts'), 'utf8');
    const get = src.slice(src.indexOf('async getItem'), src.indexOf('async setItem'));
    expect(get).toContain('if (out.legacy)');
    expect(get.indexOf('await this.setItem(key, out.plaintext)')).toBeLessThan(get.indexOf('return out.plaintext'));
    // deletion stays reserved for a genuinely undecryptable blob (thrown error)
    expect(get.indexOf('catch (e)')).toBeGreaterThan(get.indexOf('return out.plaintext'));
  });
});

describe('(d) round trip', () => {
  it('v2 encrypt → decrypt returns the plaintext, with a distinct IV each time', () => {
    const b1 = encryptV2(KEY, P1), b2 = encryptV2(KEY, P1);
    expect(isV2Blob(b1)).toBe(true);
    expect(decryptAny(KEY, b1)).toEqual({ plaintext: P1, legacy: false });
    expect(decryptAny(KEY, b2).plaintext).toBe(P1);
    expect(b1.slice(3, 35)).not.toBe(b2.slice(3, 35)); // the IVs differ
  });
  it('re-encrypting a legacy plaintext yields a v2 blob that decrypts', () => {
    const legacy = hex.fromBytes(new aesjs.ModeOfOperation.ctr(KEY, new aesjs.Counter(1)).encrypt(aesjs.utils.utf8.toBytes(P2)));
    const { plaintext } = decryptAny(KEY, legacy);
    const v2 = encryptV2(KEY, plaintext);
    expect(decryptAny(KEY, v2)).toEqual({ plaintext: P2, legacy: false });
  });
  it('a wrong-length IV is rejected rather than silently truncated', () => {
    expect(() => encryptV2(KEY, P1, new Uint8Array(8))).toThrow();
  });
});

describe('(e) the adapter no longer uses a fixed counter for writes', () => {
  it('encrypt goes through encryptV2 with a stable key', () => {
    const src = readFileSync(resolve(__dirname, '..', 'src/lib/secureStorage.ts'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    const enc = src.slice(src.indexOf('async function encrypt'), src.indexOf('async function decrypt'));
    expect(enc).toContain('encryptV2(await loadOrCreateKey(key), value)');
    expect(enc).not.toContain('Counter(1)');
    expect(src).not.toMatch(/Counter\(1\)/); // Counter(1) lives only in the legacy decrypt path of sessionCipher
  });
});
