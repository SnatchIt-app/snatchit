/**
 * F-BIDS-1 — Bids never shows "nothing here" before, or instead of, the buyer's purchases.
 *
 * Owner, Build 18 under Very Bad Network: Bids showed its empty message while loading, on an account that
 * shows 21 purchases. Bids is "bids + purchases": fetchMyBids reads public.bids, then the buyer's transfers,
 * and merges them. Cause (reproduced on f412d10): loading ended after the bids read alone, so a buyer with no
 * bids saw the empty message for the whole purchases read; and the purchases read's error was never checked,
 * so a failed read rendered as "no purchases" (and on a refresh replaced the rows already shown).
 *
 * Owner's requirements (2026-09-17): loading accounts for both requests; a failed request never looks like
 * genuine emptiness; purchases already on screen stay visible when a refresh fails, with a clear failure
 * indication.
 *
 * These tests run the REAL app/(tabs)/bids.tsx (hook dispatcher from nav-stack-harness) with both reads under
 * test control, and read what the buyer would see from the rendered tree. Not a device result.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { BIDS_REFRESH_FAILED_COPY } from '@/src/lib/bids/bidState';
import { STATE_COPY } from '@/src/lib/ui/loadState';
import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

type Reply = { data: unknown; error: { message: string } | null };

const h = vi.hoisted(() => {
  const deferred = () => {
    let resolve!: (r: { data: unknown; error: { message: string } | null }) => void;
    const promise = new Promise<{ data: unknown; error: { message: string } | null }>((r) => { resolve = r; });
    return { promise, resolve };
  };
  return {
    deferred,
    bids: [] as ReturnType<typeof deferred>[],
    transfers: [] as ReturnType<typeof deferred>[],
    session: { user: { id: 'buyer-1' } },
    dock: { onScroll: () => {}, expand: () => {} },
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
  FlatList: 'FlatList', Pressable: 'Pressable', RefreshControl: 'RefreshControl', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {} } }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: (cb: () => void) => { h.focus.current = cb; } }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ session: h.session }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => h.network }));
vi.mock('@/src/lib/coverImage', () => ({ getCoverImageUrl: () => null }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({ Chip: 'Chip', EmptyState: 'EmptyState', Skeleton: 'Skeleton' }));
vi.mock('@/src/components/nav/dockContext', () => ({ useDockScroll: () => h.dock }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/components/bids/BidCard', () => ({ BidCard: 'BidCard' }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}) }));
vi.mock('@/src/lib/supabase', () => {
  const chain = (queue: { promise: Promise<unknown> }[], make: () => { promise: Promise<unknown> }) => {
    const d = make();
    queue.push(d as never);
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'eq', 'in', 'order']) q[m] = () => q;
    q.then = (ok: (v: unknown) => unknown, bad: (e: unknown) => unknown) => d.promise.then(ok, bad);
    return q;
  };
  return {
    supabase: {
      from: (table: string) =>
        table === 'bids' ? chain(h.bids as never, h.deferred) : chain(h.transfers as never, h.deferred),
    },
  };
});

const flush = async () => { for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r)); };

function listing(n: number, extra: Record<string, unknown> = {}) {
  return {
    id: `l-${n}`, event_name: 'Sandbox L6', venue: 'Venue', ends_at: '2026-09-09T00:00:00Z', current_bid: 100,
    status: 'sold', auction_status: 'ended', winner_user_id: 'buyer-1', winning_bid_amount: 100,
    buy_now_enabled: false, buy_now_price: null, cover_image_path: null, reserved_until: null, reserved_by: null,
    ...extra,
  };
}
const purchase = (n: number) => ({
  id: `t-${n}`, listing_id: `l-${n}`, status: 'disputed', created_at: '2026-09-10T00:00:00Z',
  delivery_email: 'buyer@example.test', delivery_phone: null, listing: listing(n),
});
const bid = (n: number) => ({
  id: `b-${n}`, amount: 50, created_at: '2026-09-16T00:00:00Z', listing_id: `bl-${n}`,
  listing: { ...listing(n, { status: 'active', auction_status: 'active', winner_user_id: null, winning_bid_amount: null, ends_at: '2099-01-01T00:00:00Z' }), id: `bl-${n}` },
});
const PURCHASES = Array.from({ length: 21 }, (_, i) => purchase(i));
const OK = (data: unknown): Reply => ({ data, error: null });
const FAIL: Reply = { data: null, error: { message: 'upstream timeout' } };

type View = 'loading' | { state: unknown } | 'empty' | { rows: number; notice: string | null };

/** What the buyer sees: loading placeholders, a full-screen state, the empty message, or rows (+ any failure notice). */
function view(host: HookHost): View {
  const tree = host.output;
  if (findElement(tree, (el) => el.type === 'Skeleton')) return 'loading';
  const screen = findElement(tree, (el) => el.type === 'ScreenState');
  if (screen) return { state: screen.props.state };
  const list = findElement(tree, (el) => el.type === 'FlatList') as Element;
  const data = (list.props.data ?? []) as unknown[];
  if (data.length === 0) return 'empty';
  const alert = findElement(list.props.ListHeaderComponent, (el) => el.props.accessibilityRole === 'alert');
  const text = alert ? findElement(alert, (el) => el.type === 'Text') : undefined;
  return { rows: data.length, notice: text ? String(text.props.children) : null };
}

