/**
 * V3 — word-boundary truncation (§2, acceptance 3) and the scrim curve (§3), pure halves.
 * Device rendering of both is a separate check; these pin the values and the trimming rule.
 */
import { describe, expect, it, vi } from 'vitest';

vi.mock('react-native', () => ({ Text: 'Text', StyleSheet: { create: <T,>(x: T) => x } }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}) }));

import { trimToWordBoundary } from '@/src/components/NameText';
import { scrimAlpha, scrimStops } from '@/src/lib/design/scrim';

describe('trimToWordBoundary — a cut name ends with … on a word boundary', () => {
  it('N1: a name that fits is left alone', () => {
    expect(trimToWordBoundary('MIDNIGHT ARCADE', ['MIDNIGHT ARCADE'], 2)).toBeNull();
    expect(trimToWordBoundary('the lot radio x nowadays', ['the lot radio x ', 'nowadays'], 2)).toBeNull();
  });

  it('N2: overflow trims back to the last WHOLE word that fits, then …', () => {
    // Three rendered lines against a 2-line cap; the visible prefix ends mid-phrase.
    expect(
      trimToWordBoundary(
        'Midnight Arcade presents The Foundry Warehouse Sessions',
        ['Midnight Arcade presents ', 'The Foundry ', 'Warehouse Sessions'],
        2,
      ),
    ).toBe('Midnight Arcade presents The Foundry…');
  });

  it('N3: never a mid-word cut, and trailing separators are swept before the ellipsis', () => {
    const out = trimToWordBoundary('Björk: Cornucopia — extended orchestral evening', ['Björk: Cornucopia — ', 'extended ', 'orchestral evening'], 2);
    expect(out).toBe('Björk: Cornucopia — extended…');
    expect(out).not.toMatch(/[ ,;:·—-]…$/u);   // no dangling separator before the ellipsis
  });

  it('N4: a single unbroken 66+ character word still ends with …, one character shy of the cut', () => {
    const long = 'A'.repeat(70);
    const out = trimToWordBoundary(long, [long.slice(0, 30), long.slice(30, 60), long.slice(60)], 2);
    expect(out).toBe(`${long.slice(0, 59)}…`);
  });
});

describe('scrimAlpha — the approved curve, floor first', () => {
  it('S1: the 0.20 floor is reached by t = 0.30 and eases in from 0 with no seam', () => {
    expect(scrimAlpha(0)).toBe(0);
    expect(scrimAlpha(0.15)).toBeCloseTo(0.2 * 0.5, 5);   // smoothstep midpoint
    expect(scrimAlpha(0.3)).toBeCloseTo(0.2, 5);
  });

  it('S2: linear from the floor to 0.97 at the baseline', () => {
    expect(scrimAlpha(0.65)).toBeCloseTo(0.2 + 0.77 * 0.5, 5);
    expect(scrimAlpha(1)).toBeCloseTo(0.97, 5);
  });

  it('S3: monotonic and clamped — no band can invert', () => {
    let prev = -1;
    for (let i = 0; i <= 100; i++) {
      const a = scrimAlpha(i / 100);
      expect(a).toBeGreaterThanOrEqual(prev);
      prev = a;
    }
    expect(scrimAlpha(-1)).toBe(0);
    expect(scrimAlpha(2)).toBeCloseTo(0.97, 5);
  });

  it('S4: the stops sample the curve densely enough to hide the knee', () => {
    const stops = scrimStops();
    expect(stops.length).toBeGreaterThanOrEqual(15);
    expect(stops[0]).toEqual({ position: 0, color: 'rgba(0,0,0,0.0000)' });
    expect(stops[stops.length - 1].color).toBe('rgba(0,0,0,0.9700)');
  });
});

describe('row clearance (§3)', () => {
  it('R1: the feed row keeps ROW_META_CLEARANCE under its metadata, from the shared constant (source pin)', async () => {
    const { readFileSync } = await import('node:fs');
    const card = readFileSync('src/components/discovery/DiscoveryCard.tsx', 'utf8');
    expect(card).toContain('paddingBottom: ROW_META_CLEARANCE');
    const metrics = readFileSync('src/lib/design/rowMetrics.ts', 'utf8');
    expect(metrics).toContain('export const ROW_META_CLEARANCE = 12;');
    expect(card).not.toMatch(/height: \d+/);   // content-driven: no hard-coded row height
  });
});

