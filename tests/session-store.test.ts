/**
 * tests/session-store.test.ts — persistence boundaries of the session store,
 * exercised as behaviour with fault-injected in-memory backends.
 *
 * Review of 5a6e6ad (Claude A): a transient read failure must not delete a
 * recoverable session; only "no key" and "authentication failed" may clear.
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';

import { createSessionStore, blobKeyName, secureKeyName, StorageUnavailable, type BlobBackend, type SecureBackend } from '../src/lib/sessionStore';
import { blobFormat, encryptLegacyForTests, encryptV2ForTests, encryptV3 } from '../src/lib/sessionCipher';
import { randomBytes as nodeRandom } from 'node:crypto';

const rng = (n: number) => new Uint8Array(nodeRandom(n));

const KEY = 'sb-test-auth-token';
const SESSION = '{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.aaa","refresh_token":"r1"}';
const SESSION2 = '{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.bbb","refresh_token":"r2"}';

type Fault = { on: 'get' | 'set' | 'delete' | 'remove'; times?: number; after?: number };

function fakeBackends() {
  const kv = new Map<string, string>();
  const secureMap = new Map<string, string>();
  const faults: { secure: Fault[]; blob: Fault[] } = { secure: [], blob: [] };
  const calls = { secureSet: 0, blobSet: 0 };
  const hit = (list: Fault[], op: Fault['on']) => {
    const f = list.find((x) => x.on === op && (x.times ?? 1) > 0);
    if (!f) return false;
    if (f.after && f.after-- > 0) return false;
    if (f.times !== undefined) f.times--; else f.times = 0;
    return true;
  };
  const unav = () => ({ ok: false as const, reason: 'unavailable' as const, error: new Error('keychain busy') });
  const secure: SecureBackend = {
    async get(n) { return hit(faults.secure, 'get') ? unav() : { ok: true, value: secureMap.get(n) ?? null }; },
    async set(n, v) { if (hit(faults.secure, 'set')) return unav(); calls.secureSet++; secureMap.set(n, v); return { ok: true }; },
    async delete(n) { if (hit(faults.secure, 'delete')) return unav(); secureMap.delete(n); return { ok: true }; },
  };
  const blob: BlobBackend = {
    async get(n) { return hit(faults.blob, 'get') ? unav() : { ok: true, value: kv.get(n) ?? null }; },
    async set(n, v) { if (hit(faults.blob, 'set')) return unav(); calls.blobSet++; kv.set(n, v); return { ok: true }; },
    async remove(n) { if (hit(faults.blob, 'remove')) return unav(); kv.delete(n); return { ok: true }; },
  };
  const warn = vi.fn();
  return { kv, secureMap, faults, calls, secure, blob, warn, store: createSessionStore({ secure, blob, warn, random: rng }) };
}

let f: ReturnType<typeof fakeBackends>;
beforeEach(() => { f = fakeBackends(); });

const keyBytes = () => Uint8Array.from((f.secureMap.get(secureKeyName(KEY))!.match(/.{2}/g) ?? []).map((x) => parseInt(x, 16)));

describe('persistence boundaries', () => {
  it('normal write then read round-trips as v3', async () => {
    await f.store.setItem(KEY, SESSION);
    expect(blobFormat(f.kv.get(blobKeyName(KEY))!)).toBe('v3');
    expect(await f.store.getItem(KEY)).toBe(SESSION);
  });

  it('interruption after the Keychain write, before the blob write: next launch reads the previous session', async () => {
    await f.store.setItem(KEY, SESSION);              // generation 1 persisted
    f.faults.blob.push({ on: 'set' });                // the second write dies between the two stores
    await expect(f.store.setItem(KEY, SESSION2)).rejects.toBeInstanceOf(StorageUnavailable);
    const relaunched = createSessionStore({ secure: f.secure, blob: f.blob, warn: f.warn, random: rng });
    expect(await relaunched.getItem(KEY)).toBe(SESSION); // key was never replaced, so the old blob still opens
  });

  it('interruption on the Keychain write itself: nothing half-written, previous session intact', async () => {
    await f.store.setItem(KEY, SESSION);
    f.secureMap.clear();                              // simulate a Keychain whose key is being (re)created
    f.faults.secure.push({ on: 'set' });
    await expect(f.store.setItem(KEY, SESSION2)).rejects.toBeInstanceOf(StorageUnavailable);
    expect(f.kv.get(blobKeyName(KEY))).toBeDefined();  // blob untouched
  });

  it('two concurrent first writes mint exactly one key and both blobs stay readable', async () => {
    await Promise.all([f.store.setItem(KEY, SESSION), f.store.setItem(KEY, SESSION2)]);
    expect(f.calls.secureSet).toBe(1);
    const read = await f.store.getItem(KEY);
    expect([SESSION, SESSION2]).toContain(read);
  });

  it('a relaunch between key creation and first blob write reads null, not an error, and keeps the key', async () => {
    f.faults.blob.push({ on: 'set' });
    await expect(f.store.setItem(KEY, SESSION)).rejects.toBeInstanceOf(StorageUnavailable);
    const relaunched = createSessionStore({ secure: f.secure, blob: f.blob, warn: f.warn, random: rng });
    expect(await relaunched.getItem(KEY)).toBeNull();
    await relaunched.setItem(KEY, SESSION);
    expect(await relaunched.getItem(KEY)).toBe(SESSION);
  });
});

describe('older generations are read, migrated to v3, and never deleted', () => {
  it.each([
    ['legacy', (k: Uint8Array) => encryptLegacyForTests(k, SESSION)],
    ['v2', (k: Uint8Array) => encryptV2ForTests(k, SESSION)],
  ])('%s blob decrypts and is rewritten as v3 on read', async (_name, make) => {
    await f.store.setItem(KEY, 'seed');                  // establishes the key
    f.kv.set(blobKeyName(KEY), make(keyBytes()));         // replace with an older-format blob
    expect(await f.store.getItem(KEY)).toBe(SESSION);
    expect(blobFormat(f.kv.get(blobKeyName(KEY))!)).toBe('v3');
    expect(await f.store.getItem(KEY)).toBe(SESSION);     // and it still reads after migration
  });

  it('a migration that cannot write leaves the old blob in place and still returns the session', async () => {
    await f.store.setItem(KEY, 'seed');
    f.kv.set(blobKeyName(KEY), encryptV2ForTests(keyBytes(), SESSION));
    f.faults.blob.push({ on: 'set' });
    expect(await f.store.getItem(KEY)).toBe(SESSION);
    expect(blobFormat(f.kv.get(blobKeyName(KEY))!)).toBe('v2');   // deferred, not destroyed
  });
});

describe('malformed and truncated blobs', () => {
  it('a tampered v3 blob fails authentication and is cleared, never returned as garbage', async () => {
    await f.store.setItem(KEY, SESSION);
    const b = f.kv.get(blobKeyName(KEY))!;
    const flipped = b.slice(0, -2) + (b.slice(-2) === '00' ? '01' : '00');
    f.kv.set(blobKeyName(KEY), flipped);
    expect(await f.store.getItem(KEY)).toBeNull();
    expect(f.kv.has(blobKeyName(KEY))).toBe(false);
    expect(f.warn).toHaveBeenCalledWith(expect.stringContaining('undecryptable'), expect.anything());
  });

  it('a truncated v3 blob is undecryptable, not partially decrypted', async () => {
    await f.store.setItem(KEY, SESSION);
    f.kv.set(blobKeyName(KEY), f.kv.get(blobKeyName(KEY))!.slice(0, 40));
    expect(await f.store.getItem(KEY)).toBeNull();
    expect(f.kv.has(blobKeyName(KEY))).toBe(false);
  });

  it('a wrong key fails cleanly', async () => {
    await f.store.setItem(KEY, SESSION);
    f.secureMap.set(secureKeyName(KEY), 'ab'.repeat(32));
    expect(await f.store.getItem(KEY)).toBeNull();
  });
});

describe('transient unavailability keeps the ciphertext', () => {
  it('Keychain unavailable on read: null now, session recovered on the next read', async () => {
    await f.store.setItem(KEY, SESSION);
    f.faults.secure.push({ on: 'get' });
    expect(await f.store.getItem(KEY)).toBeNull();
    expect(f.kv.has(blobKeyName(KEY))).toBe(true);        // blob survived
    expect(f.secureMap.has(secureKeyName(KEY))).toBe(true); // key survived
    expect(await f.store.getItem(KEY)).toBe(SESSION);      // recovered
  });

  it('AsyncStorage unavailable on read: null now, nothing cleared', async () => {
    await f.store.setItem(KEY, SESSION);
    f.faults.blob.push({ on: 'get' });
    expect(await f.store.getItem(KEY)).toBeNull();
    expect(await f.store.getItem(KEY)).toBe(SESSION);
  });

  it('only a genuinely missing key clears the entry', async () => {
    await f.store.setItem(KEY, SESSION);
    f.secureMap.clear();                                   // OS restore wiped the Keychain
    expect(await f.store.getItem(KEY)).toBeNull();
    expect(f.kv.has(blobKeyName(KEY))).toBe(false);
  });
});

describe('ciphertext non-determinism', () => {
  it('two writes of the same plaintext differ and share no XOR relation', async () => {
    await f.store.setItem(KEY, SESSION);
    const b1 = f.kv.get(blobKeyName(KEY))!;
    await f.store.setItem(KEY, SESSION);
    const b2 = f.kv.get(blobKeyName(KEY))!;
    expect(b1).not.toBe(b2);
    const k = keyBytes();
    const body = (b: string) => Uint8Array.from((b.slice(3 + 48).match(/.{2}/g) ?? []).map((x) => parseInt(x, 16)));
    const c1 = body(b1), c2 = body(b2), c3 = body(encryptV3(k, SESSION2, rng(24)));
    const xor = (a: Uint8Array, b: Uint8Array) => Array.from(a.slice(0, Math.min(a.length, b.length)), (x, i) => x ^ b[i]).join(',');
    expect(xor(c1, c2)).not.toBe('0,'.repeat(c1.length - 1) + '0');   // same plaintext, different keystream
    const p12 = Array.from(new TextEncoder().encode(SESSION), (x, i) => x ^ new TextEncoder().encode(SESSION2)[i]).join(',');
    expect(xor(c1, c3)).not.toBe(p12);
  });
});

describe('no token material is ever logged', () => {
  it('every warn call carries a message and an error, never the session value', async () => {
    await f.store.setItem(KEY, SESSION);
    f.faults.secure.push({ on: 'get' });
    await f.store.getItem(KEY);
    f.kv.set(blobKeyName(KEY), 'zz');
    await f.store.getItem(KEY);
    expect(f.warn.mock.calls.length).toBeGreaterThan(0);
    for (const [msg, err] of f.warn.mock.calls) {
      expect(String(msg)).not.toContain('eyJ');
      expect(String(msg)).not.toContain(SESSION);
      if (err !== undefined) expect(String((err as Error)?.message ?? err)).not.toContain('eyJ');
    }
  });
});
