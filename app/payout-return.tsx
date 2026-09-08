/**
 * app/payout-return.tsx — Stripe Connect onboarding return target (V2).
 *
 * PRESENTATION rebuilt on the V2 system; behaviour unchanged. Stripe redirects
 * sellers here after Express onboarding; the profile screen verifies the real
 * status on focus. Auto-routes to Profile after a short confirmation (router.replace
 * so back doesn't return to this landing page), with a manual Continue button.
 */

import { useEffect } from 'react';
import { router } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';

import { Badge, Button } from '@/src/components/ui';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

const AUTO_REDIRECT_MS = 1500;

export default function PayoutReturnScreen() {
  useEffect(() => {
    const timer = setTimeout(() => { router.replace('/(tabs)/profile'); }, AUTO_REDIRECT_MS);
    return () => clearTimeout(timer);
  }, []);

  return (
    <View style={s.root}>
      <SettingsHeader title="Payouts" onBack={() => router.replace('/(tabs)/profile')} />
      <View style={s.body}>
        <Badge label="Connected" tone="success" />
        <Text style={[textStyle('displayMd'), s.title]} accessibilityRole="header">Payout setup complete</Text>
        <Text style={[textStyle('body'), s.subtitle]}>
          Your Stripe account is connected. You&apos;re ready to receive payouts when your tickets sell.
        </Text>
        <Button label="Continue to profile" onPress={() => router.replace('/(tabs)/profile')} block style={s.cta} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },
  body: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: v2.space.xl, gap: v2.space.md },
  title: { color: v2.text.primary, textAlign: 'center', marginTop: v2.space.sm },
  subtitle: { color: v2.text.secondary, textAlign: 'center', maxWidth: 360 },
  cta: { marginTop: v2.space.lg, alignSelf: 'stretch' },
});
