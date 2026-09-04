/**
 * tests/product-v2-foundation.test.ts — Product V2 Tier-0 foundation.
 *
 * These test the three things most likely to cause customer-visible harm:
 *   1. the media layer silently rendering a broken or mis-cropped image,
 *   2. the pricing layer showing a number that is not what the buyer pays,
 *   3. the provenance layer labelling a fan's ticket as venue-issued.
 */

import { describe, expect, it, beforeAll } from 'vitest';

import {
  MEDIA_SLOTS,
  slotHeight,
  slotPixelWidth,
  slotQuality,
  type MediaSlotName,
} from '../src/lib/media/slots';
import {
  DEFAULT_FOCAL,
  focalToObjectPosition,
  normalizePath,
  resolveImage,
  transformUrl,
  IMMUTABLE_CACHE_CONTROL,
} from '../src/lib/media/url';
import { buyerFeeCents, buyerTotalCents } from '../src/lib/money';
import {
  allInFromPrimaryCheckout,
  allInPrice,
  asCents,
  centsFromDollars,
  formatMinor,
  marketplaceCentsFromMinorColumn,
  priceLadder,
} from '../src/lib/pricing/allIn';
import { inventoryKindOf, provenanceLabel, provenanceSortWeight } from '../src/lib/pricing/provenance';

beforeAll(() => {
  process.env.EXPO_PUBLIC_SUPABASE_URL = 'https://example.supabase.co';
});

describe('brand token parity', () => {
  it('the package copy has not drifted from the mobile runtime source', async () => {
    const mobile = await import('../src/theme/v2');
    const pkg = await import('../packages/design-tokens/src/brand');
    expect(pkg.brandTokens).toStrictEqual(mobile.brandTokens);
  });

  it('carries the brand values measured from the live site, not the legacy palette', async () => {
    const t = await import('../src/theme/v2');
    expect(t.surface.canvas).toBe('#000000');
    expect(t.brand.red).toBe('#FF1A1A');
    expect(t.text.inverse).toBe('#000000');
    // Radius 0 is the brand. The legacy 6/10/16/24 ladder must not reappear.
    expect(t.radius.none).toBe(0);
    expect(Object.values(t.radius)).not.toContain(6);
    // Red-tinted hairlines, never gray.
    expect(t.border.default).toContain('255,26,26');
    // Metadata must clear the 4.5:1 minimum: it carries dates and venue names.
    expect(t.text.muted).toBe('rgba(255,255,255,0.55)');
    // A destructive action must not share a color with a primary action.
    expect(t.status.error).not.toBe(t.brand.red);
    // Prices must not jitter as a live bid updates: the variant travels with the
    // token rather than living only in a comment.
    expect(t.type.price.fontVariant).toContain('tabular-nums');
  });
});

describe('media slots', () => {
  const names = Object.keys(MEDIA_SLOTS) as MediaSlotName[];

  it('defines every slot the redesign references', () => {
    for (const required of [
      'DISCOVERY_CARD',
      'FEATURED_EVENT',
      'EVENT_HERO',
      'EVENT_GALLERY',
      'VENUE_HERO',
      'CHECKOUT_THUMBNAIL',
      'TICKET_ART',
      'SEARCH_RESULT',
      'DASHBOARD_THUMBNAIL',
      'PROMOTER_SHARE',
    ]) {
      expect(names).toContain(required);
    }
  });

  it('is square everywhere, because radius 0 is the brand', () => {
    for (const n of names) expect(MEDIA_SLOTS[n].radius).toBe(0);
  });

  it('puts a scrim behind every slot that carries text over artwork', () => {
    // If text sits on the image, an unscrimmed slot would be unreadable over
    // bright artwork and invisible over dark artwork.
    expect(MEDIA_SLOTS.FEATURED_EVENT.scrim).not.toBe('none');
    expect(MEDIA_SLOTS.TICKET_ART.scrim).not.toBe('none');
    // The discovery card deliberately places text BELOW the image, so it needs none.
    expect(MEDIA_SLOTS.DISCOVERY_CARD.scrim).toBe('none');
  });

  it('derives height from width and ratio rather than hard-coding it', () => {
    // 4:5 portrait at 168 wide is 210 tall.
    expect(slotHeight('DISCOVERY_CARD', 'mobile')).toBe(210);
    expect(slotHeight('SEARCH_RESULT', 'mobile')).toBe(64);
  });

  it('caps density at 2x and halves quality as density doubles', () => {
    expect(slotPixelWidth('DISCOVERY_CARD', 'mobile', 1)).toBe(168);
    expect(slotPixelWidth('DISCOVERY_CARD', 'mobile', 2)).toBe(336);
    // A 3x screen must not request 3x bytes.
    expect(slotPixelWidth('DISCOVERY_CARD', 'mobile', 3)).toBe(336);
    expect(slotQuality(1)).toBe(80);
    expect(slotQuality(2)).toBe(45);
  });
});

