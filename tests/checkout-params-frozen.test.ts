/**
 * tests/checkout-params-frozen.test.ts — F4 (warm return): the checkout screen's params are
 * frozen at mount, so a later in-place replacement of the route's params cannot change its mode
 * or its figures.
 *
 * A's independent reviewer confirmed the warm 3-D Secure return as the common case: expo-router
 * dispatches NAVIGATE to checkout/[id] with the return URL's params, StackClient reuses the same
 * route key and REPLACES the params in place (no remount). With {id} only, isBuyNow flipped to
 * false mid-settlement — the countdown and the Pay withdrawal vanished, the breakdown said
 * "Winning bid", and later actions routed to the auction handlers.
 *
 * Mutant this file must kill: unfreezing (reading the live params on every render).
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { HookHost } from './helpers/nav-stack-harness';
import { freezeCheckoutParams, useFrozenCheckoutParams } from '@/src/screens/checkout/useFrozenCheckoutParams';
import { parseCheckoutMode } from '@/src/screens/checkout/checkoutMode';

const strip = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const BUY_NOW = { id: 'abc', mode: 'buy_now', totalCents: '16500', bidAmount: '150', eventName: 'Pool party', venue: 'LIV' };

describe('F4 · params are read once, at mount', () => {
  it('FP1: a replacement of the route params with {id} only does not change the mode or the figures', () => {
    // The component reads `live` on every render, exactly as useLocalSearchParams would hand back
    // the replaced params after the 3DS return.
    let live: Record<string, string> = { ...BUY_NOW };
    let seen: ReturnType<typeof useFrozenCheckoutParams> | null = null;
    const host = new HookHost(() => { seen = useFrozenCheckoutParams(live); return null; }, new Map());
    host.mount();
    expect(seen!.mode).toBe('buy_now');
    expect(seen!.totalCents).toBe('16500');

    live = { id: 'abc' };            // the warm return: same route key, params replaced in place
    host.flush();                     // re-render with the replaced params
    expect(seen!.mode, 'the mode must survive the replacement').toBe('buy_now');
    expect(seen!.totalCents).toBe('16500');
    expect(seen!.bidAmount).toBe('150');
    expect(seen!.eventName).toBe('Pool party');
    expect(parseCheckoutMode(seen!.mode)).toBe('buy_now');
    host.unmount();
  });

  it('FP2: the freeze reads exactly the five named fields and nothing else from the URL', () => {
    const raw = { ...BUY_NOW, payment_intent: 'pi_x', payment_intent_client_secret: 'cs_x' } as Record<string, string>;
    const frozen = freezeCheckoutParams(raw);
    expect(Object.keys(frozen).sort()).toEqual(['bidAmount', 'eventName', 'id', 'mode', 'totalCents', 'venue']);
    expect(JSON.stringify(frozen)).not.toMatch(/pi_x|cs_x|payment_intent/);
  });

  it('FP3: array-valued params take their first value', () => {
    expect(freezeCheckoutParams({ id: ['a', 'b'], mode: ['auction'] }).mode).toBe('auction');
  });
});

describe('F4 · CheckoutNative is wired to the frozen params', () => {
  const src = strip('src/screens/checkout/CheckoutNative.tsx');

  it('FP4: the screen reads its params through useFrozenCheckoutParams', () => {
    expect(src).toContain('useFrozenCheckoutParams(');
  });

  it('FP5: nothing in the screen reads the live params after the freeze — every field comes from the frozen copy', () => {
    // `params.` must appear only as the argument to the freeze. Any other `params.<field>` read
    // would follow a later replacement.
    const reads = src.match(/\bparams\.(id|mode|bidAmount|totalCents|eventName|venue)\b/g) ?? [];
    expect(reads, `live param reads: ${reads.join(', ')}`).toEqual([]);
  });

  it('FP6: the screen never logs or reports route params', () => {
    expect(src).not.toMatch(/(dlog|console\.(log|warn|error)|addBreadcrumb|captureMessage|reportCheckoutFailure)\([^)]*\b(params|frozen)\b/);
  });
});
