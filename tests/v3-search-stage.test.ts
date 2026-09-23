/**
 * V3 search stage — the filter model, the §5 results header and empty state, and the screen pins.
 *
 * The chips are CLIENT-SIDE narrowing of the one authorized read (annotation ②: ticket type,
 * price and delivery method are real `listings` columns already in the row). "Under $150" claims
 * the number the buyer SEES — the all-in price — so it is measured through the one money module,
 * never against the raw pre-fee column. No count of excluded listings exists anywhere (§7).
 */
import { describe, expect, it } from 'vitest';

import {
  activeSearchFilterCount,
  CLEAR_ALL_LABEL,
  CLEAR_PRICE_LABEL,
  matchesSearchFilters,
  NO_SEARCH_FILTERS,
  searchEmptyState,
  searchResultsHeader,
  SORT_LABEL,
  UNDER_150_ALL_IN_CENTS,
} from '@/src/lib/search/searchFilters';

const NOW = Date.parse('2026-09-22T18:00:00');

function listing(extra: Record<string, unknown> = {}) {
  return {
    status: 'active', auction_status: 'active',
    ends_at: new Date(NOW + 3 * 3600_000).toISOString(),
    buy_now_enabled: false, buy_now_price: null,
    starting_bid: 90, current_bid: 120, bid_count: 6,
    ticket_type: 'GA', transfer_method: 'mobile_transfer',
    ...extra,
  } as never;
}

describe('searchFilters — three real-column chips', () => {
  it('SF1: no filters means every row passes and the empty state is the plain one', () => {
    expect(matchesSearchFilters(listing(), NO_SEARCH_FILTERS, NOW)).toBe(true);
    expect(activeSearchFilterCount(NO_SEARCH_FILTERS)).toBe(0);
    expect(searchEmptyState('neon', NO_SEARCH_FILTERS)).toBeNull();
  });

  it('SF2: GA filters on the stored ticket type', () => {
    const f = { ...NO_SEARCH_FILTERS, ga: true };
    expect(matchesSearchFilters(listing(), f, NOW)).toBe(true);
    expect(matchesSearchFilters(listing({ ticket_type: 'VIP' }), f, NOW)).toBe(false);
  });

  it('SF3: Under $150 measures the ALL-IN of the displayed price, through the money module', () => {
    const f = { ...NO_SEARCH_FILTERS, under150: true };
    // current bid $120 → $132.00 all-in: passes. $143 base → $157.30 all-in: fails.
    expect(UNDER_150_ALL_IN_CENTS).toBe(15000);
    expect(matchesSearchFilters(listing(), f, NOW)).toBe(true);
    expect(matchesSearchFilters(listing({ current_bid: 143 }), f, NOW)).toBe(false);
    // The number tested is the one shown: a no-bid listing is judged on its starting bid.
    expect(matchesSearchFilters(listing({ bid_count: 0, current_bid: 999, starting_bid: 90 }), f, NOW)).toBe(true);
  });

  it('SF4: Mobile transfer filters on the stored delivery method', () => {
    const f = { ...NO_SEARCH_FILTERS, mobileTransfer: true };
    expect(matchesSearchFilters(listing(), f, NOW)).toBe(true);
    expect(matchesSearchFilters(listing({ transfer_method: 'email' }), f, NOW)).toBe(false);
  });

  it('SF5: the results header counts what is on screen; the sort label matches the real order', () => {
    expect(searchResultsHeader(2)).toBe('2 listings');
    expect(searchResultsHeader(1)).toBe('1 listing');
    expect(SORT_LABEL).toBe('Soonest first');
  });

  it('SF6: the §5 empty state, exactly, and only when filters are active', () => {
    const s = searchEmptyState('neon', { ga: true, under150: true, mobileTransfer: false });
    expect(s?.title).toBe('Nothing matched “neon” with these filters');
    expect(s?.body).toBe('Clear a filter to widen the search, or edit the words above.');
    expect(s?.clearPrice).toBe(true);
    expect(searchEmptyState('neon', { ga: true, under150: false, mobileTransfer: false })?.clearPrice).toBe(false);
    expect(CLEAR_PRICE_LABEL).toBe('Clear price filter');
    expect(CLEAR_ALL_LABEL).toBe('Clear all');
  });

  it('SF7: no excluded-listing count exists anywhere in the model (§7: the read does not return one)', async () => {
    const { readFileSync } = await import('node:fs');
    // Comments stripped: the rule is about strings a user could ever see, not the rationale.
    const src = readFileSync('src/lib/search/searchFilters.ts', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src).not.toMatch(/excluded|hidden by filters/i);
  });
});

describe('search screen — §5 wiring pins', () => {
  const src = () => import('node:fs').then(({ readFileSync }) =>
    readFileSync('app/(tabs)/explore.tsx', 'utf8'));

  it('SP1: results render as §3 rows through FeedRow; the two-up card grid is gone', async () => {
    const s = await src();
    expect(s).toContain("from '@/src/components/discovery/FeedRow'");
    expect(s).not.toContain('DiscoveryCard');
    expect(s).not.toContain('numColumns={2}');
  });

  it('SP2: header, empty state and chip labels come from the one model module', async () => {
    const s = await src();
    for (const marker of [
      'searchResultsHeader(', 'SORT_LABEL', 'searchEmptyState(', 'matchesSearchFilters(',
      'CLEAR_PRICE_LABEL', 'CLEAR_ALL_LABEL',
    ]) expect(s, marker).toContain(marker);
    expect(s).toContain("'Under $150'");
    expect(s).toContain("'Mobile transfer'");
  });

  it('SP3: the data layer survives — same read, same blocked-seller filter, same failure policy', async () => {
    const s = await src();
    for (const marker of ['applyBlockedSellerFilter', '.ilike.', 'failureSurface', 'stageCardHandoff']) {
      expect(s, marker).toContain(marker);
    }
  });
});