describe('media url resolution', () => {
  it('requests a derivative sized to the box, never the original', () => {
    const r = resolveImage({ path: 'covers/1783029690066.jpg' }, 'DISCOVERY_CARD', {
      devicePixelRatio: 2,
    });
    expect(r.kind).toBe('image');
    if (r.kind !== 'image') return;
    // The defect this prevents: a 6.3 MB original shipped into a 358x180 card.
    expect(r.uri).toContain('/render/image/public/auction-media/');
    expect(r.uri).toContain('width=336');
    expect(r.uri).toContain('quality=45');
  });

  it('fits legacy landscape assets in a portrait slot instead of re-cropping them', () => {
    // The old mobile picker cropped destructively to 16:9, so the portrait
    // pixels never existed. Cropping again would remove the subject entirely.
    const legacy = resolveImage(
      { path: 'covers/old.jpg', contract: 'legacy' },
      'DISCOVERY_CARD',
    );
    expect(legacy.kind).toBe('image');
    if (legacy.kind !== 'image') return;
    expect(legacy.fit).toBe('fit');
    // `fit` drives the CLIENT contentFit; the server request only needs to be
    // slot-sized. Asserting the server `resize` value would assert an inert
    // parameter, because it only takes effect when a height is also sent.
    expect(legacy.uri).toContain('width=');
  });

  it('crops v2 portrait assets, which were uploaded for this frame', () => {
    const v2asset = resolveImage(
      { path: 'covers/new.jpg', contract: 'v2', fit: 'cover' },
      'DISCOVERY_CARD',
    );
    expect(v2asset.kind).toBe('image');
    if (v2asset.kind !== 'image') return;
    expect(v2asset.fit).toBe('cover');
    expect(v2asset.uri).toContain('width=');
  });

  it('requests the width the component is ACTUALLY laid out at, not the slot default', () => {
    // Regression: a 150pt card used to request the slot's 336px, and a 140pt hero
    // used to request 780px, which defeats the whole point of the system.
    const r = resolveImage({ path: 'covers/a.jpg' }, 'EVENT_HERO', {
      devicePixelRatio: 2,
      layoutWidth: 140,
    });
    if (r.kind !== 'image') throw new Error('expected image');
    expect(r.uri).toContain('width=280');
    expect(r.uri).not.toContain('width=780');
  });

  it('returns a fallback rather than a broken URL when the path is missing', () => {
    // The live defect this prevents: a missing path produced a bucket DIRECTORY
    // URL which was then published into OpenGraph and JSON-LD.
    expect(resolveImage({ path: null }, 'DISCOVERY_CARD')).toEqual({
      kind: 'fallback',
      reason: 'no-path',
    });
    expect(resolveImage({ path: '   ' }, 'DISCOVERY_CARD').kind).toBe('fallback');
  });

  it('refuses traversal paths', () => {
    expect(normalizePath('../avatars/secret.png', 'auction-media')).toBeNull();
    const r = resolveImage({ path: '../other/x.jpg' }, 'DISCOVERY_CARD');
    expect(r).toEqual({ kind: 'fallback', reason: 'unsafe-path' });
  });

  it('strips an accidental bucket prefix from older rows', () => {
    expect(normalizePath('auction-media/covers/a.jpg', 'auction-media')).toBe('covers/a.jpg');
  });

  it('passes absolute legacy URLs through without inventing a transform host', () => {
    const r = resolveImage({ path: 'https://cdn.example.com/a.jpg' }, 'DISCOVERY_CARD');
    expect(r.kind).toBe('image');
    if (r.kind !== 'image') return;
    expect(r.uri).toBe('https://cdn.example.com/a.jpg');
  });

  it('derives a backdrop from the same artwork, never a generated image', () => {
    const r = resolveImage({ path: 'covers/a.jpg' }, 'EVENT_HERO');
    if (r.kind !== 'image') throw new Error('expected image');
    expect(r.backdropUri).toContain('covers/a.jpg');
    expect(r.backdropUri).toContain('width=32');
  });

  it('encodes the focal point as an object position', () => {
    expect(focalToObjectPosition(DEFAULT_FOCAL)).toBe('50% 40%');
    expect(focalToObjectPosition({ x: 0, y: 1 })).toBe('0% 100%');
    // Out-of-range values are clamped rather than producing invalid CSS.
    expect(focalToObjectPosition({ x: -1, y: 2 })).toBe('0% 100%');
  });

  it('uses an immutable cache policy, since upload paths are timestamped', () => {
    // The live defect: cacheControl '3600' on an immutable object, 8,760x short.
    expect(IMMUTABLE_CACHE_CONTROL).toContain('31536000');
    expect(IMMUTABLE_CACHE_CONTROL).toContain('immutable');
  });

  it('builds a well-formed transform url', () => {
    const u = transformUrl({
      base: 'https://x.supabase.co/storage/v1',
      bucket: 'auction-media',
      path: 'covers/a b.jpg',
      width: 100,
      quality: 80,
      resize: 'cover',
    });
    expect(u).toContain('covers/a%20b.jpg');
    expect(u).toContain('width=100');
  });
});

