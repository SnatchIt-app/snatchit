/**
 * tests/listing-handoff.test.ts — the card-to-detail handoff (CFT-101).
 *
 * A tapped card used to push `/listing/{id}` and nothing else, so the detail
 * screen opened on a spinner. It now stages what the card already showed, in
 * memory, and the detail screen paints that until the fresh row arrives.
 *
 * Half of this file is the pure module, driven directly. The other half is the
 * contract that matters more than the feature: the handoff is DISPLAY ONLY, and
 * every transactional control and total on the detail screen is still gated on
 * the fetched row (contract A-17).
 */

import { beforeEach, describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  MAX_STAGED_HANDOFFS,
  clearCardHandoffs,
  parseCardHandoff,
  readCardHandoff,
  stageCardHandoff,
} from '../src/lib/listing/cardHandoff';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
/** Comments quote the rules; the guards read the code. */
const code = (rel: string) =>
  read(rel)
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');

const full = {
  coverPath: 'uuid/covers/1715000000000.jpg',
  eventName: 'Bad Bunny',
  venue: 'LIV',
  eventDate: '2026-10-17',
  eventTime: '22:00:00',
  neighborhood: 'south beach',
  priceLabel: 'Buy now',
  priceAllIn: '$66',
};

describe('parseCardHandoff — tolerant of what a card may not have', () => {
  it('carries every display field through, trimmed', () => {
    expect(parseCardHandoff({ ...full, venue: '  LIV  ' })).toEqual({ ...full, venue: 'LIV' });
  });

  it('is nothing without a name to show', () => {
    expect(parseCardHandoff(null)).toBeNull();
    expect(parseCardHandoff(undefined)).toBeNull();
    expect(parseCardHandoff('Bad Bunny')).toBeNull();
    expect(parseCardHandoff({})).toBeNull();
    expect(parseCardHandoff({ ...full, eventName: '   ' })).toBeNull();
    expect(parseCardHandoff({ ...full, eventName: undefined })).toBeNull();
  });

  it('degrades missing or blank fields to empty, never to a crash', () => {
    const h = parseCardHandoff({ eventName: 'Bad Bunny' });
    expect(h).toEqual({
      coverPath: null,
      eventName: 'Bad Bunny',
      venue: '',
      eventDate: '',
      eventTime: '',
      neighborhood: null,
      priceLabel: '',
      priceAllIn: '',
    });
    expect(parseCardHandoff({ ...full, coverPath: '   ' })?.coverPath).toBeNull();
    expect(parseCardHandoff({ ...full, neighborhood: '' })?.neighborhood).toBeNull();
  });

  it('accepts strings only — a number is not a price label', () => {
    const h = parseCardHandoff({ ...full, priceAllIn: 66, priceLabel: null, coverPath: 42 });
    expect(h?.priceAllIn).toBe('');
    expect(h?.priceLabel).toBe('');
    expect(h?.coverPath).toBeNull();
  });
});

describe('stage / read — in memory, by listing id, bounded', () => {
  beforeEach(() => clearCardHandoffs());

  it('reads back what a card staged, and nothing for an unknown id', () => {
    stageCardHandoff('l1', full);
    expect(readCardHandoff('l1')).toEqual(full);
    expect(readCardHandoff('l2')).toBeNull();
  });

  it('is left in place after a read, so a remount or a return visit still has it', () => {
    stageCardHandoff('l1', full);
    readCardHandoff('l1');
    expect(readCardHandoff('l1')).toEqual(full);
  });

  it('replaces an earlier handoff for the same listing', () => {
    stageCardHandoff('l1', full);
    stageCardHandoff('l1', { ...full, priceAllIn: '$70' });
    expect(readCardHandoff('l1')?.priceAllIn).toBe('$70');
  });

  it('stages nothing for an unusable card or a missing id', () => {
    stageCardHandoff('l1', { venue: 'LIV' });
    stageCardHandoff('', full);
    expect(readCardHandoff('l1')).toBeNull();
    expect(readCardHandoff('')).toBeNull();
  });

  it('evicts the oldest past the bound', () => {
    for (let i = 0; i <= MAX_STAGED_HANDOFFS; i++) stageCardHandoff(`l${i}`, full);
    expect(readCardHandoff('l0')).toBeNull();
    expect(readCardHandoff('l1')).not.toBeNull();
    expect(readCardHandoff(`l${MAX_STAGED_HANDOFFS}`)).not.toBeNull();
  });

  it('re-staging refreshes recency rather than evicting the refreshed entry', () => {
    for (let i = 0; i < MAX_STAGED_HANDOFFS; i++) stageCardHandoff(`l${i}`, full);
    stageCardHandoff('l0', full); // now the newest
    stageCardHandoff('extra', full); // evicts l1, not l0
    expect(readCardHandoff('l0')).not.toBeNull();
    expect(readCardHandoff('l1')).toBeNull();
  });
});

