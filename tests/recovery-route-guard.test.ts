/**
 * N7 — the reset screen is reached by STATE, not by a navigation call raced against Expo Router.
 *
 * Builds 25/27 navigated with router.replace inside the deep-link handler: on a cold start that runs
 * before the Stack mounts (expo-router throws "Attempted to navigate before mounting the Root Layout
 * component"), and on a warm start Expo Router's own handling of snatchit://?code=… routes to "/" →
 * Home in no fixed order with it. The root layout now owns the move: while the recovery hold is up and
 * the navigator is ready, it puts the person on the reset screen; when the hold is released with no
 * session, it takes them off it. Pure function + source pins. Not device evidence.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { isResetScreen, recoveryRouteTarget } from '../src/lib/auth/rootRoute';

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const read = (p: string) => strip(readFileSync(resolve(__dirname, '..', p), 'utf8'));

describe('recoveryRouteTarget', () => {
  const base = { isRecovery: false, onResetScreen: false, signedIn: false, loading: false };

  it('G1: hold up, not on the reset screen → go to the reset screen (signed in or not yet)', () => {
    expect(recoveryRouteTarget({ ...base, isRecovery: true })).toBe('/(auth)/reset-password');
    expect(recoveryRouteTarget({ ...base, isRecovery: true, signedIn: true })).toBe('/(auth)/reset-password');
  });

  it('G2: hold up and already there → stay', () => {
    expect(recoveryRouteTarget({ ...base, isRecovery: true, onResetScreen: true, signedIn: true })).toBeNull();
  });

  it('G3: hold released with no session while on the reset screen → login, where a new link can be requested', () => {
    expect(recoveryRouteTarget({ ...base, onResetScreen: true })).toBe('/(auth)/login');
  });

  it('G4: no hold → the guard never moves anyone (the phase router decides)', () => {
    expect(recoveryRouteTarget(base)).toBeNull();
    expect(recoveryRouteTarget({ ...base, signedIn: true })).toBeNull();
    expect(recoveryRouteTarget({ ...base, onResetScreen: true, signedIn: true })).toBeNull();
    expect(recoveryRouteTarget({ ...base, onResetScreen: true, loading: true })).toBeNull();
  });
});

describe('isResetScreen', () => {
  it('G5: true only for the (auth)/reset-password route', () => {
    expect(isResetScreen(['(auth)', 'reset-password'])).toBe(true);
    expect(isResetScreen(['(auth)', 'login'])).toBe(false);
    expect(isResetScreen(['(tabs)', 'home'])).toBe(false);
    expect(isResetScreen(['reset-password'])).toBe(false);
    expect(isResetScreen([])).toBe(false);
  });
});

describe('wiring', () => {
  const layout = read('app/_layout.tsx');
  const shell = read('src/providers/NativeAppShell.native.tsx');

  it('W1: the guard is a component rendered as the Stack\'s sibling in the same branch, so it exists only once the Stack does', () => {
    // Review (2026-10-15): useRootNavigationState() is always set in the root layout (it returns the
    // __root navigator's own state), so a "navReady" built on it gated nothing. Mount order is the gate.
    expect(layout).toMatch(/<\/Stack>\s*(\{\s*\}\s*)?<RecoveryRouteGuard\b/);   // a stripped JSX comment leaves {}
    expect(layout).toMatch(/\{fontsReady \? \(\s*<>\s*<Stack /);
    const guard = layout.slice(layout.indexOf('function RecoveryRouteGuard('));
    expect(guard).toMatch(/const onResetScreen = isResetScreen\(useSegments\(\) as string\[\]\);/);
    expect(guard).toMatch(/recoveryRouteTarget\(\{ isRecovery, onResetScreen, signedIn, loading \}\)/);
    // The layout body itself no longer navigates for recovery.
    const body = layout.slice(layout.indexOf('function RootLayout('), layout.indexOf('function RecoveryRouteGuard('));
    expect(body).not.toMatch(/recoveryRouteTarget\(/);
    expect(layout).not.toMatch(/useRootNavigationState/);
  });

  it('W2: nothing navigates to the reset screen directly any more — the guard owns that move', () => {
    expect(layout).not.toContain("router.replace('/(auth)/reset-password')");
    expect(shell).not.toContain("router.replace('/(auth)/reset-password')");
  });

  it('W3: the shell hands the dispatch the stored-verifier check and keeps the F7 release', () => {
    expect(shell).toContain('isRecoveryCode: () => pendingCodeIsRecovery(supabase.auth)');
    expect(shell).toContain('onRecovery: () => { setIsRecovery(true);');
    expect(shell).toContain('onRecoveryFailed: () => setIsRecovery(false)');
  });

  it('W4: the PASSWORD_RECOVERY event still raises the hold (web, token_hash links)', () => {
    expect(layout).toMatch(/event === 'PASSWORD_RECOVERY'\)\s*\{\s*setIsRecovery\(true\);/);
  });
});
