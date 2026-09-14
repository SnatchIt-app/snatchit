/**
 * src/lib/checkout/payControl.ts — the checkout pay button's state, as pure logic.
 *
 * The button's states (authenticating, setting up, processing, checking, ready,
 * hold lost, error, unavailable) used to be resolved inline and duplicated
 * across the Buy Now and auction branches of the JSX. This is the single
 * mapping, so the two modes cannot drift and the matrix is testable without a
 * Stripe harness.
 *
 * IT DECIDES NOTHING ABOUT MONEY. The formatted total is passed in already
 * computed from the server breakdown; this only chooses the label and whether
 * the control is live.
 *
 * PREMIUM BATCH 1 (A-04, CFT-302/305). Pay is withdrawn when the hold has
 * PAY_EXPIRY_MARGIN_MS or less left, so a tap can no longer race the server's
 * expiry; the screen re-checks with the server at that point. `checking` is
 * the state while a payment result is being reconciled: no Pay, no retry.
 *
 * PREMIUM BATCH 1 (CFT-301, D9-UX-1). When the hold is gone the control is
 * "Back to listing" (action 'back'), because only a fresh Buy Now can
 * re-reserve. "Try again" is kept for transient or unverifiable setup errors,
 * where the hold may still be live.
 */

export type PayAction = 'pay' | 'retry' | 'back' | 'none';

/**
 * Seconds before the hold's deadline at which Pay is withdrawn. Absorbs
 * device-vs-server clock skew. Owned by A (contract A-04); do not tune here.
 */
export const PAY_EXPIRY_MARGIN_MS = 15_000;

export interface PayControlInput {
  authLoading: boolean;
  paymentLoading: boolean;
  confirming: boolean;
  /** A payment result is being reconciled with the server. */
  checking?: boolean;
  paymentReady: boolean;
  paymentError: boolean;
  /** The hold is known to be gone: expired, released, or taken. */
  holdLost?: boolean;
  /** Milliseconds left on the buyer's hold; null when there is no countdown. */
  reservationMsLeft?: number | null;
  /** Preformatted all-in total, e.g. "$66". Never recomputed here. */
  formattedTotal: string;
}

export interface PayControl {
  label: string;
  loading: boolean;
  disabled: boolean;
  action: PayAction;
}

/** True when Pay must not be offered because the hold is inside the margin. */
export function withinExpiryMargin(reservationMsLeft: number | null | undefined): boolean {
  return reservationMsLeft != null && reservationMsLeft <= PAY_EXPIRY_MARGIN_MS;
}

export function payControl(i: PayControlInput): PayControl {
  // Order matters: an in-flight charge outranks every setup state, reconciling
  // outranks readiness, and a lost hold outranks both readiness and error.
  if (i.confirming)     return { label: 'Processing',        loading: true,  disabled: true,  action: 'none' };
  if (i.checking)       return { label: 'Checking your payment', loading: true, disabled: true, action: 'none' };
  if (i.authLoading)    return { label: 'Authenticating',    loading: true,  disabled: true,  action: 'none' };
  if (i.paymentLoading) return { label: 'Setting up payment', loading: true, disabled: true,  action: 'none' };
  if (i.holdLost)       return { label: 'Back to listing',   loading: false, disabled: false, action: 'back' };
  if (i.paymentReady && withinExpiryMargin(i.reservationMsLeft)) {
    return { label: 'Checking your hold', loading: true, disabled: true, action: 'none' };
  }
  if (i.paymentReady)   return { label: `Pay ${i.formattedTotal}`, loading: false, disabled: false, action: 'pay' };
  if (i.paymentError)   return { label: 'Try again',         loading: false, disabled: false, action: 'retry' };
  return { label: 'Payment unavailable', loading: false, disabled: true, action: 'none' };
}

/** Reservation countdown "m:ss". Shared so the value never drifts by format. */
export function fmtCountdown(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const m = Math.floor(total / 60);
  const sec = total % 60;
  return `${m}:${String(sec).padStart(2, '0')}`;
}