function listProps(host: HookHost): Record<string, unknown> {
  return (findElement(host.output, (el) => el.type === 'FlatList') as Element).props;
}
async function pullToRefresh(host: HookHost): Promise<void> {
  const control = listProps(host).refreshControl as Element;
  void (control.props.onRefresh as () => Promise<void>)();
  await flush();
}
function tapNoticeRetry(host: HookHost): void {
  const alert = findElement(listProps(host).ListHeaderComponent, (el) => el.props.accessibilityRole === 'alert')!;
  const retry = findElement(alert, (el) => el.type === 'Pressable')!;
  (retry.props.onPress as () => void)();
}

async function mountBids(): Promise<HookHost> {
  const { default: BidsScreen } = await import('@/app/(tabs)/bids');
  const host = new HookHost(() => BidsScreen(), new Map());
  host.mount();
  return host;
}
/** Mount and complete a first load that shows the 21 purchases. */
async function loadedWithPurchases(): Promise<HookHost> {
  const host = await mountBids();
  h.bids[0]!.resolve(OK([]));
  await flush();
  h.transfers[0]!.resolve(OK(PURCHASES));
  await flush();
  expect(view(host)).toEqual({ rows: 21, notice: null });
  return host;
}

beforeEach(() => {
  h.bids.length = 0;
  h.transfers.length = 0;
  h.network.isOffline = false;
});

describe('F-BIDS-1 · first load: loading lasts until BOTH reads have answered', () => {
  it('both reads finish: the 21 purchases show, with no failure notice', async () => {
    await loadedWithPurchases();
  });

  it('bids answered with none, purchases still loading: still loading, never the empty message', async () => {
    const host = await mountBids();
    h.bids[0]!.resolve(OK([]));
    await flush();
    expect(h.transfers).toHaveLength(1);
    expect(view(host)).toBe('loading');
  });

  it('bids answered with some, purchases still loading: still loading, not a partial list', async () => {
    const host = await mountBids();
    h.bids[0]!.resolve(OK([bid(1), bid(2)]));
    await flush();
    expect(view(host)).toBe('loading');
    h.transfers[0]!.resolve(OK(PURCHASES));
    await flush();
    expect(view(host)).toEqual({ rows: 23, notice: null });
  });

  it('a genuinely empty account still shows the empty message once both reads say so', async () => {
    const host = await mountBids();
    h.bids[0]!.resolve(OK([]));
    await flush();
    h.transfers[0]!.resolve(OK([]));
    await flush();
    expect(view(host)).toBe('empty');
  });
});

describe('F-BIDS-1 · first load fails: a failure never looks like emptiness', () => {
  it('purchases read fails: the error state, not the empty message', async () => {
    const host = await mountBids();
    h.bids[0]!.resolve(OK([]));
    await flush();
    h.transfers[0]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ state: 'error' });
  });

  it('purchases read fails after some bids loaded: the error state, not bids shown as if nothing was bought', async () => {
    const host = await mountBids();
    h.bids[0]!.resolve(OK([bid(1)]));
    await flush();
    h.transfers[0]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ state: 'error' });
  });

  it('bids read fails: the error state (the purchases read is not needed to say so)', async () => {
    const host = await mountBids();
    h.bids[0]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ state: 'error' });
  });

  it('the full-screen Retry loads again and shows the purchases', async () => {
    const host = await mountBids();
    h.bids[0]!.resolve(OK([]));
    await flush();
    h.transfers[0]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ state: 'error' });
    const screen = findElement(host.output, (el) => el.type === 'ScreenState')!;
    (screen.props.onRetry as () => void)();
    await flush();
    expect(view(host)).toBe('loading');
    h.bids[1]!.resolve(OK([]));
    await flush();
    h.transfers[1]!.resolve(OK(PURCHASES));
    await flush();
    expect(view(host)).toEqual({ rows: 21, notice: null });
  });
});

