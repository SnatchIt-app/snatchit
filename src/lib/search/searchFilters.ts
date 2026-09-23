/**
 * src/lib/search/searchFilters.ts — the V3 search chips and the §5 results header / empty state
 * (owner 2026-09-22; B's package §5 + the search mockups, annotation ②).
 *
 * Three chips, each a REAL column already present in the one authorized read — narrowing is
 * client-side and adds no query. "Under $150" claims the number the buyer sees, so it is judged
 * on the ALL-IN of the price the row displays (via cardState's selection and the one money
 * module), never on the raw pre-fee column. Deliberately absent (§7): any count of listings the
 * filters excluded — no read returns it, so the screen must not say it.
 *
 * The mockup's "Any date" chip is NOT built: its semantics (picker? preset?) have no spec text.
 * Flagged for B rather than shipped as a control that does nothing.
 */

import { cardPresentation, type CardListing } from '@/src/lib/listing/cardState';
import { buyerTotalCents, dollarsToCents } from '@/src/lib/money';

export interface SearchFilters {
  ga: boolean;
  under150: boolean;
  mobileTransfer: boolean;
}

export const NO_SEARCH_FILTERS: SearchFilters = { ga: false, under150: false, mobileTransfer: false };

export function activeSearchFilterCount(f: SearchFilters): number {
  return Number(f.ga) + Number(f.under150) + Number(f.mobileTransfer);
}

/** "Under $150" is strict: an all-in of exactly $150.00 is not under it. */
export const UNDER_150_ALL_IN_CENTS = 15000;

export type SearchFilterRow = CardListing & {
  ticket_type: string;
  transfer_method: string;
};

export function matchesSearchFilters(row: SearchFilterRow, f: SearchFilters, nowMs: number): boolean {
  if (f.ga && row.ticket_type !== 'GA') return false;
  if (f.mobileTransfer && row.transfer_method !== 'mobile_transfer') return false;
  if (f.under150) {
    // The same price selection the row displays, made all-in the one place fee math lives.
    const shown = cardPresentation(row, nowMs).priceDollars;
    if (buyerTotalCents(dollarsToCents(shown)) >= UNDER_150_ALL_IN_CENTS) return false;
  }
  return true;
}

/** "2 listings" — a count of what is ON SCREEN, nothing else. */
export function searchResultsHeader(count: number): string {
  return `${count} listing${count === 1 ? '' : 's'}`;
}

/** The query really is ordered by `ends_at` ascending; this label asserts only that. */
export const SORT_LABEL = 'Soonest first';

export const CLEAR_PRICE_LABEL = 'Clear price filter';
export const CLEAR_ALL_LABEL = 'Clear all';

/**
 * The §5 empty state — only when filters are active, because its heading blames them. With no
 * filters the screen keeps its existing plain no-match state.
 */
export function searchEmptyState(
  query: string,
  f: SearchFilters,
): { title: string; body: string; clearPrice: boolean } | null {
  if (activeSearchFilterCount(f) === 0) return null;
  return {
    title: `Nothing matched “${query}” with these filters`,
    body: 'Clear a filter to widen the search, or edit the words above.',
    clearPrice: f.under150,
  };
}
