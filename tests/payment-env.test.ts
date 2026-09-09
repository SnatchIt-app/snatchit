/**
 * tests/payment-env.test.ts — the config-corruption class that caused
 * kCFErrorDomainCFNetwork -1001 at payment-sheet presentation, plus the
 * customer-facing failure copy.
 *
 * Root cause under test: `.env` held the publishable key wrapped in SMART quotes.
 * dotenv strips straight quotes only, so the app booted with a non-empty but
 * malformed key; the empty-key guard never fired and the failure only surfaced as
 * a network timeout when the sheet loaded.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { envValue, looksLikeStripePublishableKey, stripeKeyMode } from '../src/config/envValue';
import {
  isCancelledPaymentError,
  isNetworkPaymentError,
  paymentSheetErrorCopy,
} from '../src/lib/checkout/paymentErrors';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');

const KEY = 'pk_live_51AbCdEfGhIjKlMnOpQrStUv';

describe('env value sanitising', () => {
  it('strips the smart quotes that caused the incident', () => {
    expect(envValue('‘' + KEY + '’')).toBe(KEY); // ‘ ’
    expect(envValue('“' + KEY + '”')).toBe(KEY); // “ ”
  });

  it('still strips straight quotes and whitespace', () => {
    expect(envValue(`"${KEY}"`)).toBe(KEY);
    expect(envValue(`'${KEY}'`)).toBe(KEY);
    expect(envValue(`   ${KEY}   `)).toBe(KEY);
  });

  it('leaves a bare value alone and handles missing values', () => {
    expect(envValue(KEY)).toBe(KEY);
    expect(envValue(undefined)).toBe('');
    expect(envValue(null)).toBe('');
  });
});

describe('publishable key validation', () => {
  it('accepts real keys and rejects the malformed one', () => {
    expect(looksLikeStripePublishableKey(KEY)).toBe(true);
    expect(looksLikeStripePublishableKey('pk_test_abc123')).toBe(true);
    // the exact shape that shipped to the device
    expect(looksLikeStripePublishableKey('‘' + KEY + '’')).toBe(false);
    expect(looksLikeStripePublishableKey('')).toBe(false);
    expect(looksLikeStripePublishableKey('sk_live_abc')).toBe(false); // never a secret key
  });

  it('reports mode for diagnostics only', () => {
    expect(stripeKeyMode(KEY)).toBe('live');
    expect(stripeKeyMode('pk_test_abc')).toBe('test');
    expect(stripeKeyMode('‘' + KEY + '’')).toBe(null);
  });

  it('a sanitised malformed key becomes valid (the fix end to end)', () => {
    expect(looksLikeStripePublishableKey(envValue('‘' + KEY + '’'))).toBe(true);
  });
});

describe('customer-facing failure copy', () => {
  const cfnetwork = {
    code: 'Failed',
    message: "The operation couldn't be completed. (kCFErrorDomainCFNetwork error -1001.)",
  };

  it('a CFNetwork timeout reads as a timeout, never as raw system text', () => {
    expect(isNetworkPaymentError(cfnetwork)).toBe(true);
    const copy = paymentSheetErrorCopy(cfnetwork);
    expect(copy).toBe('Payment connection timed out. Try again.');
    expect(copy).not.toMatch(/kCFErrorDomain|-1001|NSURLError/);
  });

  it('other failures get the generic line; cancel is not an error', () => {
    expect(paymentSheetErrorCopy({ code: 'Failed', message: 'card_declined' }))
      .toBe("We couldn't complete payment. Please try again.");
    expect(isCancelledPaymentError({ code: 'Canceled' })).toBe(true);
  });

  it('no copy contains an em dash or AI phrasing', () => {
    for (const e of [cfnetwork, { code: 'Failed', message: 'x' }]) {
      expect(paymentSheetErrorCopy(e)).not.toMatch(/—|--/);
    }
  });
});

describe('shipped wiring', () => {
  const shell = read('src/providers/NativeAppShell.native.tsx');
  const config = read('src/config/app.ts');
  const checkout = read('src/screens/checkout/CheckoutNative.tsx');
  const listing = read('src/screens/ListingDetailScreen.tsx');

  it('the publishable key is sanitised before it reaches StripeProvider', () => {
    expect(config).toContain('envValue(process.env.EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY)');
    expect(shell).toContain('looksLikeStripePublishableKey');
    expect(shell).toContain('publishableKey={APP_CONFIG.STRIPE_PUBLISHABLE_KEY}');
  });

  it('the raw SDK message is never shown to the customer', () => {
    expect(checkout).not.toMatch(/Alert\.alert\('Payment Failed', paymentError\.message\)/);
    expect(checkout).toContain('paymentSheetErrorCopy(paymentError)');
  });

  it('presentPaymentSheet is gated behind a successful init', () => {
    // paymentReady is only set after initPaymentSheet returns no error, and the
    // pay action only exists when paymentReady is true.
    expect(checkout).toContain('setPaymentReady(true)');
    expect(read('src/lib/checkout/payControl.ts')).toMatch(/paymentReady\)\s*return \{ label: `Pay/);
  });

  it('a failed payment setup never releases the reservation', () => {
    // Superseded contract (2026-09-08): checkout used to be forbidden from
    // releasing at all, because release was wired to navigation exit only.
    // Cancelling the PaymentSheet then left the Buy-Now hold standing for the
    // full 10-minute server TTL and the listing vanished from Home (which
    // filters status='active') — the symptom reported from the device test.
    //
    // The narrower invariant is what actually protects the money, and it still
    // holds: a SETUP failure or a sheet ERROR must never release. The single
    // release call site lives in the cancel path and only runs after the
    // BACKEND has confirmed the payment did not happen.
    expect(listing).toContain("navigation.addListener('beforeRemove'");

    // exactly one release CALL SITE in checkout (log lines naming the RPC don't count)
    const releaseSites = checkout.match(/supabase\.rpc\(\s*'release_reservation'/g) ?? [];
    expect(releaseSites).toHaveLength(1);

    // …and it sits inside the helper that asks the backend first
    const helper = checkout.slice(
      checkout.indexOf('async function releaseAbandonedHold'),
      checkout.indexOf('release_reservation'),
    );
    expect(helper).toContain('confirmPaymentSuccess');

    // the release is never reachable from the setup-failure or sheet-error paths
    expect(checkout).not.toMatch(/initPaymentSheet[\s\S]{0,400}release_reservation/);
    expect(checkout).not.toMatch(/paymentSheetErrorCopy[\s\S]{0,400}release_reservation/);
  });

  it('no localhost or tunnel host anywhere in the payment path', () => {
    for (const src of [checkout, shell, read('src/lib/payments.ts')]) {
      expect(src).not.toMatch(/localhost|127\.0\.0\.1|192\.168\.|ngrok/);
    }
  });
});