/**
 * A value shaped exactly like what `public.listings.buy_now_price` /
 * `listing.current_bid` actually hand a screen: a plain number of WHOLE DOLLARS.
 */
const listingPriceFromColumn: number = 50;

/** A server quote as the primary-checkout edge returns it: face + fee = charge. */
const directQuote = (face: number, fee: number) =>
  ({
    rail: 'direct',
    faceValueMinor: asCents(face),
    buyerServiceFee: { source: 'server-quote', feeMinor: asCents(fee) },
    chargeTotalMinor: asCents(face + fee),
  }) as const;

describe('all-in pricing — marketplace rail (resale, live: behaviour is FROZEN)', () => {
  it('adds the buyer fee on the marketplace rail', () => {
    const r = allInPrice({ rail: 'marketplace', baseMinor: centsFromDollars(50) });
    expect(r).toEqual({
      kind: 'all-in',
      totalMinor: 5500,
      faceValueMinor: 5000,
      buyerServiceFeeMinor: 500,
      taxMinor: null,
      currency: 'USD',
      rail: 'marketplace',
    });
  });

  it('REGRESSION: the resale total is still exactly buyerTotalCents, to the cent', () => {
    // The A5 rewrite touched the direct rail only. If any of these drift, the
    // client has forked from `_shared/money.ts` and create-payment-intent will
    // start rejecting client totals. 0 and 1 are boundaries; 5 and 15 exercise
    // the half-up rounding inside buyerFeeCents; 999999 is a large odd base.
    // These are CENT-level bases chosen to exercise buyerFeeCents' rounding; no
    // production column produces them (every resale column is whole dollars),
    // which is exactly what the named escape hatch is for.
    for (const base of [0, 1, 5, 15, 99, 100, 2500, 5000, 12345, 999999]) {
      const r = allInPrice({ rail: 'marketplace', baseMinor: marketplaceCentsFromMinorColumn(base) });
      if (r.kind !== 'all-in') throw new Error(`expected a price for ${base}`);
      expect(r.totalMinor).toBe(buyerTotalCents(base));
      expect(r.buyerServiceFeeMinor).toBe(buyerFeeCents(base));
      expect(r.faceValueMinor).toBe(base);
      // The breakdown must add up, or the itemized receipt would contradict the
      // headline number.
      expect(r.faceValueMinor + r.buyerServiceFeeMinor).toBe(r.totalMinor);
      expect(r.taxMinor).toBeNull();
      expect(Number.isSafeInteger(r.totalMinor)).toBe(true);
    }
  });

  it('converts the repo whole-dollar columns rather than treating them as cents', () => {
    // The trap: listing prices in this repo are WHOLE DOLLARS. Passing 50 as if
    // it were cents renders a $50 ticket as $0.55. The branded type makes that a
    // compile error; this asserts the conversion is the right one.
    expect(centsFromDollars(50)).toBe(5000);
    const r = allInPrice({ rail: 'marketplace', baseMinor: centsFromDollars(50) });
    if (r.kind !== 'all-in') throw new Error('expected a price');
    expect(formatMinor(r.totalMinor)).toBe('$55');
    // $50 must never render as $0.50 or $0.55.
    expect(formatMinor(r.totalMinor)).not.toBe('$0.55');
    expect(formatMinor(r.faceValueMinor)).not.toBe('$0.50');
  });

  it('refuses to quote rather than guessing when the base is absent or invalid', () => {
    expect(allInPrice({ rail: 'marketplace', baseMinor: null })).toEqual({
      kind: 'unavailable',
      reason: 'missing-base',
    });
    // A fractional cent is not a price.
    expect(allInPrice({ rail: 'marketplace', baseMinor: 12.5 as never }).kind).toBe('unavailable');
    // A negative amount must never render as a price.
    expect(allInPrice({ rail: 'marketplace', baseMinor: -100 as never }).kind).toBe('unavailable');
  });

  it('refuses on the resale rail too when tax could apply, since no schema models it', () => {
    expect(
      allInPrice({
        rail: 'marketplace',
        baseMinor: centsFromDollars(50),
        tax: { status: 'applies-unknown' },
      }),
    ).toEqual({ kind: 'unavailable', reason: 'tax-unmodelled' });
    // Even a *known* amount is refused here: no resale column carries tax, so a
    // caller supplying one is quoting a total the server would reject.
    expect(
      allInPrice({
        rail: 'marketplace',
        baseMinor: centsFromDollars(50),
        tax: { status: 'applies', taxMinor: asCents(400) },
      }),
    ).toEqual({ kind: 'unavailable', reason: 'tax-unmodelled' });
  });
});

