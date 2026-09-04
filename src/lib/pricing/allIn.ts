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
 * It does not change fee economics. It computes no rate of its own. It only
 * decides whether a truthful all-in number CAN be shown, and refuses to show one
 * when it cannot. A wrong all-in price is worse than no all-in price.
 *
 * THE CONTRACT, per rail, verified against the schema:
 *
 *   MARKETPLACE (resale, live today)
 *     all-in = base + buyerFee(base), buyer fee 10%, from `src/lib/money.ts`,
 *     which mirrors the server's `_shared/money.ts` byte for byte and is asserted
 *     by tests. The server recomputes and rejects a client total that disagrees.
 *     -> all-in is FULLY SUPPORTED. Behaviour here is FROZEN: the total is
 *        `buyerTotalCents(base)` and nothing in this file may change that number.
 *
 *   DIRECT (venue-native, dark) — REWRITTEN FOR OWNER RULING A5
 *     *** `venue."order".total_minor` IS FACE VALUE. IT IS NOT THE CHARGE. ***
 *     Ruling A5 (docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md:113) fixes
 *     the venue's entitlement AT the configured ticket face value and funds
 *     Snatch It through a configurable BUYER-SIDE service fee. Migration 093
 *     (docs/phase2/_impl/093_parts/30_connect_org.sql:726-800) therefore has
 *     `venue.create_primary_checkout` return THREE numbers:
 *
 *         total_minor        — face value; the venue's gross, the settlement basis
 *         buyer_fee_minor    — round(face * fee.buyer_service_bps / 10000), half-up
 *         charge_total_minor — face + fee; the ONLY figure a PaymentIntent is minted for
 *
 *     and `supabase/functions/primary-checkout/index.ts` surfaces them as
 *     `amount`, `buyer_fee` and `total`. **`total` is the price. `amount` is not.**
 *
 *     The previous version of this header said the direct order total "IS the
 *     whole charge, and it is all-in by construction, because there is no
 *     buyer-fee column and no tax column". A5 made that false. A caller who
 *     followed it passed `order.total_minor` and under-showed the real price by
 *     exactly the service fee — the precise dishonesty this module exists to
 *     prevent. That is why `DirectPriceInput` no longer has a single "total"
 *     field a caller can fill in with the wrong number: it demands the face
 *     value and the fee SEPARATELY, and refuses if the fee is not known.
 *
 *   THE FEE RATE IS OWNER CONFIG, AND ITS ABSENCE IS A REFUSAL
 *     `fee.buyer_service_bps` is seeded NULL. The RPC raises
 *     `service_fee_unset` and the edge answers 503 rather than selling a ticket
 *     at face value with no platform revenue (settlement is append-only; revenue
 *     not recognised at the sale can never be restated). This module mirrors that
 *     stop exactly: `{ source: 'unset' }` yields `unavailable: 'service-fee-unset'`.
 *     There is NO zero fallback and NO hardcoded percentage anywhere in this file.
 *
 *   TAX, STILL UNMODELLED ON BOTH RAILS
 *     Neither rail has a tax column. If tax could apply and its amount is not
 *     known, this refuses (`tax-unmodelled`) rather than under-quote. The
 *     `{ status: 'applies', taxMinor }` branch exists so that the day a schema
 *     models tax, the primitive already carries it into the total instead of
 *     needing a redesign under time pressure.
 *
 *   MONEY ARITHMETIC
 *     Direct-rail arithmetic in this file is INTEGER ONLY — no rate is ever
 *     multiplied as a float, and no division happens outside an exact-multiple
 *     case. The one float is inside `money.ts`'s `buyerFeeCents` (`base * 0.10`),
 *     deliberately untouched: that file is a byte-identical mirror of the
 *     server's `_shared/money.ts` and parity is asserted by tests. Changing it to
 *     integer basis points would fork the client from the server. Recorded as a
 *     known divergence in docs/phase2/_impl/G5_pricing_contract.md.
 */

