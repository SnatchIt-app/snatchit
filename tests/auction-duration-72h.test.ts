/**
 * N4 — sellers can choose a 72-hour auction (owner, via A, 2026-10-15: add 72 h, keep 1/3/6/12/24/48).
 *
 * Migration 155 widens listings_duration_hours_check to {1,3,6,12,24,48,72} and stamps
 * ends_at := now() + duration_hours server-side on untrusted inserts (A). The app keeps sending ends_at;
 * the server value wins. Old builds already render a 72 h listing: every clock derives from ends_at.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { DURATION_OPTIONS, durationLabel } from '../src/lib/sell/durations';
import { countdownLabel } from '../src/lib/listing/cardState';
import { timeLeftLabel } from '../src/lib/listing/sellerListing';

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('N4 — the 72 h option', () => {
  it('D1: 72 is offered after the existing six, which stay', () => {
    expect(DURATION_OPTIONS).toEqual([1, 3, 6, 12, 24, 48, 72]);
  });
  it('D2: the chip reads "3d"; the others keep their labels', () => {
    expect(DURATION_OPTIONS.map(durationLabel)).toEqual(['1h', '3h', '6h', '12h', '1d', '2d', '3d']);
  });
  it('D3: the sell screen renders the shared options and labels (no local copy of the list)', () => {
    const src = strip(readFileSync(resolve(__dirname, '..', 'src/screens/CreateListingScreen.tsx'), 'utf8'));
    expect(src).toContain('DURATION_OPTIONS.map((h) => (');
    expect(src).toContain('label={durationLabel(h)}');
    expect(src).not.toMatch(/const DURATION_OPTIONS/);
  });
  it('D4: a 72 h listing\'s clocks read correctly (already true on old builds)', () => {
    const now = Date.parse('2026-10-15T12:00:00Z');
    const endsAt = new Date(now + 72 * 3_600_000).toISOString();
    expect(countdownLabel(endsAt, now)).toBe('3d 0h left');
    expect(timeLeftLabel(endsAt, now)).toBe('3d 0h left');
  });
});
