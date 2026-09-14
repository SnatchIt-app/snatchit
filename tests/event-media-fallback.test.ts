/**
 * tests/event-media-fallback.test.ts — stable imagery (CFT-106).
 *
 * EventMedia reserved the frame and drew a branded plate when there was no
 * path, but a URL that FAILED to load left the frame blank: no onError handling
 * existed. And the seller's My Listings row bypassed EventMedia with a raw
 * expo-image, so it had no frame, no fallback and no slot-sized derivative.
 *
 * The resolver is pure and driven directly; the component is effect-bound
 * (layout measurement, image events), so its failure handling is guarded from
 * the shipped source, the way the other media guards in this suite work.
 */

import { beforeAll, describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { resolveImage } from '../src/lib/media/url';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const code = (rel: string) =>
  read(rel)
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');

beforeAll(() => {
  process.env.EXPO_PUBLIC_SUPABASE_URL = 'https://example.supabase.co';
});

describe('resolution — a renderable URL is a render URL, so failure is a load event', () => {
  it('resolves the seller thumbnail to the transformation endpoint, not the raw object', () => {
    // This is the URL the sandbox answers with 400 for fixture paths. The
    // resolver cannot know that; the component has to handle the failure.
    const r = resolveImage({ path: 'uuid/covers/1715000000000.jpg', contract: 'legacy' }, 'SEARCH_RESULT', {
      layoutWidth: 76,
      devicePixelRatio: 2,
    });
    expect(r.kind).toBe('image');
    if (r.kind !== 'image') return;
    expect(r.uri).toMatch(/\/storage\/v1\/render\/image\/public\/auction-media\//);
    expect(r.width).toBe(152);
    expect(r.height).toBe(152);
  });

  it('still reports a missing path as a fallback before any request is made', () => {
    expect(resolveImage({ path: null }, 'SEARCH_RESULT').kind).toBe('fallback');
  });
});

describe('EventMedia — a failed load falls back in the same frame', () => {
  const src = code('src/components/media/EventMedia.tsx');

  it('handles onError on the artwork image', () => {
    expect(src).toMatch(/onError=\{\(\) => setFailedUri\(resolved\.uri\)\}/);
  });

  it('keys the failure by URI so a recycled row starts clean', () => {
    expect(src).toMatch(/const \[failedUri, setFailedUri\] = useState<string \| null>\(null\)/);
    expect(src).toMatch(/const failed = resolved\.kind === 'image' && failedUri === resolved\.uri/);
  });

  it('routes the failure into the existing designed fallback, not a new branch', () => {
    expect(src).toMatch(/if \(resolved\.kind === 'fallback' \|\| failed\) \{/);
    // One plate. The failure path renders the same FallbackPlate inside the same
    // `frame` style, so nothing changes size and nothing flashes.
    expect(src.match(/<FallbackPlate /g) ?? []).toHaveLength(1);
    expect(src.match(/<View style=\{\[frame, styles\.edge, style\]\}/g) ?? []).toHaveLength(2);
  });

  it('keeps the recycling key, caching and priority behaviour', () => {
    expect(src).toContain('recyclingKey={resolved.uri}');
    expect(src).toContain('recyclingKey={`${resolved.backdropUri}:bg`}');
    expect(src.match(/cachePolicy="memory-disk"/g) ?? []).toHaveLength(2);
    expect(src).toContain("priority={spec.preload ? 'high' : 'normal'}");
  });
});

describe('SellerListingCard — the cover goes through EventMedia', () => {
  const src = code('src/components/SellerListingCard.tsx');
  const screen = code('app/my-listings.tsx');

  it('imports EventMedia and no raw Image', () => {
    expect(src).toContain("import { EventMedia } from '@/src/components/media/EventMedia'");
    expect(src).not.toMatch(/from 'expo-image'/);
    expect(src).not.toMatch(/<Image[\s>]/);
  });

  it('uses a square slot at the row\'s own edge, on the raw stored path', () => {
    expect(src).toMatch(/slot="SEARCH_RESULT"/);
    expect(src).toMatch(/width=\{THUMB\}/);
    expect(src).toMatch(/const THUMB = 76;/);
    expect(src).toMatch(/asset=\{\{ path: listing\.cover_image_path, contract: 'legacy', bucket: 'auction-media' \}\}/);
    // No hand-built URL and no pre-resolved one: the card no longer takes a coverUrl.
    expect(src).not.toMatch(/coverUrl/);
    expect(screen).not.toMatch(/coverUrl|getCoverImageUrl/);
  });

  it('keeps its single spoken label', () => {
    expect(src).toContain('accessibilityLabel={a11yLabel}');
  });
});
