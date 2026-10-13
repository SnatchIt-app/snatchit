/**
 * tests/listing-detail-state.test.ts — what the listing detail screen offers.
 *
 * These are the decisions that were previously spread across a dozen booleans
 * recombined at five render sites, where two of them were wrong in production:
 * Buy Now was rendered as the weaker of the two actions on every dual-mode
 * listing, and a seller was shown an enabled bid button that the database
 * refuses by design (`validate_and_apply_bid`'s shill-bid guard).
 *
 * State mapping, not pixels. Nothing here asserts a layout.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { LISTING_READ_FAILED_COPY,
  detailState,
  listingActions,
  listingStatus,
  transactionMode,
  viewerRole,
  type DetailStateInput,
} from '../src/lib/listing/detailState';

const SELLER = 'seller-uuid';
const BUYER = 'buyer-uuid';
const OTHER = 'other-uuid';

type Over = Partial<Omit<DetailStateInput, 'listing'>> & {
  listing?: Partial<DetailStateInput['listing']>;
};

function input(over: Over = {}): DetailStateInput {
  const { listing: listingOver, ...rest } = over;
  return {
    userId: BUYER,
    clockEnded: false,
    reservationActive: false,
    finalizing: false,
    reserving: false,
    transfer: { id: null, status: null, buyerId: null },
    isHighestBidder: false,
    hasBid: false,
    buyNowAllIn: null,
    ...rest,
    // Merged last and separately, so a partial listing override can never drop
    // seller_id and silently turn the seller into a visitor.
    listing: {
      status: 'active',
      auction_status: 'active',
      buy_now_enabled: false,
      buy_now_price: null,
      seller_id: SELLER,
      reserved_by: null,
      winner_user_id: null,
      bid_count: 0,
      ...(listingOver ?? {}),
    },
  };
}

const withBuyNow = (over: Over = {}) =>
  input({
    ...over,
    listing: { buy_now_enabled: true, buy_now_price: 60, ...(over.listing ?? {}) },
    buyNowAllIn: '$66',
  });

describe('transaction mode', () => {
  it('is auction-only when there is no Buy Now price', () => {
    expect(transactionMode(input())).toBe('auction_only');
  });

  it('carries both offers when Buy Now is enabled', () => {
    expect(transactionMode(withBuyNow())).toBe('auction_and_buy_now');
  });

  it('closes on sold, cancelled, ended, and a run-out clock', () => {
    expect(transactionMode(input({ listing: { ...input().listing, status: 'sold' } }))).toBe('closed');
    expect(
      transactionMode(input({ listing: { ...input().listing, auction_status: 'cancelled' } })),
    ).toBe('closed');
    expect(
      transactionMode(input({ listing: { ...input().listing, auction_status: 'ended' } })),
    ).toBe('closed');
    expect(transactionMode(input({ clockEnded: true }))).toBe('closed');
  });

  it('closes while someone else holds the reservation, and stays open for the holder', () => {
    const held = { ...input().listing, reserved_by: OTHER };
    expect(transactionMode(input({ listing: held, reservationActive: true }))).toBe('closed');

    const mine = { ...input().listing, reserved_by: BUYER };
    expect(transactionMode(input({ listing: mine, reservationActive: true }))).not.toBe('closed');
  });
});

describe('actions — the hierarchy when both are available', () => {
  it('leads with the BID and offers Buy Now beneath it (owner ruling 2026-09-25, Option B)', () => {
    /*
     * SETTLED, and it supersedes the earlier Buy-Now-first hierarchy this suite used to lock down:
     * "Place a bid is first, full-width and red. Its minimum all-in amount sits beneath the label
     * inside the button. Buy Now is second, full-width and outlined."
     *
     * Asserted on the RESOLVER rather than on the screen because that is where the owner required
     * it to live: the footer paints `primary` filled-red first and `secondary` outlined below, so
     * a screen-level override would let other consumers of the resolver disagree with the footer.
     */
    const { primary, secondary } = listingActions(withBuyNow({ nextBidAllIn: '$104.50' }));
    expect(primary.kind).toBe('place_bid');
    // The minimum rides INSIDE the leading button, as its sub-label.
    expect(primary.subLabel).toBe('minimum $104.50 all-in');
    expect(secondary?.kind).toBe('buy_now');
    // Buy Now keeps its quantity-aware label, its price and its subline, exactly as approved.
    expect(secondary?.label).toContain('$66');
    expect(secondary?.subLabel).toBe('all-in, ends the auction');
    // And the superseded arrangement is gone, not merely unasserted.
    expect(primary.kind).not.toBe('buy_now');
  });

  it('the ruling reaches ONLY the both-available state — every other state keeps its action', () => {
    /*
     * The owner was explicit: "Do not force this pair onto reserved, sold, ended, own-listing or
     * other states with different valid actions." A hierarchy change is the kind of edit that
     * leaks, so each state is named and pinned rather than covered by a sweep.
     */
    const states: [string, DetailStateInput][] = [
      ['auction only', input()],
      ['reserved by me', input({ listing: { status: 'reserved' }, reservationActive: true })],
      ['reserved by someone else', input({ listing: { reserved_by: 'other' }, reservationActive: true })],
      ['own listing', input({ listing: { seller_id: 'me' }, userId: 'me' })],
      ['sold', input({ listing: { status: 'sold' } })],
      ['auction ended', input({ listing: { auction_status: 'ended' } })],
      ['cancelled', input({ listing: { auction_status: 'cancelled' } })],
      ['clock ended', input({ clockEnded: true })],
      ['won it', input({ listing: { auction_status: 'ended', winner_user_id: 'me' }, userId: 'me' })],
      // The pair itself, as the control: the invariant below must be able to find it.
      ['both available', withBuyNow()],
    ];
    for (const [name, i] of states) {
      const actions = listingActions(i);
      const isThePair = actions.primary.kind === 'place_bid' && actions.secondary?.kind === 'buy_now';
      expect(isThePair, `${name}: the pair appears iff both actions are valid`)
        .toBe(transactionMode(i) === 'auction_and_buy_now');
      // Outside that one mode the screen offers a single action, so nothing sits beside it.
      if (transactionMode(i) !== 'auction_and_buy_now') {
        expect(actions.secondary, `${name} has no second button`).toBeNull();
      }
    }
    /*
     * NOT asserted, because it does not exist: a "buy-now-only" state. `transactionMode` has no
     * branch that drops bidding — every row carries an auction (`starting_bid` and `ends_at` are
     * NOT NULL), so Buy Now is always an addition. A first draft of this test asserted such a
     * state and failed, which is the useful kind of failure: the state was mine, not the product's.
     */
  });

  it('leads with bidding, and offers nothing else, when there is no Buy Now', () => {
    const { primary, secondary } = listingActions(input());
    expect(primary.kind).toBe('place_bid');
    expect(secondary).toBeNull();
  });

  it('V3 (O-2): the bid CTA says what it does — it OPENS bid entry, it does not submit', () => {
    // ListingDetailScreen routes place_bid to router.push('/bid/…') — nothing is submitted from
    // the listing. So the label is "Place a bid", and the minimum travels as an informational
    // sub-line, never as a price the button would submit.
    const bidOnly = listingActions(input({ nextBidAllIn: '$104.50' }));
    expect(bidOnly.primary.kind).toBe('place_bid');
    expect(bidOnly.primary.label).toBe('Place a bid');
    expect(bidOnly.primary.subLabel).toBe('minimum $104.50 all-in');
    expect(bidOnly.primary.label).not.toMatch(/\$/);

    // Beside Buy Now the bid now LEADS (owner 2026-09-25), and it still submits nothing — the
    // label is the same verb and the minimum is still an informational sub-line.
    const both = listingActions(withBuyNow({ nextBidAllIn: '$104.50' }));
    expect(both.primary.kind).toBe('place_bid');
    expect(both.primary.label).toBe('Place a bid');
    expect(both.primary.subLabel).toBe('minimum $104.50 all-in');
    expect(both.primary.label).not.toMatch(/\$/);

    // No all-in supplied (e.g. closed, or the price is still loading): no number is invented.
    expect(listingActions(input()).primary.subLabel).toBeUndefined();

    // §5: Buy Now beside a live auction carries its truth — all-in, and it ends the auction.
    expect(both.secondary?.kind).toBe('buy_now');
    expect(both.secondary?.subLabel).toBe('all-in, ends the auction');
  });

  it('V3 (owner ruling 2026-09-22): the buy-now verb counts the tickets — the price is the WHOLE listing', () => {
    // "Buy both now" for two; other quantities named accurately; one ticket needs no counting.
    // Beside a live auction the buy-now action is the SECONDARY (owner 2026-09-25); its label,
    // price and subline are unchanged by that ruling, which is what these assertions protect.
    const two = listingActions(withBuyNow({ listing: { quantity: 2 } }));
    expect(two.secondary?.label).toBe('Buy both now · $66');
    const three = listingActions(withBuyNow({ listing: { quantity: 3 } }));
    expect(three.secondary?.label).toBe('Buy all 3 now · $66');
    const one = listingActions(withBuyNow({ listing: { quantity: 1 } }));
    expect(one.secondary?.label).toBe('Buy now · $66');
    // Quantity unknown to the caller: no count is invented.
    expect(listingActions(withBuyNow()).secondary?.label).toBe('Buy now · $66');
    // The whole-listing identification also survives a missing price string. (Built via input():
    // withBuyNow force-sets buyNowAllIn after its overrides.)
    const priceless = listingActions(input({
      listing: { buy_now_enabled: true, buy_now_price: 60, quantity: 2 },
      buyNowAllIn: null,
    }));
    expect(priceless.secondary?.label).toBe('Buy both now');
    // The bid leads beside Buy Now (owner 2026-09-25).
    expect(two.primary.kind).toBe('place_bid');
    expect(two.secondary?.kind).toBe('buy_now');
  });

  it('never shows an auction price as the Buy Now price', () => {
    // No all-in string supplied means no number is invented for the label.
    const { secondary } = listingActions(
      input({
        listing: { ...input().listing, buy_now_enabled: true, buy_now_price: 60 },
        buyNowAllIn: null,
      }),
    );
    // The buy-now action is the SECONDARY beside a live auction (owner 2026-09-25).
    expect(secondary?.label).toBe('Buy now');
  });
});

