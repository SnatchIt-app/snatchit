/**
 * src/lib/pricing/allIn.ts — the all-in price primitive.
 *
 * WHY
 * Competitor research found that price honesty is the cheapest credibility a
 * ticket marketplace can buy, and the clearest differentiator in the category.
 * One benchmark has no word for "fee" anywhere in its shipped translation
 * dictionary because its prices are all-in, which is why they are never round.
 * Another promises transparency and shows a card price 17% below what the buyer
 * actually pays. Snatch It already computes all-in correctly; it under-shows it.
 *
 * WHAT THIS DOES NOT DO
 * It does not change fee economics. It computes nothing new. It only decides
 * whether a truthful all-in number CAN be shown, and refuses to show one when it
 * cannot. A wrong all-in price is worse than no all-in price.
 *
 * THE CONTRACT, per rail, verified against the schema:
 *
 *   MARKETPLACE (resale, live today)
 *     all-in = base + buyerFee(base), buyer fee 10%, from `src/lib/money.ts`,
 *     which mirrors the server's `_shared/money.ts` byte for byte and is asserted
 *     by tests. The server recomputes and rejects a client total that disagrees.
 *     -> all-in is FULLY SUPPORTED.
 *
 *   DIRECT (venue-native, dark)
 *     `venue."order".total_minor` is a server-authoritative snapshot equal to
 *     the sum of `order_item.unit_price_minor * quantity` (migration 082).
 *     There is NO buyer-fee column and NO tax column anywhere on this rail.
 *     So the order total IS the whole charge, and it is all-in by construction.
 *     -> all-in is SUPPORTED, with one caveat recorded below.
 *
 *   THE CAVEAT, and it is a real gap
 *     Neither rail models TAX. If Snatch It ever needs to collect tax on a direct
 *     sale, the current schema cannot express it, and any "all-in" label would
 *     become a lie at that moment. This is an open item for the owner decision
 *     packet, not something this module can paper over.
 */

import { buyerTotalCents } from '@/src/lib/money';

/**
 * A branded cent amount.
 *
 * THIS EXISTS BECAUSE OF A REAL COLLISION. Marketplace prices in this repository
 * are stored and passed as WHOLE DOLLARS (`public.listings.buy_now_price` is an
 * integer of dollars, and four live screens pass `listing.current_bid` straight
 * into a dollars helper). A plain `number` parameter called `baseMinor` happily
 * accepts `50` meaning fifty dollars and renders it as fifty cents. Branding the
 * type makes that a compile error instead of a 100x price bug.
 *
 * Convert explicitly at the boundary with `centsFromDollars` or `asCents`.
 */
export type Cents = number & { readonly __brand: 'cents' };

/** Assert a value is already in minor units. Use where the source is cents. */
export function asCents(minor: number): Cents {
  return minor as Cents;
}

/** Convert the repo's whole-dollar columns into cents. */
export function centsFromDollars(dollars: number): Cents {
  return Math.round(dollars * 100) as Cents;
}

export type PriceRail = 'marketplace' | 'direct';

export type AllInResult =
  | {
      kind: 'all-in';
      /** The complete amount the buyer will be charged, in cents. */
      totalMinor: Cents;
      currency: string;
      rail: PriceRail;
    }
  | {
      kind: 'unavailable';
      /**
       * Why no truthful all-in figure can be shown. Callers must render a price
       * without an all-in claim, or no price at all. They must never substitute
       * a base price and label it all-in.
       */
      reason:
        | 'missing-base'
        | 'invalid-base'
        | 'unknown-rail'
        | 'tax-unmodelled'
        | 'server-total-missing';
    };

export interface MarketplacePriceInput {
  rail: 'marketplace';
  /** Listing price in CENTS, before the buyer fee. Use `centsFromDollars` for
   *  the repo's whole-dollar listing columns. */
  baseMinor: Cents | null | undefined;
  currency?: string;
}

