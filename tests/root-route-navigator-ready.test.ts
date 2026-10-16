/**
 * N7c — the phase router does not navigate before the navigator exists.
 *
 * Production T1 trace (2026-10-16, frozen 7fc72a08): auth finished loading while the brand fonts were
 * still registering, so the Stack (rendered only once fonts are ready) did not exist yet. The phase
 * router issued router.replace('/(auth)/login') anyway, and Expo Router unmounted and replaced the whole
 * root layout 5 ms later — the remount that lost the recovery hold. The sandbox runs passed only because
 * fonts happened to be ready first. The rule now waits for the navigator. Pure function + source pin.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { rootRouteDecision } from '../src/lib/auth/rootRoute';

const base = { loading: false, isRecovery: false, onboarding: false } as const;

describe('rootRouteDecision — waits for the navigator', () => {
  it('NR1: no navigator yet → no navigation, for a first signed-out route, a first signed-in route and a signed-out tab', () => {
    const waiting = { navigate: false, reason: 'navigator' };
    expect(rootRouteDecision({ ...base, navigatorReady: false, phase: 'signed_out', lastRoutedPhase: null })).toEqual(waiting);
    expect(rootRouteDecision({ ...base, navigatorReady: false, phase: 'signed_in:u1', lastRoutedPhase: null })).toEqual(waiting);
    expect(rootRouteDecision({ ...base, navigatorReady: false, phase: 'signed_out', lastRoutedPhase: 'signed_out', inSignedInArea: true })).toEqual(waiting);
  });

  it('NR2: once the navigator exists the decision is the same as before', () => {
    expect(rootRouteDecision({ ...base, navigatorReady: true, phase: 'signed_out', lastRoutedPhase: null }))
      .toEqual({ navigate: true, to: '/(auth)/login' });
    expect(rootRouteDecision({ ...base, navigatorReady: true, phase: 'signed_in:u1', lastRoutedPhase: 'signed_out' }))
      .toEqual({ navigate: true, to: '/(tabs)/home' });
  });

  it('NR3: loading still reports loading, and callers that do not pass navigatorReady behave exactly as before', () => {
    expect(rootRouteDecision({ ...base, loading: true, navigatorReady: false, phase: 'signed_out', lastRoutedPhase: null }))
      .toEqual({ navigate: false, reason: 'loading' });
    expect(rootRouteDecision({ ...base, phase: 'signed_out', lastRoutedPhase: null }))
      .toEqual({ navigate: true, to: '/(auth)/login' });
  });
});

describe('wiring', () => {
  it('NR4: the root layout says the navigator is ready only when the Stack renders (fonts ready), and re-runs when it flips', () => {
    const layout = readFileSync(resolve(__dirname, '..', 'app/_layout.tsx'), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(layout).toMatch(/\{fontsReady \? \(\s*<>\s*<Stack /);
    expect(layout).toMatch(/rootRouteDecision\(\{[\s\S]{0,300}navigatorReady: fontsReady,/);
    expect(layout).toMatch(/\}, \[session, routingLoading, isRecovery, onboarding, inDevHarness, inSignedInArea, fontsReady\]\);/);
  });
});
