/**
 * V3 home/search stage — the pure halves (§3 layout formulas, §5 row vocabulary, the CSS scrim).
 *
 * The §3 heights are FORMULAS, not constants: hard-coding 205/266 is exactly what the package
 * forbids. The row vocabulary is the §5 approved copy plus the mockup's clock forms; the one
 * inference (the same-day boundary between "2h 14m left" and "Ends Sat 20:30") is flagged in the
 * backlog for B. Rendering truth on device is acceptance 3–6/13; these pin the values.
 */
import { describe, expect, it } from 'vitest';

import {
  FEATURE_GUTTER,
  FEATURE_NAME_BLOCK_BOTTOM,
  FEATURE_META1_BELOW_NAME,
  FEATURE_META2_BELOW_NAME,
  featureHeight,
  heroHeight,
  HERO_DATE_BOTTOM,
  HERO_NAME_GAP,
  ROW_ART,
  ROW_ART_RADIUS,
  ROW_GUTTER,
} from '@/src/lib/design/featureMetrics';
import { scrimBackgroundImage } from '@/src/lib/design/scrim';
import {
  clockLabel,
  featureMetaLine,
  priceCaption,
  rowMeta,
  rowWhenLabel,
} from '@/src/lib/listing/feedRowState';

describe('featureMetrics — §3 formulas, never constants', () => {
  it('M1: feature height follows (w − 40) × 0.49 + 34 at every width', () => {
    expect(featureHeight(390)).toBeCloseTo(205.5, 5);
    expect(featureHeight(375)).toBeCloseTo((375 - 40) * 0.49 + 34, 5);
    expect(featureHeight(430)).toBeCloseTo((430 - 40) * 0.49 + 34, 5);
  });

  it('M2: hero height follows w × 0.62 + 24', () => {
    expect(heroHeight(390)).toBeCloseTo(265.8, 5);
    expect(heroHeight(320)).toBeCloseTo(320 * 0.62 + 24, 5);
  });

  it('M3: the §3 constants are the drawn values', () => {
    expect(FEATURE_GUTTER).toBe(20);
    expect(FEATURE_NAME_BLOCK_BOTTOM).toBe(44);
    expect(FEATURE_META1_BELOW_NAME).toBe(2);
    expect(FEATURE_META2_BELOW_NAME).toBe(19);
    expect(HERO_DATE_BOTTOM).toBe(78);
    expect(HERO_NAME_GAP).toBe(19);
    expect(ROW_ART).toBe(62);
    expect(ROW_ART_RADIUS).toBe(8);
    expect(ROW_GUTTER).toBe(20);
  });
});

describe('scrimBackgroundImage — the approved curve as a CSS gradient (no native module)', () => {
  it('C1: full-height linear gradient, 15 stops, 0 at the top and 0.97 at the baseline', () => {
    const css = scrimBackgroundImage();
    expect(css.startsWith('linear-gradient(to bottom, rgba(0,0,0,0.0000) 0%')).toBe(true);
    expect(css.endsWith('rgba(0,0,0,0.9700) 100%)')).toBe(true);
    expect(css.match(/rgba/g)?.length).toBe(15);
  });

  it('C2: the floor is inside the string — the stop nearest t=0.30 carries ≈0.20 alpha', () => {
    // 15 stops step by 1/14; stop 4 sits at t≈0.286, alpha 0.2·smoothstep(0.952)≈0.1987.
    const css = scrimBackgroundImage();
    expect(css).toContain('rgba(0,0,0,0.1987)');
  });
});

describe('feedRowState — §5 vocabulary', () => {
  it('W1: rowWhenLabel is locale-independent: "Sat 26 Sep · 21:00"', () => {
    expect(rowWhenLabel('2026-09-26', '21:00:00')).toBe('Sat 26 Sep · 21:00');
    expect(rowWhenLabel('2026-10-30', '21:30')).toBe('Fri 30 Oct · 21:30');
    expect(rowWhenLabel('not-a-date', '21:00')).toBe('');
  });

  it('R1: meta lines — date · time · venue, then qty × type · bids', () => {
    const m = rowMeta({
      eventDate: '2026-09-26', eventTime: '22:00:00', venue: 'The Foundry',
      quantity: 2, ticketType: 'GA', bidCount: 11,
    });
    expect(m.meta1).toBe('Sat 26 Sep · 22:00 · The Foundry');
    expect(m.meta2).toBe('2 × GA · 11 bids');
  });

  it('R2: zero bids says "no bids yet" — never "0 bids"; one bid is singular', () => {
    expect(rowMeta({ eventDate: '2026-09-26', eventTime: '22:00', venue: 'V', quantity: 1, ticketType: 'GA', bidCount: 0 }).meta2)
      .toBe('1 × GA · no bids yet');
    expect(rowMeta({ eventDate: '2026-09-26', eventTime: '22:00', venue: 'V', quantity: 1, ticketType: 'VIP', bidCount: 1 }).meta2)
      .toBe('1 × VIP · 1 bid');
  });

  it('K1: under 15 minutes → "Ending in 11m", urgent (amber is the §5 rule)', () => {
    const now = Date.parse('2026-09-22T20:00:00');
    const ends = new Date(now + 11 * 60_000).toISOString();
    expect(clockLabel(ends, now)).toEqual({ text: 'Ending in 11m', urgent: true });
  });

  it('K2: same local day, 15m or more → "2h 14m left", not urgent', () => {
    const now = Date.parse('2026-09-22T18:00:00');
    expect(clockLabel(new Date(now + (2 * 60 + 14) * 60_000).toISOString(), now))
      .toEqual({ text: '2h 14m left', urgent: false });
    expect(clockLabel(new Date(now + 44 * 60_000).toISOString(), now))
      .toEqual({ text: '44m left', urgent: false });
  });

  it('K3: a later calendar day → "Ends Sat 20:30"; a dead clock is null, never "Ended −3m"', () => {
    const now = Date.parse('2026-09-22T18:00:00');   // Tuesday
    expect(clockLabel('2026-09-26T20:30:00', now)).toEqual({ text: 'Ends Sat 20:30', urgent: false });
    expect(clockLabel(new Date(now - 1000).toISOString(), now)).toBeNull();
  });

  it('P1: the price caption is the presentation label, lowercased, with the §5 "all-in"', () => {
    expect(priceCaption('Current bid')).toBe('current bid, all-in');
    expect(priceCaption('Buy now')).toBe('buy now, all-in');
    expect(priceCaption('Starting bid')).toBe('starting bid, all-in');
  });

  it('F1: the feature drops the date only when the event is genuinely today', () => {
    const now = Date.parse('2026-09-22T09:41:00');
    expect(featureMetaLine({ eventDate: '2026-09-22', eventTime: '19:30:00', venue: 'Lantern Room' }, now))
      .toBe('19:30 · Lantern Room');
    expect(featureMetaLine({ eventDate: '2026-09-26', eventTime: '21:00:00', venue: 'Halcyon Hall' }, now))
      .toBe('Sat 26 Sep · 21:00 · Halcyon Hall');
  });
});
