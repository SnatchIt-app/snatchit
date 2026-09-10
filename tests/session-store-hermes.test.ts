/**
 * tests/session-store-hermes.test.ts — the session store on a runtime with NO
 * `crypto` global, which is what Hermes is. Build 14 crashed at cold launch with
 * "Property 'crypto' doesn't exist" (Sentry 19d8d967…) because the native
 * binding lost its react-native-get-random-values import.
 *
 * Every case below runs with `globalThis.crypto` deleted for the whole suite and
 * an injected audited-shaped RNG — the exact contract the native binding now
 * supplies. This is as close to the RN path as vitest can execute: Hermes itself
 * cannot run here, so the binding's import order is pinned by a source guard.
 */

import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { randomBytes as nodeRandom } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { createSessionStore, blobKeyName, secureKeyName, type BlobBackend, type SecureBackend } from '../src/lib/sessionStore';
import { blobFormat, encryptLegacyForTests, encryptV2ForTests } from '../src/lib/sessionCipher';

const KEY = 'sb-ofaidukbieeekqaboscm-auth-token';
const SESSION = JSON.stringify({ access_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.cold', refresh_token: 'r-cold', user: { id: '919d511e' } });
const SESSION_AFTER_REFRESH = JSON.stringify({ access_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.fg', refresh_token: 'r-fg', user: { id: '919d511e' } });

// A device-shaped RNG: bytes only, no global involved.
const deviceRandom = (n: number) => new Uint8Array(nodeRandom(n));

let savedCrypto: unknown;
beforeAll(() => { savedCrypto = (globalThis as { crypto?: unknown }).crypto; delete (globalThis as { crypto?: unknown }).crypto; });
afterAll(() => { (globalThis as { crypto?: unknown }).crypto = savedCrypto; });

/** Persistent "device": survives store instances (each instance = one app launch). */
function device() {
  const asyncStorage = new Map<string, string>();
  const keychain = new Map<string, string>();
  const down = { keychain: false, storage: false };
  const unav = () => ({ ok: false as const, reason: 'unavailable' as const, error: new Error('unavailable') });
  const secure: SecureBackend = {
    async get(n) { return down.keychain ? unav() : { ok: true, value: keychain.get(n) ?? null }; },
    async set(n, v) { if (down.keychain) return unav(); keychain.set(n, v); return { ok: true }; },
    async delete(n) { if (down.keychain) return unav(); keychain.delete(n); return { ok: true }; },
  };
  const blob: BlobBackend = {
    async get(n) { return down.storage ? unav() : { ok: true, value: asyncStorage.get(n) ?? null }; },
    async set(n, v) { if (down.storage) return unav(); asyncStorage.set(n, v); return { ok: true }; },
    async remove(n) { if (down.storage) return unav(); asyncStorage.delete(n); return { ok: true }; },
  };
  const warn = vi.fn();
  const launch = () => createSessionStore({ secure, blob, random: deviceRandom, warn }); // one app process
  const keyBytes = () => Uint8Array.from((keychain.get(secureKeyName(KEY))!.match(/.{2}/g) ?? []).map((x) => parseInt(x, 16)));
  return { asyncStorage, keychain, down, warn, launch, keyBytes };
}

let d: ReturnType<typeof device>;
beforeEach(() => { d = device(); expect((globalThis as { crypto?: unknown }).crypto).toBeUndefined(); });

describe('cold launch with no crypto global', () => {
  it('a fresh install restores nothing and does not throw', async () => {
    expect(await d.launch().getItem(KEY)).toBeNull();
  });

  it('sign-in writes a v3 blob without touching any global', async () => {
    await d.launch().setItem(KEY, SESSION);
    expect(blobFormat(d.asyncStorage.get(blobKeyName(KEY))!)).toBe('v3');
  });

  it('a relaunch restores the session written by the previous process', async () => {
    await d.launch().setItem(KEY, SESSION);
    expect(await d.launch().getItem(KEY)).toBe(SESSION);
  });
});

describe('the build 13 → 14 upgrade path (the exact crash)', () => {
  it('a legacy blob from build 13 is restored at cold launch and migrated, not crashed on', async () => {
    // build 13 left: legacy fixed-counter blob + its key in the Keychain
    await d.launch().setItem(KEY, 'seed');
    d.asyncStorage.set(blobKeyName(KEY), encryptLegacyForTests(d.keyBytes(), SESSION));
    const app = d.launch();
    expect(await app.getItem(KEY)).toBe(SESSION);             // this is where build 14 threw
    expect(blobFormat(d.asyncStorage.get(blobKeyName(KEY))!)).toBe('v3');
    expect(await d.launch().getItem(KEY)).toBe(SESSION);      // and the next launch reads the migrated blob
  });

  it('a v2 blob migrates the same way', async () => {
    await d.launch().setItem(KEY, 'seed');
    d.asyncStorage.set(blobKeyName(KEY), encryptV2ForTests(d.keyBytes(), SESSION, deviceRandom(16)));
    expect(await d.launch().getItem(KEY)).toBe(SESSION);
    expect(blobFormat(d.asyncStorage.get(blobKeyName(KEY))!)).toBe('v3');
  });
});

describe('background / foreground', () => {
  it('a token refresh on foreground rewrites the blob and the next restore reads the new session', async () => {
    const app = d.launch();
    await app.setItem(KEY, SESSION);                          // signed in
    expect(await app.getItem(KEY)).toBe(SESSION);             // backgrounded, then foregrounded: restore
    await app.setItem(KEY, SESSION_AFTER_REFRESH);            // refresh loop rotated the token
    expect(await app.getItem(KEY)).toBe(SESSION_AFTER_REFRESH);
    expect(await d.launch().getItem(KEY)).toBe(SESSION_AFTER_REFRESH); // cold relaunch later
    expect(d.warn).not.toHaveBeenCalled();
  });
});

describe('storage unavailable during restore', () => {
  it('Keychain locked at launch: signed-out this time, session intact, recovered next launch', async () => {
    await d.launch().setItem(KEY, SESSION);
    d.down.keychain = true;
    expect(await d.launch().getItem(KEY)).toBeNull();
    expect(d.asyncStorage.has(blobKeyName(KEY))).toBe(true);
    d.down.keychain = false;
    expect(await d.launch().getItem(KEY)).toBe(SESSION);
  });

  it('AsyncStorage unavailable at launch: same', async () => {
    await d.launch().setItem(KEY, SESSION);
    d.down.storage = true;
    expect(await d.launch().getItem(KEY)).toBeNull();
    d.down.storage = false;
    expect(await d.launch().getItem(KEY)).toBe(SESSION);
  });
});

describe('malformed ciphertext at restore', () => {
  it('a tampered blob clears cleanly and the next sign-in works', async () => {
    await d.launch().setItem(KEY, SESSION);
    d.asyncStorage.set(blobKeyName(KEY), 'v3.' + 'ff'.repeat(60));
    expect(await d.launch().getItem(KEY)).toBeNull();
    expect(d.asyncStorage.has(blobKeyName(KEY))).toBe(false);
    await d.launch().setItem(KEY, SESSION);
    expect(await d.launch().getItem(KEY)).toBe(SESSION);
  });
});

describe('the native binding supplies the source in the right order', () => {
  const binding = readFileSync(resolve(__dirname, '..', 'src/lib/secureStorage.ts'), 'utf8');
  const code = binding.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
  const cipher = readFileSync(resolve(__dirname, '..', 'src/lib/sessionCipher.ts'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
  const store = readFileSync(resolve(__dirname, '..', 'src/lib/sessionStore.ts'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');

  it('react-native-get-random-values is the FIRST import of the binding', () => {
    const firstImport = code.match(/^\s*import[^\n]*$/m)?.[0] ?? '';
    expect(firstImport).toContain("import 'react-native-get-random-values'");
  });
  it('the binding hands the guarded device source to the store explicitly', () => {
    expect(code).toContain('createSessionStore({ secure, blob, random: deviceRandomBytes })');
    expect(code).not.toMatch(/crypto\./);
  });
  it('no cipher or store path reads TextDecoder/TextEncoder — Hermes has no TextDecoder', () => {
    expect(cipher).not.toMatch(/TextDecoder|TextEncoder/);
    expect(store).not.toMatch(/TextDecoder|TextEncoder/);
  });
  it('neither the store nor the cipher reaches a crypto global on any write path', () => {
    expect(store).not.toMatch(/\bcrypto\./);
    const writePaths = cipher.slice(0, cipher.indexOf('export function randomBytes')) + cipher.slice(cipher.indexOf('export function encryptV3'));
    expect(writePaths).not.toMatch(/\bcrypto\./);
  });
  it('the dependency exists', () => {
    const pkg = JSON.parse(readFileSync(resolve(__dirname, '..', 'package.json'), 'utf8'));
    expect(pkg.dependencies['react-native-get-random-values']).toBeTruthy();
  });
});
