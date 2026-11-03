/**
 * tests/outbid-toast-spring.test.ts — M2: the outbid banner re-targets on interruption.
 *
 * The banner used a fixed-duration `Animated.timing`, so an interruption mid-flight
 * restarted a full run. It now uses a spring, which re-targets from the current
 * position. These are source-level assertions because this repo has no React Native
 * test renderer (no @testing-library/react-native, no react-test-renderer): the
 * component is never mounted in CI, so the behaviour is pinned at the call site.
 *
 * The ζ assertion is NOT a text match — it recomputes the damping ratio from the
 * published token and fails if the banner is ever retuned into a bounce.
 */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

import * as v2 from '@/src/theme/v2';

const src = readFileSync('src/components/listing/OutbidToast.tsx', 'utf8');

describe('M2 — the outbid banner springs instead of timing', () => {
  it('drives the banner with Animated.spring and the shared motion token', () => {
    expect(src).toContain('Animated.spring(progress, {');
    expect(src).toContain('...v2.motion.bannerSpring,');
    // The fixed-duration run is gone: that is the whole point of the change.
    expect(src).not.toContain('Animated.timing(');
  });

  it('still runs on the native driver', () => {
    expect(src).toContain('useNativeDriver: true');
  });

  it('snaps instead of animating under the OS reduced-motion setting', () => {
    // A spring has no duration to collapse to 0, so reduce motion must take an
    // early return that sets the value directly — never a spring with movement.
    expect(src).toMatch(/if \(reduceMotion\) \{[\s\S]*progress\.setValue\(visible \? 1 : 0\);[\s\S]*return;[\s\S]*\}/);
  });

  it('keeps the banner inert, announced and below the header', () => {
    expect(src).toContain('pointerEvents="none"');
    expect(src).toContain('accessibilityLiveRegion="polite"');
    expect(src).toContain('useAnnounceOnce(visible ? message : null)');
    expect(src).toContain('paddingTop: v2.space.sm + topPad');
  });
});

describe('M2 — the banner spring is critically damped (the no-bounce rule)', () => {
  const { stiffness, damping, mass, overshootClamping } = v2.motion.bannerSpring;

  it('has zeta exactly 1: it settles without overshoot', () => {
    // zeta = c / (2 * sqrt(k * m)). press.ts states the product's no-bounce rule;
    // a banner that overshoots would break it, so this is an invariant, not a style.
    const zeta = damping / (2 * Math.sqrt(stiffness * mass));
    expect(zeta).toBe(1);
  });

  it('clamps overshoot as belt-and-braces', () => {
    expect(overshootClamping).toBe(true);
  });

  it('settles in about the swift token, so the banner feels unchanged in the common case', () => {
    // Critically damped: ~2% of the distance remains after about 5.8 / omega_n.
    const settleMs = (5.8 / Math.sqrt(stiffness / mass)) * 1000;
    expect(Math.abs(settleMs - v2.motion.swift)).toBeLessThan(15);
  });

  it('uses only keys React Native forwards to the native driver', () => {
    // RN 0.81.5 SpringAnimation.js:186-197 sends stiffness/damping/mass/overshootClamping.
    expect(Object.keys(v2.motion.bannerSpring).sort()).toEqual(
      ['damping', 'mass', 'overshootClamping', 'stiffness'],
    );
  });
});
