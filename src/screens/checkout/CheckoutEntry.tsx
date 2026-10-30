/**
 * src/screens/checkout/CheckoutEntry.tsx — the base (non-native) checkout entry.
 *
 * Metro resolves CheckoutEntry.native.tsx on native and THIS file everywhere
 * else, so it is what the web bundle gets. It imports no native module, which is
 * what keeps @stripe/stripe-react-native (and its native-only code) out of the
 * web build. A base .tsx rather than a .web.tsx so the eslint TS resolver can
 * resolve the import from the bracketed route file app/checkout/[id].tsx.
 * Checkout runs in the mobile app; web explains that.
 */
import { router } from 'expo-router';
import { useMemo } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { Button } from '@/src/components/ui';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export default function CheckoutWeb() {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  return (
    <View style={s.wrap}>
      <View style={s.card}>
        <Text style={[textStyle('displaySm'), s.title]} accessibilityRole="header">
          Open the app to check out
        </Text>
        <Text style={[textStyle('body'), s.body]}>
          Payments run in the Snatch It mobile app.
        </Text>
        <Button label="Go back" variant="secondary" size="md" onPress={() => router.back()} />
      </View>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  wrap: { flex: 1, backgroundColor: p.surface.canvas, alignItems: 'center', justifyContent: 'center', padding: v2.space.lg },
  card: { alignItems: 'center', gap: v2.space.md, maxWidth: 400, width: '100%' },
  title: { color: p.text.primary, textAlign: 'center' },
  body: { color: p.text.muted, textAlign: 'center' },
});
}
