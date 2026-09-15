/**
 * tests/auth-sign-out.test.ts — CFT-611 (A-08c): one sign-out for the app,
 * which deactivates this device's push token first and never blocks on it.
 */

import { describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

vi.mock('@/src/lib/supabase', () => ({ supabase: {} }));

import { revokeDeviceToken, revokeThenSignOut, REVOKE_RPC, SIGN_OUT_REVOKE_TIMEOUT_MS, type RevokeDeps, type SignOutDeps } from '../src/lib/auth/signOut';
import { getRegisteredPushToken, setRegisteredPushToken } from '../src/lib/push/registeredToken';

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

describe('revoked_reason spelling (migration 128 legacy path, A 2026-09-14)', () => {
  it("writes 'signed_out' — the one value the server's own writer uses and 128 keys on", () => {
    const src = readFileSync(resolve(__dirname, '..', 'src/lib/auth/signOut.ts'), 'utf8');
    expect(src).toContain("revoked_reason: 'signed_out'");
    expect(src).not.toContain("revoked_reason: 'sign_out'");
  });
});

describe('128 G-2: the revoke goes through the server verb; the table write is the pre-128 fallback only', () => {
  function rdeps(over: Partial<RevokeDeps> = {}) {
    const calls: string[] = [];
    const d: RevokeDeps & { calls: string[] } = {
      calls,
      rpc: vi.fn(async () => { calls.push('rpc'); return { data: 1, error: null }; }),
      legacyUpdate: vi.fn(async () => { calls.push('legacy'); return 1; }),
      ...over,
    };
    return d;
  }

  it('uses the verb and never touches the table when the verb exists', async () => {
    const d = rdeps();
    expect(await revokeDeviceToken(d, 'tok', 'user-1')).toBe(1);
    expect(d.calls).toEqual(['rpc']);
    expect(d.rpc).toHaveBeenCalledWith('tok');
  });

  it('falls back to the direct update only when the verb is missing (PGRST202 = no 128 here)', async () => {
    const d = rdeps({ rpc: vi.fn(async () => ({ data: null, error: { code: 'PGRST202', message: 'Could not find the function public.revoke_push_token' } })) });
    expect(await revokeDeviceToken(d, 'tok', 'user-1')).toBe(1);
    expect(d.legacyUpdate).toHaveBeenCalledWith('tok', 'user-1');
  });

  it('a 42501 (or any other verb error) is a failure, never a reason to write the table', async () => {
    const d = rdeps({ rpc: vi.fn(async () => ({ data: null, error: { code: '42501', message: 'permission denied' } })) });
    await expect(revokeDeviceToken(d, 'tok', 'user-1')).rejects.toBeTruthy();
    expect(d.legacyUpdate).not.toHaveBeenCalled();
  });

  it('reads a count from the verb reply when it gives one', async () => {
    expect(await revokeDeviceToken(rdeps({ rpc: vi.fn(async () => ({ data: { revoked: 0 }, error: null })) }), 'tok', 'u')).toBe(0);
    expect(await revokeDeviceToken(rdeps({ rpc: vi.fn(async () => ({ data: 2, error: null })) }), 'tok', 'u')).toBe(2);
  });

  it('the live binding calls the verb by name before any push_tokens write', () => {
    const src = readFileSync(resolve(__dirname, '..', 'src/lib/auth/signOut.ts'), 'utf8');
    expect(REVOKE_RPC).toBe('revoke_push_token');
    const rpcAt = src.indexOf("supabase.rpc(REVOKE_RPC, { p_token: token })");
    const tableAt = src.indexOf(".from('push_tokens')");
    expect(rpcAt).toBeGreaterThan(-1);
    expect(tableAt).toBeGreaterThan(rpcAt);
    // The revoke columns appear once, inside the legacy fallback only.
    expect(src.match(/revoked_reason: 'signed_out'/g)?.length).toBe(1);
  });

  it('nothing else in app/ or src/ updates push_tokens, and the legacy touch writes only scoped columns', () => {
    const root = resolve(__dirname, '..');
    const { execSync } = require('node:child_process') as typeof import('node:child_process');
    const hits = execSync("grep -rl \"from('push_tokens')\" app src --include='*.ts' --include='*.tsx'", { cwd: root, encoding: 'utf8' })
      .trim().split('\n').filter(Boolean).sort();
    expect(hits).toEqual(['src/lib/auth/signOut.ts', 'src/lib/push/registerToken.ts']);
    const reg = readFileSync(resolve(root, 'src/lib/push/registerToken.ts'), 'utf8');
    // G-2 scope: platform, device_name, last_used, is_active. The touch writes two of them and nothing else.
    expect(reg).toContain(".update({ last_used: nowIso, is_active: true })");
    expect(reg.match(/\.update\(/g)?.length).toBe(1);
    expect(reg).not.toMatch(/revoked_at|revoked_reason|user_id:\s*[^,}]+\}\)\.eq/);
  });
});
