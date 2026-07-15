/**
 * Canonical money math tests — the 10/10 fee model in integer cents.
 * Covers server (_shared/money.ts) and client (src/lib/money.ts) and
 * asserts the two implementations agree exactly (parity).
 */
import { describe, expect, it } from 'vitest';
import * as server from '../supabase/functions/_shared/money';
import * as client from '../src/lib/money';

const CASES = [
  { dollars: 25,     base: 2500,  fee: 250,  total: 2750,  net: 2250 },
  { dollars: 99,     base: 9900,  fee: 990,  total: 10890, net: 8910 },
  { dollars: 100,    base: 10000, fee: 1000, total: 11000, net: 9000 },
  { dollars: 199.99, base: 19999, fee: 2000, total: 21999, net: 17999 }, // 1999.9 → 2000 (half-up)
];

describe('10% buyer fee', () => {
  it.each(CASES)('base $%s', ({ base, fee }) => {
    expect(server.buyerFeeCents(base)).toBe(fee);
  });
});

describe('10% seller fee (from BASE, never from buyer total)', () => {
  it.each(CASES)('base $%s', ({ base, net }) => {
    expect(server.sellerFeeCents(base)).toBe(base - net);
    expect(server.sellerNetCents(base)).toBe(net);
  });

  it('seller fee is 10% of BASE — not 10% of the buyer all-in total', () => {
    // $100 base: buyer total is 11000¢; 10% of THAT would be 1100¢ — wrong.
    const feeFromBase  = server.sellerFeeCents(10000);
    const feeFromTotal = Math.round(server.buyerTotalCents(10000) * 0.10);
    expect(feeFromBase).toBe(1000);
    expect(feeFromTotal).toBe(1100);
    expect(feeFromBase).not.toBe(feeFromTotal);
  });
});

describe('cent rounding (half-up, integer cents only)', () => {
  it('rounds 10% of odd cent amounts half-up', () => {
    expect(server.buyerFeeCents(105)).toBe(11);   // 10.5 → 11
    expect(server.buyerFeeCents(104)).toBe(10);   // 10.4 → 10
    expect(server.buyerFeeCents(19999)).toBe(2000); // 1999.9 → 2000
    expect(server.buyerFeeCents(1)).toBe(0);      // 0.1 → 0
    expect(server.buyerFeeCents(5)).toBe(1);      // 0.5 → 1 (half-up)
  });

  it('rejects non-integer and negative inputs', () => {
    expect(() => server.buyerFeeCents(10.5)).toThrow();
    expect(() => server.buyerFeeCents(-100)).toThrow();
    expect(() => server.sellerFeeCents(NaN)).toThrow();
  });

  it('dollarsToCents converts whole and fractional dollars exactly', () => {
    expect(server.dollarsToCents(100)).toBe(10000);
    expect(server.dollarsToCents(199.99)).toBe(19999);
    expect(server.dollarsToCents(0.1 + 0.2)).toBe(30); // float-safe
  });
});

describe('auction bid total & Buy Now total (same canonical path)', () => {
  it.each(CASES)('bid/buy-now of $%s → all-in total', ({ dollars, total }) => {
    // Bids are BASE prices; the buyer's commitment is base + 10%.
    expect(server.buyerTotalCents(server.dollarsToCents(dollars))).toBe(total);
  });
});

describe('seller payout', () => {
  it.each(CASES)('base $%s → seller receives net', ({ base, net }) => {
    expect(server.sellerNetCents(base)).toBe(net);
  });

  it('base = sellerNet + sellerFee always (no lost cents)', () => {
    for (let base = 1; base < 5000; base += 7) {
      expect(server.sellerNetCents(base) + server.sellerFeeCents(base)).toBe(base);
    }
  });
});

describe('full eligible refund', () => {
  it('a full refund equals the buyer total (base + buyer fee), matching the PaymentIntent charge', () => {
    // enforce-transfer-expiry issues POST /refunds with no amount → Stripe
    // refunds the full charge, which is buyerTotalCents by construction.
    for (const { base, total } of CASES) {
      expect(server.feeBreakdown(base).buyerTotalCents).toBe(total);
    }
  });
});

describe('platform gross', () => {
  it.each(CASES)('base $%s → platform keeps buyer fee + seller fee', ({ base, fee, net }) => {
    expect(server.platformGrossCents(base)).toBe(fee + (base - net));
  });
});

describe('client/server parity', () => {
  it('identical results across the full range', () => {
    for (let base = 0; base < 30000; base += 13) {
      expect(client.buyerFeeCents(base)).toBe(server.buyerFeeCents(base));
      expect(client.buyerTotalCents(base)).toBe(server.buyerTotalCents(base));
      expect(client.sellerFeeCents(base)).toBe(server.sellerFeeCents(base));
      expect(client.sellerNetCents(base)).toBe(server.sellerNetCents(base));
    }
  });

  it('rates match', () => {
    expect(client.BUYER_FEE_RATE).toBe(server.BUYER_FEE_RATE);
    expect(client.SELLER_FEE_RATE).toBe(server.SELLER_FEE_RATE);
  });
});

describe('client display formatting (all-in first price)', () => {
  it('formats whole-dollar totals without cents', () => {
    expect(client.allInLabel(100)).toBe('$110 total');
    expect(client.allInFromDollars(100)).toBe('$110');
  });
  it('keeps real cents', () => {
    expect(client.allInLabel(25)).toBe('$27.50 total');
    expect(client.buyerFeeFromDollars(25)).toBe('$2.50');
    expect(client.sellerNetFromDollars(25)).toBe('$22.50');
  });
  it('historical/legacy base prices render unchanged through baseFromDollars', () => {
    // Historical payments rows store their own persisted amounts; base
    // display for old records stays exactly what was stored.
    expect(client.baseFromDollars(100)).toBe('$100');
    expect(client.baseFromDollars(199.99)).toBe('$199.99');
  });
});

describe('client/server total mismatch rejection (contract)', () => {
  it('server total for a listing differs from a tampered client total', () => {
    // create-payment-intent computes totalCents = feeBreakdown(base) and
    // returns 409 when expected_total_cents !== totalCents. This asserts the
    // canonical function is deterministic — the contract the 409 relies on.
    const serverTotal = server.feeBreakdown(server.dollarsToCents(100)).buyerTotalCents;
    const tamperedClientTotal = 10000; // buyer tried to pay base-only
    expect(serverTotal).toBe(11000);
    expect(tamperedClientTotal).not.toBe(serverTotal);
  });
});
