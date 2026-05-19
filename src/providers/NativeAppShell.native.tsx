/**
 * src/providers/NativeAppShell.native.tsx
 *
 * Native-only app shell: Sentry, StripeProvider, Notifications, Linking,
 * reanimated, and push-token registration.
 *
 * Platform resolution ensures the web bundle never sees these imports.
 */

import React, { useEffect } from 'react';
import * as Sentry from '@sentry/react-native';
import Constants from 'expo-constants';
import * as Linking from 'expo-linking';
import * as Notifications from 'expo-notifications';
import { StripeProvider } from '@stripe/stripe-react-native';
import 'react-native-reanimated';

import { router } from 'expo-router';
import { supabase } from '@/src/lib/supabase';
import { usePushToken } from '@/src/hooks/usePushToken';
import { APP_CONFIG } from '@/src/config/app';

// ── Sentry bootstrap (module-level, runs once) ──────────────────────────────

const _version = Constants.expoConfig?.version ?? '1.0.0';
const _build   = Constants.expoConfig?.ios?.buildNumber
              ?? Constants.expoConfig?.android?.versionCode?.toString()
              ?? '1';

Sentry.init({
  dsn:              process.env.EXPO_PUBLIC_SENTRY_DSN,
  enabled:          !__DEV__,
  environment:      process.env.EXPO_PUBLIC_APP_ENV ?? 'production',
  release:          `com.jdt-inc.snatchit@${_version}`,
  dist:             _build,
  tracesSampleRate: __DEV__ ? 0 : 0.1,
  debug:            false,
});

// ── Notification handler (module-level) ─────────────────────────────────────

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true,
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

// ── Exported helpers ────────────────────────────────────────────────────────

/** Wrap the root component with Sentry's error boundary. */
export function wrapRootComponent(component: React.ComponentType): React.ComponentType {
  return Sentry.wrap(component);
}

/** Set (or clear) the Sentry user context for crash attribution. */
export function setSentryUser(user: { id: string; email?: string } | null) {
  if (user) {
    Sentry.setUser({ id: user.id, email: user.email ?? undefined });
  } else {
    Sentry.setUser(null);
  }
}

// ── Provider component ──────────────────────────────────────────────────────

interface AppShellProps {
  children: React.ReactNode;
}

/**
 * Wraps children in StripeProvider.
 *
 * Notes on the publishableKey check:
 *   - A missing publishable key still results in failed checkout, but the
 *     failure is surfaced LATER (inside PaymentSheet) with a clear error
 *     code instead of crashing native at module load. A previous version
 *     of this file threw at module load, which manifested as an instant
 *     iOS crash on TestFlight builds whose env vars weren't bundled
 *     (e.g. preview profile with no .env.staging file).
 *   - The Stripe SDK does not crash on empty publishableKey; it logs an
 *     error when initPaymentSheet is called. CheckoutNative already
 *     captures that error and shows the existing "Setup Failed" UI.
 *   - For visibility, we log a clear console.error at module load. EAS
 *     build logs will show it; runtime devs will see it in dev tools.
 *
 *   `urlScheme` lets the Stripe iOS SDK bring the app back into focus
 *   after Apple Pay interstitial sheets and 3DS redirects. Must match
 *   `scheme` in app.json and CFBundleURLSchemes in Info.plist.
 *
 *   `merchantIdentifier` must match the Apple Pay merchant ID registered
 *   in the Apple Developer portal, attached to the App ID, and uploaded
 *   to Stripe Dashboard (verified `merchant.com.snatchit`).
 */
if (!APP_CONFIG.STRIPE_PUBLISHABLE_KEY) {
  // Soft warning, NOT a throw. A throw here would terminate the JS runtime
  // before React mounts; the app would crash on launch with no UI to
  // recover. Instead, let the app boot and surface a clean payment error
  // when checkout is attempted.
  console.error(
    '[SnatchIt] EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY is empty. Checkout will fail until this is set.\n' +
    '  • Production builds need pk_live_…; preview/dev builds need pk_test_….\n' +
    '  • Configure via eas.json env block (preferred) or .env.<profile> file.',
  );
}

export function AppShell({ children }: AppShellProps) {
  return (
    <StripeProvider
      publishableKey={APP_CONFIG.STRIPE_PUBLISHABLE_KEY}
      merchantIdentifier="merchant.com.snatchit"
      urlScheme="snatchit"
    >
      {children}
    </StripeProvider>
  );
}

// ── Native-only effects hook ────────────────────────────────────────────────

interface NativeEffectsOptions {
  userId?: string;
  isRecovery: boolean;
  setIsRecovery: (v: boolean) => void;
}

/**
 * Runs native-only side effects: deep link handling and push token
 * registration. Call this inside the root layout component.
 */
export function useNativeEffects({ userId, isRecovery, setIsRecovery }: NativeEffectsOptions) {
  // Register Expo push token on every app launch (only when authenticated)
  usePushToken(userId);

  // ── Deep link handler ───────────────────────────────────────────────────
  useEffect(() => {
    async function handleUrl(url: string) {
      if (!url) return;
      const hash   = url.includes('#') ? url.split('#')[1] : url.split('?')[1] ?? '';
      const params = new URLSearchParams(hash);
      const type          = params.get('type');
      const access_token  = params.get('access_token');
      const refresh_token = params.get('refresh_token');

      if (type === 'recovery') {
        setIsRecovery(true);
        router.replace('/(auth)/reset-password');
      }

      if (access_token && refresh_token) {
        const { error } = await supabase.auth.setSession({ access_token, refresh_token });
        if (error) console.warn('[auth] setSession error:', error.message);
      }
    }

    Linking.getInitialURL().then(url => { if (url) handleUrl(url); });
    const sub = Linking.addEventListener('url', ({ url }) => handleUrl(url));
    return () => sub.remove();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
}
