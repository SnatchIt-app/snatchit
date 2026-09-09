/**
 * src/components/ui/Spinner.tsx — the busy indicator, wrapped once.
 *
 * It exists so that a screen reader announces "busy" instead of nothing, and so
 * that a reduced-motion user gets a static mark rather than a spinning one. The
 * platform indicator does neither on its own.
 */

import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';

import { useReducedMotion } from '@/src/hooks/useReducedMotion';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export function Spinner({
  color = v2.text.primary,
  size = 'small',
  label = 'Loading',
}: {
  color?: string;
  size?: 'small' | 'large';
  label?: string;
}) {
  const reduceMotion = useReducedMotion();

  if (reduceMotion) {
    return (
      <View style={styles.static} accessibilityRole="progressbar" accessibilityLabel={label}>
        <Text style={[textStyle('micro'), { color }]}>{'• • •'}</Text>
      </View>
    );
  }

  return (
    <ActivityIndicator
      color={color}
      size={size}
      accessibilityRole="progressbar"
      accessibilityLabel={label}
    />
  );
}

const styles = StyleSheet.create({
  static: { alignItems: 'center', justifyContent: 'center' },
});
