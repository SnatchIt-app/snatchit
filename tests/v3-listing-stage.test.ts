/**
 * V3 listing-detail stage (§3 hero over the curve scrim; §5 price panel, minimum-bid breakdown
 * and the corrected commitment sentence — mockup midnight-listing, freeze reconciliation §2).
 *
 * Truth rules pinned here: the panel states the CURRENT price and nothing about the buyer's
 * total; the breakdown belongs to the bid being offered and comes preformatted from the one
 * money module; "current bid" is never claimed with zero bids; the buy-now amount lives on its
 * CTA, not in the panel; identity moves onto the artwork but nothing transactional does.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });

vi.mock('react-native', () => ({
  Animated: { View: 'Animated.View' },
  Pressable: 'Pressable', Text: 'Text', View: 'View',
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  StyleSheet: {
    create: <T,>(s: T) => s,
    hairlineWidth: 1,
    absoluteFill: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
    absoluteFillObject: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
  },
}));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/PriceDisplay', () => ({ PriceDisplay: 'PriceDisplay' }));
vi.mock('@/src/components/ui', () => ({ FromAFanBadge: 'FromAFanBadge', IconButton: 'IconButton' }));
vi.mock('@/src/hooks/usePulseOnChange', () => ({ usePulseOnChange: () => ({ opacity: 1 }) }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));

import { bidCommitmentCopy } from '@/src/lib/listing/detailState';
import { findElement, HookHost } from './helpers/nav-stack-harness';

const byText = (host: HookHost, text: string) =>
  findElement(host.output, (el) => el.type === 'Text' && el.props.children === text);
const priceDisplay = (host: HookHost, label: string) =>
  findElement(host.output, (el) => el.type === 'PriceDisplay' && el.props.label === label);

async function mountPanel(over: Record<string, unknown> = {}) {
  const mod = await import('@/src/components/listing/TransactionPanel');
  const Panel = mod.TransactionPanel as unknown as (p: unknown) => unknown;
  const host = new HookHost(() => Panel({
    mode: 'auction_and_buy_now',
    currentAllIn: '$99.00',
    buyNowAllIn: '$132.00',
    nextBidAllIn: '$104.50',
    minBidBase: '$95.00',
    minBidFee: '$9.50',
    clock: { text: '2h 14m left', urgent: false },
    soldAllIn: null,
    bidCount: 6,
    quantity: 2,
    ticketType: 'GA',
    ...over,
  }), new Map());
  host.mount();
  host.flush();
  return host;
}

async function mountHero(over: Record<string, unknown> = {}) {
  const mod = await import('@/src/components/listing/ListingHero');
  const Hero = mod.ListingHero as unknown as (p: unknown) => unknown;
  const host = new HookHost(() => Hero({
    asset: { path: 'covers/a.jpg', contract: 'legacy', bucket: 'auction-media' },
    eventName: 'Neon Choir',
    venue: 'Lantern Room',
    eventDate: '2026-09-26',
    eventTime: '19:30:00',
    neighborhood: 'Bushwick',
    onBack: () => {},
    onOverflow: () => {},
    ...over,
  }), new Map());
  host.mount();
  host.flush();
  return host;
}

beforeEach(() => { vi.resetModules(); });

describe('bidCommitmentCopy — the §5 sentence, corrected, and never a false "current bid"', () => {
  it('LP1: with bids, the exact approved sentence; with none, the truthful starting-bid variant', () => {
    expect(bidCommitmentCopy({ currentAllIn: '$99.00', nextBidAllIn: '$104.50', bidCount: 6 })).toBe(
      "A bid is a commitment. The current bid is $99.00; the lowest you can place is $104.50 all-in. " +
      "If you win, you'll pay your own bid to complete the purchase.",
    );
    const none = bidCommitmentCopy({ currentAllIn: '$99.00', nextBidAllIn: '$104.50', bidCount: 0 });
    expect(none).toContain('The starting bid is $99.00');
    expect(none).not.toContain('current bid');
    // The corrected copy never claims an automatic charge.
    expect(none.toLowerCase()).not.toContain('charged automatically');
  });
});

describe('TransactionPanel — the §5 panel', () => {
  it('LP2: states the current price, the qty column and the sub-line — nothing about the buyer\'s total', async () => {
    const host = await mountPanel();
    expect(priceDisplay(host, 'Current bid')).toBeDefined();
    expect((priceDisplay(host, 'Current bid')?.props as { amount?: string }).amount).toBe('$99.00');
    expect(byText(host, '2 × GA tickets')).toBeDefined();
    expect(byText(host, 'sold together')).toBeDefined();
    expect(byText(host, 'all-in · 6 bids · 2h 14m left')).toBeDefined();
    expect(byText(host, '$104.50')).toBeDefined();          // the breakdown headline — separate block
  });

  it('LP3: one ticket is singular and NOT "sold together"; zero bids is "Starting bid" and "no bids yet"', async () => {
    const host = await mountPanel({ quantity: 1, bidCount: 0 });
    expect(byText(host, '1 × GA ticket')).toBeDefined();
    expect(byText(host, 'sold together')).toBeUndefined();
    expect(priceDisplay(host, 'Starting bid')).toBeDefined();
    expect(priceDisplay(host, 'Current bid')).toBeUndefined();
    expect(byText(host, 'all-in · no bids yet · 2h 14m left')).toBeDefined();
  });

  it('LP4: the minimum-bid breakdown, preformatted rows only — and absent when there is no next bid', async () => {
    const host = await mountPanel();
    expect(byText(host, 'If you bid the minimum')).toBeDefined();
    expect(byText(host, 'Tickets (2 × GA)')).toBeDefined();
    expect(byText(host, '$95.00')).toBeDefined();
    expect(byText(host, 'Service fee (10%)')).toBeDefined();
    expect(byText(host, '$9.50')).toBeDefined();
    expect(byText(host, 'Your total if you win')).toBeDefined();

    const closed = await mountPanel({ mode: 'closed', nextBidAllIn: null, minBidBase: null, minBidFee: null, clock: null });
    expect(byText(closed, 'If you bid the minimum')).toBeUndefined();
    expect(byText(closed, 'Your total if you win')).toBeUndefined();

    // Defence in depth: even if a caller hands a closed panel the row values (L6 survived the
    // first control run because only the nulled case was pinned), the block must stay hidden —
    // a would-be total on a closed auction is an offer that no longer exists.
    const closedWithValues = await mountPanel({ mode: 'closed', clock: null });
    expect(byText(closedWithValues, 'If you bid the minimum')).toBeUndefined();
    expect(byText(closedWithValues, 'Your total if you win')).toBeUndefined();
  });

  it('LP5: sold shows what it went for, and no bid arithmetic at all', async () => {
    const host = await mountPanel({ soldAllIn: '$99.00' });
    expect(priceDisplay(host, 'Sold for')).toBeDefined();
    expect(byText(host, 'If you bid the minimum')).toBeUndefined();
  });

  it('LP6: the buy-now amount lives on its CTA — the panel no longer prints it', async () => {
    const host = await mountPanel();
    expect(priceDisplay(host, 'Buy now')).toBeUndefined();
    expect(byText(host, 'Yours immediately. No waiting for the auction.')).toBeUndefined();
  });

  it('LP7: the panel does no money arithmetic (source pin)', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/components/listing/TransactionPanel.tsx', 'utf8');
    expect(src).not.toMatch(/\* 100|\/ 100|\* 0\.1|lib\/money/);
  });
});

describe('ListingHero — identity over the curve-scrimmed §3 hero', () => {
  it('LH1: the V3 hero slot, fluid, with the dated identity line and the name over the artwork', async () => {
    const host = await mountHero();
    const art = findElement(host.output, (el) => el.type === 'EventMedia');
    expect(art?.props.slot).toBe('LISTING_HERO_V3');
    expect(art?.props.fluid).toBe(true);
    expect(byText(host, 'Sat 26 Sep · 19:30 · Lantern Room')).toBeDefined();
    const name = findElement(host.output, (el) => (el.props as { token?: string }).token === 'nameDetail');
    expect(name?.props.children).toBe('Neon Choir');
  });

  it('LH2: provenance is not quietly dropped — the badge still renders', async () => {
    const host = await mountHero();
    expect(findElement(host.output, (el) => el.type === 'FromAFanBadge')).toBeDefined();
  });

  it('LH3: nothing transactional over the image, and no local font override (source pins)', async () => {
    const { readFileSync } = await import('node:fs');
    // Comments stripped — the rule is about what RENDERS, and the rationale comment itself
    // names the price it forbids (the SL4/B15 lesson applied on first writing).
    const src = readFileSync('src/components/listing/ListingHero.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src).not.toMatch(/fontSize: \d/);
    expect(src).not.toMatch(/price|allIn|\$\{.*Amount/i);   // identity only — never a price on the hero
  });
});

describe('screen wiring (source pins)', () => {
  it('LS1: the screen renders the commitment sentence, the relocated neighborhood row, and the platform on Delivery', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/screens/ListingDetailScreen.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src).toContain('bidCommitmentCopy(');
    expect(src).toContain("label: 'Neighborhood'");
    expect(src).toContain('PLATFORM_INSTRUCTIONS[');
    expect(src).toContain('minBidBase');
  });
});
