/**
 * V3 home stage — the components (§3 feature + row, the curve scrim through the slot system).
 *
 * Witness discipline: every "shows X" assertion reads the PROPS of a found element, never a
 * flattened-text scan that could pass vacuously. The scrim and height rules are pinned both as
 * slot data (unit) and in EventMedia's source (the only consumer of the spec).
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });

// The migrated screens read the resolved appearance. These suites assert behaviour, not colour, so
// the boundary is mocked to Midnight — whose values ARE the v2 tokens, so nothing they pin moves.
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return {
    useTheme: () => ({ scheme: 'dark', palette: dark }),
    useAppearancePreference: () => ({ preference: 'system', setPreference: () => {} }),
  };
});
const rn = vi.hoisted(() => ({ fontScale: 1 }));
vi.mock('react-native', () => ({
  Animated: { View: 'Animated.View' },
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: rn.fontScale }),
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

import { ROW_ART, ROW_ART_RADIUS, ROW_ART_W } from '@/src/lib/design/featureMetrics';
import * as v2 from '@/src/theme/v2';
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

beforeEach(() => { vi.resetModules(); rn.fontScale = 1; });

describe('slot system — V3 slots carry the §3 geometry and the curve', () => {
  it('SL1: HOME_FEATURE_V3 — a 4:5 poster, fitted, preloaded, and NO gradient', () => {
    const s = MEDIA_SLOTS.HOME_FEATURE_V3;
    expect(s.aspectRatio).toBe(v2.ratio.portrait);
    // `fit`, not `cover`: the feature is the largest poster in the product and the one where a
    // crop would cut the most type off a flyer.
    expect(s.defaultFit).toBe('fit');
    expect(s.preload).toBe(true);
    /*
     * The curve scrim is GONE (owner ruling 2026-09-25: "Remove the gradient used to support the
     * old text overlay"). It was never decoration — it darkened a flyer's own printed type so ours
     * could sit on top. With the identity block beneath the poster there is nothing to make
     * legible, so a gradient would only dim the artwork the feature exists to show.
     */
    expect(s.scrim).toBe('none');
  });

  it('SL2: LISTING_HERO_V3 — a 4:5 poster, fitted, preloaded, and NO gradient', () => {
    const s = MEDIA_SLOTS.LISTING_HERO_V3;
    expect(s.aspectRatio).toBe(v2.ratio.portrait);
    expect(s.defaultFit).toBe('fit');
    expect(s.preload).toBe(true);
    // Owner 2026-09-25: the identity moved beneath the poster, so the gradient that supported it
    // has nothing to support. The navigation chips left on the artwork carry their own plate.
    expect(s.scrim).toBe('none');
  });

  it('SL3: FEED_ROW_ART — a 50 × 62 poster, radius 8, no scrim (text sits beside it)', () => {
    const s: SlotSpec = MEDIA_SLOTS.FEED_ROW_ART;
    expect(s.aspectRatio).toBe(v2.ratio.portrait);
    // The REFERENCE width is the derived poster width, not the row height.
    expect(s.layoutWidth.mobile).toBe(ROW_ART_W);
    expect(s.layoutWidth.mobile).not.toBe(ROW_ART);
    expect(s.radius).toBe(ROW_ART_RADIUS);
    expect(s.scrim).toBe('none');
  });

  it('SL4: EventMedia consumes the curve, and uses a caller height EXACTLY (source pin)', async () => {
    const { readFileSync } = await import('node:fs');
    // Comments stripped: B15 survived the first run because a COMMENT contained the word
    // "heightFor" and satisfied the bare regex while the code no longer called it.
    const src = readFileSync('src/components/media/EventMedia.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src).toContain('scrimBackgroundImage(');
    expect(src).toMatch(/scrim === 'curve'/);
    // The retired landscape escape hatch must not come back.
    expect(src).not.toContain('heightFor');
    // A caller-given height is the box height verbatim, and the width is derived from it.
    expect(src).toContain('!fluid && height != null ? height');
    expect(src).toContain('Math.round(height * spec.aspectRatio)');
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

  it('FR6: artwork goes through EventMedia at the row slot and the row HEIGHT, never a width', async () => {
    const host = await mountRow();
    const art = media(host);
    expect(art?.props.slot).toBe('FEED_ROW_ART');
    // The poster direction inverts which edge the row gives the media. Handing 62 as a WIDTH is
    // now a defect, not a synonym: EventMedia would derive a 78pt height and overflow the approved
    // 80pt one-line row. So the absence of `width` is asserted as well as the presence of `height`.
    expect(art?.props.height).toBe(ROW_ART);
    expect(art?.props.width).toBeUndefined();
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
    /*
     * RETARGETED (owner 2026-09-24). This used to assert the screen contained no "Tonight" /
     * "This week" at all, because at the time their grouping rule was written nowhere and an
     * unbacked heading is a claim the data cannot meet. The owner's finding is that the boards'
     * section headings ARE part of the approved Home, so the rule now exists as one pure function
     * and the pin moves to the property that actually matters: the screen may not name a section
     * itself. Every heading it draws comes from `src/lib/home/sections.ts`.
     */
    expect(src).not.toMatch(/'Tonight'|'This week'|"Tonight"|"This week"/);
    expect(src).toContain('groupByEventDate');
    expect(src).toContain('headingFor.get(item.id)');
  });

  it('HW2: the section rule is total, stable, and never names a bucket it cannot back', async () => {
    const { groupByEventDate, sectionFor } = await import('@/src/lib/home/sections');
    const now = Date.parse('2026-09-24T18:00:00');
    const at = (days: number) => {
      const d = new Date(now);
      d.setDate(d.getDate() + days);
      return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    };
    expect(sectionFor(at(0), now)).toBe('tonight');
    expect(sectionFor(at(1), now)).toBe('week');
    expect(sectionFor(at(7), now)).toBe('week');
    expect(sectionFor(at(8), now)).toBe('later');
    // A past event — every row of the Recently sold and Ended datasets — is NOT given a heading.
    expect(sectionFor(at(-1), now)).toBe('undated');
    expect(sectionFor('not-a-date', now)).toBe('undated');

    const rows = [
      { id: 'a', event_date: at(9) },
      { id: 'b', event_date: at(0) },
      { id: 'c', event_date: at(-3) },
      { id: 'd', event_date: at(3) },
      { id: 'e', event_date: at(10) },
    ];
    const sections = groupByEventDate(rows, (r) => r.event_date, now);
    // Total: nothing is filtered away by grouping.
    expect(sections.flatMap((s) => s.items).map((r) => r.id).sort()).toEqual(['a', 'b', 'c', 'd', 'e']);
    // Ordered soonest first, with the unnameable bucket last and unlabelled.
    expect(sections.map((s) => [s.key, s.label])).toEqual([
      ['tonight', 'Tonight'],
      ['week', 'This week'],
      ['later', 'Later'],
      ['undated', null],
    ]);
    // Stable: 'a' arrived before 'e', and stays before it inside their section.
    expect(sections[2].items.map((r) => r.id)).toEqual(['a', 'e']);
  });
});

/*
 * LARGE TEXT (B's native finding at d5217530, owner-settled 2026-10-06). At the largest
 * accessibility size the price caption truncated to "current bid, al…", losing the word "all-in";
 * at the largest standard size the "Ends…" line was cut. The owner's requirement: "all-in" stays
 * VISIBLY readable at the supported large text sizes — wrap it or adjust the layout, price
 * semantics unchanged — and complete spoken text does not excuse clipped visible text, so the
 * accessibility value is a separate check rather than a defence.
 *
 * The identity block is two columns, and the caption lives in the narrow right-hand one. At a
 * large scale the two columns cannot both fit, so the block stacks and each line gets the full
 * width. The threshold is a pure function so it can be stated once and tested.
 */
describe('HomeFeature — "all-in" survives the supported text sizes', () => {
  const content = (host: HookHost) =>
    findElement(host.output, (el) => el.type === 'View' && Array.isArray(el.props.style)
      ? false
      : el.type === 'View' && (el.props.style as { flexDirection?: string } | undefined)?.flexDirection != null);

  const captionOf = (host: HookHost) =>
    findElement(host.output, (el) => el.type === 'Text' && String(el.props.children).includes('all-in'));

  it('LT1: the caption is never capped to one line, so it can wrap instead of clipping', async () => {
    const host = await mountFeature();
    const caption = captionOf(host);
    expect(caption, 'the caption must be on screen at all').toBeDefined();
    expect(String(caption!.props.children)).toContain('all-in');
    // `numberOfLines={1}` is what produced "current bid, al…".
    expect(caption!.props.numberOfLines).not.toBe(1);
  });

  it('LT2: at the standard size the block is still two columns', async () => {
    rn.fontScale = 1;
    const host = await mountFeature();
    expect(content(host)?.props.style).toMatchObject({ flexDirection: 'row' });
  });

  it('LT3: at the largest standard size and above it stacks, so each line has the full width', async () => {
    for (const scale of [1.35, 2, 3.1]) {
      rn.fontScale = scale;
      const host = await mountFeature();
      expect(content(host)?.props.style, `fontScale ${scale}`).toMatchObject({ flexDirection: 'column' });
    }
  });

  it('LT4: the clock line can wrap too — "Ends…" was the other one cut', async () => {
    // Far enough out that the clock is the "Ends <day> <time>" form rather than a countdown —
    // that long form is the one B saw cut at the largest standard size.
    const host = await mountFeature({ ends_at: new Date(NOW + 3 * 24 * 3600_000).toISOString() });
    // The clock is the TAIL of the combined meta line ("2 × GA · 11 bids · Ends Fri 18:00"),
    // which is why the cut landed on it: it is the last thing on the longest line.
    const clock = findElement(host.output, (el) => el.type === 'Text' && / · Ends /.test(String(el.props.children)));
    expect(clock, 'the clock line must be on screen').toBeDefined();
    expect(clock!.props.numberOfLines).not.toBe(1);
  });

  it('LT4b: the venue line can wrap too — the a3xl capture of LT4\u2019s own fix showed it clipped', async () => {
    // "19:30 · Lanter…" at accessibility-extra-extra-extra-large, in the C-operated capture taken
    // to verify the caption fix. Fixing one line of a two-line block and leaving its sibling
    // clipped would have shipped the same defect one row up.
    const host = await mountFeature();
    const venue = findElement(host.output, (el) => el.type === 'Text' && / · Lantern Room$/.test(String(el.props.children)));
    expect(venue, 'the venue line must be on screen').toBeDefined();
    expect(venue!.props.numberOfLines).not.toBe(1);
  });

  it('LT5: the spoken label still carries the whole sentence — recorded SEPARATELY, not as a defence', async () => {
    /*
     * The owner was explicit that a complete accessibility value does not excuse clipped visible
     * text. This pins that the spoken string stays complete while LT1-LT4 hold the VISIBLE text to
     * its own standard; if the two ever disagree, both fail here rather than one covering for the
     * other.
     */
    const host = await mountFeature();
    const pressable = findElement(host.output, (el) => el.type === 'Pressable');
    const label = String(pressable!.props.accessibilityLabel);
    expect(label).toContain('all-in');
    expect(label).toContain('$99.00');
  });

  it('LT6: the threshold is one stated rule, not a number repeated in a component', async () => {
    const { identityStacks, IDENTITY_STACK_SCALE } = await import('@/src/lib/design/featureMetrics');
    expect(identityStacks(1)).toBe(false);
    expect(identityStacks(1.2)).toBe(false);
    expect(identityStacks(IDENTITY_STACK_SCALE)).toBe(true);
    expect(identityStacks(3.1)).toBe(true);
    // The standard sizes end around 1.35, which is where B saw the first cut, so the threshold has
    // to be at or below it rather than only catching the accessibility sizes.
    expect(IDENTITY_STACK_SCALE).toBeLessThanOrEqual(1.35);
  });
});
