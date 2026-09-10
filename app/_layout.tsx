/**
 * app/_layout.tsx — Root layout / Auth gate (platform-safe)
 *
 * All native-only dependencies (Sentry, Stripe, Notifications, Linking,
 * reanimated) are isolated in src/providers/NativeAppShell which has
 * .native.tsx and .web.tsx variants resolved by the bundler.
 *
 * This file contains ZERO native-only imports, so Expo Router's
 * require.context can process it safely for both native and web builds.
 */

// FIRST import, before anything that can reach the session cipher. Hermes has no
// `crypto` global; this installs `crypto.getRandomValues` from the device RNG.
// Module evaluation follows the import graph, so a leaf-module import is order
// by luck — build 14 crashed at cold launch when that luck ran out.
import 'react-native-get-random-values';

import { DarkTheme, ThemeProvider } from '@react-navigation/native';
import { router, Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { ENV_GUARD_FAILURE, IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { useAuth } from '@/src/hooks/useAuth';
import { useIsOnboarding } from '@/src/lib/auth/onboardingGate';
import { authPhase, rootRouteDecision, type AuthPhase } from '@/src/lib/auth/rootRoute';
import { supabase } from '@/src/lib/supabase';
import ErrorBoundary from '@/src/components/ErrorBoundary';
// Imported from the leaf module (not the ui barrel) so the web-safe root layout
// pulls in no native-only siblings. Spinner's own deps are all platform-safe.
import { Spinner } from '@/src/components/ui/Spinner';
import * as v2 from '@/src/theme/v2';
import { useBrandFonts } from '@/src/theme/fonts';

// Platform-resolved: .native.tsx wraps in StripeProvider + Sentry;
// .web.tsx is a passthrough.
import {
  AppShell,
  setSentryUser,
  useNativeEffects,
  wrapRootComponent,
  // eslint-disable-next-line import/no-unresolved -- platform-suffixed module (.native/.web); tsc resolves via tsconfig moduleSuffixes
} from '@/src/providers/NativeAppShell';

export const unstable_settings = {
  anchor: '(tabs)',
};

function RootLayout() {
  const { session, loading } = useAuth();
  const [isRecovery, setIsRecovery] = useState(false);
  // Sign up creates the account partway through, so a session appears while the
  // person still has steps to answer. While that flag is raised the signup screen
  // owns navigation and this gate stays out of the way. It gates routing only:
  // it grants nothing and blocks nothing else.
  const onboarding = useIsOnboarding();
  // The phase this layout last navigated for. Navigation follows a change of
  // authentication phase, never a change of session object identity: Supabase
  // hands out a fresh session on USER_UPDATED and TOKEN_REFRESHED too, and
  // treating those as sign-ins is what threw a signed-in person out of Settings
  // phone verification and onto Home the moment the code was sent.
  const routedPhaseRef = useRef<AuthPhase | null>(null);

  // Brand typefaces. The navigator is held until these register, because
  // `fontFamily()` resolves when a StyleSheet is constructed: a screen built
  // before the faces land would keep the system face for its whole life, since
  // nothing re-renders it when loading completes. The wait is over bundled
  // assets, and a load failure reports ready, so the app can never wedge here.
  const fontsReady = useBrandFonts();

  // Native-only: deep link handling, push token registration.
  // No-op on web.
  useNativeEffects({
    userId: session?.user?.id,
    isRecovery,
    setIsRecovery,
  });

  // Detect PASSWORD_RECOVERY and route to reset screen.
  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event) => {
      if (event === 'PASSWORD_RECOVERY') {
        setIsRecovery(true);
        router.replace('/(auth)/reset-password');
      }
      if (event === 'SIGNED_OUT') {
        setIsRecovery(false);
      }
    });
    return () => subscription.unsubscribe();
  }, []);

  // Identity reporting tracks the current user on every change, including the
  // ones that must not navigate.
  useEffect(() => {
    if (loading) return;
    setSentryUser(session ? { id: session.user.id, email: session.user.email ?? undefined } : null);
  }, [session, loading]);

  // Navigation is a separate concern and runs only on a real phase boundary.
  useEffect(() => {
    const phase = authPhase(session);
    const decision = rootRouteDecision({
      loading,
      isRecovery,
      onboarding,
      phase,
      lastRoutedPhase: routedPhaseRef.current,
    });
    if (!decision.navigate) return;
    routedPhaseRef.current = phase;
    router.replace(decision.to);
  }, [session, loading, isRecovery, onboarding]);

  return (
    <ErrorBoundary>
    <AppShell>
    <SafeAreaProvider>
    <ThemeProvider value={DarkTheme}>
      {fontsReady ? (
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="(auth)" />
        <Stack.Screen name="listing/[id]" />
        <Stack.Screen name="listing/edit/[id]" />
        <Stack.Screen name="bid/[id]" />
        <Stack.Screen name="checkout/[id]" />
        <Stack.Screen name="settings/index" />
        <Stack.Screen name="settings/edit-profile" />
        <Stack.Screen name="settings/notifications" />
        <Stack.Screen name="settings/payout-setup" />
        <Stack.Screen name="settings/verify-phone" />
        <Stack.Screen name="settings/preferences" />
        <Stack.Screen name="settings/support" />
        <Stack.Screen name="settings/legal" />
        <Stack.Screen name="settings/privacy" />
        <Stack.Screen name="my-listings" />
        <Stack.Screen name="transfer/receive/[id]" />
        <Stack.Screen name="transfer/send/[id]" />
        <Stack.Screen name="payout-return" />
        <Stack.Screen name="payout-refresh" />
        <Stack.Screen name="report/[type]/[id]" />
        <Stack.Screen name="settings/blocked-users" />
        <Stack.Screen name="profile/[id]" />
      </Stack>
      ) : null}

      {(loading || !fontsReady) && (
        <View style={StyleSheet.absoluteFill} pointerEvents="none">
          <View style={styles.splash}>
            <Spinner size="large" color={v2.brand.red} label="Loading Snatch It" />
          </View>
        </View>
      )}

      {/* Environment pairing failure: a non-dismissible blocker. Rendered last so
          it covers everything, and it captures touches (no pointerEvents="none")
          so the app underneath cannot be used. */}
      {ENV_GUARD_FAILURE ? (
        <View style={StyleSheet.absoluteFill}>
          <View style={styles.envBlock}>
            <Text style={styles.envBlockTitle}>Build misconfigured</Text>
            <Text style={styles.envBlockBody}>
              This build pairs the wrong Supabase project with the wrong Stripe account and has been
              stopped before any network call.
            </Text>
            <Text style={styles.envBlockCode}>{ENV_GUARD_FAILURE}</Text>
          </View>
        </View>
      ) : null}

      {/* Unmistakable label so a sandbox build is never mistaken for production. */}
      {IS_SANDBOX_BUILD ? (
        <View style={styles.sandboxBadge} pointerEvents="none">
          <Text style={styles.sandboxBadgeText}>SANDBOX — TEST MONEY ONLY</Text>
        </View>
      ) : null}

      <StatusBar style="light" />
    </ThemeProvider>
    </SafeAreaProvider>
    </AppShell>
    </ErrorBoundary>
  );
}

// On native: Sentry.wrap(RootLayout). On web: identity (returns RootLayout).
export default wrapRootComponent(RootLayout);

const styles = StyleSheet.create({
  envBlock: {
    flex: 1,
    backgroundColor: '#1a0000',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 28,
    gap: 14,
  },
  envBlockTitle: { color: '#FF1A1A', fontSize: 22, fontWeight: '700', textAlign: 'center' },
  envBlockBody: { color: '#fff', fontSize: 15, textAlign: 'center', lineHeight: 21 },
  envBlockCode: { color: '#ffb3b3', fontSize: 12, textAlign: 'center', fontFamily: 'Courier' },
  sandboxBadge: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    backgroundColor: '#7a3b00',
    paddingTop: 52,
    paddingBottom: 6,
    alignItems: 'center',
  },
  sandboxBadgeText: { color: '#ffd9a0', fontSize: 11, fontWeight: '700', letterSpacing: 1 },
  splash: {
    flex: 1,
    backgroundColor: v2.surface.canvas,
    justifyContent: 'center',
    alignItems: 'center',
  },
});
