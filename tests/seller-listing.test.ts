/**
 * tests/seller-listing.test.ts — the seller-listing model + My Listings / Edit
 * source guards (delete/cancel rules, the edit gate, and money untouched).
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  sellerBadge,
  sellerBadgeLabel,
  canEditListing,
  canDeleteListing,
  canCancelListing,
  timeLeftLabel,
  type SellerListingLike,
} from '../src/lib/listing/sellerListing';

const NOW = 1_000_000_000_000;
const future = new Date(NOW + 6 * 3600_000).toISOString();
const past = new Date(NOW - 3600_000).toISOString();

function l(over: Partial<SellerListingLike> = {}): SellerListingLike {
  return { status: 'active', auction_status: 'active', ends_at: future, bid_count: 0, ...over };
}

describe('seller badge', () => {
  it('classifies the states in priority order', () => {
    expect(sellerBadge(l({ auction_status: 'cancelled' }), NOW)).toBe('cancelled');
    expect(sellerBadge(l({ status: 'sold' }), NOW)).toBe('sold');
    expect(sellerBadge(l({ status: 'reserved', reserved_until: future }), NOW)).toBe('reserved');
    expect(sellerBadge(l({ ends_at: past }), NOW)).toBe('ended');
    expect(sellerBadge(l({ auction_status: 'ended' }), NOW)).toBe('ended');
    expect(sellerBadge(l({ ends_at: new Date(NOW + 5 * 60_000).toISOString() }), NOW)).toBe('ending_soon');
    expect(sellerBadge(l(), NOW)).toBe('active');
  });
  it('labels are sentence case, not shouting', () => {
    expect(sellerBadgeLabel('ending_soon')).toBe('Ending soon');
  });
});

describe('edit / delete / cancel gates mirror the server rule', () => {
  it('live + no bids can edit and delete', () => {
    expect(canEditListing(l())).toBe(true);
    expect(canDeleteListing(l())).toBe(true);
    expect(canCancelListing(l())).toBe(false);
  });
  it('live + has bids can only cancel', () => {
    const withBids = l({ bid_count: 3 });
    expect(canEditListing(withBids)).toBe(false);
    expect(canDeleteListing(withBids)).toBe(false);
    expect(canCancelListing(withBids)).toBe(true);
  });
  it('sold / ended can do none of the three', () => {
    const sold = l({ status: 'sold', auction_status: 'ended' });
    expect(canEditListing(sold)).toBe(false);
    expect(canCancelListing(sold)).toBe(false);
  });
});

describe('time left', () => {
  it('renders days, hours, minutes, and ended', () => {
    expect(timeLeftLabel(new Date(NOW + 26 * 3600_000).toISOString(), NOW)).toBe('1d 2h left');
    expect(timeLeftLabel(new Date(NOW + 2 * 3600_000 + 5 * 60_000).toISOString(), NOW)).toBe('2h 5m left');
    expect(timeLeftLabel(new Date(NOW + 12 * 60_000).toISOString(), NOW)).toBe('12m left');
    expect(timeLeftLabel(past, NOW)).toBe('Ended');
  });
});

describe('My Listings / Edit — shipped-source guards', () => {
  const root = resolve(__dirname, '..');
  const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
  const list = read('app/my-listings.tsx');
  const edit = read('app/listing/edit/[id].tsx');

  it('My Listings keeps the delete/cancel split and the send-tickets routing', () => {
    expect(list).toContain("rpc('cancel_listing'"); // has-bids path
    expect(list).toMatch(/from\('listings'\)\s*\.delete\(\)/s); // no-bids path
    expect(list).toContain('/transfer/send/');
    expect(list).toContain('/listing/edit/');
  });

  it('Edit keeps the safe-metadata scope + the moderation gate, no price fields', () => {
    expect(edit).toContain('findBannedContent(');
    for (const field of ['event_name:', 'venue:', 'restrictions:', 'ticket_platform:']) {
      expect(edit).toContain(field);
    }
    // pricing / quantity / dates are not editable here
    expect(edit).not.toMatch(/starting_bid|buy_now_price|current_bid|quantity:/);
  });

  it('neither screen touches money math or kernel.tickets', () => {
    for (const src of [list, edit]) {
      expect(src).not.toMatch(/lib\/money|lib\/payments/);
      expect(src).not.toMatch(/kernel[^\n]*tickets/);
    }
  });
});
