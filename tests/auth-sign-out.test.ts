/**
 * tests/auth-sign-out.test.ts — CFT-611 (A-08c): one sign-out for the app,
 * which deactivates this device's push token first and never blocks on it.
 */

import { describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

vi.mock('@/src/lib/supabase', () => ({ supabase: {} }));

import { revokeThenSignOut, SIGN_OUT_REVOKE_TIMEOUT_MS, type SignOutDeps } from '../src/lib/auth/signOut';
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