describe('cards — stage the handoff and keep the route', () => {
  const home = code('app/(tabs)/home.tsx');
  const search = code('app/(tabs)/explore.tsx');

  it.each([
    ['home', home],
    ['search', search],
  ])('%s stages display strings, then pushes the unchanged route', (_name, src) => {
    const press = /stageCardHandoff\(item\.id, \{([\s\S]*?)\}\);\s*router\.push\(`\/listing\/\$\{item\.id\}`\);/.exec(src);
    expect(press, 'the handoff is staged immediately before the push').not.toBeNull();
    const fields = press?.[1] ?? '';
    for (const key of ['coverPath', 'eventName', 'venue', 'eventDate', 'eventTime', 'priceLabel', 'priceAllIn']) {
      expect(fields, `${key} is handed over`).toContain(key);
    }
    // The price crosses as the card's preformatted string, never as a number.
    expect(fields).toMatch(/priceAllIn,?\s*\n/);
    expect(fields).not.toMatch(/priceDollars|buy_now_price|current_bid/);
  });
});

describe('detail screen — the handoff paints, the fetched row decides (A-17)', () => {
  const screen = code('src/screens/ListingDetailScreen.tsx');

  it('reads the handoff once, as display state', () => {
    expect(screen).toContain("from '@/src/lib/listing/cardHandoff'");
    expect(screen).toMatch(/const \[handoff\] = useState<CardHandoff \| null>\(\(\) => readCardHandoff\(id\)\)/);
  });

  it('shows the handoff only before the first row, and never a transactional control with it', () => {
    const start = screen.indexOf('if (loading && !listing && handoff) return (');
    const end = screen.indexOf('if (loading) return (');
    expect(start).toBeGreaterThan(-1);
    expect(end).toBeGreaterThan(start);
    const preview = screen.slice(start, end);
    expect(preview).toContain('<ListingHero');
    expect(preview).toContain('<PriceDisplay');
    expect(preview).toContain('<Spinner');
    for (const forbidden of ['<Button', 'runAction', 'handleBuyNow', 'navigateToCheckout', 'router.push', 'detailState', 'onOverflow']) {
      expect(preview, `${forbidden} must not appear in the preview`).not.toContain(forbidden);
    }
  });

  it('gates every offer on the fetched row, exactly as before', () => {
    const notFound = screen.indexOf('if (!listing) return (');
    const decision = screen.indexOf('const state = detailState({');
    expect(notFound).toBeGreaterThan(-1);
    expect(decision).toBeGreaterThan(notFound);
    // Nothing after the not-found guard reads the handoff: the whole
    // transactional half of the screen cannot see it.
    expect(screen.slice(notFound)).not.toMatch(/handoff/);
    // The decision is fed the fresh row's fields, by name.
    const feed = screen.slice(decision, screen.indexOf('});', decision));
    for (const field of ['listing.status', 'listing.auction_status', 'listing.buy_now_enabled', 'listing.buy_now_price', 'listing.reserved_by']) {
      expect(feed).toContain(field);
    }
    expect(screen).toContain('disabled={state.primary.disabled || state.primary.kind === \'unavailable\'}');
  });

  it('computes the checkout total from the fetched row, untouched', () => {
    expect(screen).toContain('const price = listing.buy_now_price;');
    expect(screen).toContain('totalCents: String(buyerTotalCents(dollarsToCents(price)))');
    expect(screen).toContain("const winAmount = (listing as any).winning_bid_amount ?? listing.current_bid ?? 0;");
    expect(screen).toContain('totalCents: String(buyerTotalCents(dollarsToCents(winAmount)))');
    expect(screen.match(/dollarsToCents\(/g) ?? []).toHaveLength(2);
  });
});
