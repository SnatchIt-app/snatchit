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
 *  - Radius 0. There is no pill button in this brand.
 *  - There is no filled secondary. Secondary is a hairline and a white label.
 */

import { Animated, Pressable, StyleSheet, Text, View, type ViewStyle } from 'react-native';

import { textStyle, MAX_DISPLAY_FONT_SCALE } from '@/src/theme/typography';
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
  block = false,
  style,
  accessibilityLabel,
  accessibilityHint,
  testID,
}: ButtonProps) {
  const inert = disabled || loading;
  const press = usePressScale(!inert);

  const fill: ViewStyle =
    variant === 'primary'
      ? { backgroundColor: v2.brand.red }
      : variant === 'secondary'
        ? { borderWidth: 1, borderColor: v2.border.strong }
        : variant === 'destructive'
          ? { borderWidth: 1, borderColor: v2.status.error }
          : {};

  const labelColor =
    variant === 'primary'
      ? v2.text.inverse
      : variant === 'destructive'
        ? v2.status.error
        : v2.text.primary;

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
        style={[
          styles.base,
          // minHeight (not height): the box grows if the label wraps taller at
          // large Dynamic Type instead of clipping. Normal-size height is unchanged.
          { minHeight: HEIGHT[size] },
          fill,
          block && styles.block,
          disabled && styles.disabled,
          style,
        ]}
        accessibilityRole="button"
        accessibilityLabel={accessibilityLabel ?? label}
        accessibilityHint={accessibilityHint}
        accessibilityState={{ disabled: inert, busy: loading }}
        testID={testID}
      >
        {/* The label stays mounted but invisible while loading, so the button
            cannot change width mid-press and move what is under the finger. */}
        <Text
          style={[textStyle('label'), { color: labelColor }, loading && styles.hidden]}
          numberOfLines={1}
          maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}
        >
          {label}
        </Text>
        {loading ? (
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

const styles = StyleSheet.create({
  base: {
    borderRadius: v2.radius.none,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: v2.space.lg,
    paddingVertical: v2.space.xs,
  },
  block: { alignSelf: 'stretch', width: '100%' },
  disabled: { opacity: 0.4 },
  hidden: { opacity: 0 },
  spinnerWrap: { flex: 1, alignItems: 'center', justifyContent: 'center' },
});
