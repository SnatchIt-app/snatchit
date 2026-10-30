/**
 * app/payout-return.tsx — Stripe Connect onboarding return target.
 *
 * Stripe sends the seller here whenever they LEAVE Express onboarding — finished or not — so
 * arriving here establishes nothing. This screen used to render a success badge, "Payout setup
 * complete" and "Your Stripe account is connected" unconditionally and then auto-route to Profile.
 * Owner truth: returning from another app never confirms or releases anything (F5, 2026-10-12).
 *
 * It now claims nothing and hands off to /settings/payout-setup, which verifies the real status
 * through the `status_only` probe and owns the settled wording ("Not connected" / "Connected").
 * router.replace, so back does not return to this landing page.
 */

import { useEffect, useMemo } from 'react';
import { router } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';

import { Spinner } from '@/src/components/ui';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

const HANDOFF_MS = 400;
const VERIFY_ROUTE = '/settings/payout-setup';

export default function PayoutReturnScreen() {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);

  useEffect(() => {
    const timer = setTimeout(() => { router.replace(VERIFY_ROUTE); }, HANDOFF_MS);
    return () => clearTimeout(timer);
  }, []);

  return (
    <View style={s.root}>
      <SettingsHeader title="Payouts" onBack={() => router.replace(VERIFY_ROUTE)} />
      <View style={s.body}>
        <Spinner />
        <Text style={[textStyle('body'), s.subtitle]} accessibilityRole="text">
          Checking your payout setup…
        </Text>
      </View>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  root: { flex: 1, backgroundColor: p.surface.canvas },
  body: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: v2.space.xl, gap: v2.space.md },
  subtitle: { color: p.text.secondary, textAlign: 'center', maxWidth: 360 },
  });
}