describe('actions — nothing is offered that cannot work', () => {
  it('offers the seller of a live listing no buyer action at all', () => {
    // The database refuses a seller's bid on their own listing. The old screen
    // showed them an enabled "Place Bid" whose only outcome was a raw error.
    const { primary, secondary } = listingActions(withBuyNow({ userId: SELLER }));
    expect(primary.kind).toBe('unavailable');
    expect(primary.disabled).toBe(true);
    expect(secondary).toBeNull();
  });

  it('suppresses purchase on a sold listing', () => {
    const { primary, secondary } = listingActions(
      withBuyNow({ listing: { ...withBuyNow().listing, status: 'sold' } }),
    );
    expect(primary.kind).toBe('unavailable');
    expect(primary.label).toBe('Sold');
    expect(secondary).toBeNull();
  });

  it('suppresses purchase once the auction has ended', () => {
    const { primary } = listingActions(
      withBuyNow({ listing: { ...withBuyNow().listing, auction_status: 'ended' } }),
    );
    expect(primary.kind).toBe('unavailable');
    expect(primary.label).toBe('Ended');
  });

  it('says a listing is on hold rather than offering it to a second buyer', () => {
    const { primary } = listingActions(
      withBuyNow({
        listing: { ...withBuyNow().listing, reserved_by: OTHER },
        reservationActive: true,
      }),
    );
    expect(primary.label).toBe('On hold');
    expect(primary.disabled).toBe(true);
  });

  it('sends the reservation holder to checkout instead of re-reserving', () => {
    const { primary } = listingActions(
      withBuyNow({
        listing: { ...withBuyNow().listing, reserved_by: BUYER },
        reservationActive: true,
      }),
    );
    expect(primary.kind).toBe('continue_reservation');
  });

  it('shows nothing purchasable while the auction is being finalized', () => {
    expect(listingActions(withBuyNow({ finalizing: true })).primary.kind).toBe('unavailable');
  });
});

