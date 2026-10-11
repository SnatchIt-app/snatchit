/**
 * tests/v3-poster-ratio.test.ts — the 4:5 poster direction as a CONTRACT, not a habit.
 *
 * Owner, 2026-09-24: event artwork is a 4:5 portrait poster across the consumer app; originals are
 * preserved; nothing is stretched or destructively re-cropped; a non-4:5 original is fitted whole
 * rather than losing flyer information. That is four separate promises, and three of them are
 * invisible in a screenshot — a frame can be the right shape while the REQUEST crops, and a crop
 * that removes a flyer's bottom line looks like a perfectly good poster unless you know what was
 * there. So each one is pinned at the place it can actually fail.
 *
 * Every absence here carries a positive control. An assertion that "no slot crops" is worthless if
 * the check cannot detect a slot that does, so each sweep is paired with a case that must fail it:
 * the non-poster slots for the ratio rule, a `resize=cover` slot for the fit rule, and a
 * deliberately height-less `transformUrl` call for the both-dimensions rule.
 */

import { beforeAll, describe, expect, it } from 'vitest';

import { readFileSync } from 'node:fs';
import { readdirSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

import { MEDIA_RADIUS, posterWidth, ROW_ART, ROW_ART_W } from '../src/lib/design/featureMetrics';
import { MEDIA_SLOTS, slotHeight, type MediaSlotName } from '../src/lib/media/slots';
import { resolveImage, transformUrl } from '../src/lib/media/url';
import * as v2 from '../src/theme/v2';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');

beforeAll(() => {
  process.env.EXPO_PUBLIC_SUPABASE_URL = 'https://example.supabase.co';
});

/** Every slot that carries EVENT ARTWORK, and so every slot the owner's direction governs. */
const POSTER_SLOTS = [
  'DISCOVERY_CARD',
  'FEATURED_EVENT',
  'EVENT_HERO',
  'EVENT_GALLERY',
  'CHECKOUT_THUMBNAIL',
  'TICKET_ART',
  'SEARCH_RESULT',
  'HOME_FEATURE_V3',
  'LISTING_HERO_V3',
  'FEED_ROW_ART',
] as const satisfies readonly MediaSlotName[];

/**
 * The slots that are deliberately NOT posters, each with the reason it is exempt. A reason is
 * recorded here rather than in a comment because the exemption list is the one place this contract
 * can be quietly widened: adding a slot here is how someone would opt an event image out of the
 * direction, and it should read as a claim that has to be true.
 */
const NOT_A_POSTER: Record<string, string> = {
  VENUE_HERO: 'a photograph of a room, not a poster — photography has no edge information to protect',
  DASHBOARD_THUMBNAIL: "the operator console (D's surface); no consumer screen renders it",
  PROMOTER_SHARE: 'a server-rendered share card at the square size the platforms crop to',
};

/** The frames the product actually lays out, so the request assertions test real boxes. */
const REAL_BOXES: Partial<Record<MediaSlotName, { w: number; h: number; why: string }>> = {
  FEED_ROW_ART: { w: ROW_ART_W, h: ROW_ART, why: 'feed/search row' },
  SEARCH_RESULT: { w: posterWidth(76), h: 76, why: 'my-listings row' },
  CHECKOUT_THUMBNAIL: { w: posterWidth(72), h: 72, why: 'checkout / order / bids row' },
  HOME_FEATURE_V3: { w: 393, h: Math.round(393 / v2.ratio.portrait), why: 'full-bleed at 393pt' },
  LISTING_HERO_V3: { w: 393, h: Math.round(393 / v2.ratio.portrait), why: 'full-bleed at 393pt' },
};

describe('the classification is exhaustive — a new slot cannot slip past the direction', () => {
  it('PC1: every slot is either a poster or a named exemption, never both and never neither', () => {
    const all = Object.keys(MEDIA_SLOTS).sort();
    const classified = [...POSTER_SLOTS, ...Object.keys(NOT_A_POSTER)].sort();
    expect(classified).toEqual(all);
    // No slot is in both lists, which is how a contradiction would hide.
    for (const n of POSTER_SLOTS) expect(NOT_A_POSTER[n]).toBeUndefined();
    // Every exemption states a reason rather than existing silently.
    for (const [n, why] of Object.entries(NOT_A_POSTER)) expect(why.length).toBeGreaterThan(20);
  });
});

describe('geometry — the frame is the poster shape everywhere it carries a poster', () => {
  it('PC2: every poster slot is 4:5 and FITTED, and the exempt slots are neither (control)', () => {
    for (const n of POSTER_SLOTS) {
      expect(MEDIA_SLOTS[n].aspectRatio, `${n} ratio`).toBe(v2.ratio.portrait);
      // `fit` is what makes the ratio non-destructive: it contains the whole poster and fills the
      // slack with a blurred copy of the same artwork. An on-ratio 4:5 source renders identically
      // under fit and cover, so this costs nothing where the shape already agrees.
      expect(MEDIA_SLOTS[n].defaultFit, `${n} fit`).toBe('fit');
    }
    // POSITIVE CONTROL for the sweep above: if these passed too, the assertion would be vacuous
    // (e.g. if someone made every slot portrait-fitted, including the venue photograph).
    for (const n of Object.keys(NOT_A_POSTER) as MediaSlotName[]) {
      expect(MEDIA_SLOTS[n].aspectRatio, `${n} must not be a poster`).not.toBe(v2.ratio.portrait);
      expect(MEDIA_SLOTS[n].defaultFit, `${n} must not be fitted`).toBe('cover');
    }
  });

  it('PC3: radius follows the role — media 8, full-bleed and parent-clipped 0', () => {
    const FULL_BLEED_OR_CLIPPED: MediaSlotName[] = [
      'HOME_FEATURE_V3', 'LISTING_HERO_V3', 'EVENT_HERO', 'TICKET_ART',
    ];
    for (const n of POSTER_SLOTS) {
      const expected = FULL_BLEED_OR_CLIPPED.includes(n) ? v2.radius.none : MEDIA_RADIUS;
      expect(MEDIA_SLOTS[n].radius, `${n} radius`).toBe(expected);
    }
    // The two roles are genuinely different values, or the table above asserts nothing.
    expect(MEDIA_RADIUS).toBeGreaterThan(v2.radius.none);
  });

  it('PC4: the frame holds its shape at every real device width, to within a point', () => {
    for (const w of [375, 390, 393, 402, 430]) {
      const h = Math.round(w / v2.ratio.portrait);
      expect(Math.abs(w / h - v2.ratio.portrait)).toBeLessThan(0.002);
    }
    /*
     * The row slots' REFERENCE box, and the one place to be precise rather than tidy: a 4:5 box
     * with whole-point edges cannot always round-trip. posterWidth(62) is 50, and 50 / 0.8 is 62.5,
     * which rounds to 63 — so the reference height for the feed row comes back a point taller than
     * the 62 the row budgets. SEARCH_RESULT happens to round-trip exactly (51 / 0.8 = 63.75 → 64).
     *
     * This costs nothing where it matters, because it only describes a caller that passes NEITHER
     * edge. Every real consumer passes the height, and EventMedia uses a caller-given height
     * verbatim instead of re-deriving it from the rounded width — which is exactly why it does.
     * So the assertion is: the reference is within a point, and the RENDERED box is exact.
     */
    expect(Math.abs(slotHeight('FEED_ROW_ART', 'mobile') - ROW_ART)).toBeLessThanOrEqual(1);
    expect(slotHeight('SEARCH_RESULT', 'mobile')).toBe(64);
    // A point of rounding noise is the tolerance; a landscape reference is not. 62 wide would be
    // 78 tall, the shape this direction rejected, and that would fail the assertion above.
    expect(slotHeight('FEED_ROW_ART', 'mobile')).toBeLessThan(70);
    // The rendered box is exact, from the component's own rule.
    const media = read('src/components/media/EventMedia.tsx');
    expect(media).toContain('!fluid && height != null ? height');
  });
});

describe('the request — where a crop would actually happen, unseen', () => {
  const LEGACY = { path: 'uuid/covers/1715000000000.jpg', contract: 'legacy' as const };

  it('PC5: every poster request carries BOTH dimensions, in the frame\'s own proportions', () => {
    for (const n of POSTER_SLOTS) {
      const box = REAL_BOXES[n] ?? {
        w: MEDIA_SLOTS[n].layoutWidth.mobile,
        h: slotHeight(n, 'mobile'),
        why: 'slot reference box',
      };
      const r = resolveImage(LEGACY, n, { layoutWidth: box.w, layoutHeight: box.h, devicePixelRatio: 2 });
      expect(r.kind, `${n} resolves`).toBe('image');
      if (r.kind !== 'image') continue;
      const q = new URL(r.uri).searchParams;
      // A width-only request returned a 56x1176 sliver against this project (B's measurement), and
      // a sliver LOADS — so no onError fires and the fallback never engages. The missing height is
      // therefore invisible to every guard we have, which is why it is asserted here.
      expect(q.get('height'), `${n} sends a height`).toBeTruthy();
      expect(q.get('width'), `${n} sends a width`).toBeTruthy();
      const asked = Number(q.get('width')) / Number(q.get('height'));
      expect(asked, `${n} asks for the frame's shape (${box.why})`).toBeCloseTo(box.w / box.h, 1);
      // `contain` is what makes the SERVER unable to crop: it fits the whole asset in the box.
      expect(q.get('resize'), `${n} never asks the server to crop`).toBe('contain');
    }
  });

  it('PC6: the both-dimensions check can fail — a height-less URL has no height (control)', () => {
    const bare = transformUrl({
      base: 'https://example.supabase.co/storage/v1',
      bucket: 'auction-media',
      path: 'a/b.jpg',
      width: 100,
      quality: 45,
      resize: 'contain',
    });
    expect(bare).not.toMatch(/[?&]height=/);
    // And the resize control: a non-poster slot is the one place `cover` is still correct, so the
    // "never asks the server to crop" assertion above is discriminating rather than universal.
    const photo = resolveImage(LEGACY, 'VENUE_HERO', { layoutWidth: 393, layoutHeight: 221, devicePixelRatio: 2 });
    expect(photo.kind).toBe('image');
    if (photo.kind === 'image') expect(new URL(photo.uri).searchParams.get('resize')).toBe('cover');
  });

  it('PC7: the blurred backdrop is sized too, or the blur smears one column of pixels', () => {
    const r = resolveImage(LEGACY, 'LISTING_HERO_V3', { layoutWidth: 393, layoutHeight: 491, devicePixelRatio: 2 });
    expect(r.kind).toBe('image');
    if (r.kind !== 'image') return;
    const q = new URL(r.backdropUri).searchParams;
    expect(q.get('width')).toBe('32');
    expect(q.get('height')).toBeTruthy();
    // The backdrop is deliberately CROPPED to the frame — it exists to fill the slack behind a
    // fitted poster — which is the one place `cover` is right on a poster slot.
    expect(q.get('resize')).toBe('cover');
  });

  it('PC8: a legacy 16:9 asset is FITTED in a poster slot, never re-cropped', () => {
    for (const n of POSTER_SLOTS) {
      const r = resolveImage(LEGACY, n, { layoutWidth: 100, layoutHeight: 125, devicePixelRatio: 2 });
      if (r.kind !== 'image') continue;
      expect(r.fit, `${n} fits legacy artwork`).toBe('fit');
    }
    // Even when a caller explicitly asks to crop one: those portrait pixels never existed, so the
    // request cannot be honoured without cutting the flyer. The resolver overrides the caller.
    const forced = resolveImage({ ...LEGACY, fit: 'cover' }, 'FEED_ROW_ART', { layoutWidth: ROW_ART_W, layoutHeight: ROW_ART });
    expect(forced.kind).toBe('image');
    if (forced.kind === 'image') expect(forced.fit).toBe('fit');
  });
});

describe('the missing-artwork plate keeps the poster geometry', () => {
  it('PC9: the fallback branch renders the SAME frame object as the image branch', () => {
    // Geometry parity cannot be asserted from the resolver (a fallback has no box), and the
    // component is effect-bound, so it is pinned at the source: one `frame` is computed from the
    // slot and both branches spread the identical style array. A plate in a different box would
    // shift every row the moment an image failed to load.
    const src = read('src/components/media/EventMedia.tsx')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    const frames = src.match(/style=\{\[frame, styles\.edge, style\]\}/g) ?? [];
    expect(frames.length).toBe(2);
    expect(src).toContain('<FallbackPlate');
    // The plate fills the frame rather than sizing itself.
    expect(src).toMatch(/height: boxHeight/);
  });
});

describe('no screen owns a poster edge', () => {
  it('PC10: the 4:5 arithmetic lives in the media layer, and nowhere else', () => {
    const OWNS_THE_RATIO = ['src/lib/media/slots.ts', 'src/lib/media/url.ts', 'src/theme/v2.ts', 'src/lib/design/featureMetrics.ts'];
    const files: string[] = [];
    const walk = (dir: string) => {
      for (const e of readdirSync(resolve(root, dir))) {
        const rel = join(dir, e);
        if (statSync(resolve(root, rel)).isDirectory()) walk(rel);
        else if (/\.tsx?$/.test(e)) files.push(rel);
      }
    };
    walk('app');
    walk('src');

    const offenders: string[] = [];
    for (const f of files) {
      if (OWNS_THE_RATIO.includes(f)) continue;
      const body = read(f);
      // A numeric aspect ratio, or the poster ratio spelled out by hand. Reading it from a token or
      // from MEDIA_SLOTS is the sanctioned form and is not matched.
      for (const m of body.matchAll(/aspectRatio:\s*([\d.]+\s*(?:\/\s*[\d.]+)?)\s*[,}]/g)) offenders.push(`${f}: aspectRatio: ${m[1]}`);
      for (const m of body.matchAll(/(?<![\w.])4\s*\/\s*5(?![\w])/g)) offenders.push(`${f}: 4 / 5 (${m.index})`);
    }
    expect(offenders).toEqual([]);

    // POSITIVE CONTROL: the scan must be able to see the ratio where it legitimately lives, or an
    // empty offender list proves only that the walk found nothing.
    expect(read('src/theme/v2.ts')).toMatch(/portrait:\s*4\s*\/\s*5/);
    expect(files.length).toBeGreaterThan(100);
    expect(files).toContain(join('src', 'components', 'media', 'EventMedia.tsx'));
  });
});
