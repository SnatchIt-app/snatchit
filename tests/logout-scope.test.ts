/**
 * tests/logout-scope.test.ts — K-2 (owner-approved 2026-09-15): ordinary
 * "Sign out" ends this device's session only; "Sign out of all devices" is a
 * separate, labelled act that revokes every push binding first (131's verb
 * where it exists) and ends every session. Not in the pinned candidate build.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';

vi.mock('@/src/lib/supabase', () => ({ supabase: { rpc: vi.fn(), from: vi.fn(), auth: { signOut: vi.fn(), getSession: vi.fn() } } }));

import { resolveSignOutOptions, revokeAllBindings, REVOKE_ALL_RPC, SIGN_OUT_REVOKE_TIMEOUT_MS } from '@/src/lib/auth/signOut';
import { SESSION_END_NOTICE } from '@/src/lib/auth/sessionEnd';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

describe('K-2: two named sign-outs', () => {
  it('ordinary sign-out is scope local with the user reason', () => {
    expect(resolveSignOutOptions()).toEqual({ scope: 'local', reason: 'user' });
    expect(resolveSignOutOptions({ scope: 'global', reason: 'password_changed' })).toEqual({ scope: 'global', reason: 'password_changed' });
  });

  it('signOutAllDevices revokes every binding first, ignores its failure, then signs out globally; one SDK call site', () => {
    const so = stripComments(read('src/lib/auth/signOut.ts'));
    expect(REVOKE_ALL_RPC).toBe('revoke_all_push_bindings');
    const rpcAt = so.indexOf('await supabase.rpc(REVOKE_ALL_RPC)');
    const outAt = so.indexOf("performSignOut({ scope: 'global', reason: opts.reason })");
    expect(rpcAt).toBeGreaterThan(-1);
    expect(outAt).toBeGreaterThan(rpcAt);
    expect(so.match(/supabase\.auth\.signOut\(/g)?.length).toBe(1);
    expect(so).toContain('await supabase.auth.signOut({ scope })');
    expect(so).not.toContain('signOutEverywhere');
  });

  it('every site uses the act it should: this-device for Sign out, profile and the stale-refresh path; all-devices for the row, deletion (K-1) and a password change', () => {
    const settings = read('app/settings/index.tsx');
    expect(settings).toContain('label="Sign out"');
    expect(settings).toContain('label="Sign out of all devices"');
    expect(settings).toContain('await signOutThisDevice()');
    expect(settings.match(/await signOutAllDevices\(\)/g)?.length).toBe(2);
    expect(read('app/(tabs)/profile.tsx')).toContain('await signOutThisDevice()');
    expect(read('src/hooks/useAuth.ts')).toContain('await signOutThisDevice()');
    expect(stripComments(read('app/(auth)/reset-password.tsx'))).toContain("signOutAllDevices({ reason: 'password_changed' })");
    for (const p of ['app/settings/index.tsx', 'app/(tabs)/profile.tsx', 'app/(auth)/reset-password.tsx', 'src/hooks/useAuth.ts']) {
      expect(read(p)).not.toContain('signOutEverywhere');
    }
  });

  it('F-K2-1: the all-devices revoke is bounded — a hanging verb yields null within the budget and never blocks the sign-out', async () => {
    const started = Date.now();
    const hung = await revokeAllBindings(() => new Promise(() => {}), 20);
    expect(hung).toBeNull();
    expect(Date.now() - started).toBeLessThan(1_000);
    expect(SIGN_OUT_REVOKE_TIMEOUT_MS).toBeLessThanOrEqual(5_000);
    expect(await revokeAllBindings(async () => ({ data: { revoked: 2 }, error: null }))).toBe(2);
    expect(await revokeAllBindings(async () => ({ data: null, error: { code: 'PGRST202', message: 'Could not find the function public.revoke_all_push_bindings' } }))).toBeNull();
    expect(await revokeAllBindings(async () => { throw new Error('network'); })).toBeNull();
  });

  it('F-K2-2: a call that rejects after the timeout won is not an unhandled rejection', async () => {
    const unhandled: unknown[] = [];
    const onUnhandled = (reason: unknown) => { unhandled.push(reason); };
    process.on('unhandledRejection', onUnhandled);
    try {
      let rejectLater: (e: Error) => void = () => {};
      const late = new Promise<{ data: unknown; error: null }>((_, rej) => { rejectLater = rej; });
      expect(await revokeAllBindings(() => late, 10)).toBeNull();
      rejectLater(new Error('aborted fetch'));
      await new Promise((res) => setTimeout(res, 20));
      expect(unhandled).toEqual([]);
    } finally {
      process.off('unhandledRejection', onUnhandled);
    }
  });

  it('the login screen explains a password change', () => {
    expect(SESSION_END_NOTICE.password_changed).toMatch(/new password/i);
  });
});
