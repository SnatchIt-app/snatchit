/**
 * src/lib/nav/keyboardLift.ts — pure bottom/top clearance decisions for
 * screens with a sticky action bar (F-SELL-1, build 17).
 *
 * While a text keyboard is up, the floating dock hides itself
 * (AdaptiveDock) and the home indicator sits under the keyboard, so a bar
 * that keeps its dock lift and its home-indicator padding floats ~160–200 pt
 * above the keyboard with nothing in between. These helpers give the bar
 * only its own padding while the keyboard is up and restore the lift when
 * it closes.
 */

/** Padding a sticky bar keeps below its content. */
export function stickyBottomPadding(i: { keyboardUp: boolean; insetBottom: number; base: number }): number {
  return i.base + (i.keyboardUp ? 0 : i.insetBottom);
}

/** Lift above the floating dock; none while the keyboard (and no dock) is up. */
export function ctaLift(i: { keyboardUp: boolean; dockOffset: number }): number {
  return i.keyboardUp ? 0 : i.dockOffset;
}

/**
 * The sandbox badge is an absolute overlay at the top of every screen on
 * sandbox builds: one 11-pt line plus 6 pt below it, past the status-bar
 * inset. Headers add this so their title clears the badge. Production builds
 * have no badge and add nothing.
 */
export const SANDBOX_BADGE_EXTRA = 20;

export function topInset(i: { insetTop: number; sandbox: boolean }): number {
  return i.insetTop + (i.sandbox ? SANDBOX_BADGE_EXTRA : 0);
}
