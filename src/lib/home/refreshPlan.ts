/**
 * src/lib/home/refreshPlan.ts — which Home reads run, and when.
 *
 * Builds 25/27 loaded Recently sold and Ended once per session, re-read only the live feed on focus,
 * and never re-read on returning to the foreground. A non-participant never receives the realtime
 * UPDATE that hides a listing (RLS is checked against the new row), so a list fetched before the
 * legacy cleanup stayed on screen until a pull-to-refresh or a relaunch (N3, 2026-10-15). Every
 * selection and every return now re-reads what is on screen. The reads are small (limit 30/50).
 */
import type { QuickChip } from './filterModel';

export type HomeRead = 'live' | 'recently_sold' | 'ended';
export type HomeRefreshTrigger = 'chip_selected' | 'focus' | 'foreground';

/** The lazy dataset a chip shows, if any. */
function datasetFor(chip: QuickChip): HomeRead | null {
  return chip === 'recently_sold' ? 'recently_sold' : chip === 'ended' ? 'ended' : null;
}

export function homeReadsFor(trigger: HomeRefreshTrigger, chip: QuickChip): HomeRead[] {
  const dataset = datasetFor(chip);
  // A selection only needs its own dataset; the live feed is loaded and filtered locally.
  if (trigger === 'chip_selected') return dataset ? [dataset] : [];
  return dataset ? ['live', dataset] : ['live'];
}
