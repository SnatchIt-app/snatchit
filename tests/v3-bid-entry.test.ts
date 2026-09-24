/**
 * V3 bid entry — the owner's FINAL bid-summary direction (2026-09-23, "implement and
 * reconcile without another approval round"):
 *
 *   identity + quantity · the market price ONCE, in the SAME UNITS as the editable bid (R-1:
 *   the underlying bid, never a fee-inclusive figure beside a fee-exclusive input) · one
 *   labelled editable bid · exactly three summary rows — Bid / Fee (10%) / Total, Total
 *   strongest — directly above a plain "Place bid" button · no side total, no "all-in", no
 *   caption or sentence inside the summary · one concise payment sentence OUTSIDE it.
 *
 * The bid value repeating inside the summary is intentional per the direction. Payment truth
 * unchanged: placing a bid charges nothing; the winner pays at checkout.
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
vi.mock('react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }) }));
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

const collect = (node: unknown, out: string[]) => {
  if (Array.isArray(node)) { node.forEach((n) => collect(n, out)); return; }
  const el = node as Element | null;
  if (!el || typeof el !== 'object' || !('props' in el)) return;
  if (typeof el.props.children === 'string') out.push(el.props.children);
  collect(el.props.children, out);
};
const textsIn = (node: unknown): string[] => { const out: string[] = []; collect(node, out); return out; };
const byText = (host: HookHost, text: string) =>
  findElement(host.output, (el) => el.type === 'Text' && el.props.children === text);
const byTestId = (host: HookHost, id: string) => findElement(host.output, (el) => el.props.testID === id);

beforeEach(() => { vi.resetModules(); });

describe('identity and the market price, in the bid\'s own units (R-1)', () => {
  it('BE1: name in the display voice, the dated line, the whole-listing quantity', async () => {
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

  it('BE3: "Current bid" shows the UNDERLYING bid — same units as the editable value — and no "all-in" anywhere', async () => {
    const host = await mount(listing());
    expect(byText(host, 'Current bid · $100')).toBeDefined();
    expect(textsIn(host.output).some((t) => /all-in/.test(t))).toBe(false);
  });

  it('BE4: with zero bids the line says "Starting bid" — never a current bid nobody placed', async () => {
    const host = await mount(listing({ bid_count: 0 }));
    expect(byText(host, 'Starting bid · $100')).toBeDefined();
    expect(textsIn(host.output).some((t) => t.startsWith('Current bid'))).toBe(false);
  });
});

describe('the editable bid and the three-row summary', () => {
  it('BE5: one labelled editable bid with minimum guidance; the old central-total copy is gone', async () => {
    const host = await mount(listing());
    expect(byText(host, 'Your bid')).toBeDefined();
    const stepVal = findElement(host.output, (el) => String(el.props.accessibilityLabel ?? '').startsWith('Your bid '));
    expect(stepVal?.props.children).toBe('$105');
    expect(byText(host, 'Minimum $105')).toBeDefined();
    const texts = textsIn(host.output);
    for (const gone of ['your total if you win', 'Lowest you can place', 'Steps raise your bid']) {
      expect(texts.some((t) => t.includes(gone))).toBe(false);
    }
    // The old sticky kicker was the standalone text "If you win"; the payment sentence may
    // still use those words mid-sentence.
    expect(texts).not.toContain('If you win');
  });

  it('BE6: exactly three rows — Bid / Fee (10%) / Total — from the existing calculation, and nothing else inside', async () => {
    const host = await mount(listing());
    const summary = byTestId(host, 'bid-summary');
    expect(summary).toBeDefined();
    const inside = textsIn(summary);
    expect(inside).toEqual(['Bid', '$105', 'Fee (10%)', '$10.50', 'Total', '$115.50']);
    // Total is the strongest row: it carries the marker the styles key off.
    expect(byTestId(host, 'bid-summary-total')).toBeDefined();
  });

  it('BE7: the plain "Place bid" button sits DIRECTLY below the summary, in the same footer; no side total', async () => {
    const host = await mount(listing());
    const footer = byTestId(host, 'bid-footer');
    expect(footer).toBeDefined();
    const btn = findElement(footer, (el) => el.type === 'Button');
    expect(btn?.props.label).toBe('Place bid');
    expect(findElement(footer, (el) => el.props.testID === 'bid-summary')).toBeDefined();
    // The footer holds only the summary and the button — no kicker, no second amount.
    expect(textsIn(footer)).toEqual(['Bid', '$105', 'Fee (10%)', '$10.50', 'Total', '$115.50']);
    expect(findElement(host.output, (el) => el.type === 'StickyBar')).toBeUndefined();
  });

  it('BE8: one concise, accurate payment sentence — outside the summary; a bid charges nothing', async () => {
    const host = await mount(listing());
    const sentence = "Placing a bid doesn't charge you. If you win, you pay the total at checkout.";
    expect(byText(host, sentence)).toBeDefined();
    expect(textsIn(byTestId(host, 'bid-summary'))).not.toContain(sentence);
    expect(textsIn(host.output).some((t) => t.includes('Only charged if you win'))).toBe(false);
  });

  it('BE9: the summary tracks the bid — a raised bid moves all three rows', async () => {
    const host = await mount(listing());
    const raise = findElement(host.output, (el) => el.props.accessibilityLabel === 'Raise bid');
    (raise?.props.onPress as () => void)();
    host.flush();
    expect(textsIn(byTestId(host, 'bid-summary'))).toEqual(['Bid', '$110', 'Fee (10%)', '$11', 'Total', '$121']);
  });
});
