/**
 * tests/session-storage-torn-write.test.ts — the key is created once and reused,
 * so a write interrupted between the Keychain and AsyncStorage can never leave
 * a blob its key cannot open. Behavioural coverage lives in session-store.test.ts;
 * this pins the structural guarantee in the store and the thinness of the binding.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const read = (rel: string) => readFileSync(resolve(__dirname, '..', rel), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
const store = read('src/lib/sessionStore.ts');
const binding = read('src/lib/secureStorage.ts');

describe('key reuse', () => {
  it('load-or-create: read the Keychain first, mint only when absent, memoised per key', () => {
    const fn = store.slice(store.indexOf('async function loadOrCreateKey'), store.indexOf('async function clear'));
    expect(fn.indexOf('deps.secure.get')).toBeLessThan(fn.indexOf('randomBytes(32, deps.random)'));
    expect(fn).toContain('if (r.value) return');
    expect(fn).toContain('keyInFlight');
  });
  it('setItem writes the key before the blob and never deletes the key', () => {
    const set = store.slice(store.indexOf('async setItem'), store.indexOf('async removeItem'));
    expect(set.indexOf('loadOrCreateKey(key)')).toBeLessThan(set.indexOf('deps.blob.set'));
    expect(set).not.toContain('secure.delete');
  });
  it('the native binding only adapts the modules into typed outcomes', () => {
    expect(binding).toContain('createSessionStore({ secure, blob, random: deviceRandomBytes })');
    expect(binding).not.toMatch(/encrypt|decrypt|Counter/);
    // the global is read only inside the guarded randomness module, never here
    expect(binding).not.toMatch(/getRandomValues/);
  });
});
