/**
 * tests/checkout-mode.test.ts — F4: an absent or invalid checkout mode must never become auction.
 *
 * The 3-D Secure return URL was `snatchit://checkout/<id>` — no mode, no total. On a cold-start
 * return (iOS killed the app behind the browser) the screen remounted with {id} only, read
 * `isBuyNow` as false, and ran the AUCTION path: no hold check, createPaymentIntent with
 * mode 'auction' and no expected total, and the server refused "Auction has not ended yet" — shown
 * with "Try again" to a Buy Now buyer whose card had just been charged. Found by the read-only
 * critical-flow audit of d27aa449; contract set by A (2026-10-12).
 *
 * Contract:
 *   1. the mode is parsed, not defaulted: anything but 'buy_now' / 'auction' is NO mode.
 *   2. with no mode, setup does only the settled read: settled → completed; otherwise the existing
 *      payment_status_unknown state with "Check again". It never creates an intent.
 *   3. the return URL carries mode, totalCents and bidAmount, so a return re-enters with its mode.
 *
 * Mutant this file must kill: defaulting an absent mode to 'auction'.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { buildCheckoutReturnURL, decideNoModeSetup, parseCheckoutMode } from '@/src/screens/checkout/checkoutMode';

const strip = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const succeeded = { id: 'pay-1', status: 'succeeded', amount_refunded_cents: 0 } as never;
const refunded = { id: 'pay-2', status: 'refunded', amount_refunded_cents: 16500 } as never;

describe('F4 · parseCheckoutMode never invents a mode', () => {
  it('CM1: the two real modes parse as themselves', () => {
    expect(parseCheckoutMode('buy_now')).toBe('buy_now');
    expect(parseCheckoutMode('auction')).toBe('auction');
  });

  it('CM2: absent, empty, or unknown is NO mode — not auction', () => {
    // 'bid' is the legacy literal the winner path once pushed (B-D10): it is NOT a mode.
    for (const raw of [undefined, '', 'x', 'AUCTION', 'buy-now', 'null', 'bid']) {
      expect(parseCheckoutMode(raw), `raw=${String(raw)}`).toBeNull();
    }
  });
});

describe('F4 · with no mode, setup may only read what is settled', () => {
  it('CM3: a succeeded payment → completed', () => {
    expect(decideNoModeSetup([succeeded])).toEqual({ kind: 'completed' });
  });

  it('CM4: nothing settled → the unknown state, never an intent', () => {
    expect(decideNoModeSetup([])).toEqual({ kind: 'payment_status_unknown' });
    expect(decideNoModeSetup(null)).toEqual({ kind: 'payment_status_unknown' });
  });

  it('CM5: a refund is reported as the refund state, never as completed and never as unknown', () => {
    const out = decideNoModeSetup([refunded]);
    expect(out.kind).not.toBe('completed');
    expect(out.kind).not.toBe('payment_status_unknown');
  });
});

describe('F4 · the return URL carries the context the remount needs', () => {
  it('CM6: mode, totalCents and bidAmount ride on the URL, on the real route', () => {
    const url = buildCheckoutReturnURL({ listingId: 'abc', mode: 'buy_now', totalCents: 16500, bidAmount: 150 });
    expect(url.startsWith('snatchit://checkout/abc?')).toBe(true);
    const q = new URL(url.replace('snatchit://', 'https://x/')).searchParams;
    expect(q.get('mode')).toBe('buy_now');
    expect(q.get('totalCents')).toBe('16500');
    expect(q.get('bidAmount')).toBe('150');
  });

  it('CM7: a round trip through parseCheckoutMode keeps the mode', () => {
    const url = buildCheckoutReturnURL({ listingId: 'abc', mode: 'auction', totalCents: 0, bidAmount: 150 });
    const q = new URL(url.replace('snatchit://', 'https://x/')).searchParams;
    expect(parseCheckoutMode(q.get('mode') ?? undefined)).toBe('auction');
  });
});

describe('F4 · CheckoutNative is wired through the helpers, not through a boolean default', () => {
  const src = strip('src/screens/checkout/CheckoutNative.tsx');

  it('CM8: the mode sent to setup and to createPaymentIntent is the parsed mode, never a ternary that defaults to auction', () => {
    expect(src).toContain('parseCheckoutMode(');
    // The crash-and-charge path: `isBuyNow ? 'buy_now' : 'auction'` turns "no mode" into auction.
    expect(src).not.toMatch(/isBuyNow\s*\?\s*'buy_now'\s*:\s*'auction'/);
    // Nor may the screen fall back to a mode after parsing: the parsed value is used as-is.
    expect(src).toContain('const checkoutMode = parseCheckoutMode(frozen.mode);');
    expect(src).not.toMatch(/parseCheckoutMode\([^)]*\)\s*(\?\?|\|\|)\s*'(auction|buy_now)'/);
    expect(src).not.toMatch(/checkoutMode\s*(\?\?|\|\|)\s*'(auction|buy_now)'/);
  });

  it('CM9: with no mode, setup returns before decideCheckoutSetup and never reaches createPaymentIntent', () => {
    expect(src).toContain('decideNoModeSetup(');
    const noMode = src.indexOf('decideNoModeSetup(');
    const setup = src.indexOf('decideCheckoutSetup(');
    expect(noMode).toBeGreaterThan(-1);
    expect(noMode).toBeLessThan(setup);
  });

  it('CM10: the return URL is built by the helper that carries the context', () => {
    expect(src).toContain('returnURL: buildCheckoutReturnURL(');
    expect(src).not.toContain('returnURL: `snatchit://checkout/${listingId}`');
  });
});

describe('F4 · every caller pushes a mode the screen will parse (B-D10)', () => {
  /*
   * B's blocker on the F4 fix: the auction winner's "Pay now" pushed mode 'bid', which at the base
   * fell through to auction by accident (`params.mode === 'buy_now'` was false). With the mode
   * parsed, 'bid' became NO mode: every winner landed in the settled-only branch, saw "We couldn't
   * check whether this has already been paid" with a "Check again" that re-ran it forever, and Pay
   * never appeared. The literal must be the server's contract, 'buy_now' | 'auction'.
   */
  const detail = strip('src/screens/ListingDetailScreen.tsx');

  it('CM11: the winner checkout pushes mode auction, the Buy Now checkout pushes mode buy_now', () => {
    const winner = detail.slice(detail.indexOf('function navigateToWinnerCheckout'), detail.indexOf('\n  }', detail.indexOf('function navigateToWinnerCheckout')));
    const buyNow = detail.slice(detail.indexOf('function navigateToCheckout'), detail.indexOf('\n  }', detail.indexOf('function navigateToCheckout')));
    expect(winner).toContain("mode: 'auction'");
    expect(buyNow).toContain("mode: 'buy_now'");
    expect(detail).not.toContain("mode: 'bid'");
  });

  it('CM12: those two are the only checkout pushes in the app, and each carries a parseable mode', async () => {
    const { execSync } = await import('node:child_process');
    const hits = execSync(`grep -rln "pathname: '/checkout/\\[id\\]'" app src --include='*.ts' --include='*.tsx'`, { encoding: 'utf8' })
      .split('\n').filter(Boolean).filter((f) => !f.includes('/_dev/'));
    expect(hits).toEqual(['src/screens/ListingDetailScreen.tsx']);
    const pushes = detail.match(/pathname: '\/checkout\/\[id\]',\s*params: \{[^}]*mode: '([a-z_]+)'/g) ?? [];
    expect(pushes).toHaveLength(2);
    for (const p of pushes) expect(parseCheckoutMode(p.match(/mode: '([a-z_]+)'/)![1])).not.toBeNull();
  });
});
