/**
 * tests/auth-sign-out.test.ts — CFT-611 (A-08c): one sign-out for the app,
 * which deactivates this device's push token first and never blocks on it.
 */

import { describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

vi.mock('@/src/lib/supabase', () => ({ supabase: {} }));

import { revokeDeviceToken, revokeThenSignOut, REVOKE_RPC, REVOKE_RPC_SCHEMA, SIGN_OUT_REVOKE_TIMEOUT_MS, type RevokeDeps, type SignOutDeps } from '../src/lib/auth/signOut';
import { getRegisteredPushToken, setRegisteredPushToken } from '../src/lib/push/registeredToken';

const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

function deps(over: Partial<SignOutDeps> = {}) {
  const calls: string[] = [];
  const d: SignOutDeps & { calls: string[] } = {
    calls,
    getToken: () => 'ExponentPushToken[abc]',
    getUserId: async () => 'user-1',
    revoke: vi.fn(async () => { calls.push('revoke'); return 1; }),
    signOut: vi.fn(async () => { calls.push('signOut'); }),
    timeoutMs: 50,
    ...over,
  };
  return d;
}

describe('sign-out deactivates this device token first', () => {
  it('revokes before signing out, with the token and the user', async () => {
    const d = deps();
    const r = await revokeThenSignOut(d);
    expect(r.revoke).toBe('revoked');
    expect(d.calls).toEqual(['revoke', 'signOut']);
    expect(d.revoke).toHaveBeenCalledWith('ExponentPushToken[abc]', 'user-1');
  });

  it('reports no_match when RLS hides the row (a token bound to another account)', async () => {
    const d = deps({ revoke: vi.fn(async () => 0) });
    const r = await revokeThenSignOut(d);
    expect(r.revoke).toBe('no_match');
    expect(d.signOut).toHaveBeenCalled();
  });

  it('skips the revoke without a token or a session, and still signs out', async () => {
    const a = deps({ getToken: () => null });
    expect((await revokeThenSignOut(a)).revoke).toBe('no_token');
    expect(a.revoke).not.toHaveBeenCalled();
    expect(a.signOut).toHaveBeenCalled();

    const b = deps({ getUserId: async () => null });
    expect((await revokeThenSignOut(b)).revoke).toBe('no_session');
    expect(b.revoke).not.toHaveBeenCalled();
    expect(b.signOut).toHaveBeenCalled();
  });

  it('never blocks sign-out on a failed or slow revoke', async () => {
    const failing = deps({ revoke: vi.fn(async () => { throw new Error('boom'); }) });
    expect((await revokeThenSignOut(failing)).revoke).toBe('failed');
    expect(failing.signOut).toHaveBeenCalled();

    const slow = deps({ revoke: vi.fn(() => new Promise<number>(() => {})), timeoutMs: 20 });
    const r = await revokeThenSignOut(slow);
    expect(r.revoke).toBe('timed_out');
    expect(slow.signOut).toHaveBeenCalled();
  });

  it('bounds the wait by a short default timeout', () => {
    expect(SIGN_OUT_REVOKE_TIMEOUT_MS).toBeLessThanOrEqual(5_000);
  });

  it('remembers and forgets the registered token', () => {
    setRegisteredPushToken('ExponentPushToken[x]');
    expect(getRegisteredPushToken()).toBe('ExponentPushToken[x]');
    setRegisteredPushToken(null);
    expect(getRegisteredPushToken()).toBeNull();
  });
});

describe('every sign-out site uses the helper', () => {
  const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
  const SITES = ['app/settings/index.tsx', 'app/(tabs)/profile.tsx', 'app/(auth)/reset-password.tsx', 'src/hooks/useAuth.ts'];

  it('no screen or hook calls supabase.auth.signOut directly', () => {
    for (const p of SITES) {
      expect(read(p)).not.toMatch(/supabase\.auth\.signOut\(/);
      expect(read(p)).toMatch(/signOutEverywhere\(/);
    }
  });

  it('the privacy page describes an attempt, not a guarantee', () => {
    const src = read('app/settings/privacy.tsx');
    expect(src).not.toMatch(/automatically marked inactive/i);
    expect(src).toMatch(/asks our servers to deactivate/i);
    expect(src).toMatch(/may stay active/i);
  });

  it('the registration hook hands the token to sign-out', () => {
    expect(read('src/hooks/usePushToken.ts')).toMatch(/setRegisteredPushToken\(token\)/);
  });
});

describe('contract v2 §2.4: sign-out revokes through notify.revoke_push_token and never writes revoked_*', () => {
  function rdeps(over: Partial<RevokeDeps> = {}) {
    const d: RevokeDeps = { rpc: vi.fn(async () => ({ data: { revoked: 1 }, error: null })), ...over };
    return d;
  }

  it('uses the verb with the token only and reads { revoked }', async () => {
    const d = rdeps();
    expect(await revokeDeviceToken(d, 'tok')).toBe(1);
    expect(d.rpc).toHaveBeenCalledWith('tok');
    expect(await revokeDeviceToken(rdeps({ rpc: vi.fn(async () => ({ data: { revoked: 0 }, error: null })) }), 'tok')).toBe(0);
  });

  it('a reply that asserts nothing counts as nothing revoked', async () => {
    expect(await revokeDeviceToken(rdeps({ rpc: vi.fn(async () => ({ data: null, error: null })) }), 'tok')).toBe(0);
    expect(await revokeDeviceToken(rdeps({ rpc: vi.fn(async () => ({ data: { ok: true }, error: null })) }), 'tok')).toBe(0);
  });

  it('every verb error is a failure — a missing verb or unexposed schema included; the table is never written', async () => {
    for (const error of [
      { code: 'PGRST202', message: 'Could not find the function notify.revoke_push_token' },
      { code: 'PGRST106', message: 'The schema must be one of the following: public' },
      { code: '42501', message: 'permission denied' },
    ]) {
      await expect(revokeDeviceToken(rdeps({ rpc: vi.fn(async () => ({ data: null, error })) }), 'tok')).rejects.toBeTruthy();
    }
  });

  it('clears the registration record after the revoke and before the sign-out, and never blocks on it', async () => {
    const d = deps({ clearRegistration: vi.fn(async () => { d.calls.push('clear'); }) });
    await revokeThenSignOut(d);
    expect(d.calls).toEqual(['revoke', 'clear', 'signOut']);
    const failing = deps({ clearRegistration: vi.fn(async () => { throw new Error('storage'); }) });
    expect((await revokeThenSignOut(failing)).revoke).toBe('revoked');
    expect(failing.signOut).toHaveBeenCalled();
  });

  it('the live binding calls the verb through the notify schema and holds no push_tokens write', () => {
    const src = stripComments(readFileSync(resolve(__dirname, '..', 'src/lib/auth/signOut.ts'), 'utf8'));
    expect(REVOKE_RPC_SCHEMA).toBe('notify');
    expect(REVOKE_RPC).toBe('revoke_push_token');
    expect(src).toContain("supabase.schema(REVOKE_RPC_SCHEMA).rpc(REVOKE_RPC, { p_token: token })");
    expect(src).not.toContain(".from('push_tokens')");
    expect(src).not.toMatch(/revoked_reason|revoked_at/);
    expect(src).toContain('clearRegistration: () => saveRegistrationState(EMPTY_REGISTRATION_STATE)');
  });

  it('the only push_tokens writer left is the registration module, and its touch writes scoped columns only', () => {
    const root = resolve(__dirname, '..');
    const { execSync } = require('node:child_process') as typeof import('node:child_process');
    const hits = execSync("grep -rl \"from('push_tokens')\" app src --include='*.ts' --include='*.tsx'", { cwd: root, encoding: 'utf8' })
      .trim().split('\n').filter(Boolean).sort();
    expect(hits).toEqual(['src/lib/push/registerToken.ts']);
    const reg = stripComments(readFileSync(resolve(root, 'src/lib/push/registerToken.ts'), 'utf8'));
    // v2 §3 UPDATE scope: platform, device_name, last_used, is_active.
    expect(reg).toContain(".update({ last_used: nowIso, is_active: true })");
    expect(reg.match(/\.update\(/g)?.length).toBe(1);
    expect(reg).not.toMatch(/revoked_at|revoked_reason|device_secret_hash/);
    expect(reg).toContain(".select('id')");
  });
});
