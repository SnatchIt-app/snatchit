/**
 * tests/checkout-pay-control.test.ts — the checkout pay button state machine.
 *
 * The button resolves six states and the old screen did it inline, duplicated
 * across the Buy Now and auction branches. These pin the precedence and the
 * money-safety guards, without a Stripe render harness.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { payControl, fmtCountdown, type PayControlInput } from '../src/lib/checkout/payControl';

function input(over: Partial<PayControlInput> = {}): PayControlInput {
  return {
    authLoading: false,
    paymentLoading: false,
    confirming: false,
    paymentReady: false,
    paymentError: false,
    formattedTotal: '$66',
    ...over,
  };
}

describe('pay control precedence', () => {
  it('an in-flight charge outranks everything', () => {
    const p = payControl(input({ confirming: true, paymentReady: true, paymentError: true }));
    expect(p).toEqual({ label: 'Processing', loading: true, disabled: true, action: 'none' });
  });

  it('setup states are loading and not payable', () => {
    expect(payControl(input({ authLoading: true }))).toMatchObject({ loading: true, disabled: true, action: 'none' });
    expect(payControl(input({ paymentLoading: true }))).toMatchObject({ loading: true, disabled: true, action: 'none' });
  });

  it('ready shows the all-in total and is the only pay action', () => {
    const p = payControl(input({ paymentReady: true }));
    expect(p.label).toBe('Pay $66');
    expect(p.disabled).toBe(false);
    expect(p.action).toBe('pay');
    expect(p.loading).toBe(false);
  });

  it('setup outranks readiness, so a stale ready never shows mid-setup', () => {
    expect(payControl(input({ paymentLoading: true, paymentReady: true })).action).toBe('none');
  });

  it('an error offers retry, not pay', () => {
    const p = payControl(input({ paymentError: true }));
    expect(p.label).toBe('Try again');
    expect(p.action).toBe('retry');
    expect(p.disabled).toBe(false);
  });

  it('the idle default is disabled and unavailable', () => {
    expect(payControl(input())).toEqual({
      label: 'Payment unavailable', loading: false, disabled: true, action: 'none',
    });
  });

  it('never invents a total; it renders exactly the string it was given', () => {
    expect(payControl(input({ paymentReady: true, formattedTotal: '$1,240.50' })).label).toBe('Pay $1,240.50');
  });
});

describe('reservation countdown', () => {
  it('formats m:ss and floors at zero', () => {
    expect(fmtCountdown(9 * 60_000 + 5_000)).toBe('9:05');
    expect(fmtCountdown(65_000)).toBe('1:05');
    expect(fmtCountdown(0)).toBe('0:00');
    expect(fmtCountdown(-5_000)).toBe('0:00');
  });
});

/** Guards on the shipped checkout: money authority and platform safety. */
describe('checkout — shipped-source guards', () => {
  const root = resolve(__dirname, '..');
  const code = (rel: string) =>
    readFileSync(resolve(root, rel), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');

  const native = code('src/screens/checkout/CheckoutNative.tsx');
  const webEntry = code('src/screens/checkout/CheckoutEntry.tsx');
  const nativeEntry = code('src/screens/checkout/CheckoutEntry.native.tsx');
  const route = code('src/screens/checkout/CheckoutRoute.tsx');

  it('keeps the server as the money authority and every payment RPC intact', () => {
    // The settlement RPCs moved OUT of the screen and into the shared
    // finalizePurchase() in src/lib/payments.ts, which classifies the outcome as
    // completed / pending / failed. They must still exist on the payment path —
    // "intact", not "in this file" — so the marker set is split by where each
    // one legitimately lives now.
    const paymentsLib = code('src/lib/payments.ts');
    const paymentPath = native + '\n' + paymentsLib;

    // presentation + intent creation stay in the screen
    for (const marker of [
      'serverBreakdown',
      'createPaymentIntent',
      'initPaymentSheet',
      'presentPaymentSheet',
      'isPlatformPaySupported',
      'expectedTotalCents',
    ]) {
      expect(native, `${marker} must survive the redesign`).toContain(marker);
    }

    // the server-side settlement RPCs must survive somewhere on the path
    for (const marker of [
      'confirmPaymentSuccess',
      'mark_listing_sold',
      'complete_auction_payment',
      'ensure_transfer_exists',
    ]) {
      expect(paymentPath, `${marker} must survive the redesign`).toContain(marker);
    }

    // and the screen must route settlement through the shared helper rather than
    // re-implementing it
    expect(native).toContain('finalizePurchase');
  });

  it('renders amounts through the canonical formatter, not new arithmetic', () => {
    expect(native).toContain('formatCents(');
    // The only division of a cent amount is the pre-existing Apple Pay cart,
    // which PassKit requires as decimal strings. Nothing new divides money.
    const divisions = native.match(/\/ 100/g) ?? [];
    expect(divisions.length).toBeLessThanOrEqual(3); // the three Apple Pay cart lines
  });

  it('shows the buyer what they are paying for', () => {
    expect(native).toContain('EventMedia');
    expect(native).toContain('CHECKOUT_THUMBNAIL');
  });

  it('keeps @stripe out of the base (web) entry, and reaches it only via the native entry', () => {
    // The base entry is what the web bundle resolves; it must not touch Stripe.
    expect(webEntry).not.toMatch(/@stripe\/stripe-react-native/);
    expect(webEntry).not.toMatch(/useStripe|PaymentSheet|CheckoutNative/);
    // Only the .native entry re-exports the Stripe screen.
    expect(nativeEntry).toContain('CheckoutNative');
    // The route selects the platform-split entry rather than a Platform-guarded
    // runtime require() (which the web bundler still traced and which broke the
    // web build).
    expect(route).toContain('CheckoutEntry');
    expect(route).not.toMatch(/require\(/);
    expect(route).not.toMatch(/Platform\.OS/);
  });

  it('has no emoji interface left on checkout', () => {
    const emoji = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]/u;
    expect(emoji.test(native)).toBe(false);
    expect(emoji.test(webEntry)).toBe(false);
  });

  it('does not claim venue-direct provenance', () => {
    expect(native).not.toMatch(/Direct from event/i);
    expect(native).not.toMatch(/isVenuePrimarySale/);
  });
});
