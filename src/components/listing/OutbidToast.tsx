/**
 * src/components/listing/OutbidToast.tsx — the outbid notice.
 *
 * Replaces a red bar that slid down over the navigation header. Same trigger, same
 * timing, same haptic: it is driven by the realtime INSERT callback in the screen,
 * which is where the false-positive protection lives and which this component
 * deliberately does not touch.
 *
 * What changed is the behaviour, not the event. It sits BELOW the header instead
 * of over it, it is `pointerEvents="none"` so it can never eat a tap on the bid
 * button underneath, it translates a short distance with the brand easing and no
 * overshoot, and under reduce motion it simply appears and disappears.
 */

import { useEffect, useRef } from 'react';
import { Animated, Easing, StyleSheet, Text } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useReducedMotion } from '@/src/hooks/useReducedMotion';
import { EASING_BEZIER, textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

const [x1, y1, x2, y2] = EASING_BEZIER;

export function OutbidToast({ visible, message }: { visible: boolean; message: string }) {
  const reduceMotion = useReducedMotion();
  const insets = useSafeAreaInsets();
  const progress = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.timing(progress, {
      toValue: visible ? 1 : 0,
      duration: reduceMotion ? 0 : v2.motion.swift,
      easing: Easing.bezier(x1, y1, x2, y2),
      useNativeDriver: true,
    }).start();
  }, [visible, reduceMotion, progress]);

  return (
    <Animated.View
      pointerEvents="none"
      style={[
        styles.toast,
        {
          // The hero artwork runs under the status bar, so the toast has to clear
          // it on its own rather than inheriting a safe-area frame.
          paddingTop: v2.space.sm + insets.top,
          opacity: progress,
          transform: [
            { translateY: progress.interpolate({ inputRange: [0, 1], outputRange: [-12, 0] }) },
          ],
        },
      ]}
      // Announced once when it appears. The status banner carries the same fact
      // persistently, so a reader user who misses the announcement still has it.
      accessibilityLiveRegion="polite"
      accessibilityRole="alert"
    >
      <Text style={[textStyle('label'), styles.text]}>{message}</Text>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  toast: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 10,
    paddingVertical: v2.space.sm,
    paddingHorizontal: v2.space.lg,
    backgroundColor: v2.status.error,
    alignItems: 'center',
  },
  text: { color: v2.text.inverse },
});
