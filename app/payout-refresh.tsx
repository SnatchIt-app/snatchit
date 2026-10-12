/**
 * app/payout-refresh.tsx — Stripe Connect onboarding refresh target (V2).
 *
 * PRESENTATION rebuilt on the V2 system; behaviour unchanged. Stripe redirects
 * sellers here when the onboarding link expired or they exited mid-flow — this is
 * normal, not an error, so no red treatment. Auto-routes back to payout setup
 * (router.replace) with a manual Continue button.
 */

import { useEffect, useMemo } from 'react';
import { router } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';

import { Badge, Button } from '@/src/components/ui';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

const AUTO_REDIRECT_MS = 1500;
const RETRY_PATH = '/settings/payout-setup';

export default function PayoutRefreshScreen() {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);

  useEffect(() => {
    const timer = setTimeout(() => { router.replace(RETRY_PATH); }, AUTO_REDIRECT_MS);
    return () => clearTimeout(timer);
  }, []);

  return (
    <View style={s.root}>
      <SettingsHeader title="Payouts" onBack={() => router.replace(RETRY_PATH)} />
      <View style={s.body}>
        <Badge label="Setup incomplete" tone="warning" />
        <Text style={[textStyle('displayMd'), s.title]} accessibilityRole="header">Let&apos;s try that again</Text>
        <Text style={[textStyle('body'), s.subtitle]}>
          Your payout setup link expired or didn&apos;t finish. We&apos;ll send you back to start a fresh setup.
        </Text>
        <Button label="Continue" onPress={() => router.replace(RETRY_PATH)} block style={s.cta} />
      </View>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  root: { flex: 1, backgroundColor: p.surface.canvas },
  body: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: v2.space.xl, gap: v2.space.md },
  title: { color: p.text.primary, textAlign: 'center', marginTop: v2.space.sm },
  subtitle: { color: p.text.secondary, textAlign: 'center', maxWidth: 360 },
  cta: { marginTop: v2.space.lg, alignSelf: 'stretch' },
  });
}