describe('F-BIDS-1 · a refresh fails: purchases already shown stay, with a clear failure notice', () => {
  it('pull to refresh, purchases read fails: the 21 rows stay and the notice says the refresh failed', async () => {
    const host = await loadedWithPurchases();
    await pullToRefresh(host);
    h.bids[1]!.resolve(OK([]));
    await flush();
    h.transfers[1]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ rows: 21, notice: BIDS_REFRESH_FAILED_COPY.error });
  });

  it('pull to refresh, bids read fails (the DV-ST2b case): the 21 rows stay with the notice', async () => {
    const host = await loadedWithPurchases();
    await pullToRefresh(host);
    h.bids[1]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ rows: 21, notice: BIDS_REFRESH_FAILED_COPY.error });
  });

  it('offline during the refresh: the rows stay with the offline wording', async () => {
    const host = await loadedWithPurchases();
    h.network.isOffline = true;
    await pullToRefresh(host);
    h.bids[1]!.resolve({ data: null, error: { message: 'Network request failed' } });
    await flush();
    expect(view(host)).toEqual({ rows: 21, notice: BIDS_REFRESH_FAILED_COPY.offline });
  });

  it('offline during the refresh, the purchases read fails (the likely one under a bad network): offline wording', async () => {
    const host = await loadedWithPurchases();
    h.network.isOffline = true;
    await pullToRefresh(host);
    h.bids[1]!.resolve(OK([]));
    await flush();
    h.transfers[1]!.resolve({ data: null, error: { message: 'Network request failed' } });
    await flush();
    expect(view(host)).toEqual({ rows: 21, notice: BIDS_REFRESH_FAILED_COPY.offline });
  });

  it('a genuinely empty account whose refresh fails shows the error state, not the empty message', async () => {
    const host = await mountBids();
    h.bids[0]!.resolve(OK([]));
    await flush();
    h.transfers[0]!.resolve(OK([]));
    await flush();
    expect(view(host)).toBe('empty');
    await pullToRefresh(host);
    h.bids[1]!.resolve(OK([]));
    await flush();
    h.transfers[1]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ state: 'error' });
  });

  it("the notice's Retry refreshes; success clears the notice and shows the new rows", async () => {
    const host = await loadedWithPurchases();
    await pullToRefresh(host);
    h.bids[1]!.resolve(OK([]));
    await flush();
    h.transfers[1]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ rows: 21, notice: BIDS_REFRESH_FAILED_COPY.error });
    tapNoticeRetry(host);
    await flush();
    expect(view(host)).toEqual({ rows: 21, notice: BIDS_REFRESH_FAILED_COPY.error });   // no loading takeover while rows exist
    h.bids[2]!.resolve(OK([]));
    await flush();
    h.transfers[2]!.resolve(OK(PURCHASES.slice(0, 20)));
    await flush();
    expect(view(host)).toEqual({ rows: 20, notice: null });
  });
});

