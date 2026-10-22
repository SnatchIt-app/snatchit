/**
 * tests/saved-listing-wiring.test.ts — where the Save control and the Saved entry are mounted (C-owned
 * files: ListingHero, ListingDetailScreen, the Profile tab).
 *
 * The hero stays a layout component: it draws the control it is handed and reads nothing itself. The
 * screen owns `useSavedListing` and hands the result only to the hero it paints once the listing row
 * has loaded — never to the card-handoff hero painted while the row is still loading, and there is no
 * hero at all on the "no longer available" or failed-read screens. Profile reaches the Saved screen
 * from a "Saved listings" row in its own "Buyer" group — not under the "Seller" heading, where a screen
 * reader would read a buying feature out as a seller one, and not a bare "Saved", which VoiceOver read
 * like a status (C nit).
 *
 * The hero is mounted for real (the rc10 / v3-listing-stage mocks); the screen and Profile are pinned
 * by source, as their own suites pin them. Not a device result.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { findElement, HookHost, REPO_ROOT, type Element } from './helpers/nav-stack-harness';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });

vi.mock('@/src/theme/appearance', async () => {
  const { light } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'light', palette: light }) };
});
vi.mock('react-native', () => ({
  Animated: { View: 'Animated.View' },
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: 1 }),
  Pressable: 'Pressable', Text: 'Text', View: 'View',
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1, absoluteFill: {}, absoluteFillObject: {} },
}));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/ui', () => ({ FromAFanBadge: 'FromAFanBadge', IconButton: 'IconButton' }));
vi.mock('@/src/components/listing/SaveControl', () => ({ SaveControl: 'SaveControl', SaveNote: 'SaveNote' }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useTopInset: () => 62 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6 }));

const read = (rel: string) => readFileSync(join(REPO_ROOT, rel), 'utf8');
const code = (rel: string) => read(rel)
  .replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .replace(/(^|[^:])\/\/.*$/gm, '$1');

async function mountHero(over: Record<string, unknown> = {}) {
  const mod = await import('@/src/components/listing/ListingHero');
  const Hero = mod.ListingHero as unknown as (p: unknown) => unknown;
  const host = new HookHost(() => Hero({
    asset: { path: 'covers/a.jpg', contract: 'legacy', bucket: 'auction-media' },
    eventName: 'Neon Choir',
    venue: 'Lantern Room',
    eventDate: '2026-09-26',
    eventTime: '19:30:00',
    showsFanBadge: true,
    onBack: () => {},
    onOverflow: () => {},
    ...over,
  }), new Map());
  host.mount();
  return host;
}

function order(node: unknown): string[] {
  const kinds: string[] = [];
  const walk = (n: unknown): void => {
    if (Array.isArray(n)) { n.forEach(walk); return; }
    const el = n as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    if (el.type === 'IconButton') kinds.push(`icon:${String(el.props.glyph)}`);
    if (el.type === 'SaveControl') kinds.push('save');
    if (el.type === 'SaveNote') kinds.push('note');
    if (el.type === 'EventMedia') kinds.push('poster');
    walk(el.props.children);
  };
  walk(node);
  return kinds;
}

beforeEach(() => { vi.resetModules(); });

describe('ListingHero — draws the control it is handed, in the navigation row', () => {
  it('W1: with `save`, the bookmark sits between back and more, above the poster, wired to the screen\'s state', async () => {
    const onToggle = () => {};
    const host = await mountHero({ save: { saved: true, onToggle, note: null } });
    expect(order(host.output)).toEqual(['icon:back', 'save', 'icon:more', 'poster']);
    const save = findElement(host.output, (el) => el.type === 'SaveControl');
    expect(save?.props.saved).toBe(true);
    expect(save?.props.onToggle).toBe(onToggle);
    expect(findElement(host.output, (el) => el.type === 'SaveNote')).toBeUndefined();
  });

  it('W2: without `save` (loading, signed out, unreadable) there is no control; the seller\'s own listing keeps it without "more"', async () => {
    const none = await mountHero();
    expect(order(none.output)).toEqual(['icon:back', 'icon:more', 'poster']);
    const own = await mountHero({ onOverflow: undefined, save: { saved: false, onToggle: () => {}, note: null } });
    expect(order(own.output)).toEqual(['icon:back', 'save', 'poster']);
  });

  it('W3: a rollback note is drawn under the navigation row, above the poster', async () => {
    const host = await mountHero({ save: { saved: false, onToggle: () => {}, note: "Couldn't save this listing. Try again." } });
    expect(order(host.output)).toEqual(['icon:back', 'save', 'icon:more', 'note', 'poster']);
    expect(findElement(host.output, (el) => el.type === 'SaveNote')?.props.text).toBe("Couldn't save this listing. Try again.");
  });

  it('W4: the hero reads nothing — no data, store or hook import', () => {
    const src = code('src/components/listing/ListingHero.tsx');
    expect(src).not.toMatch(/supabase|savedStore|savedListings|useSavedListing/);
    expect(src).toContain("from '@/src/components/listing/SaveControl'");
  });
});

describe('ListingDetailScreen — owns the hook, hands it to the loaded hero only', () => {
  const src = () => code('src/screens/ListingDetailScreen.tsx');

  it('W5: the hook is enabled only once auth has resolved and the row is loaded (never in the dev harness), before any early return', () => {
    const s = src();
    expect(s).toContain("import { useSavedListing } from '@/src/hooks/useSavedListing';");
    expect(s).toMatch(/const save = useSavedListing\(\{ userId: user\?\.id, listingId: id, enabled: authReady && !!listing && !fixture \}\);/);
    // Rules of hooks: the call precedes the first conditional return of the component.
    expect(s.indexOf('useSavedListing({')).toBeLessThan(s.indexOf('if (loading && !listing && handoff) return ('));
  });

  it('W6: the card-handoff hero (row still loading) gets no control; the loaded hero does', () => {
    const s = src();
    const heroes = [...s.matchAll(/<ListingHero[\s\S]*?\/>/g)].map((m) => m[0]);
    expect(heroes).toHaveLength(2);
    expect(heroes[0]).toContain('showsFanBadge={false}');
    expect(heroes[0]).not.toContain('save=');
    expect(heroes[1]).toContain('save={save ?? undefined}');
  });
});

describe('Profile — the way in', () => {
  it('W7: a "Saved listings" row in its own "Buyer" group opens /saved; the "Seller" group does not hold it', () => {
    const s = code('app/(tabs)/profile.tsx');
    const sections = [...s.matchAll(/<AccountSection title="([^"]+)">([\s\S]*?)<\/AccountSection>/g)]
      .map((m) => ({ title: m[1], body: m[2] }));
    const holding = sections.filter((x) => x.body.includes('label="Saved listings"'));
    expect(holding.map((x) => x.title)).toEqual(['Buyer']);
    expect(holding[0].body).toMatch(/<SettingsRow label="Saved listings" onPress=\{\(\) => router\.push\('\/saved'\)\} \/>/);
    const seller = sections.find((x) => x.title === 'Seller');
    expect(seller?.body).toContain('label="My listings"');
    expect(seller?.body).not.toContain('label="Saved listings"');
  });

  it('W8: no Profile row is labelled a bare "Saved" — VoiceOver read it like a status (C nit)', () => {
    expect(code('app/(tabs)/profile.tsx')).not.toContain('label="Saved"');
  });
});
