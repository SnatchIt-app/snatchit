/**
 * src/lib/observability/sentryIdentity.ts — what the native app tells Sentry about itself (A/SENTRY-FIX-PLAN
 * S1 + S2, 2026-10-30).
 *
 * S2 (this module): the environment label. A simulator is `simulator` whatever its build profile says — the
 * REACT-NATIVE-E hangs were all simulators, 7 of them filed under production. A known EAS profile value is
 * itself; anything missing or unrecognised is `unconfigured`. Nothing here ever falls back to `production`.
 *
 * S1 (in NativeAppShell): release and dist are NOT set on Sentry.init, so @sentry/react-native's default
 * `nativeReleaseIntegration` reports `${bundleId}@${CFBundleShortVersionString}+${CFBundleVersion}` and the real
 * build number from the native bundle — EAS numbers builds remotely, so the JS-side config only ever said "1".
 */

/** The EXPO_PUBLIC_APP_ENV values the EAS build profiles ship (tests pin this against eas.json). */
export const SENTRY_KNOWN_ENVIRONMENTS = ['production', 'sandbox'] as const;

export type SentryEnvironment = (typeof SENTRY_KNOWN_ENVIRONMENTS)[number] | 'simulator' | 'unconfigured';

const KNOWN: ReadonlySet<string> = new Set(SENTRY_KNOWN_ENVIRONMENTS);

/**
 * `appEnv` is EXPO_PUBLIC_APP_ENV as built; `isDevice` is expo-device's `Device.isDevice` (false on a simulator,
 * null when the platform cannot say). Exact match only: a typo or a padded value is unconfigured, not production.
 */
export function sentryEnvironment(appEnv: string | undefined, isDevice: boolean | null): SentryEnvironment {
  if (isDevice === false) return 'simulator';
  if (appEnv !== undefined && KNOWN.has(appEnv)) return appEnv as SentryEnvironment;
  return 'unconfigured';
}
