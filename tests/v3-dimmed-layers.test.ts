/**
 * Dimming is for artwork. Text under a dimmed layer is a contrast multiplier nothing else measures
 * (owner 2026-09-24: "keep meaningful text outside dimmed artwork layers").
 *
 * Four cards recede a sold, ended or cancelled item by dropping opacity, and three of them wrapped
 * text in it. Measured in Daylight, over the canvas:
 *
 *   FeedRow            the whole row at 0.55 — the words "Sold" / "Ended" fall to 2.71:1
 *   SellerListingCard  the whole card at 0.55 — "Cancelled" and the live deadline fall with it
 *   DiscoveryCard      the status Badge sits INSIDE the artwork wrapper, so the word dims to 55%
 *   BidCard            correct already: the wrapper holds only EventMedia, the Badge sits outside
 *
 * The rule this file enforces is structural, not a per-file pin: render each card in its dimmed
 * state and walk the tree carrying the product of every ancestor's opacity. Any Text under a dimmed
 * ancestor fails, wherever it is added. Artwork may still be dimmed — that is what the recession is
 * for, and each card is asserted to keep it.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });
process.env.EXPO_PUBLIC_SUPABASE_URL = 'https://example.supabase.co';

const th = vi.hoisted(() => ({ scheme: 'light' as 'light' | 'dark' }));

vi.mock('@/src/theme/appearance', async () => {
  const { paletteFor } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: th.scheme, palette: paletteFor(th.scheme) }) };
});
vi.mock('react-native', () => ({
  Text: 'Text', View: 'View', Pressable: 'Pressable', Image: 'Image',
  Animated: { View: 'Animated.View', Text: 'Animated.Text', Value: class { interpolate() { return 0; } setValue() {} }, timing: () => ({ start: (cb?: () => void) => cb?.() }) },
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1, absoluteFillObject: {} },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  useWindowDimensions: () => ({ width: 390, height: 844 }),
}));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/ui', () => ({
  Badge: 'Badge', Tappable: 'Tappable', Button: 'Button',
  usePressScale: () => ({ scale: 1, onPressIn: () => {}, onPressOut: () => {} }),
}));
vi.mock('@/src/components/NameText', () => ({ NameText: 'NameText' }));
vi.mock('@/src/components/PriceDisplay', () => ({ PriceDisplay: 'PriceDisplay' }));
vi.mock('@/src/components/VerifiedSellerBadge', () => ({ default: 'VerifiedSellerBadge' }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
vi.mock('@/src/lib/feedback/haptics', () => ({ hapticSelect: () => {}, hapticSuccess: () => {} }));

import { HookHost, type Element } from './helpers/nav-stack-harness';

/** Every node paired with the product of the opacities on it and on all of its ancestors. */
function withEffectiveOpacity(node: unknown, acc = 1, out: { el: Element; opacity: number }[] = []) {
  if (Array.isArray(node)) { node.forEach((n) => withEffectiveOpacity(n, acc, out)); return out; }
  if (!node || typeof node !== 'object') return out;
  const el = node as Element;
  const flat: Record<string, unknown> = {};
  const walk = (s: unknown) => { if (Array.isArray(s)) s.forEach(walk); else if (s && typeof s === 'object') Object.assign(flat, s); };
  walk(el.props?.style);
  const here = typeof flat.opacity === 'number' ? acc * flat.opacity : acc;
  out.push({ el, opacity: here });
  withEffectiveOpacity(el.props?.children, here, out);
  return out;
}

/** Text, and the Badge component — whose whole job is to render a word. */
const TEXTUAL = ['Text', 'Badge', 'NameText', 'PriceDisplay'];

// FeedRow and DiscoveryCard take a resolved `presentation` (src/lib/listing/cardState.ts); the
// seller card takes a listing row. `ended` is the state that dims.
const PRESENTATION = {
  status: 'ended' as const,
  statusLabel: 'Ended',
  statusTone: 'neutral' as const,
  priceLabel: 'Final bid',
  actionHint: 'View listing',
};

const FEED_PROPS = {
  eventName: 'An Event', venue: 'A Venue', eventDate: '2026-01-01', eventTime: '20:00',
  quantity: 1, ticketType: 'GA', coverPath: null, presentation: PRESENTATION,
  bidCount: 3, priceAllIn: '$110', endsAt: '2026-01-01T00:00:00Z', nowMs: Date.parse('2026-01-02'),
  onPress: () => {},
};

const CANCELLED_LISTING = {
  id: 'l1', event_name: 'An Event', venue: 'A Venue', cover_image_path: null,
  ends_at: '2026-01-01T00:00:00Z', sold_at: null, status: 'cancelled',
  auction_status: 'cancelled', current_bid: 10000, bid_count: 3, buy_now_price: null,
  quantity: 1, starting_bid: 5000,
};

beforeEach(() => { th.scheme = 'light'; vi.resetModules(); });

async function mount(path: string, pick: (m: Record<string, unknown>) => unknown, props: unknown) {
  const mod = await import(/* @vite-ignore */ path) as Record<string, unknown>;
  const exported = pick(mod);
  const Fn = (typeof exported === 'function'
    ? exported
    : (exported as { type: (p: unknown) => unknown }).type) as (props: unknown) => unknown;
  const host = new HookHost(() => Fn(props), new Map());
  host.mount(); host.flush();
  return host;
}

const CASES: { name: string; mount: () => Promise<HookHost> }[] = [
  {
    name: 'FeedRow (ended)',
    mount: () => mount('@/src/components/discovery/FeedRow', (m) => m.FeedRow, FEED_PROPS),
  },
  {
    name: 'DiscoveryCard (ended)',
    mount: () => mount('@/src/components/discovery/DiscoveryCard', (m) => m.DiscoveryCard, FEED_PROPS),
  },
  {
    name: 'SellerListingCard (cancelled)',
    mount: () => mount('@/src/components/SellerListingCard', (m) => m.SellerListingCard ?? m.default,
      { listing: CANCELLED_LISTING, onPress: () => {} }),
  },
];

describe('dimming recedes artwork, never text', () => {
  for (const c of CASES) {
    it(`DL-${c.name}: no text is scaled by an ancestor opacity, and the artwork still recedes`, async () => {
      for (const scheme of ['light', 'dark'] as const) {
        th.scheme = scheme;
        vi.resetModules();
        const host = await c.mount();
        const nodes = withEffectiveOpacity(host.output);
        const textual = nodes.filter((n) => TEXTUAL.includes(String(n.el.type)));
        expect(textual.length, `${c.name} ${scheme}: expected text`).toBeGreaterThan(0);
        for (const t of textual) {
          expect(t.opacity, `${c.name} ${scheme}: ${String(t.el.type)} is dimmed by an ancestor`).toBe(1);
        }
        // The recession itself is kept: something in the card is still dimmed.
        expect(nodes.some((n) => n.opacity < 1), `${c.name} ${scheme}: artwork should recede`).toBe(true);
      }
    });
  }
});
