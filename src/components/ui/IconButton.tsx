/**
 * src/components/ui/IconButton.tsx — back, close, overflow, search, filters.
 *
 * There are sixteen hand-rolled back buttons in this app. Every one is a Pressable
 * wrapping a bare `←` character, and not one of them has an accessibility role or
 * a label, so a screen-reader user hears "left arrow" or nothing at all. This is
 * the replacement, and the label is required rather than optional.
 *
 * THE MARKS ARE VECTORS, NOT CHARACTERS (owner ruling 2026-09-25). They used to be typographic —
 * `≡`, `⌕`, `✕`, `⋯` — chosen so they would inherit the brand face and colour instead of looking
 * like pasted-on emoji. That reasoning was sound and the result still failed, for a reason only
 * measurement found: B checked the bundled Inter and Oswald cmaps and ALL FOUR are absent from
 * both. So none of them was inheriting the brand face; every one was being drawn by whatever
 * fallback font iOS picked, at a weight, size and baseline nobody chose. A glyph that is not in the
 * font does not inherit the font.
 *
 * They now go through `components/ui/icon-symbol` — the app's existing icon implementation, SF
 * Symbols on iOS with a Material fallback elsewhere, already used by the dock. Vector marks cannot
 * fall back to another face, and one implementation means the chrome and the dock agree.
 *
 * The filter mark changes MEANING as well as rendering: `≡` is a hamburger, which says MENU in an
 * interface (and IDENTICAL TO in mathematics). `line.3.horizontal.decrease` is three lines of
 * decreasing length, which is what a filter control looks like everywhere — B's F-91-6.
 *
 * Unchanged: the 44x44 target, the required accessible label, the count badge, and the dark plate
 * that `onArt` paints so a mark stays legible over a photograph.
 */

import { Animated, Pressable, StyleSheet, Text, View, type ViewStyle } from 'react-native';
import { useMemo } from 'react';

import { IconSymbol } from '@/components/ui/icon-symbol';
import { MIN_TOUCH_TARGET } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

import { usePressScale } from './press';

export type IconGlyph = 'back' | 'close' | 'more' | 'search' | 'filter';

/**
 * The SF Symbol for each mark, with its Material counterpart mapped in `icon-symbol.tsx`.
 *
 * `back` is a chevron rather than an arrow because the approved V3 boards draw it that way, in a
 * circular chip — the V2 left arrow on bare canvas is gone.
 */
const SYMBOL: Record<IconGlyph, 'chevron.left' | 'xmark' | 'ellipsis' | 'magnifyingglass' | 'line.3.horizontal.decrease'> = {
  back: 'chevron.left',
  close: 'xmark',
  more: 'ellipsis',
  search: 'magnifyingglass',
  filter: 'line.3.horizontal.decrease',
};

/** The mark's drawn size inside the 44pt target. Matches the optical size of the old 28pt glyphs. */
const MARK = 24;

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
        <IconSymbol
          name={SYMBOL[glyph]}
          size={MARK}
          // Over artwork the mark takes the invariant over-art ink on its own dark plate; elsewhere
          // it follows the appearance. Same two inks the typed glyphs used, so only the RENDERING
          // changed here, not the colour vocabulary.
          color={onArt ? palette.onArt.primary : palette.text.primary}
        />
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