describe('actions — after the sale', () => {
  const sold = (over: Partial<DetailStateInput>) =>
    input({
      listing: { ...input().listing, status: 'sold', auction_status: 'ended' },
      ...over,
    });

  it('asks the winner to pay', () => {
    const { primary } = listingActions(
      input({
        listing: { ...input().listing, auction_status: 'ended', winner_user_id: BUYER },
      }),
    );
    expect(primary.kind).toBe('pay_now');
  });

  it('asks the seller to send the tickets once payment lands', () => {
    const { primary } = listingActions(
      sold({ userId: SELLER, transfer: { id: 't1', status: 'pending', buyerId: BUYER } }),
    );
    expect(primary.kind).toBe('send_tickets');
  });

  it('asks the buyer to review what the seller sent', () => {
    const { primary } = listingActions(
      sold({ userId: BUYER, transfer: { id: 't1', status: 'seller_sent', buyerId: BUYER } }),
    );
    expect(primary.kind).toBe('review_transfer');
  });

  it('routes a disputed transfer to the dispute, not to a purchase', () => {
    const { primary } = listingActions(
      sold({ userId: BUYER, transfer: { id: 't1', status: 'disputed', buyerId: BUYER } }),
    );
    expect(primary.kind).toBe('view_dispute');
  });

  it('shows a passer-by nothing but the closed state', () => {
    const { primary } = listingActions(
      sold({ userId: OTHER, transfer: { id: 't1', status: 'seller_sent', buyerId: BUYER } }),
    );
    expect(primary.kind).toBe('unavailable');
    expect(primary.label).toBe('Sold');
  });
});

