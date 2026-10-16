/**
 * K-2: the tabs are signed-in only — enforced on deep links too.
 *
 * Found by C's sandbox simulator check (2026-10-15, D4): a recovery link with no pending reset on this
 * installation (expired, used, or requested on another device) arrived while the app sat signed out on Login.
 * Expo Router routed snatchit://?code=… to "/" → Home, and nothing took the person off it: the phase had
 * not changed, so rootRouteDecision said "same_phase". They were left on a signed-out Home ("Couldn't load
 * this"), with no word about the link. Pre-existing on builds 25/27 for any snatchit:// link while signed
 * out. The rule now also sends a signed-out person off the signed-in area. Pure function + source pin.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { rootRouteDecision } from '../src/lib/auth/rootRoute';

const base = { loading: false, isRecovery: false, onboarding: false } as const;

describe('rootRouteDecision — signed out inside the signed-in area', () => {
  it('K1: signed out, same phase, on a tab → login', () => {
    expect(rootRouteDecision({ ...base, phase: 'signed_out', lastRoutedPhase: 'signed_out', inSignedInArea: true }))
      .toEqual({ navigate: true, to: '/(auth)/login' });
  });
  it('K2: signed out, same phase, off the tabs (login, a public listing link) → stays', () => {
    expect(rootRouteDecision({ ...base, phase: 'signed_out', lastRoutedPhase: 'signed_out', inSignedInArea: false }))
      .toEqual({ navigate: false, reason: 'same_phase' });
  });
  it('K3: signed in on a tab → stays (token refreshes still move no one)', () => {
    expect(rootRouteDecision({ ...base, phase: 'signed_in:u1', lastRoutedPhase: 'signed_in:u1', inSignedInArea: true }))
      .toEqual({ navigate: false, reason: 'same_phase' });
  });
  it('K4: every hold still wins — loading, recovery (the reset guard owns it), onboarding', () => {
    const tabs = { phase: 'signed_out' as const, lastRoutedPhase: 'signed_out' as const, inSignedInArea: true };
    expect(rootRouteDecision({ ...base, ...tabs, loading: true }).navigate).toBe(false);
    expect(rootRouteDecision({ ...base, ...tabs, isRecovery: true }).navigate).toBe(false);
    expect(rootRouteDecision({ ...base, ...tabs, onboarding: true }).navigate).toBe(false);
  });
  it('K5: callers that do not say where they are behave exactly as before', () => {
    expect(rootRouteDecision({ ...base, phase: 'signed_out', lastRoutedPhase: 'signed_out' }))
      .toEqual({ navigate: false, reason: 'same_phase' });
  });
});

describe('wiring', () => {
  it('K6: the root layout tells the rule whether the current route is a tab, and re-runs when it changes', () => {
    const layout = readFileSync(resolve(__dirname, '..', 'app/_layout.tsx'), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(layout).toMatch(/const inSignedInArea = \(segments as string\[\]\)\[0\] === '\(tabs\)';/);
    expect(layout).toMatch(/rootRouteDecision\(\{[\s\S]{0,300}inSignedInArea,/);
    // N7c added fontsReady (the navigator-ready gate) after inSignedInArea.
    expect(layout).toMatch(/\}, \[session, routingLoading, isRecovery, onboarding, inDevHarness, inSignedInArea, fontsReady\]\);/);
  });
});