import { buyerFeeCents, buyerTotalCents } from '@/src/lib/money';

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
 * THE MIRROR-IMAGE TRAP, which the direct rail introduces: every venue column
 * (`ticket_type.price_minor`, `order.total_minor`, `buyer_fee_minor`,
 * `charge_total_minor`) is ALREADY in minor units. Those take `asCents`, never
 * `centsFromDollars` — a double conversion turns $60 into $6,000.
 *
 * WHY THE BRAND ALONE WAS NOT ENOUGH, and what was added.
 * A brand stops accidental MIXING, but `asCents` is an unchecked cast and was
 * therefore an open escape hatch into the very bug the brand exists to prevent:
 * `asCents(50)` on a whole-dollar column type-checked and quoted $0.55. Two
 * compile-time closures now stand behind the brand:
 *
 *   1. `centsFromDollars` returns `DollarDerivedCents`, a SUBTYPE of `Cents`,
 *      and the resale rail's `baseMinor` accepts only that. `asCents` cannot
 *      produce it, so `asCents(50)` on the marketplace rail no longer compiles.
 *   2. `formatMinor` accepts only `Cents`, so `formatMinor(50)` — a bare
 *      whole-dollar figure, which is what every `public.listings` price is —
 *      no longer compiles either.
 *
 * WHAT WAS DELIBERATELY NOT DONE: a magnitude guard inside `asCents` (e.g.
 * "reject two-digit values, they are probably dollars"). It would fire on
 * correct code. The direct rail legitimately carries small cent amounts — a 10%
 * `buyer_fee_minor` on a $5 face IS 50, and a tax line can be 25 — so the
 * heuristic's false positives land squarely on the fields ruling A5 introduced.
 * A guess that rejects real money is not safer than a type that cannot be wrong.
 */
export type Cents = number & { readonly __brand: 'cents' };

/**
 * Cents that PROVABLY came from a whole-dollar source through the one legal
 * converter. Required by the resale rail, where every price column in this
 * repository is whole dollars, so that the units question is answered by the
 * compiler rather than by the caller remembering.
 */
export type DollarDerivedCents = Cents & { readonly __source: 'whole-dollars' };

/**
 * Assert a value is ALREADY in minor units. Use for every `*_minor` column and
 * every field of the primary-checkout response.
 *
 * This is an unchecked cast and cannot validate units at runtime: `50` is a
 * perfectly legal `buyer_fee_minor`. It is therefore NOT accepted by the resale
 * rail (see `DollarDerivedCents`), which is the only rail in this repository
 * whose source columns are dollars.
 */
export function asCents(minor: number): Cents {
  return minor as Cents;
}

/**
 * THE conversion for the repo's whole-dollar `public.*` columns —
 * `listings.buy_now_price`, `current_bid`, `winning_bid_amount`. This is the
 * only function that can produce the type the resale rail accepts.
 */
export function centsFromDollars(dollars: number): DollarDerivedCents {
  return Math.round(dollars * 100) as DollarDerivedCents;
}

/**
 * The named escape hatch, for a marketplace price that is genuinely already in
 * minor units.
 *
 * NO SUCH COLUMN EXISTS TODAY. Every resale price in this repository is whole
 * dollars (`money.ts`: "Listing prices are stored in whole dollars"). This
 * exists so that closing the units hole does not push a future caller toward
 * `as unknown as DollarDerivedCents`, which would silently defeat all of the
 * above. It is deliberately long, greppable, and self-incriminating: if you are
 * typing it, prove the source column is minor units first.
 */
export function marketplaceCentsFromMinorColumn(minor: number): DollarDerivedCents {
  return minor as DollarDerivedCents;
}

export type PriceRail = 'marketplace' | 'direct';

/**
 * Why no truthful all-in figure can be shown. Callers must render a price
 * without an all-in claim, or no price at all. They must never substitute a
 * base or face price and label it all-in.
 *
 * This list only ever GROWS. Removing a reason weakens the refusal discipline.
 */
export type AllInUnavailableReason =
  /** Marketplace: the listing base price is absent. */
  | 'missing-base'
  /** Any amount that is not a non-negative safe integer of minor units. */
  | 'invalid-base'
  /** Not a rail this module knows about. */
  | 'unknown-rail'
  /** Tax could apply and its amount is not known. Refuse, never under-quote. */
  | 'tax-unmodelled'
  /** Direct: the server's face value (`order.total_minor`) is absent. */
  | 'server-total-missing'
  /**
   * Direct: `fee.buyer_service_bps` has no value. The A5 owner STOP. The RPC
   * raises `service_fee_unset`; the edge answers 503. There is no zero fallback
   * here either — an unpriced fee means an unquotable ticket.
   */
  | 'service-fee-unset'
  /**
   * Direct: the configured rate is not an integer 0..10000. The RPC's
   * `service_fee_out_of_range`. An owner typo in a money rate fails closed.
   */
  | 'service-fee-out-of-range'
  /**
   * Direct: the server's `charge_total_minor` does not equal face + fee + tax.
   * The client half of the edge's own `quote_incoherent` check. A quote that
   * fails its own arithmetic is a contract break, not a price.
   */
  | 'quote-incoherent';

