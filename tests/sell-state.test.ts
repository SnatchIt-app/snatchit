/**
 * tests/sell-state.test.ts — the Create Listing state model + shipped-source guards.
 *
 * The screen owns a long gate chain and two uploads; those are effects. What CAN
 * be proven in isolation lives in src/lib/sell/sellState.ts and is pinned here:
 * validation (the exact rules the insert runs against), content moderation, the
 * risk-check parser, the CTA copy, and — critically — that the money preview is
 * composed from the authoritative helpers rather than re-derived. The source
 * guards assert the redesign did not drop a gate, change the insert, or alter the
 * money contract. Behaviour, not pixels.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  digitsOnly,
  parseAmount,
  sellErrors,
  isSellValid,
  sellingMethodBlurb,
  submitCtaLabel,
  priceSummary,
  findBannedContent,
  parseRiskCheckResponse,
  type SellInput,
} from '../src/lib/sell/sellState';
import {
  allInFromDollars,
  sellerNetFromDollars,
  sellerNetDollars,
} from '../src/lib/money';

// A fully valid listing draft. Individual tests knock out one field at a time.
function draft(over: Partial<SellInput> = {}): SellInput {
  return {
    eventName: 'Rooftop set',
    venue: 'LIV Miami',
    neighborhood: 'wynwood' as SellInput['neighborhood'],
    ticketType: 'GA',
    transferMethod: 'mobile_transfer',
    startingBid: '100',
    buyNowEnabled: false,
    buyNowPrice: '',
    durationHours: 24,
    coverLocalUri: 'file:///cover.jpg',
    proofLocalUri: 'file:///proof.jpg',
    commitmentAccepted: true,
    ...over,
  };
}

// ─── Amount parsing ─────────────────────────────────────────────────────────

describe('amount parsing', () => {
  it('digitsOnly strips non-numerics so state holds only the raw number', () => {
    expect(digitsOnly('$1,234.50')).toBe('123450');
    expect(digitsOnly('abc')).toBe('');
  });
  it('parseAmount matches the historic parseInt over digits-only input', () => {
    expect(parseAmount('100')).toBe(100);
    expect(Number.isNaN(parseAmount(''))).toBe(true);
  });
});

// ─── Validation ─────────────────────────────────────────────────────────────

describe('validation — a complete draft passes', () => {
  it('is valid with every required field present', () => {
    expect(isSellValid(sellErrors(draft()))).toBe(true);
  });
});

describe('validation — each required field is enforced', () => {
  const cases: [string, Partial<SellInput>, keyof ReturnType<typeof sellErrors>][] = [
    ['eventName',      { eventName: '   ' },        'eventName'],
    ['venue',          { venue: '' },               'venue'],
    ['neighborhood',   { neighborhood: null },      'neighborhood'],
    ['ticketType',     { ticketType: null },        'ticketType'],
    ['transferMethod', { transferMethod: null },    'transferMethod'],
    ['durationHours',  { durationHours: null },     'durationHours'],
    ['coverLocalUri',  { coverLocalUri: null },     'coverImage'],
    ['proofLocalUri',  { proofLocalUri: null },     'proofImage'],
    ['commitment',     { commitmentAccepted: false }, 'commitment'],
  ];
  for (const [name, over, key] of cases) {
    it(`flags a missing ${name}`, () => {
      const e = sellErrors(draft(over));
      expect(e[key]).not.toBe('');
      expect(isSellValid(e)).toBe(false);
    });
  }
});

describe('validation — price rules', () => {
  it('rejects a starting bid below $1', () => {
    expect(sellErrors(draft({ startingBid: '0' })).startingBid).not.toBe('');
    expect(sellErrors(draft({ startingBid: '' })).startingBid).not.toBe('');
  });
  it('accepts a starting bid of exactly $1', () => {
    expect(sellErrors(draft({ startingBid: '1' })).startingBid).toBe('');
  });
});

describe('validation — Buy Now is conditional', () => {
  it('ignores the Buy Now price entirely when Buy Now is off (auction-only)', () => {
    const e = sellErrors(draft({ buyNowEnabled: false, buyNowPrice: '' }));
    expect(e.buyNowPrice).toBe('');
    expect(isSellValid(e)).toBe(true);
  });
  it('requires Buy Now to exceed the starting bid when on', () => {
    expect(sellErrors(draft({ buyNowEnabled: true, buyNowPrice: '' })).buyNowPrice).not.toBe('');
    expect(sellErrors(draft({ buyNowEnabled: true, startingBid: '100', buyNowPrice: '100' })).buyNowPrice).not.toBe('');
    expect(sellErrors(draft({ buyNowEnabled: true, startingBid: '100', buyNowPrice: '150' })).buyNowPrice).toBe('');
  });
  it('names the current starting bid in the Buy Now error', () => {
    expect(sellErrors(draft({ buyNowEnabled: true, startingBid: '80', buyNowPrice: '10' })).buyNowPrice)
      .toContain('$80');
  });
});

// ─── CTA + method copy ──────────────────────────────────────────────────────

describe('CTA + selling-method copy', () => {
  it('agrees with quantity', () => {
    expect(submitCtaLabel(1)).toBe('List ticket');
    expect(submitCtaLabel(3)).toBe('List tickets');
  });
  it('describes Buy Now only when it is on', () => {
    expect(sellingMethodBlurb(false)).not.toMatch(/Buy Now/);
    expect(sellingMethodBlurb(true)).toMatch(/Buy Now/);
  });
  it('uses no em dash in seller-facing copy', () => {
    for (const s of [sellingMethodBlurb(false), sellingMethodBlurb(true), submitCtaLabel(1), submitCtaLabel(2)]) {
      expect(s).not.toContain('—');
    }
  });
});

// ─── Money preview is composition, not re-derivation ────────────────────────

describe('price summary — wired to the authoritative helpers', () => {
  it('returns invalid for an unusable amount', () => {
    expect(priceSummary(0).valid).toBe(false);
    expect(priceSummary(NaN).valid).toBe(false);
  });
  it('mirrors money.ts exactly (no local fee math)', () => {
    const s = priceSummary(100);
    expect(s.valid).toBe(true);
    expect(s.sellerNet).toBe(sellerNetFromDollars(100));
    expect(s.sellerNetValue).toBe(sellerNetDollars(100));
    expect(s.buyerAllIn).toBe(allInFromDollars(100));
    expect(s.buyerAllInLabel).toBe(`${allInFromDollars(100)} total`);
  });
});

// ─── Content moderation ─────────────────────────────────────────────────────

describe('content moderation (Apple 1.4.3)', () => {
  it('catches a banned term across fields and returns its label', () => {
    expect(findBannedContent(['Free ALCOHOL night', 'Venue'])).toBe('alcohol');
    expect(findBannedContent(['Show', null, 'bottle service included'])).toBe('bottle service');
  });
  it('passes clean copy', () => {
    expect(findBannedContent(['Rooftop set', 'LIV Miami', '21+'])).toBeNull();
  });
});

// ─── Risk-check parsing ─────────────────────────────────────────────────────

describe('can_create_listing parsing', () => {
  it('unwraps the RETURNS TABLE array and passes an ok row', () => {
    const r = parseRiskCheckResponse([{ allowed: true, reason: 'ok', risk_tier: 'low' }], null);
    expect(r).toEqual({ status: 'ok', reason: 'ok', tier: 'low' });
  });
  it('fails OPEN on a transient RPC error', () => {
    expect(parseRiskCheckResponse(null, { message: 'network' }).status).toBe('transient');
  });
  it('fails CLOSED on an unrecognised shape', () => {
    expect(parseRiskCheckResponse({ allowed: 'yes' }, null).status).toBe('bad_shape');
    expect(parseRiskCheckResponse({ allowed: true, reason: 'mystery' }, null).status).toBe('bad_shape');
  });
  it('blocks when not allowed', () => {
    const r = parseRiskCheckResponse({ allowed: false, reason: 'listing_blocked', risk_tier: 'critical' }, null);
    expect(r.status).toBe('block');
  });
  it('warns (and gates) on high risk, warns (banner only) on medium', () => {
    expect(parseRiskCheckResponse({ allowed: true, reason: 'high_risk_warning', risk_tier: 'high' }, null).status).toBe('warn');
    expect(parseRiskCheckResponse({ allowed: true, reason: 'medium_risk_warning', risk_tier: 'medium' }, null).status).toBe('warn');
  });
});

// ─── Shipped-source guards ──────────────────────────────────────────────────

describe('create listing — shipped-source guards', () => {
  const root = resolve(__dirname, '..');
  const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
  const screen = read('src/screens/CreateListingScreen.tsx');
  const model = read('src/lib/sell/sellState.ts');

  it('preserves every publish gate, in the insert path', () => {
    for (const marker of [
      'phone_confirmed_at',                 // verified-phone gate
      "supabase.functions.invoke",          // payout status via edge function
      'create-connect-account',
      'stripe_onboarding_complete',
      "rpc('can_create_listing'",           // risk gate
      'findBannedContent',                  // moderation gate
      'coverUpload.uploadImage',            // dual upload
      'proofUpload.uploadImage',
      "from('listings')",                   // the insert
      'proof_of_ownership_path',
      'seller_commitment_accepted_at',
      'router.push(`/listing/${data.id}`)', // navigate to the real detail route
    ]) {
      expect(screen, `${marker} must survive the redesign`).toContain(marker);
    }
  });

  it('does not change the money contract in the screen', () => {
    // No cents<->dollars conversion or fee arithmetic in the presentation layer;
    // the listing price is inserted as whole dollars and previews come from helpers.
    expect(screen).not.toMatch(/\*\s*100|\/\s*100/);
    expect(screen).not.toMatch(/SELLER_FEE_RATE|BUYER_FEE_RATE/);
    expect(screen).toContain('priceSummary(');
    // starting_bid and current_bid are the whole-dollar integers, unchanged.
    expect(screen).toContain('starting_bid:                  startingBidNum');
    expect(screen).toContain('current_bid:                   startingBidNum');
  });

  it('keeps the whole-dollars listing insert (buy_now stays null when off)', () => {
    expect(screen).toContain('buy_now_price:                 buyNowEnabled ? buyNowPriceNum : null');
  });

  it('routes display type through the shared token renderer (no local font hacks)', () => {
    expect(screen).toContain("textStyle('displayMd')");
    expect(screen).not.toMatch(/fontFamily:\s*['"]Oswald/);
  });

  it('the model does no money math of its own', () => {
    expect(model).not.toMatch(/\*\s*0?\.\d|\bcents\b|\*\s*100|\/\s*100/i);
  });

  it('does not introduce a venue-primary / direct-issuance path (093 still off)', () => {
    expect(screen).not.toMatch(/kernel\.|direct_issue|venue_inventory|scan(ner)?\b/i);
  });
});
