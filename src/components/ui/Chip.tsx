/**
 * src/components/ui/Chip.tsx — filter and selection chip.
 *
 * Square, hairline, uppercase label. Selected fills with a 10% red tint and takes
 * a red border; the label goes white rather than red, because a red label on a red
 * tint is the kind of thing that looks fine on a designer's monitor and vanishes
 * on a phone in a dark club.
 *
 * Chips scroll horizontally in one row. They never wrap to a second line — that is
 * a filter bar turning into a wall.
 */

import { Animated, Pressable, StyleSheet, Text, type ViewStyle } from 'react-native';
import { useMemo } from 'react';

import { hapticSelect } from '@/src/lib/feedback/haptics';
import { textStyle, MAX_DISPLAY_FONT_SCALE } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

import { usePressScale } from './press';

export interface ChipProps {
  label: string;
  selected?: boolean;
  onPress?: () => void;
  disabled?: boolean;
  /** Optional trailing count, e.g. a filter's match count. */
  count?: number;
  style?: ViewStyle;
  testID?: string;
}

export function Chip({
  label,
  selected = false,
  onPress,
  disabled = false,
  count,
  style,
  testID,
}: ChipProps) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  const press = usePressScale(!disabled);
  const text = count == null ? label : `${label} ${count}`;

  // A chip is a selection, so the selection tick lives here (CFT-202). The
  // visible equivalent is the selected fill the parent renders on the next
  // frame; the tick is never the only feedback.
  const select = disabled || !onPress ? undefined : () => { hapticSelect(); onPress(); };

  return (
    <Animated.View style={press.style}>
      <Pressable
        onPress={select}
        onPressIn={press.onPressIn}
        onPressOut={press.onPressOut}
        disabled={disabled}
        // 32pt tall by design; hitSlop carries it to the 44pt minimum.
        hitSlop={{ top: 6, bottom: 6, left: 4, right: 4 }}
        style={[styles.base, selected && styles.selected, disabled && styles.disabled, style]}
        accessibilityRole="button"
        accessibilityLabel={text}
        accessibilityState={{ selected, disabled }}
        testID={testID}
      >
        <Text
          style={[textStyle('label'), selected ? styles.labelOn : styles.labelOff]}
          numberOfLines={1}
          maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}
        >
          {text}
        </Text>
      </Pressable>
    </Animated.View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  base: {
    minHeight: 32,
    paddingHorizontal: v2.space.md,
    borderRadius: v2.radius.none,
    borderWidth: 1,
    borderColor: p.border.default,
    alignItems: 'center',
    justifyContent: 'center',
  },
  selected: {
    borderColor: p.brand.red,
    backgroundColor: p.brand.redSoft,
  },
  disabled: { opacity: 0.4 },
  labelOff: { color: p.text.muted },
  labelOn: { color: p.text.primary },
  });
}
