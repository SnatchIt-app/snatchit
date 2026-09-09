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

import { forwardRef, useState } from 'react';
import {
  StyleSheet,
  Text,
  TextInput,
  View,
  type TextInputProps,
  type ViewStyle,
} from 'react-native';

import { textStyle } from '@/src/theme/typography';
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
  const [focused, setFocused] = useState(false);
  const hasError = !!error;

  const underline = hasError
    ? v2.status.error
    : focused
      ? v2.brand.red
      : v2.border.strong;

  return (
    <View style={[styles.wrap, disabled && styles.disabled, containerStyle]}>
      <Text style={[textStyle('micro'), styles.label]}>{label}</Text>

      <TextInput
        ref={ref}
        editable={!disabled}
        placeholderTextColor={v2.text.faint}
        selectionColor={v2.brand.red}
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

const styles = StyleSheet.create({
  wrap: { alignSelf: 'stretch' },
  disabled: { opacity: 0.4 },
  label: { color: v2.text.muted, marginBottom: v2.space.xs },
  field: {
    minHeight: 50,
    color: v2.text.primary,
    borderBottomWidth: 1,
    borderRadius: v2.radius.none,
    paddingHorizontal: 0,
    paddingVertical: v2.space.sm,
  },
  helper: { color: v2.text.muted, marginTop: v2.space.xs },
  error: { color: v2.status.error, marginTop: v2.space.xs },
});