describe('all-in pricing — direct rail (owner ruling A5: face + buyer service fee)', () => {
  it('THE BUG THIS FIXES: face value alone is never the buyer total', () => {
    // Pre-A5 this module treated `venue."order".total_minor` as the whole
    // charge. A5 made that face value. A $60 ticket at a 10% configured rate
    // costs $66, and quoting $60 under-shows it by exactly the service fee.
    const r = allInPrice(directQuote(6000, 600));
    expect(r).toEqual({
      kind: 'all-in',
      totalMinor: 6600,
      faceValueMinor: 6000,
      buyerServiceFeeMinor: 600,
      taxMinor: null,
      currency: 'USD',
      rail: 'direct',
    });
    if (r.kind !== 'all-in') throw new Error('expected a price');
    expect(r.totalMinor).not.toBe(r.faceValueMinor);
    expect(r.faceValueMinor + r.buyerServiceFeeMinor).toBe(r.totalMinor);
    expect(formatMinor(r.totalMinor)).toBe('$66');
  });

  it('reads the primary-checkout response through `total`, never through `amount`', () => {
    // The edge returns amount=face, buyer_fee, total=charge. One identifier
    // apart, and picking `amount` is the under-show. The helper removes the choice.
    const res = { order_id: 'o', amount: 10000, buyer_fee: 1000, total: 11000, currency: 'USD' };
    const r = allInFromPrimaryCheckout(res);
    if (r.kind !== 'all-in') throw new Error('expected a price');
    expect(r.totalMinor).toBe(11000);
    expect(r.totalMinor).not.toBe(res.amount);
    expect(r.faceValueMinor).toBe(10000);
    expect(r.buyerServiceFeeMinor).toBe(1000);
  });

  it('refuses a quote whose own arithmetic does not hold (the edge’s quote_incoherent)', () => {
    // charge != face + fee is a contract break between client and RPC.
    expect(
      allInPrice({
        rail: 'direct',
        faceValueMinor: asCents(6000),
        buyerServiceFee: { source: 'server-quote', feeMinor: asCents(600) },
        chargeTotalMinor: asCents(6000), // the stale, fee-free total
      }),
    ).toEqual({ kind: 'unavailable', reason: 'quote-incoherent' });
    expect(
      allInFromPrimaryCheckout({ amount: 10000, buyer_fee: 1000, total: 10000 }),
    ).toEqual({ kind: 'unavailable', reason: 'quote-incoherent' });
  });

  it('fails SAFELY when fee.buyer_service_bps is unset — no guess, no silent zero', () => {
    // The RPC raises `service_fee_unset` and the edge answers 503. The client
    // primitive has the matching explicit state. Selling at face with no
    // platform revenue is unrecoverable: settlement is append-only.
    expect(
      allInPrice({
        rail: 'direct',
        faceValueMinor: asCents(6000),
        buyerServiceFee: { source: 'unset' },
      }),
    ).toEqual({ kind: 'unavailable', reason: 'service-fee-unset' });
    // A config rate that is null reads identically to an unset key.
    expect(
      allInPrice({
        rail: 'direct',
        faceValueMinor: asCents(6000),
        buyerServiceFee: { source: 'config-rate', bps: null },
      }),
    ).toEqual({ kind: 'unavailable', reason: 'service-fee-unset' });
    // So does a server response that omitted the fee field.
    expect(allInFromPrimaryCheckout({ amount: 10000, total: 11000 })).toEqual({
      kind: 'unavailable',
      reason: 'service-fee-unset',
    });
    // And the refusal is NOT a zero-fee price hiding behind a different name.
    const unset = allInPrice({
      rail: 'direct',
      faceValueMinor: asCents(6000),
      buyerServiceFee: { source: 'unset' },
    });
    expect(unset.kind).toBe('unavailable');
  });

  it('fails closed on an out-of-range rate, mirroring service_fee_out_of_range', () => {
    for (const bps of [-1, 10001, 250.5, Number.NaN, Number.POSITIVE_INFINITY]) {
      expect(
        allInPrice({
          rail: 'direct',
          faceValueMinor: asCents(6000),
          buyerServiceFee: { source: 'config-rate', bps },
        }),
      ).toEqual({ kind: 'unavailable', reason: 'service-fee-out-of-range' });
    }
    // 0 and 10000 are the inclusive bounds the RPC accepts.
    expect(
      allInPrice({
        rail: 'direct',
        faceValueMinor: asCents(6000),
        buyerServiceFee: { source: 'config-rate', bps: 0 },
      }),
    ).toMatchObject({ kind: 'all-in', totalMinor: 6000, buyerServiceFeeMinor: 0 });
  });

  it('derives the fee with the RPC’s exact rule: round(face * bps / 10000), half-up', () => {
    // Hand-checked against Postgres `round(numeric)` (half away from zero, and
    // both operands non-negative here, so half-up).
    const cases: [face: number, bps: number, fee: number][] = [
      [6000, 1000, 600], // exact
      [1, 5000, 1], //     0.5 -> 1   (the half-up boundary)
      [3, 5000, 2], //     1.5 -> 2   (half-up, NOT banker's rounding to 2 by luck)
      [1005, 1000, 101], // 100.5 -> 101
      [999, 1000, 100], //  99.9 -> 100
      [994, 1000, 99], //   99.4 -> 99
      [0, 1000, 0],
      [12345, 733, 905], // 904.885... -> 905
      [999999, 10000, 999999], // the 100% bound
    ];
    for (const [face, bps, fee] of cases) {
      const r = allInPrice({
        rail: 'direct',
        faceValueMinor: asCents(face),
        buyerServiceFee: { source: 'config-rate', bps },
      });
      if (r.kind !== 'all-in') throw new Error(`expected a price for ${face}/${bps}`);
      expect(r.buyerServiceFeeMinor).toBe(fee);
      expect(r.totalMinor).toBe(face + fee);
    }
  });

  it('is integer-exact against a BigInt reference — no float drift anywhere', () => {
    // The client fee must equal the numeric-exact half-up value for every case,
    // including the ones where a float division would land a hair below .5.
    const ref = (face: bigint, bps: bigint): bigint => {
      const p = face * bps;
      const q = p / 10000n;
      const rem = p % 10000n;
      return rem * 2n >= 10000n ? q + 1n : q;
    };
    const faces = [0, 1, 3, 7, 99, 100, 1005, 2500, 6000, 12345, 99999, 1234567, 99999999];
    const rates = [0, 1, 7, 250, 500, 733, 1000, 1250, 3333, 5000, 9999, 10000];
    for (const face of faces) {
      for (const bps of rates) {
        const r = allInPrice({
          rail: 'direct',
          faceValueMinor: asCents(face),
          buyerServiceFee: { source: 'config-rate', bps },
        });
        if (r.kind !== 'all-in') throw new Error(`expected a price for ${face}/${bps}`);
        expect(BigInt(r.buyerServiceFeeMinor)).toBe(ref(BigInt(face), BigInt(bps)));
        expect(Number.isSafeInteger(r.buyerServiceFeeMinor)).toBe(true);
        expect(Number.isSafeInteger(r.totalMinor)).toBe(true);
        expect(r.totalMinor).toBe(face + r.buyerServiceFeeMinor);
      }
    }
  });

  it('refuses when tax could apply, and carries it when an amount is actually known', () => {
    // Neither rail models tax. "Applies but unknown" must never be quoted.
    expect(
      allInPrice({ ...directQuote(6000, 600), tax: { status: 'applies-unknown' } }),
    ).toEqual({ kind: 'unavailable', reason: 'tax-unmodelled' });
    // "Applies" with a null amount is the same lie by another route.
    expect(
      allInPrice({ ...directQuote(6000, 600), tax: { status: 'applies', taxMinor: null } }),
    ).toEqual({ kind: 'unavailable', reason: 'tax-unmodelled' });
    // The day a schema carries tax, the amount joins the total and the charge
    // cross-check has to include it.
    const r = allInPrice({
      rail: 'direct',
      faceValueMinor: asCents(6000),
      buyerServiceFee: { source: 'server-quote', feeMinor: asCents(600) },
      chargeTotalMinor: asCents(7100),
      tax: { status: 'applies', taxMinor: asCents(500) },
    });
    expect(r).toMatchObject({ kind: 'all-in', totalMinor: 7100, taxMinor: 500 });
  });

  it('refuses when the face value is absent or not a minor-unit integer', () => {
    expect(
      allInPrice({
        rail: 'direct',
        faceValueMinor: undefined,
        buyerServiceFee: { source: 'server-quote', feeMinor: asCents(600) },
      }),
    ).toEqual({ kind: 'unavailable', reason: 'server-total-missing' });
    expect(
      allInPrice({
        rail: 'direct',
        faceValueMinor: -100 as never,
        buyerServiceFee: { source: 'server-quote', feeMinor: asCents(600) },
      }),
    ).toEqual({ kind: 'unavailable', reason: 'invalid-base' });
    expect(
      allInPrice({
        rail: 'direct',
        faceValueMinor: 60.5 as never,
        buyerServiceFee: { source: 'server-quote', feeMinor: asCents(600) },
      }),
    ).toEqual({ kind: 'unavailable', reason: 'invalid-base' });
  });

  it('cannot be handed whole dollars, and cannot be double-converted', () => {
    // A venue `*_minor` column is ALREADY cents. Running it through the
    // whole-dollar converter is the mirror-image of the resale trap: $60 would
    // render as $6,000. The test pins both directions of the mistake.
    const faceFromServer = 6000; // venue."order".total_minor, i.e. $60.00
    const right = allInPrice(directQuote(faceFromServer, 600));
    if (right.kind !== 'all-in') throw new Error('expected a price');
    expect(formatMinor(right.totalMinor)).toBe('$66');

    const doubleConverted = allInPrice({
      rail: 'direct',
      faceValueMinor: centsFromDollars(faceFromServer), // the mistake, made visible
      buyerServiceFee: { source: 'config-rate', bps: 1000 },
    });
    if (doubleConverted.kind !== 'all-in') throw new Error('expected a price');
    expect(doubleConverted.totalMinor).toBe(right.totalMinor * 100);
    expect(formatMinor(doubleConverted.totalMinor)).toBe('$6,600');

    // The branded type is what stops it in the editor: a bare number from a
    // Supabase row does not type-check on either rail.
    // @ts-expect-error a raw number is not Cents — the direct rail must use asCents()
    allInPrice({ rail: 'direct', faceValueMinor: 6000, buyerServiceFee: { source: 'unset' } });
    // @ts-expect-error a raw number is not Cents — the resale rail must use centsFromDollars()
    allInPrice({ rail: 'marketplace', baseMinor: 50 });
    expect(
      // @ts-expect-error the fee is required: "I forgot it" must not compile as "it is zero"
      allInPrice({ rail: 'direct', faceValueMinor: asCents(6000) }),
      // ...and at runtime, where an untyped JSON response can still omit it, the
      // module refuses instead of throwing.
    ).toEqual({ kind: 'unavailable', reason: 'service-fee-unset' });
  });
});

