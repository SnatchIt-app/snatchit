/**
 * Marketplace listing amounts are whole US dollars. Payment amounts are cents.
 *
 * public.listings.starting_bid / buy_now_price / current_bid / winning_bid_amount and
 * public.bids.amount are `int` whole dollars (000_baseline_schema.sql:85,87,95,145,303;
 * 004_input_bounds.sql: "bids.amount is also stored in DOLLARS"; 089 projects
 * `current_bid * 100` as price_minor; the app renders them with allInFromDollars).
 * ops.listing_summary and ops.listing_detail return them as stored (116:163-165, 999-1001).
 *
 * Every money display in the console (`formatMoney`, `<Money cents>`) takes integer cents,
 * and payments are already cents (000:977-985). So a listing amount is converted here,
 * once, where RPC data becomes console data, and is never passed to `<Money>` raw.
 */

/** Whole dollars → integer cents. Missing, fractional, non-numeric or unsafe input → null (shown as "—"). */
export function listingDollarsToCents(v: unknown): number | null {
  const dollars = typeof v === "string" && /^-?\d+$/.test(v.trim()) ? Number(v.trim()) : v;
  if (typeof dollars !== "number" || !Number.isSafeInteger(dollars)) return null;
  const cents = dollars * 100;
  return Number.isSafeInteger(cents) ? cents : null;
}

/** The ops.listing_summary keys that carry whole dollars. */
export const LISTING_DOLLAR_KEYS: ReadonlySet<string> = new Set(["buy_now_price", "starting_bid", "current_bid", "winning_bid_amount"]);
