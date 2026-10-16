/**
 * RC10 — the build-28 listing follow-ups, seen on build 28's own frames (2026-10-16 captures):
 *  1. "Adiel & Yu Su with JOVIGIBS at Jolene Sound…" — the listing's name was capped at two lines on
 *     the one screen whose job is to say what the listing is, and on the bid review that commits to it.
 *  2. "From a fan" on the owner's proof-waived listings — 156 lets only an admin waive proof, on their
 *     own listing, so those are Snatch It's inventory, not a fan's resale (web #111's rule).
 *  3. Scrolled listing content drew under the clock: the scroll view runs to the top of the screen and
 *     nothing covered the status-bar area once the navigation row scrolled away.
 *  4. The scroll view's bottom edge sliced a line of text in half just above Place a bid (the "title
 *     sliver" on the listing top): content now fades into the footer instead of being cut.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';

import { light } from '@/src/theme/palette';
import { findElement, HookHost } from './helpers/nav-stack-harness';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });

vi.mock('@/src/theme/appearance', async () => {
  const { light } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'light', palette: light }) };
});
vi.mock('react-native', () => ({
  Animated: { View: 'Animated.View', Value: class { constructor(public v: number) {} interpolate() { return 0; } setValue() {} }, timing: () => ({ start: (cb?: () => void) => cb?.() }) },
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: 1 }),
  Pressable: 'Pressable', Text: 'Text', View: 'View', ActivityIndicator: 'ActivityIndicator',
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  StyleSheet: {
    create: <T,>(s: T) => s,
    hairlineWidth: 1,
    absoluteFill: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
    absoluteFillObject: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
  },
}));
vi.mock('react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, bottom: 34, left: 0, right: 0 }) }));
vi.mock('@/src/hooks/useKeyboardUp', () => ({ useKeyboardUp: () => false }));
vi.mock('@/components/ui/icon-symbol', () => ({ IconSymbol: 'IconSymbol' }));
vi.mock('@/src/hooks/useReducedMotion', () => ({ useReducedMotion: () => true }));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/ui', () => ({ FromAFanBadge: 'FromAFanBadge', IconButton: 'IconButton' }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useTopInset: () => 62 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6, EASING_BEZIER: [0.2, 0, 0, 1] }));

/** Comments out: these rules are about what renders, and the rationale comments name what they forbid. */
const code = (path: string) => readFileSync(path, 'utf8')
  .replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .replace(/(^|[^:])\/\/.*$/gm, '$1');

const flat = (style: unknown): Record<string, unknown> =>
  Array.isArray(style) ? Object.assign({}, ...style.flat(Infinity).filter(Boolean)) : (style as Record<string, unknown>) ?? {};

async function mountHero(over: Record<string, unknown> = {}) {
  const mod = await import('@/src/components/listing/ListingHero');
  const Hero = mod.ListingHero as unknown as (p: unknown) => unknown;
  const host = new HookHost(() => Hero({
    asset: { path: 'covers/a.jpg', contract: 'legacy', bucket: 'auction-media' },
    eventName: 'Adiel & Yu Su with JOVIGIBS at Jolene Sound Room',
    venue: 'Jolene Sound Room',
    eventDate: '2026-11-13',
    eventTime: '22:00:00',
    showsFanBadge: true,
    onBack: () => {},
    onOverflow: () => {},
    ...over,
  }), new Map());
  host.mount();
  host.flush();
  return host;
}

async function mountName(maxLines: number | null | undefined) {
  const mod = await import('@/src/components/NameText');
  const NameText = mod.NameText as unknown as (p: unknown) => unknown;
  const host = new HookHost(() => NameText({ token: 'nameDetail', maxLines, children: 'Adiel & Yu Su with JOVIGIBS at Jolene Sound Room' }), new Map());
  host.mount();
  host.flush();
  return host;
}

async function mountBar(layout: 'row' | 'stack') {
  const mod = await import('@/src/components/ui/StickyBar');
  const Bar = mod.StickyBar as unknown as (p: unknown) => unknown;
  const host = new HookHost(() => Bar({ layout, children: 'actions' }), new Map());
  host.mount();
  host.flush();
  return host;
}

