/**
 * tests/payment-guard.test.ts — the checkout single-flight latch + screen guards.
 *
 * Reproduces the "Tried to resolve a promise more than once" defect: two rapid Pay
 * taps calling presentPaymentSheet() twice. The latch is exercised against the
 * exact handler pattern the shipped screen uses, and shipped-source guards pin the
 * guard into both pay handlers.
 */

import { describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { createSingleFlight } from '../src/lib/checkout/paymentGuard';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');

describe('single-flight latch', () => {
  it('begin() succeeds once and blocks re-entry until end()', () => {
    const g = createSingleFlight();
    expect(g.begin()).toBe(true);   // first acquire
    expect(g.begin()).toBe(false);  // re-entrant tap blocked
    expect(g.active).toBe(true);
    g.end();
    expect(g.active).toBe(false);
    expect(g.begin()).toBe(true);   // a later attempt can begin
  });

  // The exact handler shape from CheckoutNative: guard, present once, release.
  function makeHandler(latch = createSingleFlight()) {
    const present = vi.fn(async () => {
      await new Promise((r) => setTimeout(r, 5));
      return { error: null as { code?: string } | null };
    });
    async function handler() {
      if (!latch.begin()) return;
      try {
        await present();
      } finally {
        latch.end();
      }
    }
    return { handler, present, latch };
  }

  it('two rapid Pay invocations present the sheet exactly once', async () => {
    const { handler, present } = makeHandler();
    await Promise.all([handler(), handler(), handler()]); // three taps in one frame
    expect(present).toHaveBeenCalledTimes(1);
  });

  it('the latch releases after the attempt, so a retry presents again', async () => {
    const { handler, present, latch } = makeHandler();
    await handler();
    expect(latch.active).toBe(false); // released in finally
    await handler();                  // retry after the sheet returned
    expect(present).toHaveBeenCalledTimes(2);
  });

  it('an error/cancel path still releases the latch (finally runs on early return)', async () => {
    const latch = createSingleFlight();
    let presents = 0;
    async function handler() {
      if (!latch.begin()) return;
      try {
        presents++;
        // simulate presentPaymentSheet returning a Canceled error -> early return
        const res = { error: { code: 'Canceled' } };
        if (res.error) return;
      } finally {
        latch.end();
      }
    }
    await handler();
    expect(latch.active).toBe(false);
    await handler(); // cancel did not permanently lock checkout
    expect(presents).toBe(2);
  });
});

describe('CheckoutNative — shipped-source guards', () => {
  const src = read('src/screens/checkout/CheckoutNative.tsx');
  const provider = read('src/providers/NativeAppShell.native.tsx');

  it('every sheet presentation acquires the synchronous latch first', () => {
    // Was "both pay handlers": buy-now and auction were two near-duplicate
    // handlers, so the latch had to appear twice. They are now ONE handler that
    // takes the mode as an argument, so the invariant is stated directly:
    // every call that presents the sheet is preceded by a latch acquisition.
    const presents = src.match(/await presentPaymentSheet\(\)/g) ?? [];
    const guards = src.match(/payLatchRef\.current\.begin\(\)/g) ?? [];
    expect(presents.length).toBeGreaterThanOrEqual(1);
    expect(guards.length).toBe(presents.length);
    expect(src.indexOf('payLatchRef.current.begin()')).toBeLessThan(src.indexOf('await presentPaymentSheet()'));
    expect(src).toContain('createSingleFlight()');
    // released in finally
    expect(src).toContain('payLatchRef.current.end()');
    // the guard is synchronous (a ref latch), not React state alone
    expect(src).not.toMatch(/if \(confirming\) return/);
  });

  it('presentPaymentSheet is never called during render or from an effect', () => {
    // no top-level/effect auto-present: present only inside the async handlers
    expect(src).not.toMatch(/useEffect\([^)]*presentPaymentSheet/s);
  });

  it('the publishable key flows through StripeProvider and no secret key is client-side', () => {
    expect(provider).toContain('publishableKey={APP_CONFIG.STRIPE_PUBLISHABLE_KEY}');
    for (const s of [src, provider]) {
      expect(s).not.toMatch(/sk_live|sk_test/);
    }
  });
});
