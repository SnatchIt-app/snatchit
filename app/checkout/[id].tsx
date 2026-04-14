/**
 * app/checkout/[id].tsx — Checkout route (platform-safe)
 *
 * NO native-only imports here. On native, the real Stripe checkout is
 * loaded via require() so the import is invisible to webpack / Expo web.
 * On web, a simple fallback is rendered inline.
 */

import { Platform } from 'react-native';
import { router } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, fontSize, radius, spacing } from '@/src/theme';

let CheckoutNative: React.ComponentType<any> | null = null;

if (Platform.OS !== 'web') {
  // Dynamic require — webpack (web) never evaluates this branch.
  CheckoutNative = require('@/src/screens/checkout/CheckoutNative').default;
}

export default function CheckoutRoute() {
  if (Platform.OS === 'web' || !CheckoutNative) {
    return (
      <View style={s.container}>
        <View style={s.card}>
          <Text style={s.icon}>{'\uD83D\uDCF1'}</Text>
          <Text style={s.title}>Mobile App Required</Text>
          <Text style={s.body}>
            Checkout is only available in the mobile app.
          </Text>
          <Pressable style={s.btn} onPress={() => router.back()}>
            <Text style={s.btnText}>{'\u2190'} Go Back</Text>
          </Pressable>
        </View>
      </View>
    );
  }

  return <CheckoutNative />;
}

const s = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bg,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.lg,
  },
  card: {
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.xl,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.bgCard,
    maxWidth: 400,
    width: '100%',
  },
  icon: { fontSize: 48 },
  title: {
    fontSize: fontSize.xl,
    fontWeight: '800',
    color: colors.text,
    textAlign: 'center',
  },
  body: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    textAlign: 'center',
    lineHeight: 20,
  },
  btn: {
    marginTop: spacing.sm,
    backgroundColor: colors.primary,
    borderRadius: radius.md,
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.xl,
  },
  btnText: {
    color: colors.text,
    fontSize: fontSize.sm,
    fontWeight: '700',
  },
});
