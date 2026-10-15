/**
 * N7b — a recovery session survives the app being killed on "New password", and nobody is ever stuck.
 *
 * Review finding N7-1 (2026-10-15): the hold lived only in React state and the exchange consumes the stored
 * verifier, so if iOS killed the app on the reset screen (a switch to a password manager, or the force-quit
 * that is the only way off it), the next launch restored the recovery session and routed to Home, signed in,
 * password unchanged — the original defect by another road. A decision (relayed): persist a per-user marker;
 * re-raise the hold only for the same user and within 24 h; clear it on sign-out, after a successful update
 * and on expiry; give the reset screen a Cancel that calls the EXISTING this-device sign-out helper.
 * Session-lifecycle-adjacent: flagged for E. Pure rules with an in-memory store + source pins. Not device evidence.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  RECOVERY_MARKER_KEY, RECOVERY_MARKER_TTL_MS, clearRecoveryPending, markRecoveryPending, recoveryPendingFor,
} from '../src/lib/auth/recoveryMarker';

function memStore() {
  const m = new Map<string, string>();
  return {
    m,
    getItem: async (k: string) => m.get(k) ?? null,
    setItem: async (k: string, v: string) => { m.set(k, v); },
    removeItem: async (k: string) => { m.delete(k); },
  };
}
const T0 = Date.parse('2026-10-15T05:00:00Z');

describe('the marker', () => {
  it('S1: a cold launch with the same user restores the hold', async () => {
    const st = memStore();
    await markRecoveryPending(st, 'user-1', T0);
    expect(await recoveryPendingFor(st, 'user-1', T0 + 60_000)).toBe(true);
  });
  it('S2: a different user never inherits it — and the stale marker is cleared', async () => {
    const st = memStore();
    await markRecoveryPending(st, 'user-1', T0);
    expect(await recoveryPendingFor(st, 'user-2', T0 + 60_000)).toBe(false);
    expect(st.m.has(RECOVERY_MARKER_KEY)).toBe(false);
  });
  it('S3: it expires after 24 h and is cleared on that launch', async () => {
    const st = memStore();
    await markRecoveryPending(st, 'user-1', T0);
    expect(RECOVERY_MARKER_TTL_MS).toBe(24 * 3_600_000);
    expect(await recoveryPendingFor(st, 'user-1', T0 + RECOVERY_MARKER_TTL_MS - 1)).toBe(true);
    expect(await recoveryPendingFor(st, 'user-1', T0 + RECOVERY_MARKER_TTL_MS)).toBe(false);
    expect(st.m.has(RECOVERY_MARKER_KEY)).toBe(false);
  });
  it('S4: cleared means gone; nothing stored, a malformed value or a broken store is "no hold"', async () => {
    const st = memStore();
    await markRecoveryPending(st, 'user-1', T0);
    await clearRecoveryPending(st);
    expect(await recoveryPendingFor(st, 'user-1', T0)).toBe(false);
    st.m.set(RECOVERY_MARKER_KEY, '{not json');
    expect(await recoveryPendingFor(st, 'user-1', T0)).toBe(false);
    const broken = { getItem: async () => { throw new Error('io'); }, setItem: async () => {}, removeItem: async () => {} };
    expect(await recoveryPendingFor(broken, 'user-1', T0)).toBe(false);
    expect(await recoveryPendingFor(st, '', T0)).toBe(false);
  });
});

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const read = (p: string) => strip(readFileSync(resolve(__dirname, '..', p), 'utf8'));

describe('wiring', () => {
  const layout = read('app/_layout.tsx');
  const reset = read('app/(auth)/reset-password.tsx');

  it('S5: the root layout holds routing until the launch check is done, and the check re-raises the hold for the same user', () => {
    expect(layout).toMatch(/const routingLoading = loading \|\| !recoveryChecked;/);
    expect(layout).toMatch(/rootRouteDecision\(\{\s*loading: routingLoading,/);
    expect(layout).toMatch(/<RecoveryRouteGuard isRecovery=\{isRecovery\} signedIn=\{!!session\} loading=\{routingLoading\}/);
    expect(layout).toMatch(/\(routingLoading \|\| !fontsReady\) && <SplashOverlay \/>/);
    expect(layout).toMatch(/recoveryPendingFor\(AsyncStorage, userId\)[\s\S]{0,200}setIsRecovery\(true\)/);
  });

  it('S6: the marker is written when the recovery session lands, and cleared on SIGNED_OUT', () => {
    expect(layout).toMatch(/if \(isRecovery && userId\) void markRecoveryPending\(AsyncStorage, userId\);/);
    expect(layout).toMatch(/event === 'SIGNED_OUT'\)\s*\{\s*setIsRecovery\(false\);\s*void clearRecoveryPending\(AsyncStorage\);/);
  });

  it('S7: a successful update clears the marker BEFORE the sign-out that might fail', () => {
    const at = reset.indexOf('const { error } = await supabase.auth.updateUser({ password });');
    const clear = reset.indexOf('await clearRecoveryPending(AsyncStorage);', at);
    const out = reset.indexOf('await signOutAfterPasswordChange();', at);
    expect(at).toBeGreaterThan(-1);
    expect(clear).toBeGreaterThan(at);
    expect(out).toBeGreaterThan(clear);
  });

  it('S8: Cancel calls the existing this-device sign-out helper; the success alert no longer navigates (the guard does — review N7-2)', () => {
    expect(reset).toMatch(/import \{[^}]*signOutThisDevice[^}]*\} from '@\/src\/lib\/auth\/signOut';/);
    expect(reset).toMatch(/label="Cancel"[\s\S]{0,200}onPress=\{handleCancel\}/);
    expect(reset).toMatch(/async function handleCancel\(\)[\s\S]{0,300}await signOutThisDevice\(\)/);
    expect(reset).toMatch(/Alert\.alert\('Password updated', 'Your password has been updated\. Please sign in\.', \[\s*\{ text: 'OK' \},\s*\]\);/);
    expect(reset).not.toContain("router.replace('/(auth)/login')");
  });
});
