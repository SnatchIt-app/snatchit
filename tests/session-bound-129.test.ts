/**
 * tests/session-bound-129.test.ts — 129 (PROVISIONAL) client delta for A's
 * session-bound push bindings design (docs/release/SESSION_BOUND_PUSH_BINDINGS_129_DESIGN.md §6).
 * Not part of the Friday candidate.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';

vi.mock('@/src/lib/supabase', () => ({ supabase: { rpc: vi.fn(), from: vi.fn(), schema: vi.fn(), auth: { signOut: vi.fn(), getSession: vi.fn() } } }));

import { classifyRegistrationError, decideRegistration, REGISTRATION_REMEDY } from '@/src/lib/push/registration';
import { handleSessionStale, resetSessionStaleForTests } from '@/src/lib/push/sessionStale';
import { SESSION_END_NOTICE, sessionEndNotice } from '@/src/lib/auth/sessionEnd';
import { resolveSignOutOptions, REVOKE_ALL_RPC } from '@/src/lib/auth/signOut';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

describe('P3 on the client: a session that predates a credential change is terminal until re-auth', () => {
  it('classifies the exact 42501 message as session_stale, not bound_to_other', () => {
    expect(classifyRegistrationError({ code: '42501', message: 'insufficient_privilege: session predates a credential change' })).toBe('session_stale');
    expect(classifyRegistrationError({ code: '42501', message: 'insufficient_privilege: token is bound to another account' })).toBe('bound_to_other');
  });

  it('waits (no retry timer, cold launch included) while the failure stands', () => {
    const failure = { kind: 'session_stale' as const, userId: 'u', token: 't', method: 'rpc' as const, at: 1_000, attempts: 1 };
    const d = decideRegistration({ userId: 'u', token: 't', record: null, failure, rpcAvailable: true, now: 10 ** 9, coldLaunch: true });
    expect(d).toEqual({ action: 'wait', method: 'rpc', reason: 'session_stale' });
  });

  it('has a remedy the Notifications screen can show', () => {
    expect(REGISTRATION_REMEDY.session_stale).toMatch(/password was changed/i);
  });

  it('handleSessionStale: clear record → mark credential_change → local sign-out, once per process', async () => {
    resetSessionStaleForTests();
    const calls: string[] = [];
    const deps = {
      clearRegistration: vi.fn(async () => { calls.push('clear'); }),
      markEnd: vi.fn((r: 'credential_change') => { calls.push(`mark:${r}`); }),
      signOutLocal: vi.fn(async () => { calls.push('signOut'); }),
    };
    expect(await handleSessionStale(deps)).toBe(true);
    expect(calls).toEqual(['clear', 'mark:credential_change', 'signOut']);
    expect(await handleSessionStale(deps)).toBe(false);
    expect(deps.signOutLocal).toHaveBeenCalledTimes(1);
  });

  it('a failing clear never stops the sign-out', async () => {
    resetSessionStaleForTests();
    const deps = { clearRegistration: vi.fn(async () => { throw new Error('storage'); }), markEnd: vi.fn(), signOutLocal: vi.fn(async () => {}) };
    expect(await handleSessionStale(deps)).toBe(true);
    expect(deps.signOutLocal).toHaveBeenCalled();
  });

  it('the hook routes session_stale to handleSessionStale with a local, credential_change sign-out', () => {
    const h = stripComments(read('src/hooks/usePushToken.ts'));
    expect(h).toContain("if (result.kind === 'session_stale')");
    expect(h).toContain("signOutEverywhere({ scope: 'local', reason: 'credential_change' })");
    expect(h).toContain('clearRegistration: () => saveRegistrationState(EMPTY_REGISTRATION_STATE)');
  });
});

describe('P6 / P2: ordinary sign-out is this device; all-devices is a distinct act', () => {
  it('defaults to scope local with the user reason', () => {
    expect(resolveSignOutOptions()).toEqual({ scope: 'local', reason: 'user' });
    expect(resolveSignOutOptions({ scope: 'global', reason: 'password_changed' })).toEqual({ scope: 'global', reason: 'password_changed' });
  });

  it('signOutAllDevices revokes every binding first, ignores its failure, then signs out globally', () => {
    const so = stripComments(read('src/lib/auth/signOut.ts'));
    expect(REVOKE_ALL_RPC).toBe('revoke_all_push_bindings');
    const rpcAt = so.indexOf('supabase.rpc(REVOKE_ALL_RPC)');
    const outAt = so.indexOf("signOutEverywhere({ scope: 'global' })");
    expect(rpcAt).toBeGreaterThan(-1);
    expect(outAt).toBeGreaterThan(rpcAt);
    expect(so).toContain('await supabase.auth.signOut({ scope })');
    expect(so).toContain('markSessionEnd(reason)');
  });

  it('Settings offers both acts; the reset screen signs out everywhere with the password_changed reason', () => {
    const settings = read('app/settings/index.tsx');
    expect(settings).toContain('label="Sign out"');
    expect(settings).toContain('label="Sign out of all devices"');
    expect(settings).toContain('await signOutAllDevices()');
    const reset = stripComments(read('app/(auth)/reset-password.tsx'));
    expect(reset).toContain("signOutEverywhere({ scope: 'global', reason: 'password_changed' })");
  });

  it('the login screen has a sentence for both new reasons', () => {
    expect(SESSION_END_NOTICE.credential_change).toMatch(/password was changed/i);
    expect(SESSION_END_NOTICE.password_changed).toMatch(/new password/i);
    expect(sessionEndNotice('credential_change')).toBe(SESSION_END_NOTICE.credential_change);
  });
});
