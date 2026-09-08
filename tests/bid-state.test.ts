/**
 * tests/bid-state.test.ts — the Bids screen state model.
 *
 * The screen merges auction bids and purchases into one list; this pins how each
 * row is classified, grouped, priced and actioned. Behaviour, not pixels.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  bidStatusOf,
  bidGroupOf,
  needsAction,
  bidPresentation,
  type BidRowInput,
} from '../src/lib/bids/bidState';

const ME = 'me';
const OTHER = 'other';
const future = new Date(Date.now() + 6 * 3600_000).toISOString();
const past = new Date(Date.now() - 3600_000).toISOString();

type RowOver = Partial<Omit<BidRowInput, 'listing'>> & { listing?: Partial<NonNullable<BidRowInput['listing']>> | null };

function row(over: RowOver = {}): BidRowInput {
  const { listing: lOver, ...rest } = over;
  return {
    amount: 50,
    ...rest,
    listing: lOver === null ? null : {
      status: 'active',
      auction_status: 'active',
      ends_at: future,
      current_bid: 50,
      winner_user_id: null,
      winning_bid_amount: null,
      buy_now_enabled: false,
      buy_now_price: null,
      ...(lOver ?? {}),
    },
  };
}

describe('bid status — auction states', () => {
  it('is winning when the user max is at or above the current bid', () => {
    expect(bidStatusOf(row({ amount: 60, listing: { current_bid: 60 } }), ME)).toBe('winning');
  });
  it('is outbid when the current bid is higher than the user max', () => {
    expect(bidStatusOf(row({ amount: 50, listing: { current_bid: 70 } }), ME)).toBe('outbid');
  });
  it('is won when the auction ended and this user is the winner', () => {
    expect(bidStatusOf(row({ listing: { auction_status: 'ended', winner_user_id: ME } }), ME)).toBe('won');
  });
  it('is lost when the auction ended and someone else won', () => {
    expect(bidStatusOf(row({ listing: { auction_status: 'ended', winner_user_id: OTHER } }), ME)).toBe('lost');
  });
  it('is conservative (lost) when the clock ran out but finalize has not run', () => {
    expect(bidStatusOf(row({ listing: { ends_at: past } }), ME)).toBe('lost');
  });
  it('is sold when the listing sold via Buy Now', () => {
    expect(bidStatusOf(row({ listing: { status: 'sold' } }), ME)).toBe('sold');
  });
});

describe('bid status — purchase states take precedence over the auction', () => {
  it('maps each transfer state, ignoring the underlying auction', () => {
    const base = { listing: { auction_status: 'ended', winner_user_id: ME } as const };
    expect(bidStatusOf(row({ ...base, purchaseTransferStatus: 'pending' }), ME)).toBe('awaiting_transfer');
    expect(bidStatusOf(row({ ...base, purchaseTransferStatus: 'seller_sent' }), ME)).toBe('seller_sent');
    expect(bidStatusOf(row({ ...base, purchaseTransferStatus: 'disputed' }), ME)).toBe('purchase_disputed');
    expect(bidStatusOf(row({ ...base, purchaseTransferStatus: 'buyer_confirmed' }), ME)).toBe('purchase_confirmed');
    expect(bidStatusOf(row({ ...base, purchaseTransferStatus: 'auto_released' }), ME)).toBe('purchase_confirmed');
  });
});

describe('grouping and urgency', () => {
  it('puts settled states in Past and everything else in Active', () => {
    expect(bidGroupOf('lost')).toBe('past');
    expect(bidGroupOf('sold')).toBe('past');
    expect(bidGroupOf('purchase_confirmed')).toBe('past');
    for (const s of ['winning', 'outbid', 'won', 'awaiting_transfer', 'seller_sent', 'purchase_disputed'] as const) {
      expect(bidGroupOf(s)).toBe('active');
    }
  });
  it('flags exactly the states that need the user to act', () => {
    expect(['won', 'outbid', 'awaiting_transfer', 'seller_sent', 'purchase_disputed'].every(needsAction as any)).toBe(true);
    expect(['winning', 'lost', 'sold', 'purchase_confirmed'].some(needsAction as any)).toBe(false);
  });
  it('orders a dispute above a win above a confirm prompt above bidding', () => {
    const pr = (s: BidRowInput) => bidPresentation(s, ME).priority;
    const disputed = pr(row({ purchaseTransferStatus: 'disputed' }));
    const won = pr(row({ listing: { auction_status: 'ended', winner_user_id: ME } }));
    const sent = pr(row({ purchaseTransferStatus: 'seller_sent' }));
    const outbid = pr(row({ amount: 40, listing: { current_bid: 70 } }));
    expect(disputed).toBeLessThan(won);
    expect(won).toBeLessThan(sent);
    expect(sent).toBeLessThan(outbid);
  });
});

describe('presentation — copy, price and routing', () => {
  it('never labels anything with a bare colour and never uses emoji', () => {
    const statuses = [
      row({ amount: 60, listing: { current_bid: 60 } }),
      row({ amount: 40, listing: { current_bid: 70 } }),
      row({ listing: { auction_status: 'ended', winner_user_id: ME } }),
      row({ listing: { auction_status: 'ended', winner_user_id: OTHER } }),
      row({ listing: { status: 'sold' } }),
      row({ purchaseTransferStatus: 'pending' }),
      row({ purchaseTransferStatus: 'seller_sent' }),
      row({ purchaseTransferStatus: 'disputed' }),
      row({ purchaseTransferStatus: 'buyer_confirmed' }),
    ];
    const emoji = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]/u;
    for (const r of statuses) {
      const p = bidPresentation(r, ME);
      expect(p.label.length).toBeGreaterThan(0);
      expect(emoji.test(p.label)).toBe(false);
      expect(emoji.test(p.actionHint)).toBe(false);
    }
  });

  it('won shows what the buyer must pay and leads to pay to claim', () => {
    const p = bidPresentation(row({ amount: 55, listing: { auction_status: 'ended', winner_user_id: ME, winning_bid_amount: 80 } }), ME);
    expect(p.label).toBe('Won');
    expect(p.actionHint).toBe('Pay to claim');
    expect(p.priceDollars).toBe(80);       // the winning bid, not the user's max
    expect(p.routesToTransfer).toBe(false); // pay flow is on the listing
  });

  it('outbid shows the current bid with the user max beneath it, and offers a rebid', () => {
    const p = bidPresentation(row({ amount: 50, listing: { current_bid: 75 } }), ME);
    expect(p.priceLabel).toBe('Current bid');
    expect(p.priceDollars).toBe(75);
    expect(p.secondaryLabel).toBe('Your max');
    expect(p.secondaryDollars).toBe(50);
    expect(p.actionHint).toBe('Bid again');
  });

  it('an in-flight purchase routes to the transfer flow', () => {
    expect(bidPresentation(row({ purchaseTransferStatus: 'seller_sent' }), ME).routesToTransfer).toBe(true);
    expect(bidPresentation(row({ purchaseTransferStatus: 'disputed' }), ME).routesToTransfer).toBe(true);
  });

  it('an unfilled delivery step asks the buyer to add transfer info', () => {
    const p = bidPresentation(row({ purchaseTransferStatus: 'pending', needsDeliveryInfo: true }), ME);
    expect(p.actionHint).toBe('Add transfer info');
    const q = bidPresentation(row({ purchaseTransferStatus: 'pending', needsDeliveryInfo: false }), ME);
    expect(q.actionHint).toBe('Waiting for the seller');
  });

  it('a sold listing reports what it sold for by the sale-price priority', () => {
    // Buy Now sale: no winning bid stamped, so the price is the buy-now price.
    const p = bidPresentation(row({ listing: { status: 'sold', buy_now_enabled: true, buy_now_price: 90, current_bid: 40 } }), ME);
    expect(p.priceLabel).toBe('Sold for');
    expect(p.priceDollars).toBe(90);
  });
});

/** Guards on the shipped screen: data layer preserved, tickets constraint honoured. */
describe('bids screen — shipped-source guards', () => {
  const root = resolve(__dirname, '..');
  const code = (rel: string) =>
    readFileSync(resolve(root, rel), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
  const screen = code('app/(tabs)/bids.tsx');
  const card = code('src/components/bids/BidCard.tsx');

  it('never queries kernel.tickets and builds no ticket object', () => {
    expect(screen).not.toMatch(/kernel\.tickets|from\(['"]tickets['"]\)|\.tickets\b/);
    expect(screen).not.toMatch(/Apple Wallet|add to wallet|\.pkpass|QR|barcode/i);
  });

  it('keeps the data layer it had — bids query, transfers merge, collapse', () => {
    for (const marker of [
      "from('bids')",
      "from('transfers')",
      'byListing',
      'useFocusEffect',
      'finalSoldPrice',
      'RefreshControl',
    ]) {
      expect(screen, `${marker} must survive`).toContain(marker);
    }
  });

  it('formats money through the one helper and does no arithmetic', () => {
    expect(screen).toContain('allInFromDollars(');
    expect(card).not.toMatch(/lib\/money/);      // card takes preformatted strings
    expect(card).not.toMatch(/\* 100|\/ 100/);
  });

  it('drops the hardcoded safe-area guess and any emoji UI', () => {
    expect(screen).not.toMatch(/paddingTop:\s*56/);
    const emoji = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]/u;
    expect(emoji.test(screen)).toBe(false);
    expect(emoji.test(card)).toBe(false);
  });

  it('opens the approved listing detail and transfer routes', () => {
    expect(screen).toContain('/listing/');
    expect(screen).toContain('/transfer/receive/');
  });
});
