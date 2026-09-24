/**
 * app/settings/appearance.tsx — Settings › Appearance (owner 2026-09-23).
 *
 * Three radio options: System (follow the phone, the default), Light, Dark. The choice applies
 * at once through the appearance store and is saved locally; nothing is sent anywhere. The
 * screen itself is drawn from the theme, so it demonstrates the choice as it is made.
 *
 * V3 (pkg8-appearance-{dark,light} boards): the pushed-screen header (circular back chip,
 * centred sentence-case title), rounded filled option rows at the card radius, and a RADIO at
 * the trailing edge — a border.control ring at rest, a brand-red ring around a red dot when
 * selected. Selection is said by the radio alone: the boards draw no fill or border change on
 * the chosen row. Copy is the boards': "Follows your phone" under System; Light and Dark carry
 * no sentence. The preference machinery — useAppearancePreference, setPreference and the three
 * stored values — is untouched.
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

const OPTIONS: { key: AppearancePreference; label: string; description?: string }[] = [
  { key: 'system', label: 'System', description: 'Follows your phone' },
  { key: 'light', label: 'Light' },
  { key: 'dark', label: 'Dark' },
];

export default function AppearanceScreen() {
  const topPad = useTopInset();
  const { palette } = useTheme();
  const { preference, setPreference } = useAppearancePreference();
  const s = useMemo(() => makeStyles(palette), [palette]);

  return (
    <View style={s.root}>
      {/* V3 pushed-screen header: circular back chip, centred sentence-case title, 44pt spacer. */}
      <View style={[s.header, { paddingTop: topPad + v2.space.sm }]}>
        <IconButton glyph="back" chip onPress={() => router.back()} accessibilityLabel="Back" />
        <Text style={[textStyle('screenTitle'), s.headerTitle]} accessibilityRole="header">Appearance</Text>
        <View style={s.headerSpacer} />
      </View>

      <ScrollView contentContainerStyle={s.body} accessibilityRole="radiogroup">
        {OPTIONS.map((o) => {
          const checked = preference === o.key;
          return (
            <Pressable
              key={o.key}
              style={s.row}
              onPress={() => setPreference(o.key)}
              accessibilityRole="radio"
              accessibilityState={{ checked: checked }}
              accessibilityLabel={o.label}
              accessibilityHint={o.description}
            >
              <View style={s.rowText}>
                <Text style={[textStyle('title'), s.label]}>{o.label}</Text>
                {o.description ? (
                  <Text style={[textStyle('bodySm'), s.description]}>{o.description}</Text>
                ) : null}
              </View>
              {/* The board's radio: a graded ring at rest, red ring + red dot when chosen. */}
              <View
                style={[s.radio, checked && s.radioChecked]}
                accessibilityElementsHidden
                importantForAccessibility="no"
              >
                {checked ? <View style={s.radioDot} /> : null}
              </View>
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}

const RADIO = 24;
const RADIO_DOT = 12;

function makeStyles(p: Palette) {
  return StyleSheet.create({
    root: { flex: 1, backgroundColor: p.surface.canvas },
    header: {
      flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
      paddingHorizontal: v2.space.md, paddingBottom: v2.space.sm,
    },
    headerTitle: { color: p.text.primary },
    headerSpacer: { width: 44 },
    body: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg, gap: v2.space.md },
    row: {
      flexDirection: 'row', alignItems: 'center', gap: v2.space.md,
      minHeight: 64,
      paddingVertical: v2.space.md, paddingHorizontal: v2.space.lg,
      borderRadius: v2.radius.md, backgroundColor: p.surface.surface,
    },
    rowText: { flex: 1, minWidth: 0, gap: 2 },
    label: { color: p.text.primary },
    description: { color: p.text.muted },
    radio: {
      width: RADIO, height: RADIO, borderRadius: RADIO / 2,
      borderWidth: 1.5, borderColor: p.border.control,
      alignItems: 'center', justifyContent: 'center',
    },
    radioChecked: { borderWidth: 2, borderColor: p.brand.red },
    radioDot: { width: RADIO_DOT, height: RADIO_DOT, borderRadius: RADIO_DOT / 2, backgroundColor: p.brand.red },
  });
}
