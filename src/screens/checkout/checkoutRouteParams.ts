/**
 * checkoutRouteParams.ts — the checkout route's params are an untrusted URL, not money.
 *
 * `snatchit://checkout/<id>?bidAmount=…&totalCents=…` can be opened by any app on the phone, and
 * by the 3-D Secure return (which carries none of these). CheckoutNative used to parseInt both
 * and hand the result to dollarsToCents → assertCents, which throws on NaN — during render, so a
 * crafted link dropped the whole screen into the root ErrorBoundary. Found by the read-only
 * critical-flow audit of d27aa449 (F1).
 *
 * The contract here is narrow and is NOT a money decision:
 *   - a value that is not a whole, non-negative number is treated as ABSENT (0). Never NaN,
 *     never negative, never a fraction read as dollars.
 *   - the estimate is derived exactly as before when `totalCents` is absent: the canonical
 *     buyer total of the bid, through the same money util.
 *   - 0 means "no client expectation". CheckoutNative sends
 *     `expectedTotalCents: acceptedTotalRef.current || undefined`, so the server computes and
 *     validates its own total — the server is the authority on what is charged, and nothing in
 *     this file can raise an amount.
 */
import { buyerTotalCents, dollarsToCents } from '@/src/lib/money';

export interface CheckoutRouteParamsIn {
  bidAmount?: string;
  totalCents?: string;
}

export interface CheckoutRouteParams {
  /** Whole dollars from the route, or 0 when absent or malformed. */
  bidAmount: number;
  /** Cents from the route, or the canonical buyer total of `bidAmount` when absent or malformed. */
  estimatedTotalCents: number;
}

/** Whole non-negative integer, written as digits only; anything else is "absent". */
function wholeOrZero(raw: string | undefined): number {
  if (raw === undefined || !/^\d{1,12}$/.test(raw)) return 0;
  const n = Number(raw);
  return Number.isSafeInteger(n) && n >= 0 ? n : 0;
}

export function parseCheckoutRouteParams(params: CheckoutRouteParamsIn): CheckoutRouteParams {
  const bidAmount = wholeOrZero(params.bidAmount);
  const fromRoute = wholeOrZero(params.totalCents);
  const estimatedTotalCents = fromRoute || buyerTotalCents(dollarsToCents(bidAmount));
  return { bidAmount, estimatedTotalCents };
}
