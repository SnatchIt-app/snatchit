/**
 * V3 home stage — the components (§3 feature + row, the curve scrim through the slot system).
 *
 * Witness discipline: every "shows X" assertion reads the PROPS of a found element, never a
 * flattened-text scan that could pass vacuously. The scrim and height rules are pinned both as
 * slot data (unit) and in EventMedia's source (the only consumer of the spec).
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
vi.mock('@/src/components/ui', () => ({
  Badge: 'Badge',
  usePressScale: () => ({ style: {}, onPressIn: () => {}, onPressOut: () => {} }),
}));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));

import { featureHeight, heroHeight, ROW_ART, ROW_ART_RADIUS } from '@/src/lib/design/featureMetrics';
import { cardPresentation } from '@/src/lib/listing/cardState';
import { rowMeta } from '@/src/lib/listing/feedRowState';
import { MEDIA_SLOTS, type SlotSpec } from '@/src/lib/media/slots';
import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

const NOW = Date.parse('2026-09-22T18:00:00');

function listing(extra: Record<string, unknown> = {}) {
  return {
    status: 'active', auction_status: 'active',
    ends_at: new Date(NOW + 3 * 3600_000).toISOString(),   // same local day, 3h out
    buy_now_enabled: false, buy_now_price: null,
    starting_bid: 90, current_bid: 120, bid_count: 11,
    ...extra,
  };
}

const ROW_DATA = {
  eventName: 'Midnight Arcade presents The Foundry Warehouse Sessions',
  venue: 'The Foundry', eventDate: '2026-09-26', eventTime: '22:00:00',
  quantity: 2, ticketType: 'GA', coverPath: 'covers/a.jpg',
  bidCount: 11, priceAllIn: '$132.00', nowMs: NOW,
  onPress: () => {},
};

async function mountRow(extra: Record<string, unknown> = {}, data: Record<string, unknown> = {}) {
  const l = listing(extra);
  const mod = await import('@/src/components/discovery/FeedRow');
  // memo() wraps the function in an element-type object; the harness calls the inner render.
  const Row = ((mod.FeedRow as { type?: unknown }).type ?? mod.FeedRow) as (p: unknown) => unknown;
  const host = new HookHost(
    () => Row({ ...ROW_DATA, presentation: cardPresentation(l as never, NOW), endsAt: l.ends_at, ...data }),
    new Map(),
  );
  host.mount();
  host.flush();
  return host;
}

async function mountFeature(extra: Record<string, unknown> = {}, data: Record<string, unknown> = {}) {
  const l = listing(extra);
  const mod = await import('@/src/components/discovery/HomeFeature');
  const Feature = ((mod.HomeFeature as { type?: unknown }).type ?? mod.HomeFeature) as (p: unknown) => unknown;
  const host = new HookHost(
    () => Feature({
      ...ROW_DATA, eventName: 'Neon Choir', venue: 'Lantern Room', quantity: 2,
      priceAllIn: '$99.00',
      presentation: cardPresentation(l as never, NOW), endsAt: l.ends_at, ...data,
    }),
    new Map(),
  );
  host.mount();
  host.flush();
  return host;
}

const byText = (host: HookHost, text: string) =>
  findElement(host.output, (el) => el.type === 'Text' && el.props.children === text);
const nameOf = (host: HookHost, token: string) =>
  findElement(host.output, (el) => (el.props as { token?: string }).token === token);
const media = (host: HookHost) => findElement(host.output, (el) => el.type === 'EventMedia');

beforeEach(() => { vi.resetModules(); });

describe('slot system — V3 slots carry the §3 geometry and the curve', () => {
  it('SL1: HOME_FEATURE_V3 — curve scrim, formula-driven height, preloaded cover', () => {
    const s = MEDIA_SLOTS.HOME_FEATURE_V3;
    expect(s.scrim).toBe('curve');
    expect(s.heightFor).toBe(featureHeight);
    expect(s.defaultFit).toBe('cover');
    expect(s.preload).toBe(true);
  });

  it('SL2: LISTING_HERO_V3 — curve scrim and the hero formula', () => {
    const s = MEDIA_SLOTS.LISTING_HERO_V3;
    expect(s.scrim).toBe('curve');
    expect(s.heightFor).toBe(heroHeight);
    expect(s.preload).toBe(true);
  });

  it('SL3: FEED_ROW_ART — 62pt square reference, radius 8, no scrim (text sits beside it)', () => {
    const s: SlotSpec = MEDIA_SLOTS.FEED_ROW_ART;
    expect(s.aspectRatio).toBe(1);
    expect(s.layoutWidth.mobile).toBe(ROW_ART);
    expect(s.radius).toBe(ROW_ART_RADIUS);
    expect(s.scrim).toBe('none');
    expect(s.heightFor).toBeUndefined();
  });

  it('SL4: EventMedia consumes both — the curve string and the heightFor override (source pin)', async () => {
    const { readFileSync } = await import('node:fs');
    // Comments stripped: B15 survived the first run because a COMMENT contained the word
    // "heightFor" and satisfied the bare regex while the code no longer called it.
    const src = readFileSync('src/components/media/EventMedia.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src).toContain('scrimBackgroundImage(');
    expect(src).toContain('spec.heightFor(boxWidth)');
    expect(src).toMatch(/scrim === 'curve'/);
  });
});

describe('FeedRow — the §3 row', () => {
  it('FR1: the name is the display voice — NameText, nameRow token, two-line cap', async () => {
    const host = await mountRow();
    const name = nameOf(host, 'nameRow');
    expect(name).toBeDefined();
    expect(name?.props.children).toBe(ROW_DATA.eventName);
    expect(name?.props.maxLines).toBe(2);
  });

  it('FR2: both §3 meta lines render exactly as feedRowState builds them', async () => {
    const host = await mountRow();
    const m = rowMeta({
      eventDate: ROW_DATA.eventDate, eventTime: ROW_DATA.eventTime, venue: ROW_DATA.venue,
      quantity: 2, ticketType: 'GA', bidCount: 11,
    });
    expect(byText(host, m.meta1)).toBeDefined();
    expect(byText(host, m.meta2)).toBeDefined();
  });

  it('FR3: price column — preformatted price, the plain "all-in" caption, and a calm clock', async () => {
    const host = await mountRow();
    expect(byText(host, '$132.00')).toBeDefined();
    expect(byText(host, 'all-in')).toBeDefined();
    const clock = byText(host, '3h 0m left');
    expect(clock).toBeDefined();
    expect(JSON.stringify(clock?.props.style)).not.toMatch(/FF1A1A/i);
  });

  it('FR4: a sub-15-minute close is amber and says so; amber is the only urgency ink', async () => {
    const host = await mountRow({ ends_at: new Date(NOW + 11 * 60_000).toISOString() });
    const clock = byText(host, 'Ending in 11m');
    expect(clock).toBeDefined();
    const styles = JSON.stringify(clock?.props.style);
    expect(styles).toMatch(/FFB020/i);                // §5: amber, positively — not merely "some color"
    expect(styles).not.toMatch(/FF1A1A/i);            // never the brand red
    // And the calm clock never wears the amber.
    const calm = await mountRow();
    expect(JSON.stringify(byText(calm, '3h 0m left')?.props.style)).not.toMatch(/FFB020/i);
  });

  it('FR5: a sold row says "Sold" ONCE — the status line carries the claim, the caption stays the price basis', async () => {
    // De-dup (owner 2026-09-23): "Sold" + "sold for, all-in" said the same thing twice in one
    // column. The status word (with the dimmed treatment) is the claim; "all-in" labels the
    // number's basis, exactly as on live rows.
    const host = await mountRow({ status: 'sold', winning_bid_amount: 120 });
    expect(byText(host, 'Sold')).toBeDefined();
    expect(byText(host, 'all-in')).toBeDefined();
    expect(byText(host, 'sold for, all-in')).toBeUndefined();
  });

  it('FR6: artwork goes through EventMedia at the row slot and the row width', async () => {
    const host = await mountRow();
    const art = media(host);
    expect(art?.props.slot).toBe('FEED_ROW_ART');
    expect(art?.props.width).toBe(ROW_ART);
  });

  it('FR7: one spoken label for the whole row; the row is a single button', async () => {
    const host = await mountRow();
    const btn = findElement(host.output, (el) => el.type === 'Pressable');
    expect(btn?.props.accessibilityRole).toBe('button');
    const label = String(btn?.props.accessibilityLabel);
    expect(label).toContain('Midnight Arcade presents');
    expect(label).toContain('$132.00');
  });

  it('FR8: no hard-coded row height, and the clearance constant is in force (source pin)', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/components/discovery/FeedRow.tsx', 'utf8');
    expect(src).not.toMatch(/height: \d/);
    expect(src).toContain('ROW_META_CLEARANCE');
    expect(src).not.toMatch(/supabase|rpc\(|fetch\(/);
  });
});

describe('HomeFeature — the §3 full-bleed feature', () => {
  it('HF1: name in the feature voice over the curve-scrimmed slot, fluid width', async () => {
    const host = await mountFeature();
    const name = nameOf(host, 'nameFeature');
    expect(name).toBeDefined();
    expect(name?.props.children).toBe('Neon Choir');
    const art = media(host);
    expect(art?.props.slot).toBe('HOME_FEATURE_V3');
    expect(art?.props.fluid).toBe(true);
  });

  it('HF2: the caption states the price\'s source — "current bid, all-in"', async () => {
    const host = await mountFeature();
    expect(byText(host, '$99.00')).toBeDefined();
    expect(byText(host, 'current bid, all-in')).toBeDefined();
  });

  it('HF3: meta carries when · venue and qty × type · bids · clock', async () => {
    const host = await mountFeature();
    expect(byText(host, 'Sat 26 Sep · 22:00 · Lantern Room')).toBeDefined();
    expect(byText(host, '2 × GA · 11 bids · 3h 0m left')).toBeDefined();
  });

  it('HF4: the feature is one tappable target with one spoken label', async () => {
    let opened = 0;
    const host = await mountFeature({}, { onPress: () => { opened += 1; } });
    const btn = findElement(host.output, (el) => el.type === 'Pressable');
    expect(btn?.props.accessibilityRole).toBe('button');
    (btn?.props.onPress as () => void)();
    expect(opened).toBe(1);
  });

  it('HF5: the feature never fetches and never hard-codes its height (source pin)', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/components/discovery/HomeFeature.tsx', 'utf8');
    expect(src).not.toMatch(/supabase|rpc\(|fetch\(/);
    expect(src).not.toMatch(/height: \d/);
    expect(src).toContain('FEATURE_NAME_BLOCK_BOTTOM');
  });
});

describe('home wiring — feature + rows (source pins; behaviour is the load-state suite\'s)', () => {
  it('HW1: the first LIVE listing is the feature; sold/ended never is; rows carry the §3 divider', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('app/(tabs)/home.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src).toMatch(/index === 0 &&\s*presentation\.status !== 'sold' && presentation\.status !== 'ended'/);
    expect(src).toContain('<HomeFeature {...shared} />');
    expect(src).toContain('<FeedRow {...shared} />');
    expect(src).toContain('ItemSeparatorComponent');
    expect(src).not.toContain('numColumns={2}');
    expect(src).not.toContain('DiscoveryCard');
    // The mockups' section headings are flagged, not drawn: no unbacked "Tonight"/"This week".
    expect(src).not.toMatch(/'Tonight'|'This week'/);
  });
});
