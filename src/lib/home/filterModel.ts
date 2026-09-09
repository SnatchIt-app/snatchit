/**
 * src/lib/home/filterModel.ts — the Home discovery filter model.
 *
 * Extracted so the quick row and the full FilterSheet read the SAME state and the
 * same option list; there is one filter model, not two. No query semantics change:
 * `chip` still selects exactly the datasets/predicates it always did.
 *
 * The quick row on Home shows only three controls (Your scene, Price, Filters).
 * Everything else — ticket type, sale type, ended, sold — lives inside the sheet.
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

/** Grouped for the sheet. `all` is the unfiltered feed and is not a visible chip. */
export const CHIP_GROUPS: { title: string; options: { key: QuickChip; label: string }[] }[] = [
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
 * Anything the FILTERS control is responsible for signalling. Price and Your
 * scene have their own controls, so they are deliberately excluded here and are
 * not double-counted.
 */
export function sheetFilterCount(f: Filters): number {
  return (
    f.neighborhoods.size +
    f.categories.size +
    (f.chip !== 'all' && f.chip !== 'your_scene' ? 1 : 0)
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
