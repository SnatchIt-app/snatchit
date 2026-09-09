/**
 * tests/discovery-card-state.test.ts — what a feed card says.
 *
 * Three untruths shipped in the previous feed, all of them hardcoded inside a
 * FlatList `renderItem`: every card said "Current bid" (including on Buy Now
 * listings and on listings nobody had bid on), every card offered "Bid now", and
 * every live card wore a red "ACTIVE" pill. These lock that down.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { cardPresentation, cardStatus, countdownLabel, type CardListing } from '../src/lib/listing/cardState';

const NOW = Date.parse('2026-09-03T12:00:00Z');
const inHours = (h: number) => new Date(NOW + h * 3600_000).toISOString();

function listing(over: Partial<CardListing> = {}): CardListing {
  return {
    status: 'active',
    auction_status: 'active',
    ends_at: inHours(6),
    reserved_until: null,
    buy_now_enabled: false,
    buy_now_price: null,
    starting_bid: 40,
    current_bid: 40,
    winning_bid_amount: null,
    bid_count: 0,
    ...over,
  };
}

describe('card status', () => {
  it('separates live, ending soon, reserved, ended and sold', () => {
    expect(cardStatus(listing(), NOW)).toBe('live');
    expect(cardStatus(listing({ ends_at: new Date(NOW + 5 * 60_000).toISOString() }), NOW)).toBe('ending_soon');
    expect(cardStatus(listing({ ends_at: inHours(-1) }), NOW)).toBe('ended');
    expect(cardStatus(listing({ auction_status: 'ended' }), NOW)).toBe('ended');
    expect(cardStatus(listing({ auction_status: 'cancelled' }), NOW)).toBe('ended');
    expect(cardStatus(listing({ status: 'sold' }), NOW)).toBe('sold');
    expect(
      cardStatus(listing({ status: 'reserved', reserved_until: inHours(0.1) }), NOW),
    ).toBe('reserved');
  });

  it('treats an expired hold as no hold at all', () => {
    expect(
      cardStatus(listing({ status: 'reserved', reserved_until: inHours(-0.1) }), NOW),
    ).toBe('live');
  });
});

describe('card copy is mode aware', () => {
  it('leads with Buy Now when the listing has one, and keeps the auction as the alternative', () => {
    const p = cardPresentation(listing({ buy_now_enabled: true, buy_now_price: 60, bid_count: 3, current_bid: 45 }), NOW);
    expect(p.priceLabel).toBe('Buy now');
    expect(p.priceSource).toBe('buy_now');
    expect(p.priceDollars).toBe(60);
    expect(p.altLabel).toBe('Current bid');
    expect(p.altDollars).toBe(45);
    expect(p.actionHint).toBe('Buy or bid');
  });

  it('does not call an opening price a current bid', () => {
    // The regression: "Current bid $40" on a listing nobody had bid on.
    const p = cardPresentation(listing({ bid_count: 0, starting_bid: 40 }), NOW);
    expect(p.priceLabel).toBe('Starting bid');
    expect(p.priceSource).toBe('starting_bid');
    expect(p.priceDollars).toBe(40);
    expect(p.altLabel).toBeNull();
  });

  it('says current bid once someone has actually bid', () => {
    const p = cardPresentation(listing({ bid_count: 2, current_bid: 55 }), NOW);
    expect(p.priceLabel).toBe('Current bid');
    expect(p.priceDollars).toBe(55);
  });

  it('describes a Buy Now listing with no bids as bids starting, not as a current bid', () => {
    const p = cardPresentation(listing({ buy_now_enabled: true, buy_now_price: 60, bid_count: 0, starting_bid: 30 }), NOW);
    expect(p.altLabel).toBe('Bids from');
    expect(p.altDollars).toBe(30);
  });

  it('never offers a bid verb on a listing that cannot take one', () => {
    for (const l of [
      listing({ status: 'sold' }),
      listing({ auction_status: 'ended' }),
      listing({ ends_at: inHours(-2) }),
    ]) {
      const p = cardPresentation(l, NOW);
      expect(p.actionHint).toBe('View listing');
      expect(p.showsCountdown).toBe(false);
    }
  });
});

describe('closed listings', () => {
  it('reports what a sold listing actually sold for, by the same priority as the rest of the app', () => {
    expect(cardPresentation(listing({ status: 'sold', winning_bid_amount: 75, current_bid: 70 }), NOW).priceDollars).toBe(75);
    // Buy Now sale: finalize_auction never stamps a winning bid, so the charge
    // base was the Buy Now price, not the last auction bid.
    expect(
      cardPresentation(listing({ status: 'sold', buy_now_enabled: true, buy_now_price: 60, current_bid: 40 }), NOW).priceDollars,
    ).toBe(60);
    expect(cardPresentation(listing({ status: 'sold', current_bid: 42 }), NOW).priceDollars).toBe(42);
    expect(cardPresentation(listing({ status: 'sold' }), NOW).priceLabel).toBe('Sold for');
  });

  it('distinguishes an auction that ended with bids from one that ended without any', () => {
    expect(cardPresentation(listing({ auction_status: 'ended', bid_count: 4, current_bid: 90 }), NOW).priceLabel).toBe('Final bid');
    expect(cardPresentation(listing({ auction_status: 'ended', bid_count: 0 }), NOW).priceLabel).toBe('Started at');
  });
});

describe('status badges are earned, not automatic', () => {
  it('shows no badge on an ordinary live listing', () => {
    // The old feed painted a red ACTIVE pill on every live card, which spent the
    // brand colour on the one thing every row had in common.
    expect(cardPresentation(listing(), NOW).statusLabel).toBeNull();
  });

  it('badges only the states that change what the user should do', () => {
    expect(cardPresentation(listing({ ends_at: new Date(NOW + 60_000).toISOString() }), NOW).statusLabel).toBe('Ending soon');
    expect(cardPresentation(listing({ status: 'reserved', reserved_until: inHours(0.1) }), NOW).statusLabel).toBe('On hold');
    expect(cardPresentation(listing({ status: 'sold' }), NOW).statusLabel).toBe('Sold');
    expect(cardPresentation(listing({ auction_status: 'ended' }), NOW).statusLabel).toBe('Ended');
  });

  it('never relies on tone alone', () => {
    for (const l of [
      listing({ status: 'sold' }),
      listing({ status: 'reserved', reserved_until: inHours(0.1) }),
      listing({ ends_at: new Date(NOW + 60_000).toISOString() }),
    ]) {
      expect(cardPresentation(l, NOW).statusLabel).toBeTruthy();
    }
  });
});

describe('countdown', () => {
  it('formats hours, minutes and days without drifting into a clock nobody can read', () => {
    expect(countdownLabel(new Date(NOW + 125_000).toISOString(), NOW)).toBe('02:05');
    expect(countdownLabel(new Date(NOW + 3 * 3600_000 + 65_000).toISOString(), NOW)).toBe('03:01:05');
    expect(countdownLabel(inHours(50), NOW)).toBe('2d 2h left');
    expect(countdownLabel(inHours(-1), NOW)).toBe('Ended');
  });
});

/** Guards on the shipped feed, matching the constraints in CORE_FRONTEND_HANDOFF.md. */
describe('home and search — shipped-source guards', () => {
  const root = resolve(__dirname, '..');
  const code = (rel: string) =>
    readFileSync(resolve(root, rel), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');

  const home = code('app/(tabs)/home.tsx');
  const search = code('app/(tabs)/explore.tsx');
  const card = code('src/components/discovery/DiscoveryCard.tsx');

  it('formats every price through the one money helper', () => {
    for (const [name, src] of [['home', home], ['search', search]] as const) {
      expect(src, `${name} must use allInFromDollars`).toContain('allInFromDollars(');
      expect(src, `${name} must not do money arithmetic`).not.toMatch(/\* 100|\/ 100/);
    }
    expect(card).not.toMatch(/\* 100|\/ 100/);
    // The card is handed preformatted strings; it must not import money at all.
    expect(card).not.toMatch(/lib\/money/);
  });

  it('no longer hardcodes auction language for every listing', () => {
    for (const src of [home, search, card]) {
      expect(src).not.toMatch(/'Bid now'|"Bid now"|>Bid now</);
      expect(src).not.toMatch(/'Current bid'|"Current bid"/);
    }
  });

  it('does not claim venue-direct provenance', () => {
    for (const src of [home, search, card]) {
      expect(src).not.toMatch(/Direct from event/i);
      expect(src).not.toMatch(/isVenuePrimarySale/);
    }
  });

  it('keeps the safe area off the hardcoded 56pt guess', () => {
    expect(home).not.toMatch(/paddingTop:\s*56/);
    expect(search).not.toMatch(/paddingTop:\s*56/);
    expect(code('src/components/discovery/HomeHeader.tsx')).toContain('useSafeAreaInsets');
  });

  it('has no emoji interface left in the feed', () => {
    const emoji = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]/u;
    for (const src of [home, search, card]) expect(emoji.test(src)).toBe(false);
  });

  it('opens the approved listing detail screen', () => {
    expect(home).toContain('/listing/${item.id}');
    expect(search).toContain('/listing/${item.id}');
  });

  it('keeps the data layer the feed already had', () => {
    for (const marker of [
      'applyBlockedSellerFilter',
      'useBlockedUserIds',
      'postgres_changes',
      'get_my_profile',
      'sortByNeighborhoods',
      'fetchSoldListings',
      'fetchEndedListings',
      'RefreshControl',
      'useFocusEffect',
    ]) {
      expect(home, `${marker} must survive the redesign`).toContain(marker);
    }
  });

  it('routes search through the reused explore screen rather than a second copy', () => {
    expect(home).toContain("router.push('/(tabs)/explore')");
    expect(search).toContain('applyBlockedSellerFilter');
    expect(search).toContain('.ilike.');
  });
});