export interface DirectPriceInput {
  rail: 'direct';
  /**
   * The server-authoritative order total from `venue.create_primary_checkout`.
   * A client must NEVER compute this by summing tiers itself: the server is the
   * price authority and rejects a mismatch.
   */
  serverTotalMinor: Cents | null | undefined;
  currency?: string;
  /**
   * Set true when the venue has configured tax for the event. There is no schema
   * support for this today, so it is always false in practice; the parameter
   * exists so the primitive fails safe on the day tax arrives rather than
   * silently mislabelling a total.
   */
  taxApplies?: boolean;
}

export type PriceInput = MarketplacePriceInput | DirectPriceInput;

function isUsableMinor(v: number | null | undefined): v is Cents {
  return typeof v === 'number' && Number.isFinite(v) && Number.isInteger(v) && v >= 0;
}

/**
 * Computes the all-in total, or explains why it cannot.
 * Never throws. Never guesses.
 */
export function allInPrice(input: PriceInput): AllInResult {
  const currency = input.currency ?? 'USD';

  if (input.rail === 'marketplace') {
    if (input.baseMinor === null || input.baseMinor === undefined) {
      return { kind: 'unavailable', reason: 'missing-base' };
    }
    if (!isUsableMinor(input.baseMinor)) {
      return { kind: 'unavailable', reason: 'invalid-base' };
    }
    return {
      kind: 'all-in',
      totalMinor: buyerTotalCents(input.baseMinor) as Cents,
      currency,
      rail: 'marketplace',
    };
  }

  if (input.rail === 'direct') {
    if (input.taxApplies) {
      // The schema cannot express tax. Refuse rather than under-quote.
      return { kind: 'unavailable', reason: 'tax-unmodelled' };
    }
    if (input.serverTotalMinor === null || input.serverTotalMinor === undefined) {
      return { kind: 'unavailable', reason: 'server-total-missing' };
    }
    if (!isUsableMinor(input.serverTotalMinor)) {
      return { kind: 'unavailable', reason: 'invalid-base' };
    }
    return {
      kind: 'all-in',
      totalMinor: input.serverTotalMinor,
      currency,
      rail: 'direct',
    };
  }

  return { kind: 'unavailable', reason: 'unknown-rail' };
}

/**
 * Formats minor units for display. Whole amounts drop the decimals, because
 * "$60" reads better on a card than "$60.00"; non-round amounts keep them,
 * which is what an honest all-in price usually looks like.
 */
export function formatMinor(totalMinor: Cents | number, currency = 'USD'): string {
  const major = totalMinor / 100;
  const isWhole = totalMinor % 100 === 0;
  const symbol = currency === 'USD' ? '$' : '';
  const body = isWhole
    ? String(Math.round(major))
    : major.toFixed(2);
  const withSeparators = body.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return symbol ? `${symbol}${withSeparators}` : `${withSeparators} ${currency}`;
}

/**
 * The three-state ladder a price surface uses so a card is NEVER blank:
 * a live all-in price, else the last sale, else an invitation to sell.
 */
export type PriceLadder =
  | { kind: 'from'; label: string }
  | { kind: 'last-sale'; label: string }
  | { kind: 'none'; label: string };

export function priceLadder(opts: {
  lowestAllIn?: AllInResult | null;
  lastSaleMinor?: Cents | null;
  currency?: string;
}): PriceLadder {
  const currency = opts.currency ?? 'USD';
  if (opts.lowestAllIn && opts.lowestAllIn.kind === 'all-in') {
    return { kind: 'from', label: `From ${formatMinor(opts.lowestAllIn.totalMinor, currency)}` };
  }
  if (isUsableMinor(opts.lastSaleMinor)) {
    return { kind: 'last-sale', label: `Last sale ${formatMinor(opts.lastSaleMinor, currency)}` };
  }
  return { kind: 'none', label: 'Be the first to sell' };
}
