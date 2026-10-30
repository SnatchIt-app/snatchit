/**
 * scripts/hermes/session-smoke.entry.ts — the real session cipher + store,
 * executed under the Hermes engine (not Node), with NO crypto global.
 *
 * Bundled by Metro (so it is the same module graph the app ships) and run by
 * the `hermes` CLI from react-native's SDK. It imports nothing from
 * react-native, so the bundle needs no native modules. Two assertions:
 *   1. with no randomness source, the write path throws the NAMED error,
 *      never a bare ReferenceError;
 *   2. with an injected source, sign-in write, restore, legacy migration and
 *      tamper rejection all execute on Hermes.
 * The injected source is a deterministic xorshift — it proves the cipher and
 * store EXECUTE on Hermes, not that the entropy is good; the audited native
 * source cannot run in the bare engine and is asserted on-device.
 */
import { createSessionStore, blobKeyName, secureKeyName } from '../../src/lib/sessionStore';
import { blobFormat, decryptAny, encryptLegacyForTests, RandomnessUnavailable } from '../../src/lib/sessionCipher';

declare const print: (s: string) => void;
const out = (s: string) => (typeof print === 'function' ? print(s) : console.log(s));
const fail = (m: string): never => { out('SMOKE_FAIL ' + m); throw new Error(m); };

let seed = 0x9e3779b9;
const xorshift = (n: number) => { const a = new Uint8Array(n); for (let i = 0; i < n; i++) { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; a[i] = seed & 0xff; } return a; };

function mem() {
  const kv = new Map<string, string>(); const kc = new Map<string, string>();
  return {
    kv, kc,
    secure: { async get(n: string) { return { ok: true as const, value: kc.get(n) ?? null }; }, async set(n: string, v: string) { kc.set(n, v); return { ok: true as const }; }, async delete(n: string) { kc.delete(n); return { ok: true as const }; } },
    blob: { async get(n: string) { return { ok: true as const, value: kv.get(n) ?? null }; }, async set(n: string, v: string) { kv.set(n, v); return { ok: true as const }; }, async remove(n: string) { kv.delete(n); return { ok: true as const }; } },
  };
}

(async () => {
  const g = globalThis as { crypto?: unknown };
  if (g.crypto !== undefined) fail('expected no crypto global under bare hermes');
  const KEY = 'sb-smoke-auth-token';
  const SESSION = '{"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.h","refresh_token":"r"}';

  // 1. No source: must be the named error, not ReferenceError.
  const m0 = mem();
  const noSource = createSessionStore({ secure: m0.secure, blob: m0.blob, random: (() => { throw new RandomnessUnavailable('smoke: unwired'); }) as never });
  try { await noSource.setItem(KEY, SESSION); fail('write succeeded without a source'); }
  catch (e) { if (!(e instanceof RandomnessUnavailable)) fail('wrong error type: ' + String(e)); if (!/react-native-get-random-values/.test(String((e as Error).message))) fail('error does not name the polyfill'); }

  // 2. Injected source: the real path executes on Hermes.
  const m = mem();
  const store = createSessionStore({ secure: m.secure, blob: m.blob, random: xorshift });
  await store.setItem(KEY, SESSION);
  if (blobFormat(m.kv.get(blobKeyName(KEY))!) !== 'v3') fail('not v3');
  if ((await store.getItem(KEY)) !== SESSION) fail('restore mismatch');
  const keyBytes = Uint8Array.from((m.kc.get(secureKeyName(KEY))!.match(/.{2}/g) ?? []).map((x) => parseInt(x, 16)));
  m.kv.set(blobKeyName(KEY), encryptLegacyForTests(keyBytes, SESSION));
  if ((await store.getItem(KEY)) !== SESSION) fail('legacy restore mismatch');
  if (blobFormat(m.kv.get(blobKeyName(KEY))!) !== 'v3') fail('legacy not migrated');
  const good = m.kv.get(blobKeyName(KEY))!;
  m.kv.set(blobKeyName(KEY), good.slice(0, -2) + (good.slice(-2) === '00' ? '01' : '00'));
  if ((await store.getItem(KEY)) !== null) fail('tampered blob accepted');
  try { decryptAny(keyBytes, 'v3.' + 'ab'.repeat(30)); fail('short v3 accepted'); } catch (e) { if (!(e instanceof Error) || !/undecryptable/.test(e.message)) fail('wrong short-v3 error'); }
  out('SMOKE_OK hermes session cipher+store');
})().catch((e) => { out('SMOKE_FAIL ' + String(e && (e as Error).stack || e)); });
