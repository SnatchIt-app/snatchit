/**
 * Sentry release identity and environment (A/SENTRY-FIX-PLAN S1 + S2; C, 2026-10-30).
 *
 * Before: `NativeAppShell.native.tsx` set `release = com.jdt-inc.snatchit@${expoConfig.version}` and
 * `dist = expoConfig.ios.buildNumber` — "1" on every build, because EAS numbers builds remotely and only the
 * native Info.plist carries the real CFBundleVersion — and `environment = EXPO_PUBLIC_APP_ENV ?? 'production'`,
 * so a simulator or an unconfigured build reported as production (all 15 REACT-NATIVE-E events were simulators,
 * 7 of them tagged production).
 *
 * S1: Sentry.init sets NO release/dist. @sentry/react-native 7.2.0's default `nativeReleaseIntegration`
 *     (integrations/release.js:33-52, pushed unconditionally in integrations/default.js:37) then fills
 *     `release = ${bundleId}@${CFBundleShortVersionString}+${CFBundleVersion}` and `dist = ${CFBundleVersion}`
 *     from the native bundle — the same naming the Xcode upload script uses — but ONLY when init options leave
 *     them unset (options win: release.js:33/39). So the pin is "never set them".
 * S2: `sentryEnvironment` decides the label: a simulator is `simulator` whatever the build profile says; a known
 *     profile value is itself; anything else is `unconfigured`. Never a silent `production`.
 *
 * Negative controls (run by hand, each must FAIL): drop the simulator branch (E1); default an unknown value to
 * production (E3); put `dist:` back into Sentry.init (P1); truncate the init block with a nested `});` and hide a
 * `dist:` after it (P0 fails while P1 passes vacuously — the hole P0 closes).
 */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

import { SENTRY_KNOWN_ENVIRONMENTS, sentryEnvironment } from '@/src/lib/observability/sentryIdentity';

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
const shell = strip(readFileSync('src/providers/NativeAppShell.native.tsx', 'utf8'));
const initBlock = (() => {
  const m = shell.match(/Sentry\.init\(\{([\s\S]*?)\}\);/);
  expect(m).not.toBeNull();
  return m![1];
})();

describe('sentryEnvironment (S2) — a label that cannot claim production by accident', () => {
  it('E1: a simulator is "simulator" whatever the build profile says — including a production-configured one', () => {
    expect(sentryEnvironment('production', false)).toBe('simulator');
    expect(sentryEnvironment('sandbox', false)).toBe('simulator');
    expect(sentryEnvironment(undefined, false)).toBe('simulator');
  });

  it('E2: a real device reports its build profile\'s known environment', () => {
    expect(sentryEnvironment('production', true)).toBe('production');
    expect(sentryEnvironment('sandbox', true)).toBe('sandbox');
  });

  it('E3: missing, empty or unknown profile values are "unconfigured" — never production', () => {
    for (const v of [undefined, '', '  ', 'Production', 'prod', 'staging', 'production ']) {
      expect(sentryEnvironment(v, true), String(v)).toBe('unconfigured');
    }
  });

  it('E4: an unknown device kind (null) follows the profile rules; it is not assumed to be a simulator or production', () => {
    expect(sentryEnvironment('production', null)).toBe('production');
    expect(sentryEnvironment(undefined, null)).toBe('unconfigured');
  });

  it('E5: the known set is exactly the EXPO_PUBLIC_APP_ENV values the EAS build profiles ship', () => {
    const eas = JSON.parse(readFileSync('eas.json', 'utf8')) as { build: Record<string, { env?: Record<string, string> }> };
    const shipped = new Set(Object.values(eas.build).map((p) => p.env?.EXPO_PUBLIC_APP_ENV).filter((v): v is string => !!v));
    expect([...SENTRY_KNOWN_ENVIRONMENTS].sort()).toEqual([...shipped].sort());
  });
});

describe('NativeAppShell wiring (S1 + S2)', () => {
  it('P0: premise — the extracted Sentry.init block is the WHOLE options object, so P1/P3 cannot pass on a truncated block (E on 97096c61)', () => {
    // initBlock is a lazy match up to the first `});`. A nested callback containing `});` would cut it short and
    // P1/P3 (absence checks) would then pass vacuously. Its keys must be exactly the expected list, in order,
    // ending with the last option — which also catches any key added back (release, dist, integrations…).
    const keys = [...initBlock.matchAll(/^\s*([A-Za-z_$][\w$]*)\s*:/gm)].map((m) => m[1]);
    expect(keys).toEqual(['dsn', 'enabled', 'environment', 'tracesSampleRate', 'debug']);
  });

  it('P1: Sentry.init sets no release and no dist, so the native SDK supplies bundleId@version+build and the build number', () => {
    expect(initBlock).not.toMatch(/\brelease\s*:/);
    expect(initBlock).not.toMatch(/\bdist\s*:/);
    expect(shell).not.toMatch(/expoConfig\?\.ios\?\.buildNumber/);   // the static "1" is gone from the shell entirely
    expect(shell).not.toMatch(/com\.jdt-inc\.snatchit@/);
  });

  it('P2: the environment comes from sentryEnvironment(profile, Device.isDevice) — no `?? \'production\'` default', () => {
    expect(initBlock).toMatch(/environment:\s*sentryEnvironment\(process\.env\.EXPO_PUBLIC_APP_ENV, Device\.isDevice\)/);
    expect(shell).not.toMatch(/\?\?\s*'production'/);
    expect(shell).toContain("import * as Device from 'expo-device';");
  });

  it('P3: the default integrations (which include nativeReleaseIntegration) are not replaced or filtered', () => {
    expect(initBlock).not.toMatch(/defaultIntegrations\s*:/);
    expect(initBlock).not.toMatch(/\bintegrations\s*:/);
  });
});
