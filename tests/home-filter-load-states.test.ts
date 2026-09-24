/**
 * F-HOME-1 — Home's "Recently sold" and "Ended" filters never report an empty marketplace they cannot see.
 *
 * Owner, Build 19 (f412d10), 2026-09-17 at 5:57 PM and again at 6:46 PM Eastern, Airplane Mode on with Wi-Fi
 * off: selecting Recently sold showed "NOTHING SOLD YET / Completed sales show up here." and Ended showed
 * "NO ENDED AUCTIONS / Auctions that closed without a sale show up here." — with no error, no offline banner,
 * no Retry and no spinner. The screen stayed that way through reconnection; a pull-to-refresh is what brought
 * the listings back (owner's correction, timing approximate).
 *
 * Cause: the two filter datasets are lazy and were the only reads on the screen with no loading flag and no
 * error state — `if (error) { console.warn(...); return; }` — while the chip flips immediately. The main feed
 * classifies its own failures, so the screen-level offline state could never mask this.
 *
 * Same defect class as F-BIDS-1, and this fix follows that pattern: loading is a state, a failure is
 * classified, rows already on screen survive a failed refresh with a visible notice, and the settled empty
 * copy is reserved for a read that actually returned nothing.
 *
 * These tests run the REAL app/(tabs)/home.tsx through the hook dispatcher with every read under test
 * control, and assert on what the shopper would see. Not a device result.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { HOME_FILTER_REFRESH_FAILED_COPY } from '@/src/lib/home/filterLoad';
import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

type Reply = { data: unknown; error: { message: string } | null };

const h = vi.hoisted(() => {
  const deferred = () => {
    let resolve!: (r: Reply) => void;
    const promise = new Promise<Reply>((r) => { resolve = r; });
    return { promise, resolve };
  };
  return {
    deferred,
    active: [] as ReturnType<typeof deferred>[],
    sold: [] as ReturnType<typeof deferred>[],
    ended: [] as ReturnType<typeof deferred>[],
    network: { isOffline: false },
    focus: { current: null as null | (() => void) },
  };
});

// The migrated screens read the resolved appearance. These suites assert behaviour, not colour, so
// the boundary is mocked to Midnight — whose values ARE the v2 tokens, so nothing they pin moves.
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return {
    useTheme: () => ({ scheme: 'dark', palette: dark }),
    useAppearancePreference: () => ({ preference: 'system', setPreference: () => {} }),
  };
});
vi.mock('react-native', () => ({
  Animated: {
    View: 'Animated.View',
    Value: class { constructor(public v: number) {} interpolate() { return this; } setValue() {} },
    timing: () => ({ start: () => {} }),
    spring: () => ({ start: () => {} }),
  },
  FlatList: 'FlatList', Pressable: 'Pressable', RefreshControl: 'RefreshControl', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {} } }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: (cb: () => void) => { h.focus.current = cb; } }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => h.network }));
vi.mock('@/src/hooks/useReducedMotion', () => ({ useReducedMotion: () => true }));
vi.mock('@/src/hooks/useBlockedUserIds', () => ({
  useBlockedUserIds: () => ({ blockedIds: new Set<string>() }),
  applyBlockedSellerFilter: (q: unknown) => q,
}));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({ Chip: 'Chip', EmptyState: 'EmptyState' }));
vi.mock('@/src/components/nav/dockContext', () => ({ useDockScroll: () => ({ onScroll: () => {}, expand: () => {} }) }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
// V3: home renders the feature + rows now; both are presentation-only and mocked flat here.
vi.mock('@/src/components/discovery/FeedRow', () => ({ FeedRow: 'FeedRow' }));
vi.mock('@/src/components/discovery/HomeFeature', () => ({ HomeFeature: 'HomeFeature' }));
vi.mock('@/src/components/discovery/DiscoveryGridSkeleton', () => ({ DiscoveryGridSkeleton: 'DiscoveryGridSkeleton' }));
vi.mock('@/src/components/discovery/FilterSheet', () => ({ FilterSheet: 'FilterSheet' }));
vi.mock('@/src/components/discovery/HomeHeader', () => ({ HomeHeader: 'HomeHeader' }));
vi.mock('@/src/lib/listing/cardHandoff', () => ({ stageCardHandoff: () => {} }));
// The real module loads .ttf assets, which vitest cannot parse; styles are not what these tests assert.
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
vi.mock('@/src/lib/supabase', () => {
  const chain = (queue: { promise: Promise<Reply> }[]) => {
    const d = h.deferred();
    queue.push(d);
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'eq', 'neq', 'order', 'limit']) q[m] = () => q;
    q.then = (ok: (v: Reply) => unknown, bad?: (e: unknown) => unknown) => d.promise.then(ok, bad);
    return q;
  };
  // The three reads are told apart by the filters the screen applies, in call order per dataset.
  const router = () => {
    const q: Record<string, unknown> = {};
    let kind: 'active' | 'sold' | 'ended' = 'active';
    q.select = () => q;
    q.eq = (col: string, val: string) => {
      if (col === 'status' && val === 'sold') kind = 'sold';
      if (col === 'auction_status' && val === 'ended') kind = 'ended';
      return q;
    };
    q.neq = () => q;
    q.order = () => q;
    q.limit = () => {
      const queue = kind === 'sold' ? h.sold : kind === 'ended' ? h.ended : h.active;
      return chain(queue as never);
    };
    return q;
  };
  return {
    supabase: {
      from: () => router(),
      auth: { getUser: async () => ({ data: { user: null } }) },
      rpc: () => ({ returns: () => ({ maybeSingle: async () => ({ data: null }) }) }),
      // The realtime feed is not under test; it must exist so the screen mounts.
      channel: () => {
        const ch: Record<string, unknown> = {};
        ch.on = () => ch;
        ch.subscribe = () => ch;
        return ch;
      },
      removeChannel: () => {},
    },
  };
});

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

const row = (n: number, extra: Record<string, unknown> = {}) => ({
  id: `l-${n}`, event_name: `Device D${n}`, venue: 'Club Device', status: 'active', auction_status: 'active',
  current_bid: 100, starting_bid: 50, ends_at: '2099-01-01T00:00:00Z', event_date: '2026-10-08',
  event_time: '21:00', neighborhood: 'Wynwood', ticket_type: 'GA', cover_image_path: null,
  seller_id: 's-1', created_at: '2026-09-01T00:00:00Z', buy_now_enabled: false, buy_now_price: null,
  reserved_until: null, reserved_by: null, winner_user_id: null, winning_bid_amount: null, ...extra,
});
const SOLD = [row(6, { status: 'sold' }), row(1, { status: 'sold' })];
const ACTIVE = [row(9), row(8)];
const OK = (data: unknown): Reply => ({ data, error: null });
const FAIL: Reply = { data: null, error: { message: 'upstream timeout' } };

type View =
  | 'loading'   // the skeleton is on screen
  | 'blank'     // nothing at all — not a state the shopper should ever see
  | { state: unknown }
  | { empty: string }
  | { rows: number; notice: string | null };

/** What the shopper sees under the active chip. */
function view(host: HookHost): View {
  const tree = host.output;
  const list = findElement(tree, (el) => el.type === 'FlatList') as Element;
  const data = (list.props.data ?? []) as unknown[];
  if (data.length > 0) {
    const alert = findElement(list.props.ListHeaderComponent, (el) => el.props.accessibilityRole === 'alert');
    const text = alert ? findElement(alert, (el) => typeof el.props.children === 'string') : undefined;
    return { rows: data.length, notice: text ? String(text.props.children) : null };
  }
  if (findElement(list.props.ListHeaderComponent, (el) => el.type === 'DiscoveryGridSkeleton')) return 'loading';
  const empty = list.props.ListEmptyComponent;
  const screen = findElement(empty, (el) => el.type === 'ScreenState');
  if (screen) return { state: screen.props.state };
  const settled = findElement(empty, (el) => el.type === 'EmptyState');
  if (settled) return { empty: String(settled.props.title) };
  // Nothing rendered at all. Distinct from loading on purpose: a mutant that drops the loading flag used to
  // read as "loading" here and survive.
  return 'blank';
}

