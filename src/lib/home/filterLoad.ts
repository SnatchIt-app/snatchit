/**
 * src/lib/home/filterLoad.ts — load state for Home's two lazy filter datasets.
 *
 * F-HOME-1. "Recently sold" and "Ended" are separate reads, fired the first time their chip is selected and
 * again on pull-to-refresh. They were the only reads on Home with no loading flag and no error state, so a
 * slow read rendered the settled empty copy ("Nothing sold yet") and a failed read rendered it too — the app
 * telling a shopper the marketplace is empty when it had simply failed to look. The owner reproduced it twice
 * on Build 19 with the connection off.
 *
 * The copy lives here so tests and previews pin the same strings the screen renders, exactly as
 * BIDS_REFRESH_FAILED_COPY does for the Bids screen.
 */

import type { LoadFailureKind } from '@/src/lib/ui/loadState';

/** Which lazy dataset a chip selects. `null` means the main feed, which owns its own load state. */
export type FilterDataset = 'recently_sold' | 'ended';

/** Per-dataset load state. Rows live on the screen; this is only how the read went. */
export type FilterLoadState = {
  loading: boolean;
  error: LoadFailureKind | null;
  /** A read has returned successfully at least once, so an empty result is genuine emptiness. */
  settled: boolean;
};

export const initialFilterLoadState: FilterLoadState = { loading: false, error: null, settled: false };

/**
 * Shown above rows that are still valid when a refresh fails. Distinct from the full-screen state, which is
 * reserved for a failure with nothing to keep.
 */
export const HOME_FILTER_REFRESH_FAILED_COPY: Record<LoadFailureKind, string> = {
  offline: "You're offline. Showing what loaded earlier.",
  error: "Couldn't refresh. Showing what loaded earlier.",
};

/**
 * Whether the settled empty copy may be shown at all. It may not while a read is in flight, nor after a
 * failure — both of those are the app not knowing, which is never the same as nothing being there.
 */
export function mayShowEmptyCopy(state: FilterLoadState): boolean {
  return !state.loading && state.error === null && state.settled;
}
