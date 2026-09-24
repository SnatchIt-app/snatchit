/**
 * src/components/ui/IconButton.tsx — back, close, overflow.
 *
 * There are sixteen hand-rolled back buttons in this app. Every one is a Pressable
 * wrapping a bare `←` character, and not one of them has an accessibility role or
 * a label, so a screen-reader user hears "left arrow" or nothing at all. This is
 * the replacement, and the label is required rather than optional.
 *
 * The glyphs are typographic, not emoji. `←`, `✕` and `⋯` are text characters that
 * inherit the brand face and colour; an emoji would be a colour image that ignores
 * both, which is why the product's current emoji chrome looks pasted on.
 */

import { Animated, Pressable, StyleSheet, Text, type ViewStyle } from 'react-native';
import { useMemo } from 'react';

import { MIN_TOUCH_TARGET } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

import { usePressScale } from './press';

export type IconGlyph = 'back' | 'close' | 'more' | 'search' | 'filter';

const GLYPH: Record<IconGlyph, string> = {
  // V3 (owner 2026-09-24): the approved boards draw back as a CHEVRON in a circular
  // chip, not the V2 left arrow on bare canvas.
  back: '\u2039',
  close: '✕',
  more: '⋯',
  // Typographic, not emoji: these inherit the brand face and colour. An emoji
  // magnifier would be a colour image that ignores both.
  search: '⌕',
  filter: '≡',
};

export interface IconButtonProps {
  glyph: IconGlyph;
  onPress: () => void;
  /** Required. A control with no name is unusable with a screen reader. */
  accessibilityLabel: string;
  disabled?: boolean;
  /** Over artwork, where the glyph needs a dark plate to stay legible. */
  onArt?: boolean;
  /**
   * V3: a filled circular chip behind the glyph, as the pkg8 boards draw the back
   * control on a plain screen. `onArt` already supplies its own darker plate.
   */
  chip?: boolean;
  style?: ViewStyle;
  testID?: string;
}

export function IconButton({
  glyph,
  onPress,
  accessibilityLabel,
  disabled = false,
  onArt = false,
  chip = false,
  style,
  testID,
}: IconButtonProps) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  const press = usePressScale(!disabled);
  return (
    <Animated.View style={press.style}>
      <Pressable
        onPress={disabled ? undefined : onPress}
        onPressIn={press.onPressIn}
        onPressOut={press.onPressOut}
        disabled={disabled}
        style={[styles.base, chip && styles.chip, onArt && styles.onArt, disabled && styles.disabled, style]}
        accessibilityRole="button"
        accessibilityLabel={accessibilityLabel}
        accessibilityState={{ disabled }}
        testID={testID}
      >
        <Text style={styles.glyph}>{GLYPH[glyph]}</Text>
      </Pressable>
    </Animated.View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  base: {
    width: MIN_TOUCH_TARGET,
    height: MIN_TOUCH_TARGET,
    alignItems: 'center',
    justifyContent: 'center',
    // V3: every icon control on the approved boards is a circle.
    borderRadius: v2.radius.pill,
  },
  chip: { backgroundColor: p.surface.surface },
  // A transparent control over a photograph is invisible half the time.
  onArt: { backgroundColor: 'rgba(0,0,0,0.55)' },
  disabled: { opacity: 0.4 },
  glyph: { color: p.text.primary, fontSize: 28, lineHeight: 32 },
  });
}