beforeEach(() => { vi.resetModules(); });

describe('1 — the full event name where the listing is identified and committed to', () => {
  it('RC1: NameText with maxLines={null} sets no line cap and never trims; a number still caps (control)', async () => {
    const open = await mountName(null);
    const text = findElement(open.output, (el) => el.type === 'Text');
    expect(text, 'NameText renders a Text').toBeDefined();
    expect(text!.props.numberOfLines).toBeUndefined();
    expect(text!.props.onTextLayout, 'no corrective trim pass without a cap').toBeUndefined();
    expect(text!.props.children).toBe('Adiel & Yu Su with JOVIGIBS at Jolene Sound Room');

    const capped = await mountName(2);
    expect(findElement(capped.output, (el) => el.type === 'Text')!.props.numberOfLines).toBe(2);
    const byDefault = await mountName(undefined);
    expect(findElement(byDefault.output, (el) => el.type === 'Text')!.props.numberOfLines, 'the default stays 2 for rows and cards').toBe(2);
  });

  it('RC2: the listing hero asks for the uncapped name', async () => {
    const host = await mountHero();
    const name = findElement(host.output, (el) => (el.props as { token?: string }).token === 'nameDetail');
    expect(name?.props.children).toBe('Adiel & Yu Su with JOVIGIBS at Jolene Sound Room');
    expect(name?.props.maxLines).toBeNull();
  });

  it('RC3: the bid review restates the full name too (source pin; the screen is mounted elsewhere with a server read)', () => {
    const src = code('src/screens/PlaceBidScreen.tsx');
    expect(src).toContain('<NameText token="nameOrder" maxLines={null} style={s.eventName}>{listing.event_name}</NameText>');
    expect(src).not.toMatch(/token="nameOrder" maxLines=\{2\}/);
  });
});

describe('2 — no "From a fan" on the owner\'s proof-waived inventory (web #111)', () => {
  it('RC4: showsFanBadge is the web rule — a waived listing has no pill; everything else keeps it', async () => {
    const { showsFanBadge } = await import('@/src/lib/listing/proofPresentation');
    expect(showsFanBadge({ proof_waived_at: '2026-10-15T23:55:00Z', proof_status: 'pending_review' })).toBe(false);
    expect(showsFanBadge({ proof_waived_at: '2026-10-15T23:55:00Z', proof_status: 'approved' })).toBe(false);
    expect(showsFanBadge({ proof_waived_at: null, proof_status: 'approved' })).toBe(true);
    expect(showsFanBadge({ proof_status: 'pending_review' })).toBe(true);
  });

  it('RC5: the hero draws the pill only when told to, and leaves no empty badge row behind', async () => {
    const withPill = await mountHero({ showsFanBadge: true });
    expect(findElement(withPill.output, (el) => el.type === 'FromAFanBadge')).toBeDefined();

    const without = await mountHero({ showsFanBadge: false });
    expect(findElement(without.output, (el) => el.type === 'FromAFanBadge')).toBeUndefined();
    const emptyBadgeRow = findElement(without.output, (el) =>
      el.type === 'View' && flat(el.props.style).alignSelf === 'flex-start' && flat(el.props.style).marginBottom !== undefined);
    expect(emptyBadgeRow, 'the badge wrapper goes with the badge').toBeUndefined();
  });

  it('RC6: the screen decides from the loaded row, and says nothing about provenance before it loads', () => {
    const src = code('src/screens/ListingDetailScreen.tsx');
    const heroes = src.match(/<ListingHero[\s\S]*?\/>/g) ?? [];
    expect(heroes).toHaveLength(2);
    // The handoff branch paints while the row is still loading: provenance is unknown there.
    expect(heroes[0]).toContain('showsFanBadge={false}');
    expect(heroes[1]).toContain('showsFanBadge={showsFanBadge(listing)}');
  });
});
