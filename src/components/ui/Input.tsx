/**
 * src/components/ui/Input.tsx — the one text field.
 *
 * A hairline under the field, not a box around it: the brand separates with lines
 * and surface value, never with rounded wells. Focus raises the hairline to brand
 * red, which is the one place red appears without being tappable, because a focus
 * ring IS the thing the user is currently acting on.
 *
 * THE LABEL IS NOT THE PLACEHOLDER. A placeholder disappears the moment someone
 * types, which is exactly when they need to know what the field was for.
 */

import { forwardRef, useState, useMemo } from 'react';
import {
  StyleSheet,
  Text,
  TextInput,
  View,
  type TextInputProps,
  type ViewStyle,
} from 'react-native';

import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export interface InputProps extends Omit<TextInputProps, 'style' | 'editable'> {
  label: string;
  /** Shown under the field. Replaced by `error` when there is one. */
  helper?: string;
  /** Any non-empty value puts the field in its error state. */
  error?: string | null;
  disabled?: boolean;
  containerStyle?: ViewStyle;
}

export const Input = forwardRef<TextInput, InputProps>(function Input(
  { label, helper, error, disabled = false, containerStyle, onFocus, onBlur, ...rest },
  ref,
) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  const [focused, setFocused] = useState(false);
  const hasError = !!error;

  // At rest the underline is the edge that identifies the field (border.control, 3:1 in both
  // appearances); focus raises it to brand red and an error to status.error.
  const underline = hasError
    ? palette.status.error
    : focused
      ? palette.brand.red
      : palette.border.control;

  return (
    <View style={[styles.wrap, disabled && styles.disabled, containerStyle]}>
      <Text style={[textStyle('micro'), styles.label]}>{label}</Text>

      <TextInput
        ref={ref}
        editable={!disabled}
        placeholderTextColor={palette.text.faint}
        selectionColor={palette.brand.red}
        onFocus={(e) => { setFocused(true); onFocus?.(e); }}
        onBlur={(e) => { setFocused(false); onBlur?.(e); }}
        style={[textStyle('body'), styles.field, { borderBottomColor: underline }]}
        accessibilityLabel={label}
        // The message travels with the field, so a screen reader hears why the
        // field is red instead of just that it is.
        accessibilityHint={error ?? helper}
        accessibilityState={{ disabled }}
        {...rest}
      />

      {error ? (
        <Text style={[textStyle('bodySm'), styles.error]} accessibilityRole="alert">
          {error}
        </Text>
      ) : helper ? (
        <Text style={[textStyle('bodySm'), styles.helper]}>{helper}</Text>
      ) : null}
    </View>
  );
});

function makeStyles(p: Palette) {
  return StyleSheet.create({
  wrap: { alignSelf: 'stretch' },
  disabled: { opacity: 0.4 },
  label: { color: p.text.muted, marginBottom: v2.space.xs },
  field: {
    minHeight: 50,
    color: p.text.primary,
    borderBottomWidth: 1,
    borderRadius: v2.radius.none,
    paddingHorizontal: 0,
    paddingVertical: v2.space.sm,
  },
  helper: { color: p.text.muted, marginTop: v2.space.xs },
  error: { color: p.status.error, marginTop: v2.space.xs },
  });
}
