/**
 * N2 — a listing the viewer can no longer read says so plainly, on every screen that reads one by id.
 *
 * Migration 154 (A) hides legacy listings from anyone who did not take part in them: their reads now
 * come back with zero rows and no error. A zero-row read cannot tell "hidden", "deleted" and "never
 * existed" apart, so the words don't either. Before this change: ListingDetail said "Listing not found"
 * (fine, kept graceful), PlaceBid's `.single()` turned zero rows into PGRST116 → "Couldn't load this"
 * with a Retry that can never succeed, and the edit route showed PostgREST's own sentence.
 * Source contracts + the real PlaceBid screen through the hook harness. Not device evidence.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { LISTING_UNAVAILABLE_COPY } from '../src/lib/listing/unavailable';

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const read = (p: string) => strip(readFileSync(resolve(__dirname, '..', p), 'utf8'));

describe('N2 — the words', () => {
  it('U1: one module owns them; they claim nothing the read cannot know', () => {
    expect(LISTING_UNAVAILABLE_COPY).toEqual({
      title: 'No longer available',
      body: 'This listing may have ended, sold or been removed.',
      action: 'Browse live listings',
    });
  });
});

describe('N2 — ListingDetail', () => {
  const d = read('src/screens/ListingDetailScreen.tsx');
  it('U2: the no-row branch uses the shared copy and still routes to the live feed (CFT-605)', () => {
    const at = d.indexOf('if (!listing) return (');
    expect(at).toBeGreaterThan(-1);
    const block = d.slice(at, d.indexOf('/>', at));
    expect(block).toContain('title={LISTING_UNAVAILABLE_COPY.title}');
    expect(block).toContain('body={LISTING_UNAVAILABLE_COPY.body}');
    expect(block).toContain("action={{ label: LISTING_UNAVAILABLE_COPY.action, onPress: () => router.replace('/(tabs)/home') }}");
    expect(d).not.toContain('Listing not found');
  });
  it('U3: the read that decides it is still maybeSingle (zero rows = no row, not an error)', () => {
    expect(d).toMatch(/from\('listings'\)\s*\.select\('\*'\)\s*\.eq\('id', id\)\s*\.maybeSingle\(\)/);
  });
});

describe('N2 — edit route', () => {
  it('U4: a zero-row read is the plain not-found refusal, never PostgREST text', () => {
    const e = read('app/listing/edit/[id].tsx');
    expect(e).toContain(".from('listings').select('*').eq('id', listingId).maybeSingle()");
    expect(e).not.toMatch(/\.eq\('id', listingId\)\.single\(\)/);
  });
});

describe('N2 — PlaceBid', () => {
  it('U5: the bid screen reads with maybeSingle — .single() turns zero rows into PGRST116, an error', () => {
    const b = read('src/screens/PlaceBidScreen.tsx');
    expect(b).toMatch(/\.eq\('id', id\)\s*\.maybeSingle\(\);/);
    expect(b).not.toMatch(/\.eq\('id', id\)\s*\.single\(\);/);
  });
});