/** The honest breakdown behind a displayable all-in price. */
export type AllInResult =
  | {
      kind: 'all-in';
      /** THE COMPLETE AMOUNT THE BUYER WILL BE CHARGED, in minor units. */
      totalMinor: Cents;
      /**
       * The ticket's face value / listing base, in minor units. On the direct
       * rail this is `venue."order".total_minor` — the venue's entitlement.
       * IT IS NOT A PRICE. It may appear only as a labelled breakdown row.
       */
      faceValueMinor: Cents;
      /** The buyer-side service fee included in `totalMinor`. */
      buyerServiceFeeMinor: Cents;
      /**
       * Tax included in `totalMinor`, when a schema models it. `null` means
       * "no tax applies to this sale", never "tax unknown" — unknown tax
       * refuses with `tax-unmodelled` instead of reaching this shape.
       */
      taxMinor: Cents | null;
      currency: string;
      rail: PriceRail;
    }
  | { kind: 'unavailable'; reason: AllInUnavailableReason };

/**
 * Tax state for a sale. Omit entirely to mean `not-applicable`, which is the
 * only truthful default while no schema on either rail has a tax column.
 */
export type TaxInput =
  /** No tax applies to this sale. */
  | { status: 'not-applicable' }
  /** Tax applies and the server told us the amount, in minor units. */
  | { status: 'applies'; taxMinor: Cents | null | undefined }
  /**
   * Tax could apply and the amount is NOT known. The only honest response is to
   * refuse. Set this the moment a venue configures tax for an event, before any
   * schema exists to carry the number.
   */
  | { status: 'applies-unknown' };

/**
 * The buyer-side service fee for the direct rail. There is no default: a caller
 * must say which of these three situations it is in, so that "I forgot the fee"
 * cannot silently become "the fee is zero".
 */
export type BuyerServiceFeeInput =
  /**
   * The amount the server already quoted — `buyer_fee_minor` from the RPC, or
   * `buyer_fee` from the primary-checkout edge. Authoritative; never recomputed.
   */
  | { source: 'server-quote'; feeMinor: Cents | null | undefined }
  /**
   * The configured rate in basis points (`fee.buyer_service_bps`), for quoting a
   * price BEFORE a checkout exists — e.g. a "from $X" card. The fee is derived
   * with the RPC's exact rule: `round(face * bps / 10000)`, half-up, integer
   * arithmetic only.
   */
  | { source: 'config-rate'; bps: number | null | undefined }
  /**
   * `fee.buyer_service_bps` has no value. The A5 owner STOP, made explicit and
   * unmissable at the type level rather than encoded as a missing field.
   */
  | { source: 'unset' };

interface PriceInputBase {
  currency?: string;
  /** Defaults to `{ status: 'not-applicable' }`. */
  tax?: TaxInput;
}

export interface MarketplacePriceInput extends PriceInputBase {
  rail: 'marketplace';
  /**
   * Listing price in CENTS, before the buyer fee.
   *
   * Typed `DollarDerivedCents`, not `Cents`: the repo's listing columns are
   * WHOLE DOLLARS, so this accepts ONLY the output of `centsFromDollars` (or the
   * named escape hatch). `asCents(50)` does not compile here — that cast was the
   * remaining route to rendering a $50 ticket as $0.55.
   */
  baseMinor: DollarDerivedCents | null | undefined;
}

export interface DirectPriceInput extends PriceInputBase {
  rail: 'direct';
  /**
   * `venue."order".total_minor` — the FACE VALUE, already in minor units. This
   * is the venue's entitlement and the settlement seam's gross. It is NOT the
   * buyer's charge and must never be displayed as the price on its own.
   */
  faceValueMinor: Cents | null | undefined;
  /** How the buyer-side service fee is known. Required — see the type. */
  buyerServiceFee: BuyerServiceFeeInput;
  /**
   * `charge_total_minor` from the RPC / `total` from the edge, when a real quote
   * exists. When supplied it is the AUTHORITY: this module verifies that it
   * equals face + fee + tax and refuses (`quote-incoherent`) if it does not,
   * mirroring the edge's own check. Omit it only for a pre-checkout estimate
   * built from `{ source: 'config-rate' }`.
   */
  chargeTotalMinor?: Cents | null;
}

export type PriceInput = MarketplacePriceInput | DirectPriceInput;

/** A usable minor-unit amount: a non-negative SAFE integer. */
function isUsableMinor(v: number | null | undefined): v is Cents {
  return typeof v === 'number' && Number.isSafeInteger(v) && v >= 0;
}