describe('all-in pricing — the whole-dollars/cents trap is CLOSED, not documented', () => {
  // Every one of the compile-time assertions below FAILS ON THE PREVIOUS CODE:
  // `formatMinor` used to take `Cents | number` and `baseMinor` used to take
  // `Cents`, so each `@ts-expect-error` would be an UNUSED suppression, which
  // `tsc --noEmit` reports as an error. These are enforced by the typecheck
  // gate, not by review.

  it('will not format a bare whole-dollar number: formatMinor(50) must not compile', () => {
    // THE CASE THIS PINS. `public.listings.buy_now_price` and `current_bid` are
    // WHOLE DOLLARS. Before the narrowing, `formatMinor(50)` type-checked and
    // returned "$0.50" — a 100x understatement on the conversion surface.
    // @ts-expect-error formatMinor takes Cents; a whole-dollar number is not one
    formatMinor(50);
    // @ts-expect-error the same hole via a variable, which is how it would really arrive
    formatMinor(listingPriceFromColumn);

    // The two readings of the literal 50, made explicit and both reachable only
    // through a converter that names which one you meant:
    expect(formatMinor(asCents(50))).toBe('$0.50'); //        fifty CENTS
    expect(formatMinor(centsFromDollars(50))).toBe('$50'); // fifty DOLLARS
  });

  it('will not take an asCents() cast on the resale rail: the last escape hatch is shut', () => {
    // `asCents` is an unchecked cast, so before this it was a tsc-clean route
    // straight back into the bug: baseMinor: asCents(50) quoted "$0.55".
    // @ts-expect-error the resale rail takes DollarDerivedCents — use centsFromDollars()
    allInPrice({ rail: 'marketplace', baseMinor: asCents(50) });
    // @ts-expect-error ...and a bare number is still not a price either
    allInPrice({ rail: 'marketplace', baseMinor: 50 });

    // The only correct spelling, and it is the one that reads right.
    const r = allInPrice({ rail: 'marketplace', baseMinor: centsFromDollars(50) });
    if (r.kind !== 'all-in') throw new Error('expected a price');
    expect(formatMinor(r.totalMinor)).toBe('$55');
    expect(r.totalMinor).toBe(5500);
  });

  it('keeps a named, greppable escape for a genuine minor-unit resale column', () => {
    // Closing the hole must not push a future caller to `as unknown as`, which
    // would defeat everything above. No such column exists today.
    const r = allInPrice({
      rail: 'marketplace',
      baseMinor: marketplaceCentsFromMinorColumn(5000),
    });
    expect(r).toMatchObject({ kind: 'all-in', totalMinor: 5500 });
  });

  it('leaves the direct rail able to carry the small cent amounts A5 introduced', () => {
    // Why no magnitude guard lives inside asCents: a 10% buyer fee on a $5 face
    // IS 50 cents. A heuristic that rejected two-digit values as "probably
    // dollars" would refuse correct money on exactly the field A5 added.
    const r = allInPrice({
      rail: 'direct',
      faceValueMinor: asCents(500),
      buyerServiceFee: { source: 'config-rate', bps: 1000 },
    });
    expect(r).toMatchObject({ kind: 'all-in', buyerServiceFeeMinor: 50, totalMinor: 550 });
    expect(formatMinor(asCents(50))).toBe('$0.50');
  });
});

