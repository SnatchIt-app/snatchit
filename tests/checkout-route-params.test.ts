/**
 * tests/checkout-route-params.test.ts — F1: route params are untrusted input, not money.
 *
 * `snatchit://checkout/<id>?bidAmount=x` is a URL any app on the phone can open. CheckoutNative
 * read `bidAmount` and `totalCents` with parseInt and handed the result straight to
 * dollarsToCents → assertCents, which throws on NaN — during render, so the whole screen fell
 * into the root ErrorBoundary ("Something went wrong") on a crafted link. Found by the read-only
 * critical-flow audit of d27aa449.
 *
 * The contract: a malformed or negative param is treated as ABSENT (0), never as a crash and
 * never as a number the client would charge. The server remains the authority on what is
 * charged — CheckoutNative sends `expectedTotalCents: acceptedTotalRef.current || undefined`, so
 * a 0 here means "no client expectation", which create-payment-intent handles by computing its
 * own total. Nothing in this helper can raise an amount.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { parseCheckoutRouteParams } from '@/src/screens/checkout/checkoutRouteParams';

const strip = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('F1: parseCheckoutRouteParams never throws and never invents an amount', () => {
  it('CP1: well-formed params parse as whole dollars and cents', () => {
    const p = parseCheckoutRouteParams({ bidAmount: '150', totalCents: '16500' });
    expect(p.bidAmount).toBe(150);
    expect(p.estimatedTotalCents).toBe(16500);
  });

  it('CP2: a non-numeric bidAmount is treated as absent, not as NaN', () => {
    const p = parseCheckoutRouteParams({ bidAmount: 'x' });
    expect(Number.isNaN(p.bidAmount)).toBe(false);
    expect(p.bidAmount).toBe(0);
    // and the derived estimate is a finite non-negative integer, not a throw
    expect(Number.isInteger(p.estimatedTotalCents)).toBe(true);
    expect(p.estimatedTotalCents).toBeGreaterThanOrEqual(0);
  });

  it('CP3: the crafted crash link does not throw', () => {
    expect(() => parseCheckoutRouteParams({ bidAmount: 'x', totalCents: undefined })).not.toThrow();
    expect(() => parseCheckoutRouteParams({ bidAmount: 'NaN', totalCents: 'abc' })).not.toThrow();
    expect(() => parseCheckoutRouteParams({ bidAmount: '1e999', totalCents: '-1' })).not.toThrow();
  });

  it('CP4: negative or fractional values cannot become an amount', () => {
    expect(parseCheckoutRouteParams({ bidAmount: '-50' }).bidAmount).toBe(0);
    expect(parseCheckoutRouteParams({ totalCents: '-1' }).estimatedTotalCents).toBe(0);
    // parseInt would read "12.9" as 12; the helper must not silently accept a fraction as dollars
    expect(parseCheckoutRouteParams({ bidAmount: '12.9' }).bidAmount).toBe(0);
  });

  it('CP5: when totalCents is absent, the estimate is derived from bidAmount with the canonical fee', () => {
    // 150 dollars → 15000 cents + 10% = 16500. Same arithmetic as before the fix.
    expect(parseCheckoutRouteParams({ bidAmount: '150' }).estimatedTotalCents).toBe(16500);
  });

  it('CP6: CheckoutNative reads its params through the helper and no longer calls parseInt on them', () => {
    const src = strip('src/screens/checkout/CheckoutNative.tsx');
    expect(src).toContain('parseCheckoutRouteParams(');
    expect(src, 'raw parseInt on route params is the crash path').not.toMatch(/parseInt\(params\./);
  });
});
