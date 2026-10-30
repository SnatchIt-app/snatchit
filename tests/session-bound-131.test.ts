/**
 * tests/session-bound-131.test.ts — 131 (PROVISIONAL) client delta for A's
 * session-bound push bindings design (§6), stacked on the approved K-2 logout
 * branch (tests/logout-scope.test.ts covers the two sign-out acts). Not part
 * of the Friday candidate.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';

vi.mock('@/src/lib/supabase', () => ({ supabase: { rpc: vi.fn(), from: vi.fn(), auth: { signOut: vi.fn(), getSession: vi.fn() } } }));

import { classifyRegistrationError, decideRegistration, REGISTRATION_REMEDY } from '@/src/lib/push/registration';
import { handleSessionStale, resetSessionStaleForTests } from '@/src/lib/push/sessionStale';
import { SESSION_END_NOTICE, sessionEndNotice } from '@/src/lib/auth/sessionEnd';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

describe('131 P3 on the client: a session that predates a credential change is terminal until re-auth', () => {
  it('classifies the exact 42501 message as session_stale, not bound_to_other', () => {
    expect(classifyRegistrationError({ code: '42501', message: 'insufficient_privilege: session predates a credential change' })).toBe('session_stale');
    expect(classifyRegistrationError({ code: '42501', message: 'insufficient_privilege: token is bound to another account' })).toBe('bound_to_other');
  });

  it('waits (no retry timer, cold launch included) while the failure stands', () => {
    const failure = { kind: 'session_stale' as const, userId: 'u', token: 't', method: 'rpc' as const, at: 1_000, attempts: 1 };
    const d = decideRegistration({ userId: 'u', token: 't', record: null, failure, rpcAvailable: true, now: 10 ** 9, coldLaunch: true });
    expect(d).toEqual({ action: 'wait', method: 'rpc', reason: 'session_stale' });
  });

  it('the bound-to-another-account remedy fits the shared-install-after-global-sign-out edge (A, 131 @ f102ce2)', () => {
    const r = REGISTRATION_REMEDY.bound_to_other ?? '';
    expect(r).toBe("This device is still linked to another account. Sign in to that account and sign out of this device, or reinstall. If that isn't possible, contact support.");
    expect(r.endsWith('contact support.')).toBe(true);
  });

  it('has a neutral remedy the Notifications screen can show (K-4: no cause named)', () => {
    expect(REGISTRATION_REMEDY.session_stale).toMatch(/signed out on this device/i);
    expect(REGISTRATION_REMEDY.session_stale).not.toMatch(/password/i);
  });

  it('handleSessionStale: clear record → mark credential_change → local sign-out, once per process', async () => {
    resetSessionStaleForTests();
    const calls: string[] = [];
    const deps = {
      clearRegistration: vi.fn(async () => { calls.push('clear'); }),
      markEnd: vi.fn((r: 'credential_change') => { calls.push(`mark:${r}`); }),
      signOutLocal: vi.fn(async () => { calls.push('signOut'); return true; }),
    };
    expect(await handleSessionStale(deps)).toBe(true);
    expect(calls).toEqual(['clear', 'mark:credential_change', 'signOut']);
    expect(await handleSessionStale(deps)).toBe(false);
    expect(deps.signOutLocal).toHaveBeenCalledTimes(1);
  });

  it('a failing clear never stops the sign-out', async () => {
    resetSessionStaleForTests();
    const deps = { clearRegistration: vi.fn(async () => { throw new Error('storage'); }), markEnd: vi.fn(), signOutLocal: vi.fn(async () => true) };
    expect(await handleSessionStale(deps)).toBe(true);
    expect(deps.signOutLocal).toHaveBeenCalled();
  });

  it('F-K2-3: when the forced sign-out fails (offline), a later refusal may try again', async () => {
    resetSessionStaleForTests();
    const deps = { clearRegistration: vi.fn(async () => {}), markEnd: vi.fn(), signOutLocal: vi.fn(async () => false) };
    expect(await handleSessionStale(deps)).toBe(true);
    expect(await handleSessionStale(deps)).toBe(true);
    expect(deps.signOutLocal).toHaveBeenCalledTimes(2);
    const ok = { ...deps, signOutLocal: vi.fn(async () => true) };
    expect(await handleSessionStale(ok)).toBe(true);
    expect(await handleSessionStale(ok)).toBe(false);
  });

  it('the hook routes session_stale to handleSessionStale with a this-device, credential_change sign-out', () => {
    const h = stripComments(read('src/hooks/usePushToken.ts'));
    expect(h).toContain("if (result.kind === 'session_stale')");
    expect(h).toContain("(await signOutThisDevice({ reason: 'credential_change' })).signedOut");
    expect(h).toContain('clearRegistration: () => saveRegistrationState(EMPTY_REGISTRATION_STATE)');
  });

  it('the login screen has a neutral sentence for the stale-session case (K-4)', () => {
    expect(SESSION_END_NOTICE.credential_change).toMatch(/signed out on this device/i);
    expect(SESSION_END_NOTICE.credential_change).not.toMatch(/password/i);
    expect(sessionEndNotice('credential_change')).toBe(SESSION_END_NOTICE.credential_change);
  });
});