describe('all-in pricing — display', () => {
  it('formats honestly: whole amounts stay clean, odd amounts keep cents', () => {
    expect(formatMinor(asCents(6000))).toBe('$60');
    expect(formatMinor(asCents(3922))).toBe('$39.22');
    expect(formatMinor(asCents(123456))).toBe('$1,234.56');
    expect(formatMinor(asCents(0))).toBe('$0');
    expect(formatMinor(asCents(99))).toBe('$0.99');
  });

  it('formats with integer math only, and refuses to print a non-price', () => {
    // Sign outside the symbol; a credit reads "-$60", never "$-60".
    expect(formatMinor(asCents(-6000))).toBe('-$60');
    expect(formatMinor(asCents(-99))).toBe('-$0.99');
    expect(formatMinor(asCents(-1))).toBe('-$0.01');
    // Negative zero is zero, and must not print as "-$0".
    expect(formatMinor(asCents(-0))).toBe('$0');
    expect(formatMinor(asCents(-4200), 'EUR')).toBe('-42 EUR');
    // A cent count that cannot be represented exactly is not a price.
    expect(formatMinor(asCents(1e23))).toBe('—');
    expect(formatMinor(asCents(12.5))).toBe('—');
    expect(formatMinor(asCents(-12.5))).toBe('—');
    expect(formatMinor(asCents(Number.NaN))).toBe('—');
    expect(formatMinor(asCents(Number.POSITIVE_INFINITY))).toBe('—');
    expect(formatMinor(asCents(Number.NEGATIVE_INFINITY))).toBe('—');
    // The untyped-JS backstop: the brand cannot reach a plain JS caller, so the
    // runtime guard must still refuse rather than print "$NaN" or "$null".
    expect(formatMinor(null as never)).toBe('—');
    expect(formatMinor(undefined as never)).toBe('—');
    expect(formatMinor('50' as never)).toBe('—');
    // Large amounts keep their separators and their exact cents, to the edge of
    // the exact-integer range in both directions.
    expect(formatMinor(asCents(1234567890))).toBe('$12,345,678.90');
    expect(formatMinor(asCents(100000000001))).toBe('$1,000,000,000.01');
    expect(formatMinor(asCents(Number.MAX_SAFE_INTEGER))).toBe('$90,071,992,547,409.91');
    expect(formatMinor(asCents(-Number.MAX_SAFE_INTEGER))).toBe('-$90,071,992,547,409.91');
    expect(formatMinor(asCents(4200), 'EUR')).toBe('42 EUR');
  });

  it('never renders a blank price: the ladder always yields a label', () => {
    expect(priceLadder({ lowestAllIn: allInPrice(directQuote(6000, 600)) })).toEqual({
      kind: 'from',
      label: 'From $66',
    });
    // A refusal must fall through the ladder, never surface as a price.
    expect(
      priceLadder({
        lowestAllIn: allInPrice({
          rail: 'direct',
          faceValueMinor: asCents(6000),
          buyerServiceFee: { source: 'unset' },
        }),
        lastSaleMinor: asCents(4200),
      }),
    ).toEqual({ kind: 'last-sale', label: 'Last sale $42' });
    expect(priceLadder({ lowestAllIn: null, lastSaleMinor: asCents(4200) }).kind).toBe('last-sale');
    expect(priceLadder({ lowestAllIn: null, lastSaleMinor: null }).label).toBe('Be the first to sell');
  });
});

