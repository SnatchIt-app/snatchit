/**
 * tests/saved-listings-screen.test.ts — the Saved screen (app/saved.tsx) and the route that reaches it.
 *
 * Newest first, read from the EXISTING public.saved_listings with the listing embedded by PostgREST
 * (`listing:listings(*)`). Migration 154 leaves saved_listings out of listing_private_party on purpose
 * (pgTAP 221 E1/E2): a saver who is not a party to a hidden listing gets the saved row back with a NULL
 * embed, and a deleted listing cascades its saved row away. So a null embed is counted as "no longer
 * available" — never a crash, and never a claim about why.
 *
 * The owner's "no data versus failed lookup" rule: genuinely empty, a failed read and signed out are
 * three different screens, and a failed QUIET refresh keeps the rows already shown (F-BIDS-1).
 *
 * Runs the REAL screen under the nav-stack-harness dispatcher with the read under test control.
 * Not a device result.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { findElement, HookHost, REPO_ROOT, type Element } from './helpers/nav-stack-harness';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });

type Reply = { data?: unknown; error?: { code?: string; message: string } | null };
type Call = { table: string; op: string; columns?: unknown; filters: unknown[][]; orders: unknown[][] };

const h = vi.hoisted(() => ({
  calls: [] as Call[],
  reply: (_c: Call): Promise<Reply> | Reply => ({ data: [], error: null }),
  auth: { user: { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' } as { id: string } | null, loading: false },
  network: { isOffline: false },
  focus: { current: null as null | (() => void) },
  pushed: [] as unknown[],
  replaced: [] as unknown[],
  navigated: [] as unknown[],
}));

vi.mock('@/src/lib/supabase', () => ({
  supabase: {
    from: (table: string) => {
      const call: Call = { table, op: 'select', filters: [], orders: [] };
      h.calls.push(call);
      const q: Record<string, unknown> = {};
      q.select = (cols: unknown) => { call.columns = cols; return q; };
      q.eq = (col: unknown, val: unknown) => { call.filters.push(['eq', col, val]); return q; };
      q.order = (col: unknown, opts: unknown) => { call.orders.push([col, opts]); return q; };
      q.then = (ok: (v: unknown) => unknown, bad: (e: unknown) => unknown) =>
        Promise.resolve().then(() => h.reply(call)).then(ok, bad);
      return q;
    },
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }) },
  },
}));
vi.mock('react-native', () => ({
  AccessibilityInfo: { announceForAccessibility: () => {} },
  FlatList: 'FlatList', RefreshControl: 'RefreshControl', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({
  router: {
    push: (to: unknown) => { h.pushed.push(to); },
    replace: (to: unknown) => { h.replaced.push(to); },
    navigate: (to: unknown) => { h.navigated.push(to); },
    back: () => {},
  },
}));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: (cb: () => void) => { h.focus.current = cb; } }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: h.auth.user, session: h.auth.user ? { user: h.auth.user } : null, loading: h.auth.loading }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => h.network }));
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}) }));
vi.mock('@/src/components/account/SettingsHeader', () => ({ SettingsHeader: 'SettingsHeader' }));
vi.mock('@/src/components/ui', () => ({ EmptyState: 'EmptyState' }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/discovery/DiscoveryGridSkeleton', () => ({ DiscoveryGridSkeleton: 'DiscoveryGridSkeleton' }));
vi.mock('@/src/components/discovery/FeedRow', () => ({ FeedRow: 'FeedRow' }));
vi.mock('@/src/lib/listing/cardHandoff', () => ({ stageCardHandoff: () => {} }));

const read = (rel: string) => readFileSync(join(REPO_ROOT, rel), 'utf8');
const tick = () => new Promise<void>((r) => setTimeout(r, 0));

const USER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function listing(id: string, name: string) {
  return {
    id, created_at: '2026-10-01T00:00:00Z', seller_id: 'seller-1',
    event_name: name, venue: 'Lantern Room', event_date: '2026-11-13', event_time: '22:00:00',
    quantity: 2, ticket_type: 'GA', cover_image_path: `covers/${id}.jpg`,
    status: 'active', auction_status: 'active', ends_at: '2099-01-01T00:00:00Z', reserved_until: null,
    buy_now_enabled: false, buy_now_price: null, starting_bid: 40, current_bid: 50, bid_count: 3,
  };
}

const ROWS = [
  { id: 's3', listing_id: 'L3', created_at: '2026-10-20T10:00:00Z', listing: listing('L3', 'Newest Night') },
  { id: 's2', listing_id: 'L2', created_at: '2026-10-19T10:00:00Z', listing: null },
  { id: 's1', listing_id: 'L1', created_at: '2026-10-18T10:00:00Z', listing: listing('L1', 'Older Night') },
];

async function mountScreen() {
  const mod = await import('@/app/saved');
  const Screen = mod.default as unknown as () => unknown;
  const host = new HookHost(() => Screen(), new Map());
  host.mount();
  return host;
}

const all = (node: unknown, match: (el: Element) => boolean): Element[] => {
  const out: Element[] = [];
  const walk = (n: unknown): void => {
    if (Array.isArray(n)) { n.forEach(walk); return; }
    const el = n as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    if (match(el)) out.push(el);
    for (const key of ['children', 'ListHeaderComponent', 'ListFooterComponent', 'ListEmptyComponent']) walk(el.props[key]);
  };
  walk(node);
  return out;
};
const list = (host: HookHost) => findElement(host.output, (el) => el.type === 'FlatList');
const renderedRows = (host: HookHost) => {
  const fl = list(host);
  if (!fl) return [];
  const data = fl.props.data as unknown[];
  const renderItem = fl.props.renderItem as (a: { item: unknown; index: number }) => Element;
  return data.map((item, index) => renderItem({ item, index }));
};
const texts = (host: HookHost) => all(host.output, (el) => el.type === 'Text').map((el) => el.props.children);

beforeEach(() => {
  vi.resetModules();
  h.calls = [];
  h.reply = () => ({ data: [], error: null });
  h.auth = { user: { id: USER }, loading: false };
  h.network = { isOffline: false };
  h.focus.current = null;
  h.pushed = []; h.replaced = []; h.navigated = [];
});

// ── The pure decisions ──────────────────────────────────────────────────────

describe('pure — rows, the unavailable count, and which screen shows', () => {
  it('P1: a null embed is counted as no longer available; malformed rows never crash; server order is kept', async () => {
    const { partitionSaved } = await import('@/src/lib/saved/savedState');
    const out = partitionSaved([...ROWS, null, 'junk', { id: 'x' }, { id: 's0', listing_id: 'L0', created_at: 't', listing: [] }]);
    expect(out.rows.map((r) => r.listingId)).toEqual(['L3', 'L1']);
    expect(out.rows[0]).toMatchObject({ id: 's3', listingId: 'L3', createdAt: '2026-10-20T10:00:00Z' });
    expect(out.rows[0].listing.event_name).toBe('Newest Night');
    // s2 (null embed), {id:'x'} (no embed at all) and s0 (empty embed) are saved rows with nothing readable.
    expect(out.unavailableCount).toBe(3);
    // Every saved listing id the server returned, readable or not (the store's authority).
    expect(out.savedIds).toEqual(['L3', 'L2', 'L1', 'L0']);
    expect(partitionSaved(null)).toEqual({ rows: [], unavailableCount: 0, savedIds: [] });
    expect(partitionSaved({ not: 'an array' })).toEqual({ rows: [], unavailableCount: 0, savedIds: [] });
  });

  it('P2: the unavailable line counts and never says why', async () => {
    const { unavailableLine } = await import('@/src/lib/saved/savedState');
    expect(unavailableLine(0)).toBeNull();
    expect(unavailableLine(1)).toBe('1 saved listing no longer available.');
    expect(unavailableLine(4)).toBe('4 saved listings no longer available.');
    expect(unavailableLine(4)).not.toMatch(/hidden|deleted|removed|sold|ended|cancel/i);
  });

  it('P3: auth loading, signed out, loading, failed, empty and list are separate screens', async () => {
    const { savedView, SAVED_COPY } = await import('@/src/lib/saved/savedState');
    const ready = (rows: unknown[], unavailableCount = 0, refreshFailure: 'offline' | 'error' | null = null) =>
      ({ phase: 'ready' as const, rows: rows as never[], unavailableCount, refreshFailure });
    const row = { id: 's1', listingId: 'L1', createdAt: 't', listing: listing('L1', 'A') };
    const none = () => false;
    expect(savedView({ authLoading: true, userId: null, load: { phase: 'loading' }, isUnsaved: none }).kind).toBe('auth-loading');
    expect(savedView({ authLoading: false, userId: null, load: ready([row]), isUnsaved: none }).kind).toBe('signed-out');
    expect(savedView({ authLoading: false, userId: USER, load: { phase: 'loading' }, isUnsaved: none }).kind).toBe('loading');
    expect(savedView({ authLoading: false, userId: USER, load: { phase: 'failed', failure: 'offline' }, isUnsaved: none }))
      .toEqual({ kind: 'failed', failure: 'offline' });
    expect(savedView({ authLoading: false, userId: USER, load: ready([]), isUnsaved: none }).kind).toBe('empty');
    // Only unavailable rows: something IS saved, so "Nothing saved yet" would be false.
    expect(savedView({ authLoading: false, userId: USER, load: ready([], 2), isUnsaved: none }))
      .toEqual({ kind: 'list', rows: [], unavailableLine: '2 saved listings no longer available.', refreshNote: null });
    // A row unsaved since the list loaded leaves it; if it was the last, the list is empty.
    expect(savedView({ authLoading: false, userId: USER, load: ready([row]), isUnsaved: (id) => id === 'L1' }).kind).toBe('empty');
    // A failed quiet refresh keeps the rows and says so inline.
    expect(savedView({ authLoading: false, userId: USER, load: ready([row], 0, 'error'), isUnsaved: none }))
      .toMatchObject({ kind: 'list', rows: [row], refreshNote: SAVED_COPY.refreshFailed.error });
  });
});

// ── The screen ──────────────────────────────────────────────────────────────

describe('screen — app/saved.tsx', () => {
  it('SC1: reads saved_listings newest first with the listing embedded, and draws available rows in that order', async () => {
    h.reply = () => ({ data: ROWS, error: null });
    const host = await mountScreen();
    await tick();
    expect(h.calls).toHaveLength(1);
    const call = h.calls[0];
    expect(call.table).toBe('saved_listings');
    expect(call.columns).toBe('id, listing_id, created_at, listing:listings(*)');
    expect(call.filters).toEqual([['eq', 'user_id', USER]]);
    expect(call.orders).toEqual([['created_at', { ascending: false }], ['id', { ascending: false }]]);
    const rows = renderedRows(host);
    expect(rows.map((r) => r.type)).toEqual(['FeedRow', 'FeedRow']);
    expect(rows.map((r) => r.props.eventName)).toEqual(['Newest Night', 'Older Night']);
    expect(texts(host)).toContain('1 saved listing no longer available.');
    expect(findElement(host.output, (el) => el.type === 'EmptyState')).toBeUndefined();
    // A row opens its listing.
    (rows[0].props.onPress as () => void)();
    expect(h.pushed).toEqual(['/listing/L3']);
  });

  it('SC2: nothing saved is the empty state — its own words, and a way to browse', async () => {
    h.reply = () => ({ data: [], error: null });
    const host = await mountScreen();
    await tick();
    const empty = findElement(host.output, (el) => el.type === 'EmptyState');
    expect(empty?.props.title).toBe('Nothing saved yet');
    expect(empty?.props.body).toBe('Tap the bookmark on any listing to save it here.');
    const action = empty?.props.action as { label: string; onPress: () => void };
    expect(action.label).toBe('Browse live listings');
    action.onPress();
    expect(h.navigated).toEqual(['/(tabs)/home']);
    expect(findElement(host.output, (el) => el.type === 'ScreenState')).toBeUndefined();
  });

  it('SC3: a failed first read is a failure screen, never the empty state', async () => {
    h.reply = () => ({ data: null, error: { code: 'PGRST000', message: 'upstream timeout' } });
    const host = await mountScreen();
    await tick();
    expect(findElement(host.output, (el) => el.type === 'ScreenState')?.props.state).toBe('error');
    expect(findElement(host.output, (el) => el.type === 'EmptyState')).toBeUndefined();

    vi.resetModules();
    h.reply = () => ({ data: null, error: { message: 'Network request failed' } });
    const offline = await mountScreen();
    await tick();
    expect(findElement(offline.output, (el) => el.type === 'ScreenState')?.props.state).toBe('offline');

    // Retry reads again and recovers.
    h.reply = () => ({ data: ROWS, error: null });
    const before = h.calls.length;
    await (findElement(offline.output, (el) => el.type === 'ScreenState')!.props.onRetry as () => Promise<void>)();
    await tick();
    expect(h.calls.length).toBe(before + 1);
    expect(renderedRows(offline)).toHaveLength(2);
  });

  it('SC4: signed out is a sign-in prompt, and nothing is read', async () => {
    h.auth = { user: null, loading: false };
    const host = await mountScreen();
    await tick();
    expect(h.calls).toHaveLength(0);
    const prompt = findElement(host.output, (el) => el.type === 'EmptyState');
    expect(prompt?.props.title).toBe('Sign in required');
    expect(prompt?.props.body).toBe('You need to be signed in to see your saved listings.');
    const action = prompt?.props.action as { label: string; onPress: () => void };
    expect(action.label).toBe('Sign in');
    action.onPress();
    expect(h.replaced).toEqual(['/(auth)/login']);

    // While auth is still resolving, neither the prompt nor a read.
    vi.resetModules();
    h.auth = { user: null, loading: true };
    const resolving = await mountScreen();
    await tick();
    expect(h.calls).toHaveLength(0);
    expect(findElement(resolving.output, (el) => el.type === 'EmptyState')).toBeUndefined();
    expect(findElement(resolving.output, (el) => el.type === 'DiscoveryGridSkeleton')).toBeDefined();
  });

  it('SC5: a failed refresh on focus keeps the rows on screen and says so inline', async () => {
    h.reply = () => ({ data: ROWS, error: null });
    const host = await mountScreen();
    await tick();
    expect(renderedRows(host)).toHaveLength(2);
    h.reply = () => ({ data: null, error: { code: 'PGRST000', message: 'upstream timeout' } });
    h.focus.current!();
    await tick();
    expect(renderedRows(host)).toHaveLength(2);
    expect(texts(host)).toContain("Couldn't refresh your saved listings. Showing what loaded earlier.");
    expect(findElement(host.output, (el) => el.type === 'ScreenState')).toBeUndefined();
  });

  it('SC6: a listing removed on its detail screen leaves this list at once (one in-memory state for both)', async () => {
    h.reply = () => ({ data: ROWS, error: null });
    const host = await mountScreen();
    await tick();
    expect(renderedRows(host)).toHaveLength(2);
    const store = await import('@/src/lib/saved/savedStore');
    expect(store.savedShownFor(USER, 'L3'), 'the list primed the shared state').toBe(true);
    store.toggleSaved(USER, 'L3', async () => true); // unsaved on the detail screen
    expect(renderedRows(host).map((r) => r.props.eventName)).toEqual(['Older Night']);
  });

  it('SC7: the route is registered in the root Stack', () => {
    const layout = read('app/_layout.tsx');
    const stack = layout.slice(layout.indexOf('<Stack screenOptions'), layout.indexOf('</Stack>'));
    expect(stack).toContain('<Stack.Screen name="saved" />');
  });
});
