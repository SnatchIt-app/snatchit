/**
 * checkoutMode.ts — the checkout mode is parsed from the route, never defaulted (F4).
 *
 * `isBuyNow = params.mode === 'buy_now'` read "no mode" as auction. The 3-D Secure return URL
 * carried no mode, so a cold-start return (iOS killed the app behind the browser) remounted the
 * screen as an auction checkout: no hold check, createPaymentIntent with mode 'auction' and no
 * expected total, and the server's "Auction has not ended yet" shown with "Try again" to a
 * Buy Now buyer whose card had just been charged. The warm return can lose the params too, because
 * the stack router replaces the focused route's params from the incoming URL.
 *
 * Contract (A, 2026-10-12):
 *   - absent or invalid mode is NO mode — `null`, never 'auction';
 *   - with no mode, setup may only read what is settled: settled → completed, a refund → its own
 *     state, otherwise the existing payment_status_unknown state ("Check again"). It never creates
 *     an intent;
 *   - the return URL carries mode, totalCents and bidAmount so the remount re-enters with its mode.
 *
 * This file reads from the gated setupDecision.ts; it does not change it.
 */
import {
  pickSettled, refundStateFor, settledKind, type RefundState, type SettledPayment,
} from '@/src/lib/checkout/setupDecision';

export type CheckoutMode = 'buy_now' | 'auction';

export function parseCheckoutMode(raw: string | string[] | undefined): CheckoutMode | null {
  const v = Array.isArray(raw) ? raw[0] : raw;
  return v === 'buy_now' || v === 'auction' ? v : null;
}

export type NoModeSetupDecision =
  | { kind: 'completed' }
  | RefundState
  | { kind: 'payment_status_unknown' };

/**
 * The only decision allowed without a mode. The same settled-first reading setupDecision makes,
 * stopped before the hold and before any intent: there is nothing to hold or create for a mode
 * the screen does not know.
 */
export function decideNoModeSetup(rows: SettledPayment[] | null | undefined): NoModeSetupDecision {
  const settled = pickSettled(rows);
  if (settledKind(settled) === 'already_settled') return { kind: 'completed' };
  const refund = refundStateFor(settled);
  if (refund) return refund;
  return { kind: 'payment_status_unknown' };
}

export interface ReturnURLContext {
  listingId: string;
  mode: CheckoutMode;
  totalCents: number;
  bidAmount: number;
}

/** The real route (app/checkout/[id].tsx) plus the context the remount needs to keep its mode. */
export function buildCheckoutReturnURL({ listingId, mode, totalCents, bidAmount }: ReturnURLContext): string {
  const q = new URLSearchParams({
    mode,
    totalCents: String(Math.max(0, Math.trunc(totalCents) || 0)),
    bidAmount: String(Math.max(0, Math.trunc(bidAmount) || 0)),
  });
  return `snatchit://checkout/${listingId}?${q.toString()}`;
}
