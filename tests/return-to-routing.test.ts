/**
 * CFT-603 / item 44 (slice 1) — the root routing rule returns a sign-in to the stored screen, and recovery
 * always wins over it.
 *
 * rootRouteDecision gains one optional input, `returnTo`. It is read only when the decision takes the person
 * INTO the signed-in area, only after every hold (loading, navigator, recovery, onboarding), and only if it is
 * still an allowlisted screen; otherwise Home, exactly as before. The root layout reads the stored screen and
 * the current pathname through module state and a ref, so the routing effect's dependency list stays as K6
 * pins it, and login.tsx is untouched (it still never navigates except to Sign up).
 *
 * RW1 is the negative-control target E asked for: with a destination stored, a recovery session must still
 * land on "New password" and must not consume the destination. Pure function + source pins. Not device
 * evidence.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { recoveryRouteTarget, rootRouteDecision, type AuthPhase } from '../src/lib/auth/rootRoute';

const LISTING = '/listing/4a1d2c3b-0000-4000-8000-00000000abcd';
const OUT = 'signed_out' as AuthPhase;
const USER_A = 'signed_in:user-a' as AuthPhase;
const USER_B = 'signed_in:user-b' as AuthPhase;

const decide = (over: Partial<Parameters<typeof rootRouteDecision>[0]> = {}) =>
  rootRouteDecision({ loading: false, isRecovery: false, onboarding: false, phase: USER_A, lastRoutedPhase: OUT, ...over });

describe('rootRouteDecision — return after sign-in', () => {
  it('RR1: a sign-in with a stored screen goes to that screen', () => {
    expect(decide({ returnTo: LISTING })).toEqual({ navigate: true, to: LISTING });
    expect(decide({ returnTo: '/bid/abc' })).toEqual({ navigate: true, to: '/bid/abc' });
    expect(decide({ returnTo: '/transfer/receive/t1' })).toEqual({ navigate: true, to: '/transfer/receive/t1' });
    expect(decide({ returnTo: '/my-listings' })).toEqual({ navigate: true, to: '/my-listings' });
  });

  it('RR2: Home stays the default — no stored screen, null, or a first signed-in route without one', () => {
    expect(decide()).toEqual({ navigate: true, to: '/(tabs)/home' });
    expect(decide({ returnTo: null })).toEqual({ navigate: true, to: '/(tabs)/home' });
    expect(decide({ lastRoutedPhase: null, returnTo: undefined })).toEqual({ navigate: true, to: '/(tabs)/home' });
  });

  it('RR3: the rule re-checks the allowlist itself — anything else goes Home', () => {
    for (const returnTo of [
      'https://evil.example/listing/1', '//evil.example/listing/1', '/%2F%2Fevil.example', '/\\evil.example',
      'snatchit://listing/1', '/checkout/1', '/(auth)/reset-password', '/reset-password', '/login', '/', '/home',
      '/(tabs)/home', '/settings', '/payout-return',
    ]) expect({ returnTo, d: decide({ returnTo }) }).toEqual({ returnTo, d: { navigate: true, to: '/(tabs)/home' } });
  });

  it('RR4: a stored query is never forwarded — the rule hands back the bare screen', () => {
    expect(decide({ returnTo: `${LISTING}?code=abc&amount=500` })).toEqual({ navigate: true, to: LISTING });
  });

  it('RR5: a sign-out still goes to login; a stored screen never routes a signed-out person', () => {
    expect(decide({ phase: OUT, lastRoutedPhase: USER_A, returnTo: LISTING })).toEqual({ navigate: true, to: '/(auth)/login' });
    expect(decide({ phase: OUT, lastRoutedPhase: null, returnTo: LISTING })).toEqual({ navigate: true, to: '/(auth)/login' });
    // K1: a signed-out person on a tab still goes to login
    expect(decide({ phase: OUT, lastRoutedPhase: OUT, inSignedInArea: true, returnTo: LISTING }))
      .toEqual({ navigate: true, to: '/(auth)/login' });
  });

  it('RR6: a token refresh or user update (same phase) moves no one, stored screen or not', () => {
    expect(decide({ phase: USER_A, lastRoutedPhase: USER_A, returnTo: LISTING })).toEqual({ navigate: false, reason: 'same_phase' });
    expect(decide({ phase: OUT, lastRoutedPhase: OUT, returnTo: LISTING })).toEqual({ navigate: false, reason: 'same_phase' });
  });

  it('RR7: every hold still wins over a stored screen — loading, navigator, onboarding', () => {
    expect(decide({ loading: true, returnTo: LISTING })).toEqual({ navigate: false, reason: 'loading' });
    expect(decide({ navigatorReady: false, returnTo: LISTING })).toEqual({ navigate: false, reason: 'navigator' });
    expect(decide({ onboarding: true, returnTo: LISTING })).toEqual({ navigate: false, reason: 'onboarding' });
    // released: the boundary is still honest, and now carries the screen
    expect(decide({ onboarding: false, returnTo: LISTING })).toEqual({ navigate: true, to: LISTING });
  });

  it('RR8: switching accounts is a real boundary and uses whatever the layout found for the new account', () => {
    expect(decide({ phase: USER_B, lastRoutedPhase: USER_A, returnTo: null })).toEqual({ navigate: true, to: '/(tabs)/home' });
  });
});

describe('recovery always wins', () => {
  it("RW1: a stored screen never overrides 'New password' — the recovery session is held, the guard goes to reset", () => {
    // A signed-out person opened a listing (stored), then asked for a reset link and opened it: the link mints a
    // session for user A while the recovery hold is up.
    const recovery = { isRecovery: true, phase: USER_A, lastRoutedPhase: OUT, returnTo: LISTING };
    expect(decide(recovery)).toEqual({ navigate: false, reason: 'recovery' });
    expect(decide({ ...recovery, lastRoutedPhase: null })).toEqual({ navigate: false, reason: 'recovery' });
    expect(decide({ ...recovery, onboarding: true })).toEqual({ navigate: false, reason: 'recovery' });
    expect(recoveryRouteTarget({ isRecovery: true, onResetScreen: false, signedIn: true, loading: false })).toBe('/(auth)/reset-password');
    expect(recoveryRouteTarget({ isRecovery: true, onResetScreen: true, signedIn: true, loading: false })).toBeNull();
  });

  it('RW2: the recovery hold is checked before the stored screen is ever looked at (source order)', () => {
    const code = strip(read('src/lib/auth/rootRoute.ts'));
    const body = code.slice(code.indexOf('export function rootRouteDecision('), code.indexOf('export function isResetScreen('));
    const recoveryAt = body.indexOf('if (input.isRecovery)');
    const onboardingAt = body.indexOf('if (input.onboarding)');
    const returnToAt = body.indexOf('input.returnTo');
    expect(recoveryAt).toBeGreaterThan(-1);
    expect(returnToAt).toBeGreaterThan(onboardingAt);
    expect(returnToAt).toBeGreaterThan(recoveryAt);
  });

  it('RW3: the recovery guard is untouched and still the only reset-screen navigator', () => {
    const guard = layout.slice(layout.indexOf('function RecoveryRouteGuard('));
    expect(guard).toMatch(/const to = recoveryRouteTarget\(\{ isRecovery, onResetScreen, signedIn, loading \}\);\s*if \(to\) router\.replace\(to\);/);
    expect(guard).not.toMatch(/returnTo|ReturnTo/);
  });

  it('RW4: raising the recovery hold discards any stored screen', () => {
    expect(body).toMatch(/useEffect\(\(\) => \{\s*if \(isRecovery\) clearReturnTo\(\);\s*\}, \[isRecovery\]\);/);
  });
});

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const layout = strip(read('app/_layout.tsx'));
const body = layout.slice(layout.indexOf('function RootLayout('), layout.indexOf('function RecoveryRouteGuard('));

describe('root layout wiring', () => {
  it('RL1: the routing effect keeps its pinned dependency list (K6), and reads the stored screen inside the decision', () => {
    expect(layout).toMatch(/\}, \[session, routingLoading, isRecovery, onboarding, inDevHarness, inSignedInArea, fontsReady\]\);/);
    expect(layout).toMatch(/rootRouteDecision\(\{[\s\S]{0,400}navigatorReady: fontsReady,\s*returnTo: peekReturnTo\(userIdOfPhase\(phase\)\),\s*\}\);/);
  });

  it('RL2: the destination is settled only when the decision navigates, before the one replace', () => {
    const effect = body.slice(body.indexOf('rootRouteDecision({'));
    const gate = effect.indexOf('if (!decision.navigate) return;');
    const settle = effect.indexOf('settleReturnToOnRoute({ phase, lastRoutedPhase: routedPhaseRef.current, pathname: pathnameRef.current, sessionEnd: peekSessionEnd() });');
    const record = effect.indexOf('routedPhaseRef.current = phase;');
    const nav = effect.indexOf('router.replace(decision.to);');
    expect(gate).toBeGreaterThan(-1);
    expect(settle).toBeGreaterThan(gate);
    expect(record).toBeGreaterThan(settle);
    expect(nav).toBeGreaterThan(record);
  });

  it('RL3: the pathname reaches the effect through a ref from the capture hook, never as a dependency', () => {
    expect(body).toMatch(/const pathnameRef = useRef<string \| null>\(null\);\s*useReturnToCapture\(\{ phase: authPhase\(session\), held: isRecovery \|\| onboarding, routedPhaseRef, pathnameRef \}\);/);
    expect(layout).toMatch(/import \{ useReturnToCapture \} from '@\/src\/hooks\/useReturnToCapture';/);
    // the pinned expo-router import is unchanged (unsaved-guard-native-dismiss)
    expect(read('app/_layout.tsx')).toContain("import { router, Stack, useSegments } from 'expo-router';");
  });

  it('RL4: the layout lands on the screen only — one replace, no bid, checkout or payment code', () => {
    expect((body.match(/router\.(replace|push|navigate|dismissTo)\(/g) ?? [])).toEqual(['router.replace(']);
    const imports = layout.match(/^import [\s\S]*?from '[^']+';$/gm) ?? [];
    expect(imports.length).toBeGreaterThan(10);
    for (const line of imports) expect(line).not.toMatch(/payments|bid|checkout|reserv|transfer/i);
    expect(body).not.toMatch(/placeBid\(|reserve\w*\(|checkout\w*\(/i);
  });

  it('RL5: the capture hook fires on a change of pathname only, and stores a signed-out public screen with no owner', () => {
    const hook = strip(read('src/hooks/useReturnToCapture.ts'));
    expect(hook).toMatch(/import \{ usePathname \} from 'expo-router';/);
    expect(hook).toMatch(/input\.pathnameRef\.current = pathname;/);
    expect(hook).toMatch(/if \(shouldCaptureOnEntry\(\{ phase, held, routedPhase: routedPhaseRef\.current \}\)\) captureReturnTo\(pathname, null\);\s*\}, \[pathname\]\);/);
    expect(hook).not.toMatch(/router\./);
  });

  it('RL6: login is untouched — it still never navigates except to Sign up, and knows nothing of the store', () => {
    const login = strip(read('app/(auth)/login.tsx'));
    expect(login.match(/router\.(replace|push)\('[^']*'\)/g) ?? []).toEqual(["router.push('/(auth)/signup')"]);
    expect(login).not.toMatch(/returnTo|ReturnTo/);
  });
});
