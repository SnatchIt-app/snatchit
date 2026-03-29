/**
 * app/_layout.tsx  — Root layout / Auth gate
 *
 * This is the very first component Expo Router mounts.
 * It checks whether a Supabase session exists and routes accordingly:
 *   Logged in  → /(tabs)/home
 *   Logged out → /(auth)/login
 *
 * The <Stack> is always rendered so the navigator exists before
 * router.replace() is called from useEffect (avoids Expo Router crash).
 */

import * as Sentry from '@sentry/react-native';
import { DarkTheme, ThemeProvider } from '@react-navigation/native';
import Constants from 'expo-constants';
import { router, Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useState } from 'react';
import { ActivityIndicator, StyleSheet, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import 'react-native-reanimated';

// release: matches the format expected by the Sentry source map uploader.
// dist:    build number within the release — required for iOS/Android map lookup.
// Both must be set before any errors can be symbolicated.
const _version  = Constants.expoConfig?.version ?? '1.0.0';
const _build    = Constants.expoConfig?.ios?.buildNumber
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

import * as Linking from 'expo-linking';
import * as Notifications from 'expo-notifications';
import { useAuth } from '@/src/hooks/useAuth';
import { supabase } from '@/src/lib/supabase';
import { usePushToken } from '@/src/hooks/usePushToken';
import { StripeProvider } from '@stripe/stripe-react-native';
import ErrorBoundary from '@/src/components/ErrorBoundary';
import { APP_CONFIG } from '@/src/config/app';
import { colors } from '@/src/theme';

// Show notifications even when the app is in the foreground
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true,
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

export const unstable_settings = {
  // Keeps /(tabs)/home as the default anchor for deep-links.
  anchor: '(tabs)',
};

function RootLayout() {
  const { session, loading } = useAuth();
  const [isRecovery, setIsRecovery] = useState(false);

  // Register Expo push token on every app launch (only runs when authenticated)
  usePushToken(session?.user?.id);

  // ── Deep link handler ─────────────────────────────────────────────────────
  // Supabase mobile recovery links deliver tokens in the URL hash fragment:
  //   snatchit://...#access_token=xxx&refresh_token=yyy&type=recovery
  //
  // RACE FIX: if the URL contains type=recovery we set isRecovery=true and
  // route to the reset screen SYNCHRONOUSLY before calling setSession.
  // This means the normal "if session → go home" redirect sees isRecovery=true
  // before the session ever lands, so it never fires.
  async function handleUrl(url: string) {
    if (!url) return;
    const hash   = url.includes('#') ? url.split('#')[1] : url.split('?')[1] ?? '';
    const params = new URLSearchParams(hash);
    const type          = params.get('type');
    const access_token  = params.get('access_token');
    const refresh_token = params.get('refresh_token');

    // Lock out the normal redirect and navigate first — before any await.
    if (type === 'recovery') {
      setIsRecovery(true);
      router.replace('/(auth)/reset-password');
    }

    if (access_token && refresh_token) {
      const { error } = await supabase.auth.setSession({ access_token, refresh_token });
      if (error) console.warn('[auth] setSession error:', error.message);
    }
  }

  // Cold-start URL + subsequent deep links
  useEffect(() => {
    Linking.getInitialURL().then(url => { if (url) handleUrl(url); });
    const sub = Linking.addEventListener('url', ({ url }) => handleUrl(url));
    return () => sub.remove();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Detect PASSWORD_RECOVERY and route to reset screen.
  // Clear isRecovery on SIGNED_OUT so normal auth redirects resume.
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

  useEffect(() => {
    // Don't redirect while we're still reading the cached session.
    if (loading) return;
    // PASSWORD_RECOVERY handler already routed to reset-password screen.
    if (isRecovery) return;

    if (session) {
      // Attach user identity to all subsequent Sentry events so errors can
      // be attributed to specific users and counted as unique-user impact.
      // id + email are safe to send; no PII beyond what Sentry already allows.
      Sentry.setUser({ id: session.user.id, email: session.user.email ?? undefined });
      router.replace('/(tabs)/home');
    } else {
      // Clear user context on sign-out so errors after logout are anonymous.
      Sentry.setUser(null);
      router.replace('/(auth)/login');
    }
  }, [session, loading, isRecovery]);

  return (
    <ErrorBoundary>
    <StripeProvider
      publishableKey={APP_CONFIG.STRIPE_PUBLISHABLE_KEY}
      merchantIdentifier="merchant.com.snatchit"
    >
    <SafeAreaProvider>
    <ThemeProvider value={DarkTheme}>
      {/* Navigator always mounted */}
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="(auth)" />
        {/* Route names must exactly match the file-system paths under app/ */}
        <Stack.Screen name="listing/[id]" />
        <Stack.Screen name="bid/[id]" />
        <Stack.Screen name="checkout/[id]" />
        <Stack.Screen name="settings/index" />
        <Stack.Screen name="settings/edit-profile" />
        <Stack.Screen name="settings/notifications" />
        <Stack.Screen name="settings/payment-methods" />
        <Stack.Screen name="settings/payout-setup" />
        <Stack.Screen name="settings/preferences" />
        <Stack.Screen name="settings/support" />
        <Stack.Screen name="settings/legal" />
        <Stack.Screen name="my-listings" />
        <Stack.Screen
          name="modal"
          options={{ presentation: 'modal', headerShown: true, title: 'Modal' }}
        />
      </Stack>

      {/* Black splash overlay while the session check is in progress */}
      {loading && (
        <View style={StyleSheet.absoluteFill} pointerEvents="none">
          <View style={styles.splash}>
            <ActivityIndicator color={colors.accent} size="large" />
          </View>
        </View>
      )}

      <StatusBar style="light" />
    </ThemeProvider>
    </SafeAreaProvider>
    </StripeProvider>
    </ErrorBoundary>
  );
}

export default Sentry.wrap(RootLayout);

const styles = StyleSheet.create({
  splash: {
    flex: 1,
    backgroundColor: colors.bg,
    justifyContent: 'center',
    alignItems: 'center',
  },
});
