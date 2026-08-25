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
      {/* StripeProvider types children as ReactElement; a fragment satisfies it for any ReactNode. */}
      <>{children}</>
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

  // ── Deep link handler (H-5 hardened) ────────────────────────────────────
  //
  // SECURITY: every param on an inbound custom-scheme URL is UNTRUSTED. We do
  // NOT call setSession({access_token, refresh_token}) with tokens taken from
  // the URL — that was the H-5 session-injection / session-fixation hole: an
  // attacker link could silently log the victim into the attacker's account
  // (or pin a known session). Instead we use PKCE / OTP verification, which
  // mints a session locally and is bound to secrets held only on THIS device.
  //
  // Accepted (verified) inputs:
  //   • token_hash + type  → supabase.auth.verifyOtp({ type, token_hash })
  //       Single-use hash verified server-side. Preferred for password
  //       recovery and email confirmation because `type=recovery` also tells
  //       us to route to the reset screen.
  //   • code               → supabase.auth.exchangeCodeForSession(code)
  //       PKCE. Only succeeds when the matching code_verifier is present in
  //       this device's (encrypted) storage; an attacker's code is useless.
  //
  // TODO(H-5 full closure): custom-scheme links (snatchit://) can be claimed
  // by a malicious app installed alongside ours. Fully closing H-5 also
  // requires VERIFIED deep links so only our app can receive them:
  //   • iOS  Universal Links — host apple-app-site-association (AASA) at
  //          https://<domain>/.well-known/apple-app-site-association
  //   • Android App Links    — host assetlinks.json at
  //          https://<domain>/.well-known/assetlinks.json
  // and switch Supabase redirect/email URLs to https links. That hosting/DNS
  // step is OUT OF SCOPE for this mobile-only change.
  useEffect(() => {
    async function handleUrl(url: string) {
      if (!url) return;

      // Parse BOTH the query string and the fragment; treat all as untrusted.
      const queryStr = url.includes('?') ? url.split('?')[1].split('#')[0] : '';
      const hashStr  = url.includes('#') ? url.split('#')[1] : '';
      const qp = new URLSearchParams(queryStr);
      const hp = new URLSearchParams(hashStr);
      const get = (k: string) => qp.get(k) ?? hp.get(k);

      const type       = get('type');        // 'recovery' | 'signup' | 'email' | …
      const code        = get('code');        // PKCE authorization code
      const token_hash  = get('token_hash');  // OTP / recovery verification hash
      const errParam    = get('error') ?? get('error_code');

      if (errParam) {
        console.warn('[auth] deep-link error:', errParam, get('error_description') ?? '');
      }

      // Route to the reset screen for recovery links. The recovery SESSION is
      // established below (verifyOtp / exchangeCodeForSession), never by
      // trusting tokens in the URL. Routing first just shows the UI promptly;
      // reset-password.tsx calls updateUser({password}) once the session lands.
      if (type === 'recovery') {
        setIsRecovery(true);
        router.replace('/(auth)/reset-password');
      }

      try {
        if (token_hash && type) {
          const { error } = await supabase.auth.verifyOtp({
            // EmailOtpType subset carried by Supabase email links.
            type: type as 'recovery' | 'signup' | 'email' | 'magiclink' | 'invite' | 'email_change',
            token_hash,
          });
          if (error) console.warn('[auth] verifyOtp error:', error.message);
        } else if (code) {
          const { error } = await supabase.auth.exchangeCodeForSession(code);
          if (error) console.warn('[auth] exchangeCodeForSession error:', error.message);
        }
        // NOTE: the previous unconditional
        //   supabase.auth.setSession({ access_token, refresh_token })
        // path is REMOVED. Do NOT reintroduce a setSession-from-URL path.
      } catch (e) {
        console.warn('[auth] deep-link session exchange failed:', e);
      }
    }

    Linking.getInitialURL().then(url => { if (url) handleUrl(url); });
    const sub = Linking.addEventListener('url', ({ url }) => handleUrl(url));
    return () => sub.remove();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Notification tap → deep link routing ────────────────────────────────
  // Routes the user when they tap an Expo push notification. Safe if router
  // is not ready yet (queued via setTimeout). Never throws.
  useEffect(() => {
    function routeFromNotificationData(raw: unknown) {
      try {
        if (!raw || typeof raw !== 'object') return;
        const data    = raw as Record<string, unknown>;
        const dataType    = typeof data.type === 'string' ? data.type : null;
        const listingId   = typeof data.listingId === 'string' ? data.listingId : null;
        const transferId  = typeof data.transferId === 'string' ? data.transferId : null;

        // Defer one tick — router may not be mounted at cold-start.
        const go = (path: string) => setTimeout(() => {
          try { router.push(path as any); }
          catch (e) { console.warn('[push] route failed:', e); }
        }, 0);

        // Seller-side transfer actions → send screen.
        const SELLER_TRANSFER = ['seller_action', 'ticket_sold'];
        // Buyer-side transfer actions → receive screen (it gates on the
        // delivery-info form, so it also covers "add your transfer info").
        const BUYER_TRANSFER = ['buyer_confirm', 'buyer_info_needed', 'payment_succeeded'];

        if (transferId && SELLER_TRANSFER.includes(dataType ?? '')) {
          go(`/transfer/send/${transferId}`);
        } else if (transferId && BUYER_TRANSFER.includes(dataType ?? '')) {
          go(`/transfer/receive/${transferId}`);
        } else if (transferId && dataType === 'dispute_review') {
          // notify-report sends role: 'buyer' | 'seller' — route each party
          // to their side of the disputed transfer.
          go(data.role === 'seller' ? `/transfer/send/${transferId}` : `/transfer/receive/${transferId}`);
        } else if (listingId) {
          // Everything listing-scoped lands on the listing detail:
          // bid_received, auction_won, transfer_expired_*, auto_release_*,
          // and ticket_sold / payment_succeeded fallbacks without transferId.
          go(`/listing/${listingId}`);
        }
      } catch (e) {
        console.warn('[push] routeFromNotificationData failed:', e);
      }
    }

    // Cold-start: app launched by tapping a notification
    Notifications.getLastNotificationResponseAsync()
      .then(resp => {
        if (resp?.notification?.request?.content?.data) {
          routeFromNotificationData(resp.notification.request.content.data);
        }
      })
      .catch(e => console.warn('[push] getLastNotificationResponseAsync:', e));

    // Warm: app already running when notification is tapped
    const sub = Notifications.addNotificationResponseReceivedListener(resp => {
      routeFromNotificationData(resp?.notification?.request?.content?.data);
    });
    return () => sub.remove();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
}
