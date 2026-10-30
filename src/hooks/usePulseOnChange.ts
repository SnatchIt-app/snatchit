/**
 * src/hooks/usePulseOnChange.ts — a brief, restrained acknowledgement that a
 * value on screen changed (CFT-502, item 16). The current bid moves under the
 * user's eyes without rebuilding the panel: the amount dips and returns over
 * ~350 ms. Under Reduce Motion the value simply changes — the change itself is
 * the status, and it is never hidden behind the animation.
 *
 * React Native's own Animated, like press.ts: no worklet, native driver.
 */

import { useEffect, useRef } from 'react';
import { Animated, Easing } from 'react-native';

import { useReducedMotion } from '@/src/hooks/useReducedMotion';
import { EASING_BEZIER } from '@/src/theme/typography';

const [x1, y1, x2, y2] = EASING_BEZIER;

export const PULSE_DIP = 0.35;
export const PULSE_MS = 350;

export function usePulseOnChange(value: string | number | null | undefined): { opacity: Animated.Value } {
  const reduceMotion = useReducedMotion();
  const opacity = useRef(new Animated.Value(1)).current;
  const last = useRef(value);

  useEffect(() => {
    if (Object.is(last.current, value)) return;
    const first = last.current === undefined;
    last.current = value;
    // The first real value is content arriving, not a change worth a pulse.
    if (first || reduceMotion) return;
    opacity.setValue(PULSE_DIP);
    Animated.timing(opacity, {
      toValue: 1,
      duration: PULSE_MS,
      easing: Easing.bezier(x1, y1, x2, y2),
      useNativeDriver: true,
    }).start();
  }, [value, reduceMotion, opacity]);

  return { opacity };
}
