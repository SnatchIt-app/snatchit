/**
 * app/payout-return.tsx — Stripe Connect onboarding return target.
 *
 * Stripe redirects sellers here after they finish (or believe they finished)
 * Express onboarding. Whether the connection is fully active is verified
 * by the profile screen on focus via create-connect-account?status_only=true.
 *
 * Behavior:
 *   • Show a clean success state.
 *   • Auto-route to /(tabs)/profile after a short confirmation moment so
 *     the user is never stranded on this screen.
 *   • Use router.replace() so back-button doesn't return to this redirect
 *     landing page.
 *
 * Web + native: pure React Native primitives, no native-only deps.
 */

import { useEffect } from 'react';
import { router } from 'expo-router';
import {
  ActivityIndicator,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { colors, fontSize, radius, spacing } from '@/src/theme';

const AUTO_REDIRECT_MS = 1500;

export default function PayoutReturnScreen() {
  useEffect(() => {
    const timer = setTimeout(() => {
      router.replace('/(tabs)/profile');
    }, AUTO_REDIRECT_MS);
    return () => clearTimeout(timer);
  }, []);

  return (
    <SafeAreaView style={s.safe}>
      <View style={s.container}>
        <View style={s.iconWrap}>
          <Text style={s.icon}>{'\u2713'}</Text>
        </View>

        <Text style={s.title}>Payout setup complete</Text>
        <Text style={s.subtitle}>
          Your Stripe account is connected. You{"\u2019"}re ready to receive
          payouts when your tickets sell.
        </Text>

        <ActivityIndicator
          color={colors.accent}
          size="small"
          style={s.loader}
        />

        <TouchableOpacity
          style={s.button}
          onPress={() => router.replace('/(tabs)/profile')}
          activeOpacity={0.85}
          accessibilityRole="button"
          accessibilityLabel="Continue to profile"
        >
          <Text style={s.buttonText}>Continue to Profile</Text>
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: colors.bg,
  },
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: spacing.xl,
  },
  iconWrap: {
    width: 72,
    height: 72,
    borderRadius: 36,
    backgroundColor: colors.bgCard,
    borderWidth: 2,
    borderColor: colors.success,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.lg,
  },
  icon: {
    fontSize: 36,
    color: colors.success,
    fontWeight: '800',
    lineHeight: 40,
  },
  title: {
    fontSize: fontSize.lg,
    fontWeight: '800',
    color: colors.text,
    textAlign: 'center',
    marginBottom: spacing.sm,
  },
  subtitle: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: spacing.lg,
    maxWidth: 360,
  },
  loader: {
    marginBottom: spacing.lg,
  },
  button: {
    backgroundColor: colors.accent,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.xl,
    borderRadius: radius.md,
    alignItems: 'center',
    minWidth: 220,
  },
  buttonText: {
    color: colors.text,
    fontWeight: '700',
    fontSize: fontSize.md,
    letterSpacing: 0.5,
  },
});
