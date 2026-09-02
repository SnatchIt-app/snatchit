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
import { allInPrice, formatMinor, priceLadder } from '../src/lib/pricing/allIn';
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
    // A destructive action must not share a color with a primary action.
    expect(t.status.error).not.toBe(t.brand.red);
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
    expect(legacy.uri).toContain('resize=contain');
  });

  it('crops v2 portrait assets, which were uploaded for this frame', () => {
    const v2asset = resolveImage(
      { path: 'covers/new.jpg', contract: 'v2', fit: 'cover' },
      'DISCOVERY_CARD',
    );
    expect(v2asset.kind).toBe('image');
    if (v2asset.kind !== 'image') return;
    expect(v2asset.fit).toBe('cover');
    expect(v2asset.uri).toContain('resize=cover');
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

describe('all-in pricing', () => {
  it('adds the buyer fee on the marketplace rail', () => {
    const r = allInPrice({ rail: 'marketplace', baseMinor: 5000 });
    expect(r).toEqual({ kind: 'all-in', totalMinor: 5500, currency: 'USD', rail: 'marketplace' });
  });

  it('uses the server total verbatim on the direct rail', () => {
    // The client must never sum tiers itself; the server is the price authority.
    const r = allInPrice({ rail: 'direct', serverTotalMinor: 6000 });
    expect(r).toEqual({ kind: 'all-in', totalMinor: 6000, currency: 'USD', rail: 'direct' });
  });

  it('refuses to quote rather than guessing when inputs are absent', () => {
    expect(allInPrice({ rail: 'marketplace', baseMinor: null }).kind).toBe('unavailable');
    expect(allInPrice({ rail: 'direct', serverTotalMinor: undefined }).kind).toBe('unavailable');
    expect(allInPrice({ rail: 'marketplace', baseMinor: 12.5 as unknown as number }).kind).toBe(
      'unavailable',
    );
  });

  it('refuses when tax would apply, because no schema models tax', () => {
    // Showing "all-in" while a tax is coming later would be a lie.
    const r = allInPrice({ rail: 'direct', serverTotalMinor: 6000, taxApplies: true });
    expect(r).toEqual({ kind: 'unavailable', reason: 'tax-unmodelled' });
  });

  it('formats honestly: whole amounts stay clean, odd amounts keep cents', () => {
    expect(formatMinor(6000)).toBe('$60');
    expect(formatMinor(3922)).toBe('$39.22');
    expect(formatMinor(123456)).toBe('$1,234.56');
  });

  it('never renders a blank price: the ladder always yields a label', () => {
    expect(priceLadder({ lowestAllIn: allInPrice({ rail: 'direct', serverTotalMinor: 6000 }) }).kind).toBe('from');
    expect(priceLadder({ lowestAllIn: null, lastSaleMinor: 4200 }).kind).toBe('last-sale');
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
    expect(inventoryKindOf({ isDirect: undefined })).toBe('marketplace_fixed');
    expect(inventoryKindOf({ isDirect: false, listingMode: 'auction' })).toBe('marketplace_auction');
    expect(inventoryKindOf({ isDirect: true })).toBe('direct');
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
