/**
 * B-D2 (B's RC2 verdict, A's GO 2026-10-21): "Check status" and the setup Retry had no latch, while
 * Pay had one. Two taps in the same frame both ran: two `finalizePurchase` calls from Check status,
 * two setup runs (two intents) from Retry. Check status now takes Pay's own latch, so it can't
 * overlap a payment either; Retry takes a latch of its own, so the mount-time setup isn't blocked.
 *
 * CheckoutNative imports the Stripe native module, so no harness mounts it. The behaviour is proven
 * on the real latch with the screen's call shape; the source contract pins that the screen uses it.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { createSingleFlight } from '@/src/lib/checkout/paymentGuard';

const src = readFileSync('src/screens/checkout/CheckoutNative.tsx', 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const fnBody = (s: string, name: string) => {
  const at = s.indexOf(`async function ${name}(`);
  expect(at, name).toBeGreaterThan(-1);
  return s.slice(at, s.indexOf('\n  }\n', at));
};

describe('Check status and Retry are single-flight', () => {
  // A's review: RL1 exercises the latch PRIMITIVE with a test-local function shaped like the screen's
  // handler; it does not mount CheckoutNative (no harness can: the Stripe native module). RL2/RL3 are
  // what tie the screen to it. The name now says so.
  it('RL1: the paymentGuard latch admits one of two same-frame calls; unlatched admits both (primitive only, not the screen)', async () => {
    let calls = 0;
    const finalizePurchase = async () => { calls++; await new Promise((r) => setTimeout(r, 5)); };

    const latch = createSingleFlight();
    const recheck = async () => {
      if (!latch.begin()) return;
      try { await finalizePurchase(); } finally { latch.end(); }
    };
    await Promise.all([recheck(), recheck()]);
    expect(calls).toBe(1);
    await recheck();                       // released afterwards: a later tap still works
    expect(calls).toBe(2);

    calls = 0;
    const unlatched = async () => { await finalizePurchase(); };
    await Promise.all([unlatched(), unlatched()]);
    expect(calls).toBe(2);
  });

  it('RL2: recheckPayment takes Pay\'s latch and releases it in finally', () => {
    const body = fnBody(src, 'recheckPayment');
    expect(body).toMatch(/if \(!payLatchRef\.current\.begin\(\)\) return;/);
    expect(body).toMatch(/finally \{\s*payLatchRef\.current\.end\(\);\s*\}/);
    expect(body.indexOf('payLatchRef.current.begin()')).toBeLessThan(body.indexOf('reconcileAfterSheetError()'));
  });

  it('RL3: the Retry action goes through its own latch, not straight to setup', () => {
    expect(src).toMatch(/pay\.action === 'retry' \? retrySetup/);
    expect(src).not.toMatch(/pay\.action === 'retry' \? \(\) => setupPaymentRef\.current\?\.\(\)/);
    expect(src).toMatch(/const setupLatchRef = useRef\(createSingleFlight\(\)\);/);
    expect(src).toMatch(/function retrySetup\(\) \{\s*if \(!setupLatchRef\.current\.begin\(\)\) return;/);
  });
});
