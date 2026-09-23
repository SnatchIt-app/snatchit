/**
 * V3 bid entry — the DE-DUPLICATED screen (owner direction 2026-09-23, superseding the pkg2
 * board's repetitions and this suite's earlier pins):
 *
 *   identity + quantity · the market price ONCE · one clearly-labelled editable bid ·
 *   the service fee ONCE · the final total beside the "Place bid" button — and nowhere else.
 *
 * No duplicate central total, no repeated proposed-bid summary, at most one "all-in" label,
 * no sentence explaining that the stepper steps. The payment explanation is the verified
 * truth: nothing charges automatically — the winner pays through checkout (runAction
 * 'pay_now' → winner checkout → payControl's Pay, the only charging control in the app).
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
const collect = (node: unknown, out: string[]) => {
  if (Array.isArray(node)) { node.forEach((n) => collect(n, out)); return; }
  const el = node as Element | null;
  if (!el || typeof el !== 'object' || !('props' in el)) return;
  if (typeof el.props.children === 'string') out.push(el.props.children);
  collect(el.props.children, out);
};
const allTexts = (host: HookHost): string[] => { const out: string[] = []; collect(host.output, out); return out; };
const stickyTexts = (host: HookHost): string[] => {
  const bar = findElement(host.output, (el) => el.type === 'StickyBar');
  const out: string[] = [];
  collect(bar?.props.left, out);
  return out;
};

beforeEach(() => { vi.resetModules(); });

describe('V3 bid entry — each fact exactly once', () => {
  it('BE1: identity and quantity — name in the display voice, the dated line, the whole-listing count', async () => {
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

  it('BE3: the market price ONCE — one line, all-in, and no comparison columns', async () => {
    const host = await mount(listing());
    expect(byText(host, 'Current bid · $110 all-in')).toBeDefined();
    // The old two-column layout and its sub-lines are gone.
    expect(byText(host, 'all-in · $100 bid + fee')).toBeUndefined();
    expect(byText(host, 'all-in · $105 bid + fee')).toBeUndefined();
    // At most one "all-in" on the whole screen (the market line).
    expect(allTexts(host).filter((t) => /all-in/.test(t))).toHaveLength(1);
  });

  it('BE4: with zero bids the market line says "Starting bid" — never a current bid nobody placed', async () => {
    const host = await mount(listing({ bid_count: 0 }));
    expect(byText(host, 'Starting bid · $110 all-in')).toBeDefined();
    expect(allTexts(host).some((t) => t.startsWith('Current bid'))).toBe(false);
  });

  it('BE5: one labelled editable bid, minimum guidance at the point of entry, and NO central total', async () => {
    const host = await mount(listing());
    expect(byText(host, 'Your bid')).toBeDefined();
    const stepVal = findElement(host.output, (el) =>
      String(el.props.accessibilityLabel ?? '').startsWith('Your bid '));
    expect(stepVal?.props.children).toBe('$105');
    expect(byText(host, 'Minimum $105')).toBeDefined();
    // The total lives beside the action and nowhere in the scroll content.
    expect(allTexts(host).filter((t) => t === '$115.50')).toHaveLength(0);
    expect(allTexts(host).some((t) => t.includes('your total if you win'))).toBe(false);
    expect(allTexts(host).some((t) => t.startsWith('Steps raise your bid'))).toBe(false);
    expect(allTexts(host).some((t) => t.startsWith('Lowest you can place'))).toBe(false);
  });

  it('BE6: the fee ONCE, and one truthful payment sentence — the winner pays at checkout', async () => {
    const host = await mount(listing());
    expect(byText(host, 'Service fee (10%)')).toBeDefined();
    expect(byText(host, '$10.50')).toBeDefined();
    expect(byText(host,
      "Nothing is charged now. If you win, you'll pay this total at checkout to complete the purchase.",
    )).toBeDefined();
    // The old sentence implied an automatic charge on winning; the winner in fact returns to pay.
    expect(allTexts(host).some((t) => t.includes('Only charged if you win'))).toBe(false);
  });

  it('BE7: the final total sits BESIDE the plain "Place bid" action — on it or beside it, never both', async () => {
    const host = await mount(listing());
    const btn = findElement(host.output, (el) => el.type === 'Button' && typeof el.props.label === 'string');
    expect(btn?.props.label).toBe('Place bid');
    const beside = stickyTexts(host);
    expect(beside).toContain('If you win');
    expect(beside).toContain('$115.50');
  });
});
