/**
 * src/lib/nav/dockMachine.ts — the Home dock collapse state machine (pure).
 *
 * The dock collapses when the user intentionally scrolls DOWN through Home and
 * expands when they scroll UP, near the top, or tap the compact control. This is
 * NOT `y > 80 → collapsed`: that flickers on jitter and ignores direction. Instead
 * we accumulate sustained travel in the current direction and only flip once it
 * clears a threshold, so finger jitter and iOS bounce never toggle it.
 *
 * Pure and tested — the component owns the effect (setState) and the animation;
 * this owns the decision.
 */

export interface DockState {
  /** Last observed scroll offset. */
  y: number;
  /** Whether the dock is collapsed to the compact Home control. */
  collapsed: boolean;
  /** Sustained downward travel since the last direction change / reset. */
  downAcc: number;
  /** Sustained upward travel since the last direction change / reset. */
  upAcc: number;
}

/** Within this of the top, the dock is always expanded. */
export const TOP_THRESHOLD = 24;
/** Must be scrolled at least this far down before a collapse is allowed. */
export const COLLAPSE_AFTER = 90;
/** Sustained downward pixels required to collapse. */
export const COLLAPSE_TRAVEL = 40;
/** Sustained upward pixels required to expand. */
export const EXPAND_TRAVEL = 28;

export function initialDockState(): DockState {
  return { y: 0, collapsed: false, downAcc: 0, upAcc: 0 };
}

/**
 * Fold a new scroll offset into the dock state. Direction is the sign of the
 * delta; travel accumulates while direction holds and resets when it reverses.
 * Near the top (and on negative overscroll) the dock always expands.
 */
export function reduceDockScroll(state: DockState, y: number): DockState {
  // Near the top or overscrolled past it (iOS bounce gives negative y): expand.
  if (y <= TOP_THRESHOLD) {
    return { y, collapsed: false, downAcc: 0, upAcc: 0 };
  }

  const dy = y - state.y;
  if (dy === 0) return state;

  if (dy > 0) {
    // Scrolling down.
    const downAcc = state.downAcc + dy;
    if (!state.collapsed && downAcc >= COLLAPSE_TRAVEL && y > COLLAPSE_AFTER) {
      return { y, collapsed: true, downAcc: 0, upAcc: 0 };
    }
    return { ...state, y, downAcc, upAcc: 0 };
  }

  // Scrolling up.
  const upAcc = state.upAcc + -dy;
  if (state.collapsed && upAcc >= EXPAND_TRAVEL) {
    return { y, collapsed: false, downAcc: 0, upAcc: 0 };
  }
  return { ...state, y, upAcc, downAcc: 0 };
}

/** Tapping the compact control (or leaving/entering Home) forces expanded. */
export function expandDock(state: DockState): DockState {
  if (!state.collapsed && state.downAcc === 0 && state.upAcc === 0) return state;
  return { ...state, collapsed: false, downAcc: 0, upAcc: 0 };
}
