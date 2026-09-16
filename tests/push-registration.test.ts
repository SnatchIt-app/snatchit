/**
 * tests/push-registration.test.ts — migration 128 client half (A-08d), built
 * against A's reviewed contract of 2026-09-14 as amended after the adversarial
 * review (128 @f7b31ad: rotation reverted, recovery is delete-then-register,
 * precondition terminal; NOT frozen). 128 is applied nowhere; the legacy path
 * is the live path and must stay non-takeover.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';

import {
  DEVICE_SECRET_KEY, DEVICE_SECRET_LENGTH, generateDeviceSecret, getOrCreateDeviceSecret,
  isWellFormedSecret, toBase64Url, type SecretStore,
} from '@/src/lib/push/deviceSecret';
import {
  BACKOFF_MAX_MS, REGISTRATION_REMEDY, REGISTRATION_TTL_MS, backoffMs, classifyRegistrationError,
  decideRegistration, recordFailure, type RegistrationFailure, type RegistrationRecord,
} from '@/src/lib/push/registration';
import { registerLegacy, registerRpcWithRecovery, registerWithRpc, type RegisterDeps } from '@/src/lib/push/registerToken';
import { EMPTY_REGISTRATION_STATE, loadRegistrationState, saveRegistrationState } from '@/src/lib/push/registrationStore';

// Hoisted by vitest above the imports: registerToken.ts imports the supabase client.
vi.mock('@/src/lib/supabase', () => ({ supabase: { rpc: vi.fn(), from: vi.fn() } }));

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const seq = (n: number) => Uint8Array.from({ length: n }, (_, i) => (i * 37 + 11) & 255);

function memStore(initial: Record<string, string> = {}): SecretStore & { data: Record<string, string> } {
  const data = { ...initial };
  return { data, get: async (k) => data[k] ?? null, set: async (k, v) => { data[k] = v; } };
}

describe('device secret — per device, CSPRNG, never guessable', () => {
  it('base64url encodes without padding (known vectors)', () => {
    expect(toBase64Url(new Uint8Array([]))).toBe('');
    expect(toBase64Url(new Uint8Array([0xfb]))).toBe('-w');
    expect(toBase64Url(new Uint8Array([0xfb, 0xff]))).toBe('-_8');
    expect(toBase64Url(new Uint8Array([0xfb, 0xff, 0xbf]))).toBe('-_-_');
    expect(toBase64Url(new Uint8Array([77, 97, 110]))).toBe('TWFu');
  });

  it('is 43 characters of base64url from 32 bytes, inside the server\'s 16–512', () => {
    const s = generateDeviceSecret(seq);
    expect(s).toHaveLength(DEVICE_SECRET_LENGTH);
    expect(s).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(isWellFormedSecret(s)).toBe(true);
    expect(s.length).toBeGreaterThanOrEqual(16);
    expect(s.length).toBeLessThanOrEqual(512);
  });

  it('is created once and then reused — sign-out and account switch never touch it', async () => {
    const store = memStore();
    const a = await getOrCreateDeviceSecret(store, seq);
    const b = await getOrCreateDeviceSecret(store, seq);
    expect(a).toEqual({ ok: true, secret: expect.any(String), created: true });
    expect(b).toEqual({ ok: true, secret: (a as any).secret, created: false });
    expect(store.data[DEVICE_SECRET_KEY]).toBe((a as any).secret);
    // nothing in the module can delete, clear or rotate it
    const src = stripComments(read('src/lib/push/deviceSecret.ts'));
    expect(src).not.toMatch(/delete\(|rotate|clear/i);
    expect(src).not.toMatch(/store\.delete|removeItem/);
  });

  it('a malformed stored value is replaced rather than sent', async () => {
    const store = memStore({ [DEVICE_SECRET_KEY]: 'short' });
    const r = await getOrCreateDeviceSecret(store, seq);
    expect(r.ok).toBe(true);
    expect(store.data[DEVICE_SECRET_KEY]).not.toBe('short');
    expect(isWellFormedSecret(store.data[DEVICE_SECRET_KEY])).toBe(true);
  });

  it('never throws: an unavailable store or RNG is a reason, not a crash', async () => {
    const broken: SecretStore = { get: async () => { throw new Error('keychain'); }, set: async () => {} };
    expect(await getOrCreateDeviceSecret(broken, seq)).toEqual({ ok: false, reason: 'store_unavailable' });
    const noRng = () => { throw new Error('no crypto'); };
    expect(await getOrCreateDeviceSecret(memStore(), noRng as any)).toEqual({ ok: false, reason: 'rng_unavailable' });
    const wrongShape = () => new Uint8Array(3);
    expect(await getOrCreateDeviceSecret(memStore(), wrongShape)).toEqual({ ok: false, reason: 'rng_unavailable' });
  });

  it('the live store and the hook use the device CSPRNG, never Math.random, and never log the secret', () => {
    const hook = stripComments(read('src/hooks/usePushToken.ts'));
    expect(hook).toContain("import { deviceRandomBytes } from '@/src/lib/randomness'");
    expect(hook).toContain('getOrCreateDeviceSecret(secureSecretStore, deviceRandomBytes)');
    expect(hook).not.toMatch(/Math\.random/);
    expect(hook).not.toMatch(/console\.\w+\([^)]*secret/i);
    expect(hook).not.toMatch(/console\.\w+\([^)]*\btoken\b/);
    expect(read('src/lib/push/deviceSecretStore.ts')).toContain("from 'expo-secure-store'");
  });
});

describe('registration decisions', () => {
  const now = 1_000_000_000;
  const rec = (over: Partial<RegistrationRecord> = {}): RegistrationRecord =>
    ({ token: 'tok', userId: 'u1', method: 'rpc', outcome: 'registered', at: now - 1000, ...over });

  it('skips when signed out or without a token', () => {
    expect(decideRegistration({ userId: null, token: 'tok', record: null, failure: null, rpcAvailable: undefined, now }).reason).toBe('signed_out');
    expect(decideRegistration({ userId: 'u1', token: null, record: null, failure: null, rpcAvailable: undefined, now }).reason).toBe('no_token');
  });

  it('registers first time, on a new token, on an account switch (the rebind), on a method change, and when stale', () => {
    const base = { userId: 'u1', token: 'tok', failure: null, rpcAvailable: undefined as boolean | undefined, now };
    expect(decideRegistration({ ...base, record: null })).toMatchObject({ action: 'register', method: 'rpc', reason: 'first' });
    expect(decideRegistration({ ...base, record: rec({ token: 'old' }) }).reason).toBe('token_changed');
    expect(decideRegistration({ ...base, record: rec({ userId: 'u0' }) }).reason).toBe('account_changed');
    expect(decideRegistration({ ...base, record: rec({ method: 'legacy' }) }).reason).toBe('method_changed');
    expect(decideRegistration({ ...base, record: rec({ at: now - REGISTRATION_TTL_MS - 1 }) }).reason).toBe('stale');
    expect(decideRegistration({ ...base, record: rec() })).toMatchObject({ action: 'skip', reason: 'fresh' });
  });

  it('uses the legacy method only once the RPC is known to be missing', () => {
    const base = { userId: 'u1', token: 'tok', record: null, failure: null, now };
    expect(decideRegistration({ ...base, rpcAvailable: undefined }).method).toBe('rpc');
    expect(decideRegistration({ ...base, rpcAvailable: true }).method).toBe('rpc');
    expect(decideRegistration({ ...base, rpcAvailable: false }).method).toBe('legacy');
  });

  it('backs off exponentially after a transient failure and retries once elapsed', () => {
    expect(backoffMs(1)).toBe(30_000);
    expect(backoffMs(2)).toBe(60_000);
    expect(backoffMs(3)).toBe(120_000);
    expect(backoffMs(40)).toBe(BACKOFF_MAX_MS);
    const f: RegistrationFailure = { kind: 'network', userId: 'u1', token: 'tok', method: 'rpc', at: now, attempts: 2 };
    const base = { userId: 'u1', token: 'tok', record: null, failure: f, rpcAvailable: true };
    expect(decideRegistration({ ...base, now: now + 59_999 })).toMatchObject({ action: 'wait', reason: 'backoff', retryAt: now + 60_000 });
    expect(decideRegistration({ ...base, now: now + 60_000 })).toMatchObject({ action: 'register', reason: 'retry' });
  });

  it('"bound to another account" is terminal on both methods, until the account, token or method changes', () => {
    const f = (method: 'rpc' | 'legacy'): RegistrationFailure => ({ kind: 'bound_to_other', userId: 'u1', token: 'tok', method, at: now - 10 * 24 * 3600 * 1000, attempts: 1 });
    expect(decideRegistration({ userId: 'u1', token: 'tok', record: null, failure: f('rpc'), rpcAvailable: true, now })).toMatchObject({ action: 'wait', reason: 'bound_to_other' });
    expect(decideRegistration({ userId: 'u1', token: 'tok', record: null, failure: f('legacy'), rpcAvailable: false, now })).toMatchObject({ action: 'wait', reason: 'bound_to_other' });
    // the next account on this device starts fresh — that is the rebind
    expect(decideRegistration({ userId: 'u2', token: 'tok', record: null, failure: f('rpc'), rpcAvailable: true, now })).toMatchObject({ action: 'register', reason: 'first' });
    expect(decideRegistration({ userId: 'u1', token: 'tok2', record: null, failure: f('rpc'), rpcAvailable: true, now })).toMatchObject({ action: 'register', reason: 'first' });
    // a legacy failure does not block the rpc method once 128 is available
    expect(decideRegistration({ userId: 'u1', token: 'tok', record: null, failure: f('legacy'), rpcAvailable: true, now })).toMatchObject({ action: 'register' });
    expect(REGISTRATION_REMEDY.bound_to_other).toMatch(/Sign in to that account and sign out of this device, or reinstall/); // 131 S-13 (D's wording)
  });

  it('a precondition refusal is terminal until the inputs change — never a timer', () => {
    const f: RegistrationFailure = { kind: 'precondition', userId: 'u1', token: 'tok', method: 'rpc', at: now - 7 * 24 * 3600 * 1000, attempts: 1 };
    expect(decideRegistration({ userId: 'u1', token: 'tok', record: null, failure: f, rpcAvailable: true, now })).toMatchObject({ action: 'wait', reason: 'precondition' });
    expect(decideRegistration({ userId: 'u1', token: 'tok', record: null, failure: f, rpcAvailable: true, now }).retryAt).toBeUndefined();
    expect(decideRegistration({ userId: 'u1', token: 'tok2', record: null, failure: f, rpcAvailable: true, now })).toMatchObject({ action: 'register' });
    expect(decideRegistration({ userId: 'u1', token: 'tok', record: null, failure: f, rpcAvailable: false, now })).toMatchObject({ action: 'register', method: 'legacy' });
  });

  it('an rpc_missing failure is spent once the method switched to legacy', () => {
    const f: RegistrationFailure = { kind: 'rpc_missing', userId: 'u1', token: 'tok', method: 'rpc', at: now, attempts: 1 };
    expect(decideRegistration({ userId: 'u1', token: 'tok', record: null, failure: f, rpcAvailable: false, now })).toMatchObject({ action: 'register', method: 'legacy', reason: 'first' });
  });

  it('recordFailure counts consecutive failures of one kind for one attempt only', () => {
    const ctx = { userId: 'u1', token: 'tok', method: 'rpc' as const, now };
    const a = recordFailure(null, 'network', ctx);
    const b = recordFailure(a, 'network', { ...ctx, now: now + 1 });
    const c = recordFailure(b, 'unknown', { ...ctx, now: now + 2 });
    const d = recordFailure(b, 'network', { ...ctx, userId: 'u2', now: now + 3 });
    expect([a.attempts, b.attempts, c.attempts, d.attempts]).toEqual([1, 2, 1, 1]);
  });
});

describe('error classification follows the contract', () => {
  it('maps every named SQLSTATE/message; 42501 bound/wrong-secret/legacy-other is ONE branch', () => {
    expect(classifyRegistrationError({ code: 'PGRST202', message: 'Could not find the function public.register_push_token' })).toBe('rpc_missing');
    expect(classifyRegistrationError({ code: '42883', message: 'function does not exist' })).toBe('rpc_missing');
    expect(classifyRegistrationError({ code: '42501', message: 'not_authenticated' })).toBe('auth');
    expect(classifyRegistrationError({ code: '42501', message: 'insufficient_privilege: token is bound to another account' })).toBe('bound_to_other');
    expect(classifyRegistrationError({ code: '23505', message: 'duplicate key value violates unique constraint "push_tokens_token_key"' })).toBe('bound_to_other');
    expect(classifyRegistrationError({ code: 'P0001', message: 'precondition_failed: device secret length' })).toBe('precondition');
    expect(classifyRegistrationError({ code: 'P0001', message: 'precondition_failed: platform must be ios or android' })).toBe('precondition');
    expect(classifyRegistrationError({ code: 'P0001', message: 'precondition_failed: platform is required' })).toBe('precondition');
    expect(classifyRegistrationError({ message: 'Network request failed' })).toBe('network');
    expect(classifyRegistrationError({ status: 401, message: 'JWT expired' })).toBe('auth');
    expect(classifyRegistrationError({ message: 'weird' })).toBe('unknown');
    expect(classifyRegistrationError(null)).toBe('unknown');
  });
});

function fakeDeps(over: Partial<RegisterDeps> = {}) {
  const calls: string[] = [];
  const deps: RegisterDeps = {
    rpc: async () => { calls.push('rpc'); return { data: { token_id: 't-1', outcome: 'registered', platform: 'ios' }, error: null }; },
    legacySelect: async () => { calls.push('select'); return { data: null, error: null }; },
    legacyTouch: async () => { calls.push('touch'); return { error: null }; },
    legacyInsert: async () => { calls.push('insert'); return { error: null }; },
    deleteOwn: async () => { calls.push('delete'); return { error: null }; },
    confirmChallenge: async () => { calls.push('confirm'); return { data: null, error: null }; },
    requestChallenge: async () => { calls.push('request'); return { data: null, error: null }; },
    ...over,
  };
  return { deps, calls };
}

describe('registerWithRpc — the p_ names, every outcome, every error', () => {
  it('sends the four p_ parameters and returns the server outcome', async () => {
    let sent: unknown;
    const { deps } = fakeDeps({ rpc: async (args) => { sent = args; return { data: { token_id: 'x', outcome: 'rebound', platform: 'ios' }, error: null }; } });
    const r = await registerWithRpc(deps, { token: 'tok', platform: 'ios', secret: 's'.repeat(43), deviceName: 'Jose’s iPhone' });
    expect(sent).toEqual({ p_token: 'tok', p_platform: 'ios', p_device_secret: 's'.repeat(43), p_device_name: 'Jose’s iPhone' });
    expect(r).toEqual({ ok: true, method: 'rpc', outcome: 'rebound', tokenId: 'x', contractVersion: null });
  });
  it('classifies the error and never throws', async () => {
    const { deps } = fakeDeps({ rpc: async () => ({ data: null, error: { code: '42501', message: 'insufficient_privilege: token is bound to another account' } }) });
    expect(await registerWithRpc(deps, { token: 'tok', platform: 'ios', secret: 's'.repeat(43), deviceName: null })).toEqual({ ok: false, kind: 'bound_to_other' });
    const { deps: throwing } = fakeDeps({ rpc: async () => { throw { message: 'Network request failed' }; } });
    expect(await registerWithRpc(throwing, { token: 'tok', platform: 'ios', secret: 's'.repeat(43), deviceName: null })).toEqual({ ok: false, kind: 'network' });
    const { deps: odd } = fakeDeps({ rpc: async () => ({ data: { nope: true }, error: null }) });
    expect(await registerWithRpc(odd, { token: 'tok', platform: 'ios', secret: 's'.repeat(43), deviceName: null })).toEqual({ ok: false, kind: 'unknown' });
  });
});

describe('registerRpcWithRecovery — delete-then-register, gated, never speculative', () => {
  const args = { token: 'tok', platform: 'ios' as const, secret: 's'.repeat(43), deviceName: null };
  const ownRow = async () => ({ data: { id: 'row-9' }, error: null });

  it('recovers only when the secret is fresh AND this binding was registered via the RPC before AND a row we own exists', async () => {
    const { deps, calls } = fakeDeps({ legacySelect: ownRow });
    deps.legacySelect = async () => { calls.push('select'); return ownRow(); };
    const r = await registerRpcWithRecovery(deps, args, { freshSecret: true, previouslyRpcForThisBinding: true });
    expect(r).toMatchObject({ ok: true, method: 'rpc', recovered: true });
    expect(calls).toEqual(['select', 'delete', 'rpc']);
  });

  it('never deletes when the secret was stored, when the binding was never RPC-registered, or when no own row exists', async () => {
    for (const ctx of [
      { freshSecret: false, previouslyRpcForThisBinding: true },
      { freshSecret: true, previouslyRpcForThisBinding: false },
      { freshSecret: false, previouslyRpcForThisBinding: false },
    ]) {
      const { deps, calls } = fakeDeps({ legacySelect: ownRow });
      const r = await registerRpcWithRecovery(deps, args, ctx);
      expect(r).toMatchObject({ ok: true, method: 'rpc' });
      expect((r as any).recovered).toBeUndefined();
      expect(calls, JSON.stringify(ctx)).toEqual(['rpc']);
    }
    const { deps, calls } = fakeDeps(); // select finds nothing we own
    deps.legacySelect = async () => { calls.push('select'); return { data: null, error: null }; };
    await registerRpcWithRecovery(deps, args, { freshSecret: true, previouslyRpcForThisBinding: true });
    expect(calls).toEqual(['select', 'rpc']);
  });

  it('a failed delete stops the recovery and is classified, never followed by a register', async () => {
    const { deps, calls } = fakeDeps({ legacySelect: ownRow, deleteOwn: async () => ({ error: { message: 'Network request failed' } }) });
    const r = await registerRpcWithRecovery(deps, args, { freshSecret: true, previouslyRpcForThisBinding: true });
    expect(r).toEqual({ ok: false, kind: 'network' });
    expect(calls).not.toContain('rpc');
  });

  it('the live delete is by the row id we selected, never by token', () => {
    const src = stripComments(read('src/lib/push/registerToken.ts'));
    expect(src).toMatch(/\.delete\(\)\.eq\('id', id\)/);
    expect(src).not.toMatch(/\.delete\(\)\s*\.eq\('token'/);
    expect(src.split('.delete()').length - 1).toBe(1);
  });
});

describe('registerLegacy — Build 16 behaviour, insert-only, non-takeover', () => {
  it('touches the caller\'s own row when present', async () => {
    const { deps, calls } = fakeDeps();
    deps.legacySelect = async () => { calls.push('select'); return { data: { id: 'row-1' }, error: null }; };
    const r = await registerLegacy(deps, { userId: 'u1', token: 'tok', platform: 'ios', nowIso: 'now' });
    expect(r).toEqual({ ok: true, method: 'legacy', outcome: 'refreshed', tokenId: 'row-1' });
    expect(calls).toEqual(['select', 'touch']);
  });
  it('inserts when absent, and STOPS on conflict — another account\'s row is never claimed', async () => {
    const { deps, calls } = fakeDeps();
    deps.legacyInsert = async () => { calls.push('insert'); return { error: { code: '23505', message: 'duplicate key value violates unique constraint' } }; };
    const r = await registerLegacy(deps, { userId: 'u1', token: 'tok', platform: 'ios', nowIso: 'now' });
    expect(r).toEqual({ ok: false, kind: 'bound_to_other' });
    expect(calls).toEqual(['select', 'insert']);
  });
  it('the live bindings never upsert, never update by token, never call notify.register_push_token', () => {
    const src = stripComments(read('src/lib/push/registerToken.ts'));
    expect(src).not.toMatch(/\.upsert\(/);
    expect(src).not.toMatch(/notify\.register_push_token|schema\('notify'\)/);
    expect(src).toMatch(/\.update\(\{ last_used: nowIso, is_active: true \}\)\.eq\('id', id\)/);
    expect(src).not.toMatch(/\.update\([^)]*\)\s*\.eq\('token'/);
    expect(src).toContain("supabase.rpc('register_push_token', args)");
  });
});

describe('persisted state holds no secret, and the hook is wired to the contract', () => {
  it('load/save round-trip, tolerant of garbage', async () => {
    const mem: Record<string, string> = {};
    const kv = { getItem: async (k: string) => mem[k] ?? null, setItem: async (k: string, v: string) => { mem[k] = v; } };
    expect(await loadRegistrationState(kv)).toEqual(EMPTY_REGISTRATION_STATE);
    const record: RegistrationRecord = { token: 'tok', userId: 'u1', method: 'legacy', outcome: 'registered', at: 1 };
    await saveRegistrationState({ record, failure: null }, kv);
    expect(await loadRegistrationState(kv)).toEqual({ record, failure: null });
    mem[Object.keys(mem)[0]] = '{not json';
    expect(await loadRegistrationState(kv)).toEqual(EMPTY_REGISTRATION_STATE);
    expect(JSON.stringify(record)).not.toMatch(/secret/);
  });

  it('the contract citation is the amended one: rotation is out, recovery is delete-then-register', () => {
    for (const rel of ['src/lib/push/deviceSecret.ts', 'src/lib/push/registration.ts', 'src/lib/push/registerToken.ts']) {
      const src = read(rel);
      expect(src, rel).not.toContain('4e29fde');
    }
    expect(read('src/lib/push/deviceSecret.ts')).toContain('THE STORED HASH IS NEVER REPLACED');
    expect(read('src/lib/push/registration.ts')).toContain('`refreshed` does NOT prove the secret matches');
  });

  it('the hook: rpc first, PGRST202 → legacy once per process, records success and failure, retries on foreground', () => {
    const hook = stripComments(read('src/hooks/usePushToken.ts'));
    expect(hook).toContain("if (!result.ok && result.kind === 'rpc_missing') {");
    // the only lost-secret signal is the device finding none; recovery goes through the gated wrapper
    expect(hook).toContain('{ freshSecret: secret.created, previouslyRpcForThisBinding }');
    expect(hook).toMatch(/const previouslyRpcForThisBinding =\s*state\.record\?\.method === 'rpc' && state\.record\.token === token && state\.record\.userId === uid;/);
    expect(hook).not.toMatch(/registerWithRpc\(/);
    expect(hook).not.toMatch(/rotate/i);
    expect(hook).toContain('rpcAvailable = false;');
    expect(hook).toContain('await saveRegistrationState({ record, failure: null });');
    expect(hook).toContain('const failure = recordFailure(state.failure, result.kind, { userId: uid, token, method, now });');
        expect(hook).toContain("AppState.addEventListener('change', (st) => {"); // v3: the listener also drives the challenge on foreground/background
    expect(hook).toContain('setRegisteredPushToken(token);');
    // 131 (provisional): the only sign-out the hook performs is the forced local re-auth on session_stale.
    expect(hook).not.toMatch(/revoke/);
    expect(hook.match(/signOutThisDevice\(/g)?.length).toBe(1);
  });

  it('sign-out revokes through public.revoke_push_token (129) with the token only — never the secret, never a table write', () => {
    const so = read('src/lib/auth/signOut.ts');
    expect(so).toContain("supabase.rpc(REVOKE_RPC, { p_token: token })");
    expect(so).not.toMatch(/secret|register_push_token|\.from\('push_tokens'\)/);
  });

  it('contract v2: "too many registration attempts" backs off for the server window and retries; other preconditions stay terminal', () => {
    expect(classifyRegistrationError({ code: 'P0001', message: 'precondition_failed: too many registration attempts' })).toBe('rate_limited');
    const failure = { kind: 'rate_limited' as const, userId: 'u', token: 't', method: 'rpc' as const, at: 1_000, attempts: 1 };
    const base = { userId: 'u', token: 't', record: null, rpcAvailable: true };
    const early = decideRegistration({ ...base, failure, now: 1_000 + 599_000, coldLaunch: true });
    expect(early.action).toBe('wait');
    expect(early.retryAt).toBe(1_000 + 600_000);
    expect(decideRegistration({ ...base, failure, now: 1_000 + 600_001 }).action).toBe('register');
    const shape = { ...failure, kind: 'precondition' as const };
    expect(decideRegistration({ ...base, failure: shape, now: 1_000 + 7 * 24 * 3_600_000, coldLaunch: true }).action).toBe('wait');
  });

  it('Settings › Notifications explains a device that is not registered for this account', () => {
    const n = read('app/settings/notifications.tsx');
    expect(n).toContain('subscribeRegistrationStatus(setRegistration)');
    expect(n).toContain('REGISTRATION_REMEDY[registration.kind]');
  });
});
