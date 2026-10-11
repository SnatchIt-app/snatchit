/**
 * A's sign-off condition on the signOut.ts +5 (2026-09-24): the ordering of clearDockAvatar was
 * pinned only by source TEXT (an indexOf comparison), which passes whatever the control flow
 * does. These tests pin the BEHAVIOUR through the exported `revokeThenSignOut(deps)`:
 *
 *   (a) signOut fails  → clearDockAvatar is NOT called, result is signedOut: false;
 *   (b) success        → clearDockAvatar is called exactly once, after signOut;
 *   (c) the clear throws → the result is still signedOut: true and clearRegistration still ran.
 *
 * Negative control (run once, recorded in the sign-off message, not committed as a mutant):
 * moving the call above the signedOut-false return makes (a) fail.
 */
import { describe, expect, it, vi } from 'vitest';

vi.mock('@/src/lib/supabase', () => ({ supabase: {} }));
vi.mock('@/src/lib/push/registrationStore', () => ({
  saveRegistrationState: async () => {},
  EMPTY_REGISTRATION_STATE: {},
}));
vi.mock('@/src/lib/nav/dockAvatar', () => ({ clearDockAvatar: () => {} }));

import { revokeThenSignOut, type SignOutDeps } from '@/src/lib/auth/signOut';

function deps(over: Partial<SignOutDeps> = {}): SignOutDeps & { calls: string[] } {
  const calls: string[] = [];
  return {
    calls,
    getToken: () => 'tok-1',
    getUserId: async () => 'user-1',
    revoke: async () => { calls.push('revoke'); return 1; },
    clearRegistration: async () => { calls.push('clearRegistration'); },
    clearDockAvatar: () => { calls.push('clearDockAvatar'); },
    signOut: async () => { calls.push('signOut'); return { error: null }; },
    timeoutMs: 50,
    ...over,
  };
}

describe('sign-out clears the dock avatar — behaviour, not source order', () => {
  it('SA1: a FAILED sign-out clears nothing — the user is still signed in and keeps their photo', async () => {
    const d = deps({ signOut: async () => { d.calls.push('signOut'); return { error: { message: 'nope' } }; } });
    const r = await revokeThenSignOut(d);
    expect(r.signedOut).toBe(false);
    expect(d.calls).not.toContain('clearDockAvatar');
    expect(d.calls).not.toContain('clearRegistration');
  });

  it('SA2: success calls the clear exactly once, and only AFTER the sign-out itself', async () => {
    const d = deps();
    const r = await revokeThenSignOut(d);
    expect(r).toEqual({ signedOut: true, revoke: 'revoked' });
    expect(d.calls.filter((c) => c === 'clearDockAvatar')).toHaveLength(1);
    expect(d.calls.indexOf('clearDockAvatar')).toBeGreaterThan(d.calls.indexOf('signOut'));
  });

  it('SA3: a THROWING clear never blocks — still signed out, and the registration clear still ran', async () => {
    const d = deps({ clearDockAvatar: () => { d.calls.push('clearDockAvatar'); throw new Error('boom'); } });
    const r = await revokeThenSignOut(d);
    expect(r.signedOut).toBe(true);
    expect(d.calls).toContain('clearRegistration');
    expect(d.calls).toContain('clearDockAvatar');
  });

  it('SA4: …and symmetrically, a throwing registration clear does not stop the avatar clear', async () => {
    const d = deps({ clearRegistration: async () => { d.calls.push('clearRegistration'); throw new Error('boom'); } });
    const r = await revokeThenSignOut(d);
    expect(r.signedOut).toBe(true);
    expect(d.calls).toContain('clearDockAvatar');
  });
});
