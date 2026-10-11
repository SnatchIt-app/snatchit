/**
 * src/components/ui/Button.tsx — the only button in the product.
 *
 * Today every screen hand-rolls its own: 335 touchables across `app/` and `src/`,
 * with their own padding, their own radius and their own disabled treatment. This
 * replaces that, one screen at a time.
 *
 * BRAND RULES ENCODED HERE, not left to the caller:
 *  - Primary is `#FF1A1A` with a BLACK label. Black on red is the signature.
 *  - Destructive is a DIFFERENT red (`status.error`) and is never a filled block,
 *    so a delete can never look like a purchase. In the legacy theme they were
 *    the same colour, which is a usability defect rather than a style choice.
 *  - V3 (owner 2026-09-24, pkg8 boards): the action is a PILL with a sentence-case
 *    label. The V2 rule this replaced — "Radius 0, there is no pill button in this
 *    brand", with an uppercase 2.2-tracked label — was measured from the V2 web
 *    system and is superseded by the approved boards. Black-on-red is unchanged.
 *  - There is no filled secondary. Secondary is a hairline and a white label.
 */

import { Animated, Pressable, StyleSheet, Text, View, type ViewStyle } from 'react-native';
import { useMemo } from 'react';

import { textStyle, MAX_DISPLAY_FONT_SCALE } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

import { usePressScale } from './press';
import { Spinner } from './Spinner';

export type ButtonVariant = 'primary' | 'secondary' | 'destructive' | 'ghost';
export type ButtonSize = 'lg' | 'md' | 'sm';

export interface ButtonProps {
  label: string;
  onPress?: () => void;
  variant?: ButtonVariant;
  size?: ButtonSize;
  disabled?: boolean;
  /** Shows a spinner in place of the label and holds the button's width. */
  loading?: boolean;
  /**
   * Shown INSTEAD of a bare spinner while `loading`, e.g. "Submitting bid…".
   * It says the tap was received and what is happening — never that it
   * succeeded (CFT-203). Both labels stay mounted, the inactive one at zero
   * height, so the button holds the wider of the two widths and never moves
   * under the finger.
   */
  pendingLabel?: string;
  /** Fills the available width. Sticky-bar and form buttons want this. */
  block?: boolean;
  style?: ViewStyle;
  /** Defaults to the label, which is right almost always. */
  accessibilityLabel?: string;
  accessibilityHint?: string;
  testID?: string;
}

const HEIGHT: Record<ButtonSize, number> = { lg: 52, md: 44, sm: 36 };

/** `sm` is below the 44pt minimum on purpose, so it makes the difference up in hitSlop. */
const HIT_SLOP: Record<ButtonSize, number> = { lg: 0, md: 0, sm: 6 };

export function Button({
  label,
  onPress,
  variant = 'primary',
  size = 'md',
  disabled = false,
  loading = false,
  pendingLabel,
  block = false,
  style,
  accessibilityLabel,
  accessibilityHint,
  testID,
}: ButtonProps) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  const inert = disabled || loading;
  const press = usePressScale(!inert);
  const showPending = loading && !!pendingLabel;

  const fill: ViewStyle =
    variant === 'primary'
      ? { backgroundColor: palette.brand.red }
      : variant === 'secondary'
        ? { borderWidth: 1, borderColor: palette.border.control }
        : variant === 'destructive'
          ? { borderWidth: 1, borderColor: palette.status.error }
          : {};

  const labelColor =
    variant === 'primary'
      ? palette.text.inverse
      : variant === 'destructive'
        ? palette.status.error
        : palette.text.primary;

  return (
    <Animated.View style={[block ? styles.block : undefined, press.style]}>
      <Pressable
        onPress={inert ? undefined : onPress}
        onPressIn={press.onPressIn}
        onPressOut={press.onPressOut}
        disabled={inert}
        hitSlop={HIT_SLOP[size]}
        // Disabled dims the whole control rather than recolouring it: a disabled
        // primary that changes hue reads as a different button.
        style={({ pressed }) => [
          styles.base,
          // minHeight (not height): the box grows if the label wraps taller at
          // large Dynamic Type instead of clipping. Normal-size height is unchanged.
          { minHeight: HEIGHT[size] },
          fill,
          // F-30: a primary that is pressed shows the measured pressed red (lighter, so the black
          // label keeps ≥ 4.5:1 in both appearances) on top of the scale feedback.
          variant === 'primary' && pressed && !inert ? { backgroundColor: palette.brand.redPressed } : null,
          block && styles.block,
          // A dim that is right for a control is wrong for a STATUS. `payControl` (and the reserve and
          // bid flows) return loading AND disabled together, so an in-flight label — "Confirming
          // payment", "Reserving…", "Submitting bid…" — was being rendered at 40% opacity, the
          // faintest thing on the screen and worst in Light (B measured it on checkout, 2026-09-24).
          // The control stays inert and still reports `busy`; only the dim goes, and only while a
          // pending LABEL is carrying the news. A spinner-only loading state keeps it.
          disabled && !showPending && styles.disabled,
          style,
        ]}
        accessibilityRole="button"
        // A screen reader hears what is happening, not the resting label.
        accessibilityLabel={showPending ? pendingLabel : (accessibilityLabel ?? label)}
        accessibilityHint={accessibilityHint}
        accessibilityState={{ disabled: inert, busy: loading }}
        /*
         * The pending label is the ONLY statement of an in-flight status on some screens — checkout's
         * six payControl branches among them — so the control announces its own change rather than
         * relying on a sentence elsewhere. Polite: it reports progress, it does not interrupt.
         */
        accessibilityLiveRegion={showPending ? 'polite' : 'none'}
        testID={testID}
      >
        {/* The label stays mounted but invisible while loading, so the button
            cannot change width mid-press and move what is under the finger.
            With a pendingLabel it drops to zero height instead, so the pending
            row takes its place at the same (or the wider) width. */}
        <Text
          style={[
            textStyle('action'),
            { color: labelColor },
            loading && styles.hidden,
            showPending && styles.ghost,
          ]}
          numberOfLines={1}
          maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}
        >
          {label}
        </Text>
        {pendingLabel ? (
          <View
            style={[styles.pendingRow, !showPending && styles.ghost]}
            pointerEvents="none"
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
          >
            {showPending ? <Spinner color={labelColor} label={pendingLabel} /> : null}
            <Text
              style={[textStyle('action'), { color: labelColor }]}
              numberOfLines={1}
              maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}
            >
              {pendingLabel}
            </Text>
          </View>
        ) : null}
        {loading && !showPending ? (
          <View style={StyleSheet.absoluteFill} pointerEvents="none">
            <View style={styles.spinnerWrap}>
              <Spinner color={labelColor} />
            </View>
          </View>
        ) : null}
      </Pressable>
    </Animated.View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  base: {
    borderRadius: v2.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: v2.space.lg,
    paddingVertical: v2.space.xs,
  },
  block: { alignSelf: 'stretch', width: '100%' },
  disabled: { opacity: 0.4 },
  hidden: { opacity: 0 },
  // Keeps a label's measured WIDTH in the layout while giving it no height and
  // no pixels, so the two labels reserve the wider width between them.
  ghost: { height: 0, opacity: 0, overflow: 'hidden' },
  pendingRow: { flexDirection: 'row', alignItems: 'center', gap: v2.space.sm },
  spinnerWrap: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  });
}