describe('provenance', () => {
  it('labels the two kinds in plain language, with no internal jargon', () => {
    const direct = provenanceLabel('direct');
    const fan = provenanceLabel('marketplace_fixed');
    expect(direct.badge).toBe('Direct from event');
    expect(fan.badge).toBe('From a fan');
    for (const l of [direct, fan, provenanceLabel('marketplace_auction')]) {
      const text = `${l.badge} ${l.explanation}`.toLowerCase();
      for (const banned of ['rail', 'atom', 'primary', 'secondary', 'inventory batch', 'kernel']) {
        expect(text).not.toContain(banned);
      }
      // No customer-facing em dash anywhere.
      expect(text).not.toContain('—');
    }
  });

  it('reserves the brand tone for venue-direct inventory only', () => {
    expect(provenanceLabel('direct').tone).toBe('brand');
    expect(provenanceLabel('marketplace_fixed').tone).toBe('neutral');
    expect(provenanceLabel('marketplace_auction').tone).toBe('neutral');
  });

  it('defaults to marketplace when provenance is not positively established', () => {
    // Mislabelling a fan's ticket as venue-issued is the one error that matters.
    expect(inventoryKindOf({})).toBe('marketplace_fixed');
    expect(inventoryKindOf({ isVenuePrimarySale: undefined })).toBe('marketplace_fixed');
    expect(inventoryKindOf({ isVenuePrimarySale: false, listingMode: 'auction' })).toBe(
      'marketplace_auction',
    );
    expect(inventoryKindOf({ isVenuePrimarySale: true })).toBe('direct');
  });

  it('never labels a resale of a venue-issued ticket as venue-direct', () => {
    // The dangerous case: a fan resells a ticket the venue originally issued. If
    // the primary flag won, that auction would wear the brand-red official badge.
    expect(inventoryKindOf({ isVenuePrimarySale: true, listingMode: 'auction' })).toBe(
      'marketplace_auction',
    );
    expect(inventoryKindOf({ isVenuePrimarySale: true, listingMode: 'buy_now' })).toBe(
      'marketplace_fixed',
    );
  });

  it('sorts available direct inventory first, and sold-out direct last', () => {
    expect(provenanceSortWeight('direct', false)).toBeLessThan(
      provenanceSortWeight('marketplace_fixed', false),
    );
    expect(provenanceSortWeight('direct', true)).toBeGreaterThan(
      provenanceSortWeight('marketplace_auction', false),
    );
  });
});
