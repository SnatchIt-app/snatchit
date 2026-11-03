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
 * button underneath, it translates a short distance with a critically damped
 * spring (no overshoot), and under reduce motion it simply appears and disappears.
 */

import { useEffect, useMemo, useRef } from 'react';
import { Animated, StyleSheet, Text } from 'react-native';
import { useTopInset } from '@/src/lib/nav/navInsets';

import { useReducedMotion } from '@/src/hooks/useReducedMotion';
import { useAnnounceOnce } from '@/src/hooks/useAnnounceOnce';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export function OutbidToast({ visible, message }: { visible: boolean; message: string }) {
  // liveRegion is Android-only and role="alert" doesn't speak on iOS: VoiceOver never heard "outbid".
  useAnnounceOnce(visible ? message : null);
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  const reduceMotion = useReducedMotion();
  // F-SELL-2: the badge-aware top inset (status bar + the SANDBOX badge on sandbox builds; production unchanged).
  const topPad = useTopInset();
  const progress = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    // Reduce motion: no movement at all. Snap rather than animate — a spring has no
    // duration to collapse to zero. `setValue` is safe mid-flight because it STOPS the
    // running animation first (AnimatedValue.js:196-199) and only then updates the value.
    if (reduceMotion) {
      progress.setValue(visible ? 1 : 0);
      return;
    }
    // A spring rather than a timing, so an interruption mid-flight RE-TARGETS from the
    // current position instead of restarting a fixed 180 ms run. Verified in RN 0.81.5 on the
    // path that actually EXECUTES under `useNativeDriver: true`: `AnimatedValue.animate()`
    // stops the previous animation and starts the new one against the SAME native node,
    // passing `this._value` (AnimatedValue.js:319-322) — so the node keeps its position and
    // the native spring begins there. No position jump.
    //
    // Deliberately NOT cited: `SpringAnimation.js:292`'s `x0 = _toValue - _startPosition`.
    // That lives inside `onUpdate()`, the JS solver, and `:227-230` skips `onUpdate()` whenever
    // `__startAnimationIfNative` returns true — so it never runs for this component. (E found
    // the earlier version of this comment citing it; the conclusion held, the mechanism did not.)
    //
    // Velocity: on the JS side the carried velocity is provably 0. `_lastVelocity` starts at 0
    // (`:116`) and is only ever advanced inside `onUpdate()` (`:326`, `:354`), which does not run
    // here, so the carry from a previous spring (`:220`) copies 0 and `:193` forwards
    // `initialVelocity: 0`. Whether the NATIVE solver keeps its own velocity across a re-target
    // is unproven in EITHER direction — the native module was not read. See B's status doc.
    Animated.spring(progress, {
      toValue: visible ? 1 : 0,
      ...v2.motion.bannerSpring,
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
          paddingTop: v2.space.sm + topPad,
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

function makeStyles(p: Palette) {
  return StyleSheet.create({
  toast: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 10,
    paddingVertical: v2.space.sm,
    paddingHorizontal: v2.space.lg,
    backgroundColor: p.status.error,
    alignItems: 'center',
  },
  text: { color: p.status.onFill },
  });
}
