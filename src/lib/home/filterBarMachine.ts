/**
 * src/lib/home/filterBarMachine.ts — the Home quick-filter bar controller (pure).
 *
 * PURPOSE-BUILT, deliberately NOT the dock's machine. The dock is an overlay whose
 * collapse changes no scroll geometry; the top bar sits at the head of the feed and
 * is a different UI pattern, so it gets its own deterministic controller. The dock
 * and its thresholds are untouched.
 *
 * Behaviour:
 *  - within TOP_RESET of the top (or on negative iOS overscroll) it is always shown;
 *  - a sustained DOWNWARD travel of HIDE_TRAVEL, once past HIDE_AFTER, hides it;
 *  - a sustained UPWARD travel of SHOW_TRAVEL shows it again mid-feed;
 *  - a direction change resets the OPPOSING accumulator immediately, so stale
 *    downward travel can never make the user scroll further back up to recover the
 *    controls (the reported partial-collapse-then-reverse failure);
 *  - deltas below JITTER are ignored entirely, so finger noise never accumulates.
 *
 * Returning costs LESS travel than hiding, on purpose: hiding is a browsing
 * gesture, showing is an intent gesture.
 */

export interface FilterBarState {
  /** Last observed scroll offset. */
  y: number;
  /** Whether the quick-filter bar is hidden. */
  hidden: boolean;
  /** Sustained downward travel since the last direction change / reset. */
  downAcc: number;
  /** Sustained upward travel since the last direction change / reset. */
  upAcc: number;
}

/** Within this of the top the bar is always shown. */
export const TOP_RESET = 16;
/** Must be scrolled at least this far down before hiding is allowed. */
export const HIDE_AFTER = 72;
/** Sustained downward pixels required to hide. */
export const HIDE_TRAVEL = 48;
/** Sustained upward pixels required to show again — deliberately less than HIDE. */
export const SHOW_TRAVEL = 20;
/** Deltas smaller than this are noise and are not accumulated at all. */
export const JITTER = 2;

export function initialFilterBarState(): FilterBarState {
  return { y: 0, hidden: false, downAcc: 0, upAcc: 0 };
}

export function reduceFilterBarScroll(state: FilterBarState, y: number): FilterBarState {
  // At/near the top, and on iOS rubber-band overscroll (negative y): always shown.
  if (y <= TOP_RESET) {
    return { y, hidden: false, downAcc: 0, upAcc: 0 };
  }

  const dy = y - state.y;

  // Deadband: track the offset but accumulate nothing, so jitter cannot creep
  // toward a threshold.
  if (Math.abs(dy) < JITTER) {
    return { ...state, y };
  }

  if (dy > 0) {
    const downAcc = state.downAcc + dy;
    if (!state.hidden && downAcc >= HIDE_TRAVEL && y > HIDE_AFTER) {
      return { y, hidden: true, downAcc: 0, upAcc: 0 };
    }
    // Direction is down: the upward accumulator is stale and is cleared.
    return { y, hidden: state.hidden, downAcc, upAcc: 0 };
  }

  const upAcc = state.upAcc + -dy;
  if (state.hidden && upAcc >= SHOW_TRAVEL) {
    return { y, hidden: false, downAcc: 0, upAcc: 0 };
  }
  // Direction is up: the downward accumulator is stale and is cleared.
  return { y, hidden: state.hidden, upAcc, downAcc: 0 };
}

/** Force the bar shown (leaving/entering Home, or an explicit reset). */
export function showFilterBar(state: FilterBarState): FilterBarState {
  if (!state.hidden && state.downAcc === 0 && state.upAcc === 0) return state;
  return { ...state, hidden: false, downAcc: 0, upAcc: 0 };
}