/** Apply a quick chip the way the owner does: through the FILTERS sheet. */
function applyFilter(host: HookHost, chip: string): void {
  const sheet = findElement(host.output, (el) => el.type === 'FilterSheet') as Element;
  (sheet.props.onApply as (n: Record<string, unknown>) => void)({
    chip, neighborhoods: new Set<string>(), categories: new Set<string>(), priceMin: '', priceMax: '',
  });
  host.flush();
}

async function pullToRefresh(host: HookHost): Promise<void> {
  const list = findElement(host.output, (el) => el.type === 'FlatList') as Element;
  const control = list.props.refreshControl as Element;
  void (control.props.onRefresh as () => Promise<void>)();
  await flush();
  host.flush();
}

async function mountHome(): Promise<HookHost> {
  const { default: HomeScreen } = await import('@/app/(tabs)/home');
  const host = new HookHost(() => (HomeScreen as () => unknown)(), new Map());
  host.mount();
  await flush();
  host.flush();
  // Settle the main feed so the screen is past its own loading phase.
  h.active[0]?.resolve(OK(ACTIVE));
  await flush();
  host.flush();
  return host;
}

beforeEach(() => {
  h.active.length = 0; h.sold.length = 0; h.ended.length = 0;
  h.network.isOffline = false;
  h.focus.current = null;
  vi.resetModules();
});

