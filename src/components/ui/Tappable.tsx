/**
 * src/components/ui/Tappable.tsx — a bare tappable with the shared press response.
 *
 * For the controls that are not a Button, a Chip or an IconButton — a stepper
 * key, a list row, a text action — but must still feel like the same product
 * (CFT-201, item 8). It is `Pressable` plus `usePressScale` and nothing else:
 * no padding, no colour, no radius. The caller keeps its own layout styles.
 *
 * Layout goes on `wrapperStyle` when the control must flex inside a row
 * (`flex: 1`), because the animated wrapper is what the row lays out.
 */

import { forwardRef } from 'react';
import {
  Animated,
  Pressable,
  type GestureResponderEvent,
  type PressableProps,
  type StyleProp,
  type View,
  type ViewStyle,
} from 'react-native';

import { usePressScale } from './press';

export interface TappableProps extends Omit<PressableProps, 'style'> {
  style?: StyleProp<ViewStyle>;
  /** Layout for the animated wrapper: flex, margins, alignment. */
  wrapperStyle?: StyleProp<ViewStyle>;
}

export const Tappable = forwardRef<View, TappableProps>(function Tappable(
  { style, wrapperStyle, disabled, onPressIn, onPressOut, ...rest },
  ref,
) {
  const press = usePressScale(!disabled);
  return (
    <Animated.View style={[wrapperStyle, press.style]}>
      <Pressable
        ref={ref}
        disabled={disabled}
        style={style}
        onPressIn={(e: GestureResponderEvent) => { press.onPressIn(); onPressIn?.(e); }}
        onPressOut={(e: GestureResponderEvent) => { press.onPressOut(); onPressOut?.(e); }}
        {...rest}
      />
    </Animated.View>
  );
});
