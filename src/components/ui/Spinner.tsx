/**
 * src/components/ui/Spinner.tsx — the busy indicator, wrapped once.
 *
 * It exists so that a screen reader announces "busy" instead of nothing, and so
 * that a reduced-motion user gets a static mark rather than a spinning one. The
 * platform indicator does neither on its own.
 */

import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import { useMemo } from 'react';

import { useReducedMotion } from '@/src/hooks/useReducedMotion';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';

export function Spinner({
  color: colorProp,
  size = 'small',
  label = 'Loading',
  decorative = false,
}: {
  color?: string;
  size?: 'small' | 'large';
  label?: string;
  /**
   * The spinner is beside VISIBLE text that already says the same thing, so its own announcement
   * would be the second reading of one fact (E's finding on the checkout status row, 2026-09-24).
   * The motion stays; only the accessibility node goes.
   */
  decorative?: boolean;
}) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  const color = colorProp ?? palette.text.primary;
  const reduceMotion = useReducedMotion();

  const a11y = decorative
    ? { accessibilityElementsHidden: true, importantForAccessibility: 'no' as const }
    : { accessibilityRole: 'progressbar' as const, accessibilityLabel: label };

  if (reduceMotion) {
    return (
      <View style={styles.static} {...a11y}>
        <Text style={[textStyle('micro'), { color }]}>{'• • •'}</Text>
      </View>
    );
  }

  return (
    <ActivityIndicator color={color} size={size} {...a11y} />
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  static: { alignItems: 'center', justifyContent: 'center' },
  });
}