describe('F-HOME-1 — a filter that cannot load never claims the marketplace is empty', () => {
  it('H1: while the sold read is in flight the filter shows loading, not "Nothing sold yet"', async () => {
    const host = await mountHome();
    applyFilter(host, 'recently_sold');
    await flush();
    host.flush();

    expect(view(host)).toBe('loading');
  });

  it('H2: a failed sold read shows a classified failure, never the empty copy', async () => {
    const host = await mountHome();
    applyFilter(host, 'recently_sold');
    await flush();
    h.sold[0].resolve(FAIL);
    await flush();
    host.flush();

    expect(view(host)).toEqual({ state: 'error' });
  });

  it('H3: offline at the time of failure is classified offline', async () => {
    h.network.isOffline = true;
    const host = await mountHome();
    applyFilter(host, 'recently_sold');
    await flush();
    h.sold[0].resolve(FAIL);
    await flush();
    host.flush();

    expect(view(host)).toEqual({ state: 'offline' });
  });

  it('H4: the Ended filter behaves the same — the defect was in both datasets', async () => {
    const host = await mountHome();
    applyFilter(host, 'ended');
    await flush();
    expect(view(host)).toBe('loading');

    h.ended[0].resolve(FAIL);
    await flush();
    host.flush();
    expect(view(host)).toEqual({ state: 'error' });
  });

  it('H5: a read that genuinely returns nothing still shows the settled empty copy', async () => {
    const host = await mountHome();
    applyFilter(host, 'recently_sold');
    await flush();
    h.sold[0].resolve(OK([]));
    await flush();
    host.flush();

    expect(view(host)).toEqual({ empty: 'Nothing sold yet' });
  });

  it('H6: a successful read renders the rows (regression guard)', async () => {
    const host = await mountHome();
    applyFilter(host, 'recently_sold');
    await flush();
    h.sold[0].resolve(OK(SOLD));
    await flush();
    host.flush();

    expect(view(host)).toEqual({ rows: 2, notice: null });
  });

  it('H7: a failed refresh keeps the rows already on screen, with a failure notice', async () => {
    const host = await mountHome();
    applyFilter(host, 'recently_sold');
    await flush();
    h.sold[0].resolve(OK(SOLD));
    await flush();
    host.flush();
    expect(view(host)).toEqual({ rows: 2, notice: null });

    await pullToRefresh(host);
    h.sold[1].resolve(FAIL);
    await flush();
    host.flush();

    expect(view(host)).toEqual({ rows: 2, notice: HOME_FILTER_REFRESH_FAILED_COPY.error });
  });

  it('H8: the pull-to-refresh that recovers the screen clears the failure', async () => {
    // The owner recovered the real screen with exactly this gesture.
    const host = await mountHome();
    applyFilter(host, 'recently_sold');
    await flush();
    h.sold[0].resolve(FAIL);
    await flush();
    host.flush();
    expect(view(host)).toEqual({ state: 'error' });

    await pullToRefresh(host);
    h.sold[1].resolve(OK(SOLD));
    await flush();
    host.flush();

    expect(view(host)).toEqual({ rows: 2, notice: null });
  });

  it('H9: Retry from the failure state re-reads the same dataset', async () => {
    const host = await mountHome();
    applyFilter(host, 'recently_sold');
    await flush();
    h.sold[0].resolve(FAIL);
    await flush();
    host.flush();

    const list = findElement(host.output, (el) => el.type === 'FlatList') as Element;
    const screen = findElement(list.props.ListEmptyComponent, (el) => el.type === 'ScreenState') as Element;
    void (screen.props.onRetry as () => void | Promise<void>)();
    await flush();
    host.flush();

    expect(h.sold.length).toBe(2);
    h.sold[1].resolve(OK(SOLD));
    await flush();
    host.flush();
    expect(view(host)).toEqual({ rows: 2, notice: null });
  });

  it('H10: a failed filter never disturbs the main feed — switching back to All shows its rows', async () => {
    const host = await mountHome();
    applyFilter(host, 'recently_sold');
    await flush();
    h.sold[0].resolve(FAIL);
    await flush();
    host.flush();
    expect(view(host)).toEqual({ state: 'error' });

    applyFilter(host, 'all'); // back to the main feed
    await flush();
    host.flush();

    expect(view(host)).toEqual({ rows: 2, notice: null });
  });

  it('H11: the offline refresh wording differs from the generic one, and both are pinned', async () => {
    expect(HOME_FILTER_REFRESH_FAILED_COPY.offline).not.toBe(HOME_FILTER_REFRESH_FAILED_COPY.error);
    expect(HOME_FILTER_REFRESH_FAILED_COPY.offline.length).toBeGreaterThan(0);
    expect(HOME_FILTER_REFRESH_FAILED_COPY.error.length).toBeGreaterThan(0);
  });
});
