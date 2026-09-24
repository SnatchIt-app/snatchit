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

import { Animated, Pressable, StyleSheet, Text, View, type ViewStyle } from 'react-native';
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
  /**
   * A quantity the control is currently carrying — the number of active filters, say. Drawn as a
   * small quiet pill on the glyph's shoulder, and ONLY when it is greater than zero: the control
   * stays visible and identical at zero, because hiding or re-marking it would remove the only entry
   * point to what it opens. The spoken name is the caller's job; it must include the number.
   */
  count?: number;
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
  count,
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
        <Text style={[styles.glyph, onArt && styles.glyphOnArt]}>{GLYPH[glyph]}</Text>
        {count != null && count > 0 ? (
          // Decorative: the number is already in the control's spoken name, so a screen reader
          // meeting it twice would be reading the same fact twice.
          <View style={styles.count} accessibilityElementsHidden importantForAccessibility="no">
            <Text style={styles.countLabel} numberOfLines={1}>{count}</Text>
          </View>
        ) : null}
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
  /**
   * OVER ARTWORK the glyph joins the over-artwork inks (E's finding on B's Light listing render,
   * 2026-09-24). `onArt` paints a dark plate and the glyph was still `text.primary`, which is
   * near-black in Light: measured 1.02:1 — the back control could not be seen at all. The plate is
   * dark in both appearances, so the ink on it has to be too.
   */
  glyphOnArt: { color: p.onArt.primary },
  /**
   * The count, in the V3 selected-chip treatment: the primary ink filled, the label in the canvas.
   * Quiet on purpose — it reports a state, it does not ask for attention, so it is not the brand red
   * a warning would use.
   */
  count: {
    position: 'absolute',
    top: 4,
    right: 2,
    minWidth: 16,
    height: 16,
    paddingHorizontal: 4,
    borderRadius: v2.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: p.text.primary,
  },
  countLabel: { color: p.surface.canvas, fontSize: 11, lineHeight: 14, fontWeight: '600' },
  });
}
