/**
 * src/lib/screens/refreshPolicy.ts — when a reload may take over a screen.
 *
 * The tab screens reload on every focus. Before this, Tickets entered its
 * loading phase on each of those reloads, which unmounted the list (scroll
 * position included) and put a spinner over rows the user was already reading,
 * and Search cleared its results the moment a query failed. The rule is one
 * line: a state screen (spinner, error) replaces content only when there is no
 * content to keep. Pure, so each screen's decision is tested directly.
 */

export type RefreshPhase = 'loading' | 'ready' | 'error';

/**
 * Whether a reload should show the loading state. Only while nothing has been
 * shown yet: no rows, and the screen has not settled into `ready`. A successful
 * empty result IS a ready state — the empty copy stays on screen and refreshes
 * quietly like any other content.
 */
export function shouldShowLoading(rowCount: number, phase: RefreshPhase): boolean {
  return rowCount === 0 && phase !== 'ready';
}

/**
 * The phase a failed reload leaves behind. Content — rows, or a settled empty
 * state — survives a failed quiet refresh; the error state appears only where
 * the loading state would have been.
 */
export function phaseAfterError(rowCount: number, phase: RefreshPhase): RefreshPhase {
  return shouldShowLoading(rowCount, phase) ? 'error' : phase;
}

/**
 * How a failure is surfaced over a result list: the full state screen when
 * there is nothing to keep, inline above rows that are still valid, or not at
 * all.
 */
export type FailureSurface = 'none' | 'screen' | 'inline';

export function failureSurface(rowCount: number, failed: boolean): FailureSurface {
  if (!failed) return 'none';
  return rowCount === 0 ? 'screen' : 'inline';
}
