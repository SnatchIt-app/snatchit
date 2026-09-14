/**
 * src/lib/bid/bidEntry.ts — the pure core of the Place Bid screen.
 *
 * The screen owns the fetch, the deletion-guard probe and the insert; those are
 * effects. The arithmetic that decides what the stepper lands on and what the
 * buyer is told they'll pay is pulled out here and tested, so a presentation
 * rewrite can't quietly move the minimum or the all-in.
 *
 * Money is untouched: every figure routes through src/lib/money.ts and the
 * whole-dollars listing contract (current_bid / a bid amount are whole dollars) is
 * preserved. The bid increment is injected by the caller from APP_CONFIG rather
 * than read here, so this module stays free of app config and trivially testable.
 */

import {
  buyerFeeCents,
  buyerTotalCents,
  dollarsToCents,
  formatCents,
  formatDollars,
} from '@/src/lib/money';

/** The floor a new bid must clear: the current bid plus one increment. */
export function minNextBid(currentBid: number, increment: number): number {
  return currentBid + increment;
}

/** One step down, never below the minimum. */
export function stepDown(selected: number, minimum: number, increment: number): number {
  return Math.max(minimum, selected - increment);
}

/** One step up. */
export function stepUp(selected: number, increment: number): number {
  return selected + increment;
}

/** A quick "+$n" bump. */
export function quickAdd(selected: number, n: number): number {
  return selected + n;
}

/** Whether the selected amount is a placeable bid. */
export function canPlaceBid(selected: number, minimum: number): boolean {
  return Number.isFinite(selected) && selected >= minimum;
}

export interface BidPriceLines {
  /** The bid itself, e.g. "$80". */
  bid: string;
  /** The buyer service fee, e.g. "$8". */
  fee: string;
  /** The all-in the buyer pays if they win, e.g. "$88". */
  total: string;
}

/**
 * The breakdown shown before a bid is placed: the bid, the 10% buyer service fee
 * and the all-in total. Pure composition of the canonical money helpers — no fee
 * arithmetic of its own, so it can never drift from what checkout actually
 * charges.
 */
export function bidPriceLines(selectedDollars: number): BidPriceLines {
  const cents = dollarsToCents(selectedDollars);
  return {
    bid: formatCents(cents),
    fee: formatCents(buyerFeeCents(cents)),
    total: formatCents(buyerTotalCents(cents)),
  };
}

/** The all-in total on its own, for the sticky bar / CTA context. */
export function bidTotalLabel(selectedDollars: number): string {
  return formatCents(buyerTotalCents(dollarsToCents(selectedDollars)));
}

// ─── After the server accepted the bid (CFT-203, item 10) ────────────────────

export type BidOutcome = 'leading' | 'outbid' | 'accepted';

/**
 * What the bidder is told AFTER the insert succeeded — never before. The
 * insert trigger rejects any amount not above the current bid, so a successful
 * insert was leading at that instant; a fresh read of `current_bid` decides
 * whether it still is. The rule is the Bids tab's own (`bidStatusOf`: amount >=
 * current_bid), so the two screens tell one truth. With no fresh read the bid
 * is only "accepted": in, position unknown.
 */
export function bidOutcome(amountDollars: number, freshCurrentBid: number | null | undefined): BidOutcome {
  if (freshCurrentBid == null || !Number.isFinite(freshCurrentBid)) return 'accepted';
  return amountDollars >= freshCurrentBid ? 'leading' : 'outbid';
}

export interface BidOutcomeCopy {
  title: string;
  body: string;
}

/** Calm, exact copy for each outcome; "You're leading" only for `leading`. */
export function bidOutcomeCopy(
  outcome: BidOutcome,
  amountDollars: number,
  freshCurrentBid?: number | null,
): BidOutcomeCopy {
  const bid = formatDollars(amountDollars);
  const total = bidTotalLabel(amountDollars);
  switch (outcome) {
    case 'leading':
      return {
        title: "You're leading",
        body: `Your bid of ${bid} is in and it's the highest right now. If you win, you'll pay ${total} total (includes the 10% service fee).`,
      };
    case 'outbid':
      return {
        title: 'Bid placed, but outbid',
        body: `Your ${bid} bid is in, but someone has already bid ${freshCurrentBid != null ? formatDollars(freshCurrentBid) : 'higher'}. Go back to the listing to raise it.`,
      };
    default:
      return {
        title: 'Bid placed',
        body: `Your bid of ${bid} is in. If you win, you'll pay ${total} total (includes the 10% service fee).`,
      };
  }
}
