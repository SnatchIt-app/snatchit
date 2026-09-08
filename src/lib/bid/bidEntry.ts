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