describe('status — one at a time, by priority', () => {
  it('reports closing before anything else', () => {
    const st = listingStatus(input({ finalizing: true, hasBid: true, isHighestBidder: false }));
    expect(st?.kind).toBe('finalizing');
  });

  it('reports the sale rather than a stale outbid state', () => {
    // Previously SOLD, the reservation notice, the transfer row, the owner block
    // and the auction banner could all render at once, above the artwork.
    const st = listingStatus(
      input({
        listing: { ...input().listing, status: 'sold', auction_status: 'ended' },
        hasBid: true,
      }),
    );
    expect(st?.kind).toBe('sold');
  });

  it('tells each side of a live transfer what it needs to do', () => {
    const seller = listingStatus(
      input({
        listing: { ...input().listing, status: 'sold' },
        userId: SELLER,
        transfer: { id: 't1', status: 'pending', buyerId: BUYER },
      }),
    );
    expect(seller?.kind).toBe('transfer_pending');
    expect(seller?.label).toBe('Send the tickets');

    const buyer = listingStatus(
      input({
        listing: { ...input().listing, status: 'sold' },
        userId: BUYER,
        transfer: { id: 't1', status: 'seller_sent', buyerId: BUYER },
      }),
    );
    expect(buyer?.kind).toBe('transfer_pending');
  });

  it('separates winning from outbid, and says which in words', () => {
    const winning = listingStatus(input({ hasBid: true, isHighestBidder: true }));
    expect(winning?.kind).toBe('winning');
    expect(winning?.label).toMatch(/highest bidder/i);

    const outbid = listingStatus(input({ hasBid: true, isHighestBidder: false }));
    expect(outbid?.kind).toBe('outbid');
    expect(outbid?.tone).toBe('danger');
  });

  it('says nothing at all to a viewer with no stake in a live auction', () => {
    expect(listingStatus(input())).toBeNull();
  });

  it('congratulates the winner and tells them what happens next', () => {
    const st = listingStatus(
      input({
        listing: { ...input().listing, auction_status: 'ended', winner_user_id: BUYER },
        hasBid: true,
      }),
    );
    expect(st?.kind).toBe('won');
    expect(st?.detail).toMatch(/pay/i);
  });

  it('does not tell a non-bidder they lost', () => {
    const st = listingStatus(
      input({ listing: { ...input().listing, auction_status: 'ended' }, hasBid: false }),
    );
    expect(st?.kind).toBe('ended');
  });
});

