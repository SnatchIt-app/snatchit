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

import { DarkTheme, ThemeProvider } from '@react-navigation/native';
import { router, Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useState } from 'react';
import { ActivityIndicator, StyleSheet, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { useAuth } from '@/src/hooks/useAuth';
import { supabase } from '@/src/lib/supabase';
import ErrorBoundary from '@/src/components/ErrorBoundary';
import { colors } from '@/src/theme';

// Platform-resolved: .native.tsx wraps in StripeProvider + Sentry;
// .web.tsx is a passthrough.
import {
  AppShell,
  setSentryUser,
  useNativeEffects,
  wrapRootComponent,
} from '@/src/providers/NativeAppShell';

export const unstable_settings = {
  anchor: '(tabs)',
};

function RootLayout() {
  const { session, loading } = useAuth();
  const [isRecovery, setIsRecovery] = useState(false);

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

  useEffect(() => {
    if (loading) return;
    if (isRecovery) return;

    if (session) {
      setSentryUser({ id: session.user.id, email: session.user.email ?? undefined });
      router.replace('/(tabs)/home');
    } else {
      setSentryUser(null);
      router.replace('/(auth)/login');
    }
  }, [session, loading, isRecovery]);

  return (
    <ErrorBoundary>
    <AppShell>
    <SafeAreaProvider>
    <ThemeProvider value={DarkTheme}>
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="(auth)" />
        <Stack.Screen name="listing/[id]" />
        <Stack.Screen name="bid/[id]" />
        <Stack.Screen name="checkout/[id]" />
        <Stack.Screen name="settings/index" />
        <Stack.Screen name="settings/edit-profile" />
        <Stack.Screen name="settings/notifications" />
        <Stack.Screen name="settings/payout-setup" />
        <Stack.Screen name="settings/preferences" />
        <Stack.Screen name="settings/support" />
        <Stack.Screen name="settings/legal" />
        <Stack.Screen name="settings/privacy" />
        <Stack.Screen name="my-listings" />
        <Stack.Screen name="transfer/receive/[id]" />
        <Stack.Screen name="transfer/send/[id]" />
        <Stack.Screen
          name="modal"
          options={{ presentation: 'modal', headerShown: true, title: 'Modal' }}
        />
      </Stack>

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
    </AppShell>
    </ErrorBoundary>
  );
}

// On native: Sentry.wrap(RootLayout). On web: identity (returns RootLayout).
export default wrapRootComponent(RootLayout);

const styles = StyleSheet.create({
  splash: {
    flex: 1,
    backgroundColor: colors.bg,
    justifyContent: 'center',
    alignItems: 'center',
  },
});
