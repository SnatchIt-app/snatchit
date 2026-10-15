/**
 * N3 — a list fetched before legacy listings were hidden does not stay on screen.
 *
 * Builds 25/27: Home loaded Recently sold and Ended ONCE per session (`!soldLoadedOnce` /
 * `!endedLoadedOnce` gates), the focus refetch re-read only the live feed, nothing listened for the app
 * returning to the foreground, and a non-participant never receives the realtime UPDATE that hides a
 * row (RLS is checked against the new row). So a phone left open kept showing hidden listings in Sold
 * and Ended until a pull-to-refresh or a relaunch — and a ListingDetail open at the moment of hiding
 * kept its Bid / Buy now actions until refocus. Pure plan + source pins. Not device evidence.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { homeReadsFor } from '../src/lib/home/refreshPlan';

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const read = (p: string) => strip(readFileSync(resolve(__dirname, '..', p), 'utf8'));

describe('homeReadsFor', () => {
  it('R1: selecting Sold or Ended reads that dataset EVERY time, not just the first', () => {
    expect(homeReadsFor('chip_selected', 'recently_sold')).toEqual(['recently_sold']);
    expect(homeReadsFor('chip_selected', 'ended')).toEqual(['ended']);
    expect(homeReadsFor('chip_selected', 'buy_now')).toEqual([]);   // the live feed is already loaded and filtered locally
  });
  it('R2: returning to Home or to the app re-reads the live feed AND the dataset on screen', () => {
    for (const t of ['focus', 'foreground'] as const) {
      expect(homeReadsFor(t, 'all')).toEqual(['live']);
      expect(homeReadsFor(t, 'recently_sold')).toEqual(['live', 'recently_sold']);
      expect(homeReadsFor(t, 'ended')).toEqual(['live', 'ended']);
    }
  });
});

describe('wiring', () => {
  const home = read('app/(tabs)/home.tsx');
  const detail = read('src/screens/ListingDetailScreen.tsx');
  it('R3: chip selection is no longer gated on a first load', () => {
    expect(home).not.toMatch(/!soldLoadedOnce\.current\)\s*fetchSoldListings/);
    expect(home).not.toMatch(/!endedLoadedOnce\.current\)\s*fetchEndedListings/);
    expect(home).toMatch(/runHomeReads\(homeReadsFor\('chip_selected', next\.chip\)\)/);
  });
  it('R4: focus and foreground both run the plan for the chip on screen', () => {
    expect(home).toMatch(/runHomeReads\(homeReadsFor\('focus', chipRef\.current\)\)/);
    expect(home).toMatch(/AppState\.addEventListener\('change'[\s\S]{0,300}runHomeReads\(homeReadsFor\('foreground', chipRef\.current\)\)/);
  });
  it('R5: an open listing re-reads when the app returns to the foreground', () => {
    expect(detail).toMatch(/AppState\.addEventListener\('change'[\s\S]{0,300}fetchDataRef\.current\(true\)/);
  });
});
