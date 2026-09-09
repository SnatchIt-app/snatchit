/**
 * src/lib/nav/navInsets.ts — shared dock geometry + content clearance.
 *
 * One source of truth for the floating dock's size, how high it floats, its
 * clearance for scrollable tabs, and the gap the Create CTA must leave above it.
 * Tabs read these rather than hardcoding bottom paddings, so the dock and the
 * transactional CTA stay independent.
 *
 * Device revision: the dock now floats HIGHER (larger gap above the safe area)
 * and is slightly LARGER, for a more intentional premium floating-control feel.
 */

import { useSafeAreaInsets } from 'react-native-safe-area-context';

/** Dock bar height (the floating pill / the compact control). */
export const DOCK_HEIGHT = 66;
/**
 * Gap between the dock and the safe-area inset. Deliberately generous so the dock
 * clearly floats in the lower third of the bottom region with visible black space
 * below it — never hugging the home-indicator boundary. This is the dock's REAL
 * bottom anchor (`insets.bottom + DOCK_GAP`), applied directly to the dock, not to
 * a wrapper's padding (which an absolutely-positioned child ignores).
 */
export const DOCK_GAP = 48;
/** Horizontal inset from the screen edges to the floating dock. */
export const DOCK_SIDE_MARGIN = 16;
/** Rounded-glass dock radius (navigation is the explicit exception to radius 0). */
export const DOCK_RADIUS = 33;
/** Clear space between the Create CTA and the dock, so they never touch. */
export const CTA_DOCK_GAP = 14;

/** Space the dock occupies above the safe-area inset. */
export const DOCK_CLEARANCE = DOCK_HEIGHT + DOCK_GAP;

/** Bottom padding a scrollable tab should leave: the safe area plus the dock. */
export function useDockClearance(): number {
  const insets = useSafeAreaInsets();
  return insets.bottom + DOCK_CLEARANCE + DOCK_GAP;
}

/**
 * How far up a bottom transactional CTA (Create's List ticket bar) must sit so it
 * ends ABOVE the floating dock with a clear gap — its own surface, not the dock's.
 */
export function useCtaDockOffset(): number {
  const insets = useSafeAreaInsets();
  return insets.bottom + DOCK_GAP + DOCK_HEIGHT + CTA_DOCK_GAP;
}
