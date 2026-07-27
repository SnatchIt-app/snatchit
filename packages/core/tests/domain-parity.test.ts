/**
 * Parity: sale-price resolution, marketplace constants, and ticket-platform
 * instructions in @snatchit/core must be identical to the mobile originals.
 */
import { describe, expect, it } from 'vitest';
import * as pkg from '@snatchit/core';
import { finalSoldPrice as mobileFinalSoldPrice } from '@mobile/src/lib/salePrice';
import { PLATFORM_INSTRUCTIONS as MOBILE_PI, interpolateStep as mobileInterpolate } from '@mobile/src/lib/platformInstructions';
import { CATEGORIES as MOBILE_CATEGORIES, CATEGORY_LABELS as MOBILE_CATEGORY_LABELS } from '@mobile/src/constants/categories';
import {
  NEIGHBORHOODS as MOBILE_NEIGHBORHOODS,
  NEIGHBORHOOD_GROUPS as MOBILE_NEIGHBORHOOD_GROUPS,
  NEIGHBORHOOD_LABELS as MOBILE_NEIGHBORHOOD_LABELS,
} from '@mobile/src/constants/neighborhoods';
import { APP_CONFIG as MOBILE_APP_CONFIG } from '@mobile/src/config/app';

describe('finalSoldPrice parity', () => {
  const cases = [
    // auction win stamped
    { buy_now_enabled: true, buy_now_price: 300, current_bid: 250, winning_bid_amount: 270 },
    // Buy Now sale (no winning bid stamped)
    { buy_now_enabled: true, buy_now_price: 300, current_bid: 250, winning_bid_amount: null },
    { buy_now_enabled: true, buy_now_price: 225, current_bid: 150 },
    // legacy fallback: no buy-now
    { buy_now_enabled: false, buy_now_price: null, current_bid: 180, winning_bid_amount: null },
    // zero-guard: winning_bid_amount 0 must fall through
    { buy_now_enabled: true, buy_now_price: 250, current_bid: 180, winning_bid_amount: 0 },
    { buy_now_enabled: false, buy_now_price: 0, current_bid: 95 },
  ];
  it.each(cases.map((c, i) => [i, c] as const))('case %i', (_i, listing) => {
    expect(pkg.finalSoldPrice(listing)).toBe(mobileFinalSoldPrice(listing));
  });
});

describe('marketplace constants parity', () => {
  it('categories match', () => {
    expect(pkg.CATEGORIES).toStrictEqual(MOBILE_CATEGORIES);
    expect(pkg.CATEGORY_LABELS).toStrictEqual(MOBILE_CATEGORY_LABELS);
  });
  it('neighborhoods match', () => {
    expect(pkg.NEIGHBORHOODS).toStrictEqual(MOBILE_NEIGHBORHOODS);
    expect(pkg.NEIGHBORHOOD_GROUPS).toStrictEqual(MOBILE_NEIGHBORHOOD_GROUPS);
    expect(pkg.NEIGHBORHOOD_LABELS).toStrictEqual(MOBILE_NEIGHBORHOOD_LABELS);
  });
  it('APP_CONFIG shared keys match mobile values', () => {
    const sharedKeys = Object.keys(pkg.APP_CONFIG) as (keyof typeof pkg.APP_CONFIG)[];
    expect(sharedKeys.length).toBeGreaterThan(0);
    for (const key of sharedKeys) {
      expect(pkg.APP_CONFIG[key], `APP_CONFIG.${key}`).toStrictEqual(
        (MOBILE_APP_CONFIG as Record<string, unknown>)[key],
      );
    }
    // The only mobile key intentionally absent from the shared copy:
    const missing = Object.keys(MOBILE_APP_CONFIG).filter((k) => !(k in pkg.APP_CONFIG));
    expect(missing).toStrictEqual(['STRIPE_PUBLISHABLE_KEY']);
  });
});

describe('platform instructions parity', () => {
  it('all 16 platforms deep-equal the mobile data', () => {
    expect(Object.keys(pkg.PLATFORM_INSTRUCTIONS).sort()).toStrictEqual(
      Object.keys(MOBILE_PI).sort(),
    );
    expect(pkg.PLATFORM_INSTRUCTIONS).toStrictEqual(MOBILE_PI);
  });
  it('interpolateStep behaves identically', () => {
    const samples: [string, string | null | undefined, string | null | undefined][] = [
      ['Send to {buyer_email}', 'a@b.com', null],
      ['Text {buyer_phone} and email {buyer_email}', null, '+13055550123'],
      ['No placeholders', undefined, undefined],
      ['{buyer_email} {buyer_email}', '', ''],
    ];
    for (const [step, email, phone] of samples) {
      expect(pkg.interpolateStep(step, email, phone)).toBe(mobileInterpolate(step, email, phone));
    }
  });
});