/**
 * `round(face * bps / 10000)`, half-up, with NO float money math.
 *
 * Matches `30_connect_org.sql` (the A5 fee amount) exactly. Postgres
 * `round(numeric)` is half-away-from-zero and both operands are non-negative
 * here, so that is half-up; the integer form below is half-up by construction
 * (`rem * 2 >= 10000`).
 *
 * Returns null when `face * bps` leaves the exact-integer range, because a
 * product that cannot be represented cannot be rounded truthfully.
 */
function feeMinorFromBps(faceMinor: number, bps: number): number | null {
  const product = faceMinor * bps;
  if (!Number.isSafeInteger(product)) return null;
  const rem = product % 10000; // exact for safe integers
  const whole = (product - rem) / 10000; // exact: an exact multiple of 10000
  return rem * 2 >= 10000 ? whole + 1 : whole;
}

/** Resolve the tax component, or say why no honest total exists. */
function resolveTax(
  tax: TaxInput | undefined,
): { ok: true; taxMinor: Cents | null } | { ok: false; reason: AllInUnavailableReason } {
  if (!tax || tax.status === 'not-applicable') return { ok: true, taxMinor: null };
  if (tax.status === 'applies-unknown') return { ok: false, reason: 'tax-unmodelled' };
  // status === 'applies': the amount must actually be an amount.
  if (tax.taxMinor === null || tax.taxMinor === undefined) {
    return { ok: false, reason: 'tax-unmodelled' };
  }
  if (!isUsableMinor(tax.taxMinor)) return { ok: false, reason: 'invalid-base' };
  return { ok: true, taxMinor: tax.taxMinor };
}

/**
 * Computes the all-in total, or explains why it cannot.
 * Never throws. Never guesses. Never invents a rate.
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
    const tax = resolveTax(input.tax);
    if (!tax.ok) return { kind: 'unavailable', reason: tax.reason };
    if (tax.taxMinor !== null) {
      // No marketplace schema carries tax, so an amount here is a caller error,
      // not a price. Refuse rather than quote a total the server will reject.
      return { kind: 'unavailable', reason: 'tax-unmodelled' };
    }
    // FROZEN BEHAVIOUR: the total is `buyerTotalCents(base)` and is produced by
    // calling it, not by re-deriving it, so the number cannot drift from the
    // server mirror. The fee row is that same function's own fee component.
    return {
      kind: 'all-in',
      totalMinor: buyerTotalCents(input.baseMinor) as Cents,
      faceValueMinor: input.baseMinor,
      buyerServiceFeeMinor: buyerFeeCents(input.baseMinor) as Cents,
      taxMinor: null,
      currency,
      rail: 'marketplace',
    };
  }

  if (input.rail === 'direct') {
    // Tax first: if the total would be a lie, nothing else matters.
    const tax = resolveTax(input.tax);
    if (!tax.ok) return { kind: 'unavailable', reason: tax.reason };

    if (input.faceValueMinor === null || input.faceValueMinor === undefined) {
      return { kind: 'unavailable', reason: 'server-total-missing' };
    }
    if (!isUsableMinor(input.faceValueMinor)) {
      return { kind: 'unavailable', reason: 'invalid-base' };
    }
    const face = input.faceValueMinor;

    // The A5 fee. Every branch either produces an integer or refuses.
    let feeMinor: number;
    const fee = input.buyerServiceFee;
    // "Never throws" is part of this module's contract, and the direct rail is
    // fed by a JSON response that TypeScript cannot police at runtime. An absent
    // fee field is the same event as an unset rate: refuse.
    if (!fee || typeof fee !== 'object') {
      return { kind: 'unavailable', reason: 'service-fee-unset' };
    }
    if (fee.source === 'unset') {
      return { kind: 'unavailable', reason: 'service-fee-unset' };
    } else if (fee.source === 'server-quote') {
      if (fee.feeMinor === null || fee.feeMinor === undefined) {
        // An absent quoted fee is indistinguishable from an unset rate at this
        // boundary, and both must stop the sale. Report the owner-facing one.
        return { kind: 'unavailable', reason: 'service-fee-unset' };
      }
      if (!isUsableMinor(fee.feeMinor)) {
        return { kind: 'unavailable', reason: 'invalid-base' };
      }
      feeMinor = fee.feeMinor;
    } else {
      const bps = fee.bps;
      if (bps === null || bps === undefined) {
        return { kind: 'unavailable', reason: 'service-fee-unset' };
      }
      // The RPC's own bound: a bare integer 0..10000.
      if (!Number.isSafeInteger(bps) || bps < 0 || bps > 10000) {
        return { kind: 'unavailable', reason: 'service-fee-out-of-range' };
      }
      const derived = feeMinorFromBps(face, bps);
      if (derived === null) return { kind: 'unavailable', reason: 'invalid-base' };
      feeMinor = derived;
    }

    const total = face + feeMinor + (tax.taxMinor ?? 0);
    if (!Number.isSafeInteger(total)) {
      return { kind: 'unavailable', reason: 'invalid-base' };
    }

    // The server's own charge total wins, but only if it agrees with its parts.
    // This is the client twin of the edge's `quote_incoherent` 500.
    if (input.chargeTotalMinor !== null && input.chargeTotalMinor !== undefined) {
      if (!isUsableMinor(input.chargeTotalMinor)) {
        return { kind: 'unavailable', reason: 'invalid-base' };
      }
      if (input.chargeTotalMinor !== total) {
        return { kind: 'unavailable', reason: 'quote-incoherent' };
      }
    }

    return {
      kind: 'all-in',
      totalMinor: total as Cents,
      faceValueMinor: face,
      buyerServiceFeeMinor: feeMinor as Cents,
      taxMinor: tax.taxMinor,
      currency,
      rail: 'direct',
    };
  }

  return { kind: 'unavailable', reason: 'unknown-rail' };
}

/**
 * The `200` body of `supabase/functions/primary-checkout`, as the client sees it.
 * Field names are the wire contract (E2 §3) and must not be renamed here.
 */
