/**
 * app/settings/appearance.tsx — Settings › Appearance (owner 2026-09-23).
 *
 * Three radio options: System (follow the phone, the default), Light, Dark. The choice applies
 * at once through the appearance store and is saved locally; nothing is sent anywhere. The
 * screen itself is drawn from the theme, so it demonstrates the choice as it is made.
 */

import { router } from 'expo-router';
import { useMemo } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { IconButton } from '@/src/components/ui';
import { useTopInset } from '@/src/lib/nav/navInsets';
import type { AppearancePreference } from '@/src/lib/appearance/appearanceStore';
import { useAppearancePreference, useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

const OPTIONS: { key: AppearancePreference; label: string; description: string }[] = [
  { key: 'system', label: 'System', description: 'Follows your phone’s light or dark setting.' },
  { key: 'light', label: 'Light', description: 'Always light, whatever the phone is set to.' },
  { key: 'dark', label: 'Dark', description: 'Always dark, whatever the phone is set to.' },
];

export default function AppearanceScreen() {
  const topPad = useTopInset();
  const { palette } = useTheme();
  const { preference, setPreference } = useAppearancePreference();
  const s = useMemo(() => makeStyles(palette), [palette]);

  return (
    <View style={s.root}>
      <View style={[s.header, { paddingTop: topPad + v2.space.sm }]}>
        <IconButton glyph="back" onPress={() => router.back()} accessibilityLabel="Back" />
        <Text style={[textStyle('displaySm'), s.headerTitle]} accessibilityRole="header">Appearance</Text>
        <View style={s.headerSpacer} />
      </View>

      <ScrollView contentContainerStyle={s.body} accessibilityRole="radiogroup">
        {OPTIONS.map((o) => {
          const checked = preference === o.key;
          return (
            <Pressable
              key={o.key}
              style={[s.row, checked && s.rowChecked]}
              onPress={() => setPreference(o.key)}
              accessibilityRole="radio"
              accessibilityState={{ checked: checked }}
              accessibilityLabel={o.label}
              accessibilityHint={o.description}
            >
              <View style={s.rowText}>
                <Text style={[textStyle('title'), s.label]}>{o.label}</Text>
                <Text style={[textStyle('bodySm'), s.description]}>{o.description}</Text>
              </View>
              <Text style={[textStyle('title'), s.mark]} accessibilityElementsHidden importantForAccessibility="no">
                {checked ? '✓' : ''}
              </Text>
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
    root: { flex: 1, backgroundColor: p.surface.canvas },
    header: {
      flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
      paddingHorizontal: v2.space.md, paddingBottom: v2.space.sm,
      borderBottomWidth: 1, borderBottomColor: p.border.default,
    },
    headerTitle: { color: p.text.primary },
    headerSpacer: { width: 44 },
    body: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg, gap: v2.space.sm },
    row: {
      flexDirection: 'row', alignItems: 'center', gap: v2.space.md,
      paddingVertical: v2.space.md, paddingHorizontal: v2.space.md,
      borderWidth: 1, borderColor: p.border.default, backgroundColor: p.surface.surface,
    },
    rowChecked: { borderColor: p.brand.red, backgroundColor: p.brand.redSoft },
    rowText: { flex: 1, minWidth: 0, gap: 2 },
    label: { color: p.text.primary },
    description: { color: p.text.muted },
    mark: { color: p.brand.redText, width: 24, textAlign: 'center' },
  });
}
