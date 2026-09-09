/**
 * src/lib/checkout/payControl.ts — the checkout pay button's state, as pure logic.
 *
 * The button has six states (authenticating, setting up, processing, ready,
 * error, unavailable) and the old screen resolved them inline, duplicated across
 * the Buy Now and auction branches of the JSX. This is the single mapping, so the
 * two modes cannot drift and the matrix is testable without a Stripe harness.
 *
 * IT DECIDES NOTHING ABOUT MONEY. The formatted total is passed in already
 * computed from the server breakdown; this only chooses the label and whether the
 * control is live.
 */

export type PayAction = 'pay' | 'retry' | 'none';

export interface PayControlInput {
  authLoading: boolean;
  paymentLoading: boolean;
  confirming: boolean;
  paymentReady: boolean;
  paymentError: boolean;
  /** Preformatted all-in total, e.g. "$66". Never recomputed here. */
  formattedTotal: string;
}

export interface PayControl {
  label: string;
  loading: boolean;
  disabled: boolean;
  action: PayAction;
}

export function payControl(i: PayControlInput): PayControl {
  // Order matters: an in-flight charge outranks every setup state, and setup
  // outranks readiness. This is the exact precedence the screen shipped.
  if (i.confirming)     return { label: 'Processing',        loading: true,  disabled: true,  action: 'none' };
  if (i.authLoading)    return { label: 'Authenticating',    loading: true,  disabled: true,  action: 'none' };
  if (i.paymentLoading) return { label: 'Setting up payment', loading: true, disabled: true,  action: 'none' };
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
