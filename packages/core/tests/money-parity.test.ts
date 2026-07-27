/**
 * Parity: @snatchit/core money math must produce IDENTICAL outputs to
 *  (a) the mobile client implementation  (src/lib/money.ts)
 *  (b) the server source of truth        (supabase/functions/_shared/money.ts)
 *
 * The server-authoritative fee model is unchanged; these tests are the
 * regression gate that keeps the shared package honest.
 */
import { describe, expect, it } from 'vitest';
import * as pkg from '@snatchit/core';
import * as mobile from '@mobile/src/lib/money';
import * as server from '@server-shared/money';

const CENT_GRID = [
  0, 1, 5, 49, 50, 51, 99, 100, 101, 105, 999, 1000, 1049, 1050,
  2500, 9999, 10000, 12345, 22500, 25000, 27500, 30000, 33000,
  99999, 100000, 123456, 999999, 1000000, 25000000,
];

const DOLLAR_GRID = [0, 1, 5, 25, 99, 100, 150, 180, 225, 250, 300, 1234, 10.5, 99.99];

describe('fee rates', () => {
  it('match mobile and server constants exactly', () => {
    expect(pkg.BUYER_FEE_RATE).toBe(mobile.BUYER_FEE_RATE);
    expect(pkg.SELLER_FEE_RATE).toBe(mobile.SELLER_FEE_RATE);
    expect(pkg.BUYER_FEE_RATE).toBe(server.BUYER_FEE_RATE);
    expect(pkg.SELLER_FEE_RATE).toBe(server.SELLER_FEE_RATE);
  });
});

describe('cent math parity (package vs mobile vs server)', () => {
  it.each(CENT_GRID)('base %i cents', (base) => {
    expect(pkg.buyerFeeCents(base)).toBe(mobile.buyerFeeCents(base));
    expect(pkg.buyerFeeCents(base)).toBe(server.buyerFeeCents(base));
    expect(pkg.buyerTotalCents(base)).toBe(mobile.buyerTotalCents(base));
    expect(pkg.buyerTotalCents(base)).toBe(server.buyerTotalCents(base));
    expect(pkg.sellerFeeCents(base)).toBe(mobile.sellerFeeCents(base));
    expect(pkg.sellerFeeCents(base)).toBe(server.sellerFeeCents(base));
    expect(pkg.sellerNetCents(base)).toBe(mobile.sellerNetCents(base));
    expect(pkg.sellerNetCents(base)).toBe(server.sellerNetCents(base));
    expect(pkg.platformGrossCents(base)).toBe(mobile.platformGrossCents(base));
    expect(pkg.platformGrossCents(base)).toBe(server.platformGrossCents(base));
  });

  it('rejects non-integer and negative cents exactly like the originals', () => {
    for (const bad of [-1, 0.5, 100.01, NaN]) {
      expect(() => pkg.buyerFeeCents(bad)).toThrow();
      expect(() => mobile.buyerFeeCents(bad)).toThrow();
      expect(() => server.buyerFeeCents(bad)).toThrow();
    }
  });
});

describe('dollars→cents boundary parity', () => {
  it.each(DOLLAR_GRID)('%s dollars', (dollars) => {
    expect(pkg.dollarsToCents(dollars)).toBe(mobile.dollarsToCents(dollars));
    expect(pkg.dollarsToCents(dollars)).toBe(server.dollarsToCents(dollars));
  });
});

describe('display-helper parity (package vs mobile)', () => {
  it.each(DOLLAR_GRID)('base $%s', (dollars) => {
    expect(pkg.allInFromDollars(dollars)).toBe(mobile.allInFromDollars(dollars));
    expect(pkg.allInLabel(dollars)).toBe(mobile.allInLabel(dollars));
    expect(pkg.baseFromDollars(dollars)).toBe(mobile.baseFromDollars(dollars));
    expect(pkg.buyerFeeFromDollars(dollars)).toBe(mobile.buyerFeeFromDollars(dollars));
    expect(pkg.sellerNetFromDollars(dollars)).toBe(mobile.sellerNetFromDollars(dollars));
    expect(pkg.sellerNetDollars(dollars)).toBe(mobile.sellerNetDollars(dollars));
  });

  it.each(CENT_GRID)('formatCents(%i)', (cents) => {
    expect(pkg.formatCents(cents)).toBe(mobile.formatCents(cents));
  });

  it('demo-listing all-in prices match the App Store review inventory', () => {
    // III Points $300 → $330 · Mochakk $225 → $247.50 · Quavo $250 → $275
    expect(pkg.allInFromDollars(300)).toBe('$330');
    expect(pkg.allInFromDollars(225)).toBe('$247.50');
    expect(pkg.allInFromDollars(250)).toBe('$275');
  });
});
