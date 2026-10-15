/**
 * RC9 independent review (2026-10-15) — fixes for N3-1, N2-1 and T4. Pure helpers + source contracts.
 * Not device evidence.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { cameToForeground } from '../src/lib/ui/appForeground';
import { EDIT_REFUSAL_COPY } from '../src/lib/listing/editAccess';
import { LISTING_UNAVAILABLE_COPY } from '../src/lib/listing/unavailable';

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const read = (p: string) => strip(readFileSync(resolve(__dirname, '..', p), 'utf8'));

describe('T4 — one rule for "the app came back"', () => {
  it('F1: background or inactive → active is a return; anything else is not', () => {
    expect(cameToForeground('background', 'active')).toBe(true);
    expect(cameToForeground('inactive', 'active')).toBe(true);
    expect(cameToForeground('active', 'active')).toBe(false);       // e.g. a notification banner
    expect(cameToForeground('active', 'background')).toBe(false);
    expect(cameToForeground('background', 'inactive')).toBe(false);
    expect(cameToForeground(null, 'active')).toBe(false);
  });
  it('F2: Home and the listing read the PREVIOUS state before recording the new one', () => {
    for (const p of ['app/(tabs)/home.tsx', 'src/screens/ListingDetailScreen.tsx']) {
      const src = read(p);
      expect(src, p).toMatch(/const cameBack = cameToForeground\(appStateRef\.current, next\);\s*appStateRef\.current = next;/);
    }
    expect(read('src/screens/ListingDetailScreen.tsx')).toMatch(/if \(cameBack && initialLoadDone\.current\) void fetchDataRef\.current\(true\);/);
  });
});

describe('N3-1 — a quiet re-read that fails never turns into "No longer available"', () => {
  const d = read('src/screens/ListingDetailScreen.tsx');
  it('F3: only a visible load clears the error before the read; the answer clears it after', () => {
    expect(d).toMatch(/if \(!silent\) \{ setLoading\(true\); setError\(null\); \}\s*const listingRes = await supabase/);
    expect(d).toMatch(/if \(listingRes\.data === null\) \{ setError\(null\); setListing\(null\); setLoading\(false\); return; \}/);
    expect(d).toMatch(/const fetchedListing = listingRes\.data as Listing;\s*setError\(null\);\s*setListing\(fetchedListing\);/);
  });
});

describe('N2-1 — the edit route uses the same "no longer available" words for zero rows', () => {
  it('F4: the not-found refusal is the shared copy', () => {
    expect(EDIT_REFUSAL_COPY['not-found']).toEqual({ title: LISTING_UNAVAILABLE_COPY.title, body: LISTING_UNAVAILABLE_COPY.body });
  });
});
