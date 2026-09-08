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

import { MIN_TOUCH_TARGET } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

import { usePressScale } from './press';

export type IconGlyph = 'back' | 'close' | 'more' | 'search' | 'filter';

const GLYPH: Record<IconGlyph, string> = {
  back: '←',
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
  style?: ViewStyle;
  testID?: string;
}

export function IconButton({
  glyph,
  onPress,
  accessibilityLabel,
  disabled = false,
  onArt = false,
  style,
  testID,
}: IconButtonProps) {
  const press = usePressScale(!disabled);
  return (
    <Animated.View style={press.style}>
      <Pressable
        onPress={disabled ? undefined : onPress}
        onPressIn={press.onPressIn}
        onPressOut={press.onPressOut}
        disabled={disabled}
        style={[styles.base, onArt && styles.onArt, disabled && styles.disabled, style]}
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

const styles = StyleSheet.create({
  base: {
    width: MIN_TOUCH_TARGET,
    height: MIN_TOUCH_TARGET,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: v2.radius.none,
  },
  // A transparent control over a photograph is invisible half the time.
  onArt: { backgroundColor: 'rgba(0,0,0,0.55)' },
  disabled: { opacity: 0.4 },
  glyph: { color: v2.text.primary, fontSize: 22, lineHeight: 26 },
});
