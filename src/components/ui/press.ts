/**
 * src/components/ui/press.ts — the one press-feedback animation.
 *
 * Every pressable primitive uses this, so a button, a chip and an icon button all
 * feel like the same product. It scales to 0.98 and stops. It does not bounce and
 * it does not overshoot: this is a marketplace where people spend money, and
 * springy chrome reads as a toy.
 *
 * React Native's own `Animated` drives it. That is not a second animation library
 * — it ships with React Native — and it is deliberate here: nothing in this app has
 * ever executed a Reanimated worklet, the repo carries no `babel.config.js` of its
 * own, and a foundation primitive is the wrong place to be the first to find out.
 * Reanimated stays installed and is the right tool for gesture-driven work in a
 * later phase, once a running build has proven the plugin is wired.
 */

import { useRef } from 'react';
import { Animated, Easing } from 'react-native';

import { useReducedMotion } from '@/src/hooks/useReducedMotion';
import { EASING_BEZIER } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

const [x1, y1, x2, y2] = EASING_BEZIER;

export const PRESSED_SCALE = 0.98;

export function usePressScale(enabled = true) {
  const reduceMotion = useReducedMotion();
  const scale = useRef(new Animated.Value(1)).current;

  const run = (to: number) => {
    if (!enabled) return;
    Animated.timing(scale, {
      toValue: reduceMotion ? 1 : to,
      duration: reduceMotion ? 0 : v2.motion.instant,
      easing: Easing.bezier(x1, y1, x2, y2),
      useNativeDriver: true,
    }).start();
  };

  return {
    /** Spread onto the animated wrapper. */
    style: { transform: [{ scale }] },
    onPressIn: () => run(PRESSED_SCALE),
    onPressOut: () => run(1),
  };
}
