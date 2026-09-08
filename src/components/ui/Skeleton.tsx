/**
 * src/components/ui/Skeleton.tsx — loading placeholder.
 *
 * Opacity pulse, 0.4 to 0.7, 1200ms. No shimmer sweep: a diagonal highlight
 * travelling across a dark nightlife interface reads as a bug, and it is the
 * clearest tell of a template.
 *
 * A skeleton must mirror the geometry of the content it replaces, which is why it
 * takes width, height and ratio rather than shipping preset shapes: the caller
 * knows what is coming, this does not.
 *
 * Under reduced motion it holds still at a readable opacity instead of pulsing.
 */

import { useEffect, useRef } from 'react';
import { Animated, Easing, StyleSheet, type ViewStyle } from 'react-native';

import { useReducedMotion } from '@/src/hooks/useReducedMotion';
import * as v2 from '@/src/theme/v2';

export interface SkeletonProps {
  width?: ViewStyle['width'];
  height?: ViewStyle['height'];
  /** width / height. Use instead of `height` for media placeholders. */
  aspectRatio?: number;
  style?: ViewStyle;
  testID?: string;
}

export function Skeleton({ width = '100%', height, aspectRatio, style, testID }: SkeletonProps) {
  const reduceMotion = useReducedMotion();
  const pulse = useRef(new Animated.Value(0.5)).current;

  useEffect(() => {
    if (reduceMotion) {
      pulse.setValue(0.55);
      return;
    }
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(pulse, {
          toValue: 0.7, duration: 600, easing: Easing.inOut(Easing.quad), useNativeDriver: true,
        }),
        Animated.timing(pulse, {
          toValue: 0.4, duration: 600, easing: Easing.inOut(Easing.quad), useNativeDriver: true,
        }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [pulse, reduceMotion]);

  return (
    <Animated.View
      testID={testID}
      style={[
        styles.base,
        { width, height, aspectRatio, opacity: pulse },
        style,
      ]}
      // A skeleton is not content. VoiceOver should reach the real thing.
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    />
  );
}

const styles = StyleSheet.create({
  base: {
    backgroundColor: v2.surface.elevated,
    borderRadius: v2.radius.none,
  },
});
