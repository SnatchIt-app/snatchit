/**
 * money.ts — client mirror of the canonical marketplace money math.
 *
 * The math section is byte-identical to supabase/functions/_shared/money.ts
 * (the server source of truth); tests/money.test.ts asserts parity. The
 * client uses these ONLY for display estimates — the server recomputes and
 * charges its own numbers, and create-payment-intent rejects any client
 * total that disagrees with the server calculation.
 *
 * Formatting helpers below implement the all-in pricing display rules:
 * the FIRST price a buyer sees anywhere is the fee-inclusive total.
 */

// ─── MATH (mirror of _shared/money.ts — keep in sync) ───────────────────────

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

// ─── DISPLAY HELPERS (client-only) ───────────────────────────────────────────

/** "$27.50" / "$110" — trims ".00", keeps real cents. */
export function formatCents(cents: number): string {
  const dollars = cents / 100;
  return Number.isInteger(dollars)
    ? `$${dollars.toLocaleString('en-US')}`
    : `$${dollars.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/** All-in buyer price from a whole-dollar base, e.g. 100 → "$110". */
export function allInFromDollars(baseDollars: number): string {
  return formatCents(buyerTotalCents(dollarsToCents(baseDollars)));
}

/** Primary buyer-facing price label, e.g. 100 → "$110 total". */
export function allInLabel(baseDollars: number): string {
  return `${allInFromDollars(baseDollars)} total`;
}

/** Base price display (for labeled breakdown rows only — never lead with it). */
export function baseFromDollars(baseDollars: number): string {
  return formatCents(dollarsToCents(baseDollars));
}

/** Buyer fee display from a whole-dollar base, e.g. 25 → "$2.50". */
export function buyerFeeFromDollars(baseDollars: number): string {
  return formatCents(buyerFeeCents(dollarsToCents(baseDollars)));
}

/** Seller proceeds display from a whole-dollar base, e.g. 100 → "$90". */
export function sellerNetFromDollars(baseDollars: number): string {
  return formatCents(sellerNetCents(dollarsToCents(baseDollars)));
}

/** Seller proceeds as a number of dollars (may have cents), e.g. 25 → 22.5 */
export function sellerNetDollars(baseDollars: number): number {
  return sellerNetCents(dollarsToCents(baseDollars)) / 100;
}
