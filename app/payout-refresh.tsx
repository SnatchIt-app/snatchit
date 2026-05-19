/**
 * app/payout-refresh.tsx — Stripe Connect onboarding refresh target.
 *
 * Stripe redirects sellers here when their Express onboarding link expired
 * or they exited mid-flow. We send them back to /settings/payout-setup,
 * which generates a fresh onboarding URL.
 *
 * Behavior:
 *   • Show a clean retry state — no "error" / red treatment, this is normal
 *     when a link expires.
 *   • Auto-route to /settings/payout-setup after a short pause.
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
const RETRY_PATH = '/settings/payout-setup';

export default function PayoutRefreshScreen() {
  useEffect(() => {
    const timer = setTimeout(() => {
      router.replace(RETRY_PATH);
    }, AUTO_REDIRECT_MS);
    return () => clearTimeout(timer);
  }, []);

  return (
    <SafeAreaView style={s.safe}>
      <View style={s.container}>
        <View style={s.iconWrap}>
          <Text style={s.icon}>{'\u21BB'}</Text>
        </View>

        <Text style={s.title}>Let{"\u2019"}s try that again</Text>
        <Text style={s.subtitle}>
          Your payout setup link expired or didn{"\u2019"}t finish. We{"\u2019"}ll
          send you back to start a fresh setup.
        </Text>

        <ActivityIndicator
          color={colors.accent}
          size="small"
          style={s.loader}
        />

        <TouchableOpacity
          style={s.button}
          onPress={() => router.replace(RETRY_PATH)}
          activeOpacity={0.85}
          accessibilityRole="button"
          accessibilityLabel="Continue to payout setup"
        >
          <Text style={s.buttonText}>Continue</Text>
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
    borderColor: colors.accent,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.lg,
  },
  icon: {
    fontSize: 36,
    color: colors.accent,
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