export interface PrimaryCheckoutQuote {
  /** FACE value — the venue's entitlement basis. NOT the price. */
  amount?: number | null;
  /** Buyer-side service fee (A5). */
  buyer_fee?: number | null;
  /** THE ALL-IN CHARGE. The only number a buyer may be shown as "the price". */
  total?: number | null;
  currency?: string | null;
}

/**
 * The ONE supported way to turn a primary-checkout response into a price.
 *
 * It exists so that no screen ever has to choose between `amount` and `total`:
 * choosing wrong under-shows the price by the service fee, and the two are one
 * identifier apart. Pass the whole response; this reads the right fields and
 * cross-checks that `total === amount + buyer_fee` before believing any of them.
 */
export function allInFromPrimaryCheckout(
  res: PrimaryCheckoutQuote,
  opts?: { tax?: TaxInput },
): AllInResult {
  return allInPrice({
    rail: 'direct',
    faceValueMinor: res.amount === null || res.amount === undefined ? null : asCents(res.amount),
    buyerServiceFee: {
      source: 'server-quote',
      feeMinor:
        res.buyer_fee === null || res.buyer_fee === undefined ? null : asCents(res.buyer_fee),
    },
    chargeTotalMinor: res.total === null || res.total === undefined ? null : asCents(res.total),
    currency: res.currency ?? 'USD',
    tax: opts?.tax,
  });
}

/**
 * Formats minor units for display. Whole amounts drop the decimals, because
 * "$60" reads better on a card than "$60.00"; non-round amounts keep them,
 * which is what an honest all-in price usually looks like.
 *
 * TAKES `Cents`, NOT `number`, AND THAT IS THE POINT. This function used to
 * accept a bare `number`, which made `formatMinor(50)` — fifty DOLLARS, the
 * actual storage unit of every `public.listings` price column — return "$0.50"
 * with a clean typecheck: a silent 100x understatement on the primary
 * conversion surface. Callers holding a whole-dollar figure must convert with
 * `centsFromDollars` first, and the conversion belongs at that call site.
 *
 * There is no runtime guard on the magnitude, and there cannot be one: `50` is
 * a legitimate cent amount (a $0.50 service fee), so the units are only
 * knowable from the type. See the `Cents` doc for why a heuristic was rejected.
 *
 * INTEGER ONLY. The split into dollars and cents is done with `%` and an exact
 * division by 100, never `value / 100` into a float, so no amount can drift in
 * the last place on its way to the screen. Anything that is not a safe integer
 * of minor units is not a price and renders as an em dash rather than as
 * `$1e+23`, `$NaN`, or a silently rounded lie — this is the last line of
 * defence for an untyped JS caller, where the brand cannot reach.
 */
export function formatMinor(totalMinor: Cents, currency = 'USD'): string {
  if (!Number.isSafeInteger(totalMinor)) return '—';
  const negative = totalMinor < 0;
  const abs = Math.abs(totalMinor);
  const cents = abs % 100;
  const whole = (abs - cents) / 100; // exact: an exact multiple of 100
  const wholeText = String(whole).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  const body = cents === 0 ? wholeText : `${wholeText}.${String(cents).padStart(2, '0')}`;
  const symbol = currency === 'USD' ? '$' : '';
  const sign = negative ? '-' : '';
  // Sign OUTSIDE the symbol: "-$60", never "$-60".
  return symbol ? `${sign}${symbol}${body}` : `${sign}${body} ${currency}`;
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
