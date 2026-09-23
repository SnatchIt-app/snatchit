/**
 * V3 bid entry (Package 2, pkg2-bid-entry): the listing is RESTATED, both compare columns are
 * all-in with the bid they are built from beneath, and the HEADLINE is the total the buyer
 * would pay — the stepper moves the bid, and the screen says so.
 *
 * Correction to the package's ③ "EXISTS" tag, verified in source before this change: the big
 * figure was `fmt$(selectedBid)` — the BID, not the total. Making the headline the total is V3
 * work, recorded as such.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

type Reply = { data: unknown; error: { message: string } | null };

const h = vi.hoisted(() => ({
  reply: null as unknown,
  user: { id: 'bidder-1' },
}));

vi.mock('react-native', () => ({
  Alert: { alert: () => {} },
  ScrollView: 'ScrollView', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {} } }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: h.user }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }) }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({
  Button: 'Button', IconButton: 'IconButton', Spinner: 'Spinner', StickyBar: 'StickyBar', Tappable: 'Tappable',
}));
vi.mock('@/src/lib/feedback/haptics', () => ({ hapticConfirm: () => {} }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
vi.mock('@/src/lib/supabase', () => {
  const chain = () => {
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'eq']) q[m] = () => q;
    q.single = async () => ({ data: h.reply, error: null } as Reply);
    return q;
  };
  return { supabase: { from: () => chain() } };
});

const flush = async () => { for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r)); };

function listing(extra: Record<string, unknown> = {}) {
  return {
    id: 'l-1', event_name: 'Neon Choir', venue: 'Lantern Room',
    event_date: '2026-09-26', event_time: '19:30:00',
    quantity: 2, ticket_type: 'GA', bid_count: 6,
    current_bid: 100, starting_bid: 50, ends_at: '2099-01-01T00:00:00Z',
    ...extra,
  };
}

async function mount(l: Record<string, unknown>) {
  h.reply = l;
  const { default: PlaceBidScreen } = await import('@/src/screens/PlaceBidScreen');
  const host = new HookHost(() => (PlaceBidScreen as (p: { id: string }) => unknown)({ id: 'l-1' }), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

const byText = (host: HookHost, text: string) =>
  findElement(host.output, (el) => el.type === 'Text' && el.props.children === text);
const allTexts = (host: HookHost): string[] => {
  const out: string[] = [];
  const walk = (node: unknown) => {
    if (Array.isArray(node)) { node.forEach(walk); return; }
    const el = node as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    if (typeof el.props.children === 'string') out.push(el.props.children);
    walk(el.props.children);
  };
  walk(host.output);
  return out;
};

beforeEach(() => { vi.resetModules(); });

describe('V3 bid entry — the listing is restated, not re-sold', () => {
  it('BE1: name in the display voice, the dated line, and the whole-listing quantity', async () => {
    const host = await mount(listing());
    const name = findElement(host.output, (el) => (el.props as { token?: string }).token === 'nameOrder');
    expect(name?.props.children).toBe('Neon Choir');
    expect(byText(host, 'Sat 26 Sep · 19:30 · Lantern Room')).toBeDefined();
    expect(byText(host, '2 × GA · sold together')).toBeDefined();
  });

  it('BE2: one ticket states its count without the "sold together" claim', async () => {
    const host = await mount(listing({ quantity: 1 }));
    expect(byText(host, '1 × GA')).toBeDefined();
    expect(byText(host, '1 × GA · sold together')).toBeUndefined();
  });
});

describe('V3 bid entry — both columns all-in, each showing the bid beneath it', () => {
  it('BE3: current and your-bid columns are all-in, each stating its own bid + fee', async () => {
    const host = await mount(listing());
    // Whole-dollar amounts render centless — the one money formatter's canonical form.
    expect(byText(host, '$110')).toBeDefined();                       // current: 100 all-in
    expect(byText(host, 'all-in · $100 bid + fee')).toBeDefined();
    expect(byText(host, 'all-in · $105 bid + fee')).toBeDefined();    // yours: floor bid 105
    expect(byText(host, 'Current bid')).toBeDefined();
    // The your-bid COLUMN carries the all-in too: the figure appears exactly twice in child
    // text — headline and your column (the sticky total rides a prop, not children) — so a
    // column reverted to the raw bid cannot hide.
    expect(allTexts(host).filter((t) => t === '$115.50')).toHaveLength(2);
  });

  it('BE4: with zero bids the market column says "Starting bid" — never a current bid nobody placed', async () => {
    const host = await mount(listing({ bid_count: 0 }));
    expect(byText(host, 'Starting bid')).toBeDefined();
    expect(byText(host, 'Current bid')).toBeUndefined();
  });
});

describe('V3 bid entry — the headline is the total; the stepper moves the bid', () => {
  it('BE5: the big figure is what the buyer would pay; the bid sits in the stepper, labelled', async () => {
    const host = await mount(listing());
    const texts = allTexts(host);
    // Headline: the all-in total of the floor bid (105 → $115.50), captioned as the total —
    // witnessed on the headline ELEMENT itself, since the same figure appears elsewhere.
    const headline = findElement(host.output, (el) =>
      String(el.props.accessibilityLabel ?? '').startsWith('Your total if you win'));
    expect(headline?.props.children).toBe('$115.50');
    expect(texts).toContain('your total if you win');
    expect(texts).toContain('Lowest you can place is $115.50 all-in');
    // The stepper carries the BID it moves, and says so.
    expect(texts).toContain('$105');
    expect(texts).toContain('your bid');
    expect(texts).toContain('Steps raise your bid. The fee and your total follow.');
  });

  it('BE6: the submit control still carries the amount it submits (O-2, regression)', async () => {
    const host = await mount(listing());
    const btn = findElement(host.output, (el) => el.type === 'Button' && typeof el.props.label === 'string');
    expect(btn?.props.label).toBe('Place bid · $115.50 all-in');
    expect(byText(host, 'Only charged if you win the auction.')).toBeDefined();
  });
});