describe('roles and owner controls', () => {
  it('identifies the three viewers', () => {
    expect(viewerRole(input({ userId: SELLER }))).toBe('seller');
    expect(
      viewerRole(input({ userId: BUYER, transfer: { id: 't', status: 'pending', buyerId: BUYER } })),
    ).toBe('buyer');
    expect(viewerRole(input({ userId: OTHER }))).toBe('visitor');
  });

  it('offers owner controls to the owner only', () => {
    expect(detailState(input({ userId: SELLER })).showsOwnerActions).toBe(true);
    expect(detailState(input({ userId: BUYER })).showsOwnerActions).toBe(false);
    expect(detailState(input({ userId: undefined })).showsOwnerActions).toBe(false);
  });
});

/**
 * Source-level guards. These assert facts about the shipped screen that a state
 * test cannot reach, and each one corresponds to a live constraint from
 * CORE_FRONTEND_HANDOFF.md rather than to a style preference.
 */
describe('listing detail — shipped-source guards', () => {
  const root = resolve(__dirname, '..');
  /**
   * Comments explain the rules, and several of them quote the exact strings the
   * rules forbid. Matching raw source would fail on its own documentation, so the
   * guards read the code.
   */
  const code = (rel: string) =>
    readFileSync(resolve(root, rel), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');

  const screen = code('src/screens/ListingDetailScreen.tsx');
  const hero = code('src/components/listing/ListingHero.tsx');
  const panel = code('src/components/listing/TransactionPanel.tsx');

  it('never claims venue-direct provenance', () => {
    // Migration 093 is undeployed and every native rail flag is false, so no
    // venue-issued ticket exists for that badge to be true about.
    for (const [name, src] of [['screen', screen], ['hero', hero], ['panel', panel]] as const) {
      expect(src, `${name} must not claim direct provenance`).not.toMatch(/Direct from event/i);
      expect(src, `${name} must not set the venue-primary flag`).not.toMatch(/isVenuePrimarySale/);
    }
    expect(hero).toContain('FromAFanBadge');
  });

  it('does no money arithmetic of its own', () => {
    // One conversion exists in this app and it is in src/lib/money.ts.
    expect(screen).toMatch(/from '@\/src\/lib\/money'/);
    expect(panel).not.toMatch(/\* 100|\/ 100/);
    expect(hero).not.toMatch(/\* 100|\/ 100/);
    // The screen keeps exactly the two pre-existing checkout conversions, both
    // of which go through the canonical helper pair.
    const conversions = screen.match(/dollarsToCents\(/g) ?? [];
    expect(conversions).toHaveLength(2);
  });

  it('renders prices through the canonical primitive', () => {
    expect(panel).toContain('PriceDisplay');
    expect(screen).toContain('PriceDisplay');
  });

  it('has no emoji left in its interface', () => {
    // The old screen used ⚡ 📤 📥 ⚠️ ✏️ ⛔️ 🗑 💳 🏆 🎉 as controls and status.
    const emoji = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]/u;
    expect(emoji.test(hero)).toBe(false);
    expect(emoji.test(panel)).toBe(false);
    // The screen keeps emoji ONLY inside push-notification copy, which is OS
    // chrome rather than interface. Nothing in the JSX carries one.
    const jsx = screen.slice(screen.indexOf('─── Render ───'));
    expect(emoji.test(jsx)).toBe(false);
  });

  it('keeps the realtime and outbid machinery intact', () => {
    for (const marker of [
      'useListingRealtime',
      'handleNewBid',
      'outbidInitializedRef',
      'wasOutbidRef',
      'Haptics.notificationAsync',
      'finalize_auction',
      'reserve_buy_now',
      'cancel_listing',
      'user_blocks',
    ]) {
      expect(screen, `${marker} must survive the redesign`).toContain(marker);
    }
  });
});

describe('V3 §5 — the failed-read copy claims nothing it cannot know', () => {
  it('says the read failed and that nothing left this screen; never anything about server state', () => {
    expect(LISTING_READ_FAILED_COPY.title).toBe("We couldn't load this listing");
    expect(LISTING_READ_FAILED_COPY.body).toBe(
      "Nothing was sent from this screen — we couldn't read the listing. Check your connection and try again.",
    );
    expect(LISTING_READ_FAILED_COPY.retry).toBe('Try again');
    const all = `${LISTING_READ_FAILED_COPY.title} ${LISTING_READ_FAILED_COPY.body}`.toLowerCase();
    expect(all).not.toMatch(/your bid|unchanged|reserved|refund|charged|sold|released/);
  });

  it('the screen renders it on a non-network failure, with Try again wired to the read (source pins)', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/screens/ListingDetailScreen.tsx', 'utf8');
    expect(src).toContain('title={LISTING_READ_FAILED_COPY.title}');
    expect(src).toContain('body={LISTING_READ_FAILED_COPY.body}');
    expect(src).toContain('label: LISTING_READ_FAILED_COPY.retry, onPress: () => fetchData()');
    expect(src).toContain('<ScreenState state="offline"');   // offline keeps its own state
  });

  it("F-V3-READFAIL-1: the copy can never render AFTER a reservation left this screen", async () => {
    // D's trace (2026-09-24, verified line by line): reserve_buy_now succeeds, the post-write
    // refetch runs NON-silent, a failed read there sets `error`, navigation proceeds anyway, and
    // on return the screen says "Nothing was sent from this screen" — right after a reservation
    // WAS sent and checkout may have created a PaymentIntent on mount. The invariant that keeps
    // the sentence true is structural: only reads that precede any send may set `error`, so the
    // post-reserve refresh must be SILENT — a refresh failure keeps the loaded screen, it does
    // not replace it with a false reassurance.
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/screens/ListingDetailScreen.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    const block = src.slice(src.indexOf("supabase.rpc('reserve_buy_now'"), src.indexOf('navigateToCheckout();', src.indexOf("supabase.rpc('reserve_buy_now'")));
    expect(block.length).toBeGreaterThan(0);
    expect(block, 'the post-reserve refresh must be silent').toContain('fetchData(true)');
    expect(block, 'a non-silent read after the write re-opens the defect').not.toMatch(/fetchData\(\)/);
    // …and the error state remains reachable only from reads that precede any send: the initial
    // load and the retry controls that render only once error is already set.
    const bare = [...src.matchAll(/fetchData\(\)/g)].length;
    const retries = [...src.matchAll(/onPress: \(\) => fetchData\(\)|onRetry=\{\(\) => fetchData\(\)\}/g)].length;
    expect(bare - retries, 'every bare fetchData() must be a retry control').toBe(0);
    // …and the one explicit non-silent call is the initial load, which precedes any send.
    expect([...src.matchAll(/fetchData\(false\)/g)].length).toBe(1);
  });
});

