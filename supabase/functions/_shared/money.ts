/**
 * money.ts — canonical, server-authoritative marketplace money math.
 *
 * SINGLE SOURCE OF TRUTH for the 10/10 fee model. The client mirror
 * (src/lib/money.ts) must stay byte-identical in its math section; the
 * vitest suite (tests/money.test.ts) asserts parity between the two.
 *
 * UNITS — every function takes and returns INTEGER MINOR UNITS (cents).
 * No float dollar math is permitted anywhere in fee calculation.
 *
 * FEE MODEL (permanent business model — do not change):
 *   Buyer fee : 10% of the base (listing) price, added ON TOP.
 *   Seller fee: 10% of the base (listing) price, withheld at payout.
 *
 *   buyerTotal  = base + round(base × 0.10)   ← what the card is charged
 *   sellerNet   = base − round(base × 0.10)   ← what the seller receives
 *   platformFee = buyerFee + sellerFee        ← gross platform take
 *
 * The seller fee is ALWAYS computed from the base price, never from the
 * buyer's all-in total.
 *
 * ROUNDING — percentage fees round HALF-UP to the nearest cent via
 * Math.round on a non-negative integer×rate product (e.g. base 10999¢
 * → fee 1099.9 → 1100¢). Both fees use the same rule, so buyer fee and
 * seller fee are always equal for equal bases.
 */

export const BUYER_FEE_RATE = 0.10;
export const SELLER_FEE_RATE = 0.10;

function assertCents(cents: number, label: string): void {
  if (!Number.isInteger(cents) || cents < 0) {
    throw new Error(`money.ts: ${label} must be a non-negative integer cent amount, got ${cents}`);
  }
}

/** 10% buyer service fee in cents, rounded half-up. */
export function buyerFeeCents(baseCents: number): number {
  assertCents(baseCents, 'baseCents');
  return Math.round(baseCents * BUYER_FEE_RATE);
}

/** All-in amount the buyer pays: base + buyer fee. */
export function buyerTotalCents(baseCents: number): number {
  return baseCents + buyerFeeCents(baseCents);
}

/** 10% seller service fee in cents, computed FROM THE BASE PRICE. */
export function sellerFeeCents(baseCents: number): number {
  assertCents(baseCents, 'baseCents');
  return Math.round(baseCents * SELLER_FEE_RATE);
}

/** Seller payout: base − seller fee. */
export function sellerNetCents(baseCents: number): number {
  return baseCents - sellerFeeCents(baseCents);
}

/** Gross platform take: buyer fee + seller fee. */
export function platformGrossCents(baseCents: number): number {
  return buyerFeeCents(baseCents) + sellerFeeCents(baseCents);
}

/** Listing prices are stored in whole dollars; convert exactly once. */
export function dollarsToCents(dollars: number): number {
  const cents = Math.round(dollars * 100);
  assertCents(cents, 'dollarsToCents result');
  return cents;
}

/** Full breakdown for one base price — the shape persisted to `payments`. */
export interface FeeBreakdown {
  baseCents: number;
  buyerFeeCents: number;
  buyerTotalCents: number;
  sellerFeeCents: number;
  sellerNetCents: number;
  platformGrossCents: number;
}

export function feeBreakdown(baseCents: number): FeeBreakdown {
  assertCents(baseCents, 'baseCents');
  const bFee = buyerFeeCents(baseCents);
  const sFee = sellerFeeCents(baseCents);
  return {
    baseCents,
    buyerFeeCents: bFee,
    buyerTotalCents: baseCents + bFee,
    sellerFeeCents: sFee,
    sellerNetCents: baseCents - sFee,
    platformGrossCents: bFee + sFee,
  };
}