describe('F-BIDS-1 · overlapping loads: only the latest load decides what the screen shows (D review of 1ad216f)', () => {
  it('a pull and a focus refresh overlap; the older fails after the newer succeeded: fresh rows, no false failure notice', async () => {
    const host = await loadedWithPurchases();
    await pullToRefresh(host);   // older: bids[1]
    h.focus.current!();          // newer (returning to the tab): bids[2]
    await flush();
    h.bids[2]!.resolve(OK([]));
    await flush();
    h.transfers[1]!.resolve(OK(PURCHASES.slice(0, 20)));
    await flush();
    expect(view(host)).toEqual({ rows: 20, notice: null });
    h.bids[1]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ rows: 20, notice: null });
  });

  it('the older succeeds after the newer failed: the older snapshot does not replace the screen or clear the failure', async () => {
    const host = await loadedWithPurchases();
    await pullToRefresh(host);   // older: bids[1]
    h.focus.current!();          // newer: bids[2]
    await flush();
    h.bids[2]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ rows: 21, notice: BIDS_REFRESH_FAILED_COPY.error });
    h.bids[1]!.resolve(OK([]));
    await flush();
    for (const d of h.transfers) d.resolve(OK(PURCHASES.slice(0, 19)));   // any purchases read the older load started
    await flush();
    expect(view(host)).toEqual({ rows: 21, notice: BIDS_REFRESH_FAILED_COPY.error });
  });

  it('the newer starts while the older awaits its purchases, then fails; the older purchases arrive last: ignored', async () => {
    const host = await loadedWithPurchases();
    await pullToRefresh(host);   // older: bids[1]
    h.bids[1]!.resolve(OK([]));
    await flush();               // older now waits on transfers[1]
    h.focus.current!();          // newer: bids[2]
    await flush();
    h.bids[2]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ rows: 21, notice: BIDS_REFRESH_FAILED_COPY.error });
    h.transfers[1]!.resolve(OK(PURCHASES.slice(0, 19)));
    await flush();
    expect(view(host)).toEqual({ rows: 21, notice: BIDS_REFRESH_FAILED_COPY.error });
  });

  it('a full-screen Retry overtaken by a focus refresh: the newer result shows at once, and loading is never left on', async () => {
    const host = await mountBids();
    h.bids[0]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ state: 'error' });
    (findElement(host.output, (el) => el.type === 'ScreenState')!.props.onRetry as () => void)();   // bids[1], shows loading
    await flush();
    expect(view(host)).toBe('loading');
    h.focus.current!();          // newer, quiet: bids[2]
    await flush();
    h.bids[2]!.resolve(OK([]));
    await flush();
    h.transfers[0]!.resolve(OK(PURCHASES));
    await flush();
    expect(view(host)).toEqual({ rows: 21, notice: null });
    h.bids[1]!.resolve(OK([]));
    await flush();
    for (const d of h.transfers) d.resolve(OK(PURCHASES));
    await flush();
    expect(view(host)).toEqual({ rows: 21, notice: null });
  });

  /** First load fails, the full-screen Retry starts (loading), and a quiet focus refresh overtakes it. */
  async function retryOvertakenByFocus(): Promise<HookHost> {
    const host = await mountBids();
    h.bids[0]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ state: 'error' });
    (findElement(host.output, (el) => el.type === 'ScreenState')!.props.onRetry as () => void)();   // bids[1]
    await flush();
    expect(view(host)).toBe('loading');
    h.focus.current!();          // newer, quiet: bids[2]
    await flush();
    return host;
  }

  it('the overtaking focus refresh FAILS at its bids read: the error state, never stuck loading; the Retry answers late and changes nothing', async () => {
    const host = await retryOvertakenByFocus();
    h.bids[2]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ state: 'error' });
    h.bids[1]!.resolve(OK([]));
    await flush();
    for (const d of h.transfers) d.resolve(OK(PURCHASES));
    await flush();
    expect(view(host)).toEqual({ state: 'error' });
  });

  it('the overtaking focus refresh FAILS at its purchases read: the error state, never stuck loading; the Retry answers late and changes nothing', async () => {
    const host = await retryOvertakenByFocus();
    h.bids[2]!.resolve(OK([]));
    await flush();
    h.transfers[0]!.resolve(FAIL);
    await flush();
    expect(view(host)).toEqual({ state: 'error' });
    h.bids[1]!.resolve(OK([]));
    await flush();
    for (const d of h.transfers) d.resolve(OK(PURCHASES));
    await flush();
    expect(view(host)).toEqual({ state: 'error' });
  });
});

describe('F-BIDS-1 · copy', () => {
  it('the notice says the refresh failed and that earlier results are shown; never the full-screen empty or error wording', () => {
    expect(BIDS_REFRESH_FAILED_COPY.error).toMatch(/couldn't refresh/i);
    expect(BIDS_REFRESH_FAILED_COPY.offline).toMatch(/offline/i);
    for (const line of Object.values(BIDS_REFRESH_FAILED_COPY)) {
      expect(line).toMatch(/earlier/i);
      expect(line).not.toMatch(/No active bids|Nothing here yet/);
      expect(line).not.toBe(STATE_COPY.error.body);
    }
  });
});
