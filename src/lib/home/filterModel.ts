/**
 * src/lib/home/filterModel.ts — the Home discovery filter model.
 *
 * Extracted so the quick row and the full FilterSheet read the SAME state and the
 * same option list; there is one filter model, not two. No query semantics change:
 * `chip` still selects exactly the datasets/predicates it always did.
 *
 * V3 (B's H1 at pin 911f65fd, under the owner's placement ruling 2026-09-24): Home carries ONE
 * filter control, on the header line — the approved composition goes header → section heading →
 * feature, with no chip row in it. So the whole taxonomy now lives in the sheet, `your_scene`
 * included, and nothing the old quick row reached became unreachable.
 */

export type QuickChip =
  | 'all'
  | 'your_scene'
  | 'ga'
  | 'vip'
  | 'buy_now'
  | 'auction'
  | 'ended'
  | 'recently_sold';

/**
 * Grouped for the sheet. `all` is the unfiltered feed and is not a visible chip.
 *
 * Every group writes the SAME `chip` field, so the whole set is one single-select family shown under
 * four headings: choosing GA clears Buy now. `your_scene` joins it here rather than beside the
 * neighbourhood multi-select below, because it is that same field — putting it with the areas would
 * have implied it combines with them when in fact it replaces the selection.
 */
export const CHIP_GROUPS: { title: string; options: { key: QuickChip; label: string }[] }[] = [
  {
    title: 'Scope',
    options: [
      { key: 'your_scene', label: 'Your scene' },
    ],
  },
  {
    title: 'Sale type',
    options: [
      { key: 'buy_now', label: 'Buy now' },
      { key: 'auction', label: 'Auction' },
    ],
  },
  {
    title: 'Ticket type',
    options: [
      { key: 'ga', label: 'GA' },
      { key: 'vip', label: 'VIP' },
    ],
  },
  {
    title: 'Status',
    options: [
      { key: 'ended', label: 'Ended' },
      { key: 'recently_sold', label: 'Sold' },
    ],
  },
];

export interface Filters {
  chip: QuickChip;
  neighborhoods: Set<string>;
  categories: Set<string>;
  priceMin: string;
  priceMax: string;
}

export const DEFAULT_FILTERS: Filters = {
  chip: 'all',
  neighborhoods: new Set(),
  categories: new Set(),
  priceMin: '',
  priceMax: '',
};

/** A price bound is set. Surfaced by the PRICE quick control. */
export function hasPriceFilter(f: Pick<Filters, 'priceMin' | 'priceMax'>): boolean {
  return f.priceMin !== '' || f.priceMax !== '';
}

/**
 * What the one filter control is responsible for signalling — which is now EVERYTHING, since it is
 * the only control (B's H1). Price and `your_scene` used to be excluded because each had a control
 * of its own to show its state; after the move, a filter this does not count is a filter the user
 * cannot see is applied. A price RANGE counts once: it is one filter with two bounds.
 */
export function sheetFilterCount(f: Filters): number {
  return (
    f.neighborhoods.size +
    f.categories.size +
    (f.chip !== 'all' ? 1 : 0) +
    (hasPriceFilter(f) ? 1 : 0)
  );
}

export function hasSheetFilters(f: Filters): boolean {
  return sheetFilterCount(f) > 0;
}

/** Any filter at all is active (used for empty-state copy). */
export function activeFilterCount(f: Filters): number {
  return (
    (f.chip !== 'all' ? 1 : 0) +
    f.neighborhoods.size +
    f.categories.size +
    (f.priceMin ? 1 : 0) +
    (f.priceMax ? 1 : 0)
  );
}
