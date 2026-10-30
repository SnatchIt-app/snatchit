/**
 * src/lib/listing/cardState.ts — what a discovery card says about one listing.
 *
 * WHY THIS IS A MODULE
 * The feed hardcoded "Current bid" and "Bid now" on every card, including Buy Now
 * listings and including listings with no bids at all, and it painted a red
 * "ACTIVE" pill on every live row. Three separate untruths, each rendered inline
 * in the middle of a FlatList `renderItem`, which is why nothing caught them.
 *
 * This is the counterpart to `detailState.ts`: same vocabulary, same rules, one
 * altitude lower. A card and the screen it opens must not disagree about what is
 * being sold.
 *
 * IT DOES NO ARITHMETIC. It SELECTS which existing dollar column the price comes
 * from; formatting stays with `allInFromDollars` at the call site, which is the
 * one place fee math lives.
 */

/** Everything the presentation needs from a listing row. */
export interface CardListing {
  status: string;
  auction_status?: string | null;
  ends_at: string;
  reserved_until?: string | null;
  buy_now_enabled: boolean;
  buy_now_price: number | null;
  starting_bid: number;
  current_bid: number;
  winning_bid_amount?: number | null;
  bid_count?: number | null;
}

export type CardStatusKind = 'sold' | 'reserved' | 'ended' | 'ending_soon' | 'live';
export type CardTone = 'neutral' | 'warning' | 'danger' | 'brand';

/**
 * Which column the headline price comes from. Selection only: every one of these
 * is a WHOLE DOLLAR value on `public.listings`, converted exactly once downstream.
 */
export type PriceSource = 'sold' | 'buy_now' | 'current_bid' | 'starting_bid';

export interface CardPresentation {
  status: CardStatusKind;
  /**
   * Shown as a badge. NULL for an ordinary live listing: a status badge on every
   * card is not information, and a red one on every card spends the brand colour
   * on nothing.
   */
  statusLabel: string | null;
  statusTone: CardTone;
  /** Never "Current bid" when nobody has bid, and never on a sold listing. */
  priceLabel: string;
  priceSource: PriceSource;
  priceDollars: number;
  /**
   * The second offer, when a live listing carries both. `null` on everything
   * else, so a card never implies an auction that is over or absent.
   */
  altLabel: string | null;
  altDollars: number | null;
  /** A live clock is worth showing. A dead one is not. */
  showsCountdown: boolean;
  /** Tapping opens the listing; the card is the target, so it needs the verb. */
  actionHint: string;
}

const ENDING_SOON_MS = 15 * 60 * 1000;

export function cardStatus(listing: CardListing, now: number): CardStatusKind {
  if (listing.status === 'sold') return 'sold';
  if (
    listing.status === 'reserved' &&
    listing.reserved_until &&
    new Date(listing.reserved_until).getTime() > now
  ) {
    return 'reserved';
  }
  const ended =
    listing.auction_status === 'ended' ||
    listing.auction_status === 'cancelled' ||
    new Date(listing.ends_at).getTime() <= now;
  if (ended) return 'ended';
  return new Date(listing.ends_at).getTime() - now <= ENDING_SOON_MS ? 'ending_soon' : 'live';
}

/**
 * The final sale price, by the same priority the rest of the app uses:
 * a stamped winning bid, else the Buy Now price, else the last bid. Mirrors
 * `src/lib/salePrice.ts`, which is the authority; this exists so the card can
 * work from the narrower row shape a feed query returns.
 */
function soldDollars(l: CardListing): number {
  if (l.winning_bid_amount != null && l.winning_bid_amount > 0) return l.winning_bid_amount;
  if (l.buy_now_enabled && l.buy_now_price != null && l.buy_now_price > 0) return l.buy_now_price;
  return l.current_bid;
}

export function cardPresentation(listing: CardListing, now: number): CardPresentation {
  const status = cardStatus(listing, now);
  const bids = listing.bid_count ?? 0;
  const hasBuyNow = listing.buy_now_enabled && listing.buy_now_price != null;

  if (status === 'sold') {
    return {
      status,
      statusLabel: 'Sold',
      statusTone: 'neutral',
      priceLabel: 'Sold for',
      priceSource: 'sold',
      priceDollars: soldDollars(listing),
      altLabel: null,
      altDollars: null,
      showsCountdown: false,
      actionHint: 'View listing',
    };
  }

  if (status === 'ended') {
    return {
      status,
      statusLabel: 'Ended',
      statusTone: 'neutral',
      // Not "Current bid": there is no current anything. If nobody bid, the
      // number on the card is the price it opened at and it says so.
      priceLabel: bids > 0 ? 'Final bid' : 'Started at',
      priceSource: bids > 0 ? 'current_bid' : 'starting_bid',
      priceDollars: bids > 0 ? listing.current_bid : listing.starting_bid,
      altLabel: null,
      altDollars: null,
      showsCountdown: false,
      actionHint: 'View listing',
    };
  }

  // Live, ending soon, or held for another buyer. All three are still on offer
  // in the sense that the card's job is to get the user to open them.
  const live = {
    status,
    statusLabel:
      status === 'reserved' ? 'On hold' : status === 'ending_soon' ? 'Ending soon' : null,
    statusTone: (status === 'reserved' ? 'warning' : status === 'ending_soon' ? 'danger' : 'neutral') as CardTone,
    showsCountdown: true,
    actionHint: hasBuyNow ? 'Buy or bid' : 'Place a bid',
  };

  if (hasBuyNow) {
    return {
      ...live,
      // Buy Now leads on the card for the same reason it leads on the detail
      // screen: it is the stronger offer, and the feed used to hide it entirely.
      priceLabel: 'Buy now',
      priceSource: 'buy_now',
      priceDollars: listing.buy_now_price as number,
      altLabel: bids > 0 ? 'Current bid' : 'Bids from',
      altDollars: bids > 0 ? listing.current_bid : listing.starting_bid,
    };
  }

  return {
    ...live,
    // "Current bid" is a claim that someone has bid. With no bids it is the
    // opening price and nothing more.
    priceLabel: bids > 0 ? 'Current bid' : 'Starting bid',
    priceSource: bids > 0 ? 'current_bid' : 'starting_bid',
    priceDollars: bids > 0 ? listing.current_bid : listing.starting_bid,
    altLabel: null,
    altDollars: null,
  };
}

/** `03:12:45`, `04:12`, `2d 6h left`. One clock format for the whole feed. */
export function countdownLabel(endsAt: string, now: number): string {
  const diff = new Date(endsAt).getTime() - now;
  if (diff <= 0) return 'Ended';
  const totalSec = Math.floor(diff / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const sec = totalSec % 60;
  if (h > 23) return `${Math.floor(h / 24)}d ${h % 24}h left`;
  if (h > 0) {
    return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`;
  }
  return `${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`;
}
