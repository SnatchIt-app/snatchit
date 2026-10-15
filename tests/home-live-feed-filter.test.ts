/**
 * The live feed shows live listings only, decided by the read itself (owner-directed feed cleanup, A,
 * 2026-10-14; verified in production 02:15Z).
 *
 * THE BUG. Home's default read fetched the newest 50 rows with `status = 'active'` and dropped dead rows
 * on the phone. Ended and cancelled auctions keep `status = 'active'` forever, so in production 49 of the
 * 50 fetched rows were thrown away, and once 50 dead rows sat ahead of a live listing that listing could
 * never appear (there is no load-more). Separately, `isListingEnded` only dropped `auction_status ===
 * 'ended'` or a past `ends_at`, so a listing CANCELLED before its `ends_at` stayed in the default feed as an
 * "Ended" card (c8d04339, cancelled 02:11Z, ends_at 2026-10-18, still on RC5 Home).
 *
 * THE FIX. The default read filters `auction_status = 'active'` and `ends_at > now` before `limit(50)`, with
 * a stable `id` tie-breaker after `created_at` so the 50-row window does not shift between equal
 * timestamps; the client keeps a defence-in-depth check that drops anything not `active` or past
 * `ends_at`. The Sold and Ended chip reads are unchanged. Explore's search and a seller's public profile
 * get the same `ends_at > now` filter and tie-breaker (they already filtered `auction_status`).
 *
 * SEED SELLERS (owner instruction relayed by A, 2026-10-14). The App Review seed accounts' sold demo listings
 * come out of public discovery by FILTERING the only public read of sold listings (Home's "Recently sold"),
 * with no status or record change. Every user-history screen still shows them to the users involved.
 *
 * LF1/LF2/LF5/LF6 run the REAL app/(tabs)/home.tsx through the hook dispatcher with every read recorded.
 * LF3/LF4/LF7 pin reads by source. Not a device result.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

type Reply = { data: unknown; error: { message: string } | null };
type Call = [string, ...unknown[]];

const h = vi.hoisted(() => ({
  /** Every `from('listings')` chain, with its calls in order. */
  queries: [] as { calls: [string, ...unknown[]][] }[],
  /** What the default read answers. Deliberately NOT filtered by the mock: the client must still drop dead rows. */
  rows: [] as Record<string, unknown>[],
  focus: { current: null as null | (() => void) },
  /** Realtime handlers the screen subscribed, by postgres_changes event. */
  realtime: {} as Record<string, (payload: unknown) => unknown>,
  appState: { current: null as null | ((s: string) => void) },
}));

vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return {
    useTheme: () => ({ scheme: 'dark', palette: dark }),
    useAppearancePreference: () => ({ preference: 'system', setPreference: () => {} }),
  };
});
vi.mock('react-native', () => ({
  // N3: the screen's foreground listener is captured so the tests can send the app away and back.
  AppState: {
    currentState: 'active',
    addEventListener: (_t: string, cb: (s: string) => void) => { h.appState.current = cb; return { remove: () => {} }; },
  },
  FlatList: 'FlatList', Pressable: 'Pressable', RefreshControl: 'RefreshControl',
  Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1 },
}));
vi.mock('expo-router', () => ({ router: { push: () => {} } }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: (cb: () => void) => { h.focus.current = cb; } }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }) }));
vi.mock('@/src/hooks/useBlockedUserIds', () => ({
  useBlockedUserIds: () => ({ blockedIds: new Set<string>() }),
  applyBlockedSellerFilter: (q: unknown) => q,
}));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({ Chip: 'Chip', EmptyState: 'EmptyState' }));
vi.mock('@/src/components/discovery/DiscoveryGridSkeleton', () => ({ DiscoveryGridSkeleton: 'DiscoveryGridSkeleton' }));
vi.mock('@/src/components/discovery/FilterSheet', () => ({ FilterSheet: 'FilterSheet' }));
vi.mock('@/src/components/discovery/HomeHeader', () => ({ HomeHeader: 'HomeHeader' }));
vi.mock('@/src/components/discovery/HomeFeature', () => ({ HomeFeature: 'HomeFeature' }));
vi.mock('@/src/components/discovery/FeedRow', () => ({ FeedRow: 'FeedRow' }));
vi.mock('@/src/lib/listing/cardHandoff', () => ({ stageCardHandoff: () => {} }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6 }));
vi.mock('@/src/components/nav/dockContext', () => ({ useDockScroll: () => ({ onScroll: () => {}, expand: () => {} }) }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/lib/nav/dockAvatar', () => ({ setDockAvatar: () => {} }));
vi.mock('@/src/lib/supabase', () => {
  // Records every method call on the chain. Any method the screen uses is recorded, so a new filter
  // cannot slip past the harness by being unknown to it.
  const chain = () => {
    const rec = { calls: [] as [string, ...unknown[]][] };
    h.queries.push(rec);
    const isSold = () => rec.calls.some(([m, c, v]) => m === 'eq' && c === 'status' && v === 'sold');
    const isEnded = () => rec.calls.some(([m, c, v]) => m === 'eq' && c === 'auction_status' && v === 'ended');
    const q: Record<string | symbol, unknown> = new Proxy({}, {
      get(_t, prop) {
        if (prop === 'then') {
          return (ok: (v: Reply) => unknown, bad?: (e: unknown) => unknown) =>
            Promise.resolve({ data: isSold() || isEnded() ? [] : h.rows, error: null } as Reply).then(ok, bad);
        }
        if (typeof prop !== 'string') return undefined;
        return (...args: unknown[]) => { rec.calls.push([prop, ...args]); return q; };
      },
    });
    return q;
  };
  return {
    supabase: {
      from: () => chain(),
      auth: { getUser: async () => ({ data: { user: null } }) },
      rpc: () => ({ returns: () => ({ maybeSingle: async () => ({ data: null }) }) }),
      channel: () => {
        const ch: Record<string, unknown> = {};
        ch.on = (_type: string, filter: { event: string }, cb: (p: unknown) => unknown) => { h.realtime[filter.event] = cb; return ch; };
        ch.subscribe = () => ch;
        return ch;
      },
      removeChannel: () => {},
    },
  };
});

const row = (id: string, extra: Record<string, unknown> = {}) => ({
  id, seller_id: 'seller-1', event_name: `Event ${id}`, venue: 'Lantern Room',
  event_date: '2099-10-24', event_time: '19:30:00', quantity: 1, ticket_type: 'GA',
  status: 'active', auction_status: 'active', buy_now_enabled: true, buy_now_price: 5000,
  current_bid: 5000, starting_bid: 5000, bid_count: 0, ends_at: '2099-01-01T00:00:00Z',
  neighborhood: 'Wynwood', category: 'nightlife', cover_image_path: null, created_at: '2026-09-01',
  reserved_until: null, reserved_by: null, winner_user_id: null, winning_bid_amount: null, ...extra,
});

/** The four shapes production holds under `status = 'active'`. Only the first is live. */
const FIXTURE = [
  row('live'),
  row('cancelled-future', { auction_status: 'cancelled' }),
  row('ended-future', { auction_status: 'ended' }),
  row('live-but-expired', { ends_at: '2020-01-01T00:00:00Z' }),
];

async function mountHome(): Promise<HookHost> {
  const mod = await import('@/app/(tabs)/home');
  const Home = mod.default as (p: unknown) => unknown;
  const host = new HookHost(() => Home({}), new Map());
  host.mount();
  for (let i = 0; i < 8; i++) { await Promise.resolve(); host.flush(); }
  return host;
}

/** Ids the shopper sees under the current chip. */
function visibleIds(host: HookHost): string[] {
  const list = findElement(host.output, (el) => el.type === 'FlatList') as Element;
  return ((list.props.data ?? []) as { id: string }[]).map((l) => l.id);
}

async function applyChip(host: HookHost, chip: string): Promise<void> {
  const sheet = findElement(host.output, (el) => el.type === 'FilterSheet') as Element;
  (sheet.props.onApply as (n: Record<string, unknown>) => void)({
    chip, neighborhoods: new Set<string>(), categories: new Set<string>(), priceMin: '', priceMax: '',
  });
  for (let i = 0; i < 8; i++) { await Promise.resolve(); host.flush(); }
}

const idx = (calls: Call[], pred: (c: Call) => boolean) => calls.findIndex(pred);
const isLimit = (n: number) => (c: Call) => c[0] === 'limit' && c[1] === n;

beforeEach(() => {
  h.queries = [];
  h.rows = FIXTURE;
  h.focus.current = null;
  h.realtime = {};
  h.appState.current = null;
  vi.resetModules();
});

describe('Home: the default read asks for live listings only', () => {
  it('LF1: the default read filters auction_status = active and ends_at > now, orders by created_at then id, all before limit(50); the Sold and Ended reads do not', async () => {
    const host = await mountHome();
    const main = h.queries.find((q) => q.calls.some(isLimit(50)));
    expect(main, 'no default read with limit(50) was made').toBeTruthy();
    const calls = main!.calls as Call[];
    const limitAt = idx(calls, isLimit(50));

    const liveAt = idx(calls, (c) => c[0] === 'eq' && c[1] === 'auction_status' && c[2] === 'active');
    expect(liveAt, JSON.stringify(calls)).toBeGreaterThanOrEqual(0);
    expect(liveAt).toBeLessThan(limitAt);

    const gtAt = idx(calls, (c) => c[0] === 'gt' && c[1] === 'ends_at');
    expect(gtAt, JSON.stringify(calls)).toBeGreaterThanOrEqual(0);
    expect(gtAt).toBeLessThan(limitAt);
    // An ISO string, not a Date: postgrest-js interpolates the value into the URL as-is, and a Date
    // object would send its long toString() text, which the database rejects (the whole feed would fail).
    const cutoffRaw = calls[gtAt][2];
    expect(typeof cutoffRaw).toBe('string');
    expect(String(cutoffRaw)).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
    const cutoff = Date.parse(String(cutoffRaw));
    expect(Math.abs(cutoff - Date.now())).toBeLessThan(10_000);

    const byCreated = idx(calls, (c) => c[0] === 'order' && c[1] === 'created_at');
    const byId = idx(calls, (c) => c[0] === 'order' && c[1] === 'id' && (c[2] as { ascending?: boolean })?.ascending === false);
    expect(byCreated, JSON.stringify(calls)).toBeGreaterThanOrEqual(0);
    expect(byId, 'missing the id tie-breaker after created_at').toBeGreaterThan(byCreated);
    expect(byId).toBeLessThan(limitAt);

    // The two chip datasets keep their own predicates: Sold is status = sold, Ended is auction_status = ended.
    await applyChip(host, 'recently_sold');
    await applyChip(host, 'ended');
    const sold = h.queries.find((q) => q.calls.some(([m, c, v]) => m === 'eq' && c === 'status' && v === 'sold'));
    const ended = h.queries.find((q) => q.calls.some(([m, c, v]) => m === 'eq' && c === 'auction_status' && v === 'ended'));
    expect(sold && ended, 'the chip reads were not made').toBeTruthy();
    for (const q of [sold!, ended!]) {
      expect(q.calls.some(([m, c, v]) => m === 'eq' && c === 'auction_status' && v === 'active')).toBe(false);
      expect(q.calls.some(([m, c]) => m === 'gt' && c === 'ends_at')).toBe(false);
    }
  });

  it('LF1b: every read computes its own cutoff — a return to the tab an hour later asks for ends_at > the NEW now', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    try {
      vi.setSystemTime(new Date('2030-01-01T12:00:00.000Z'));
      await mountHome();
      const first = h.queries.filter((q) => q.calls.some(isLimit(50)));
      expect(first.length).toBeGreaterThanOrEqual(1);
      vi.setSystemTime(new Date('2030-01-01T13:00:00.000Z'));
      expect(h.focus.current, 'the screen registered no focus refetch').toBeTypeOf('function');
      h.focus.current!();
      for (let i = 0; i < 8; i++) await Promise.resolve();
      const reads = h.queries.filter((q) => q.calls.some(isLimit(50)));
      expect(reads.length, 'the focus refetch made no new default read').toBeGreaterThan(first.length);
      const cutoffOf = (q: { calls: Call[] }) => String((q.calls as Call[]).find((c) => c[0] === 'gt' && c[1] === 'ends_at')?.[2]);
      expect(cutoffOf(first[0] as never)).toBe('2030-01-01T12:00:00.000Z');
      expect(cutoffOf(reads[reads.length - 1] as never)).toBe('2030-01-01T13:00:00.000Z');
    } finally {
      vi.useRealTimers();
    }
  });

  it('LF2: if dead rows reach the screen anyway, only the live one is shown under "all" and "buy_now"', async () => {
    const host = await mountHome();
    expect(visibleIds(host)).toEqual(['live']);
    await applyChip(host, 'buy_now');
    expect(visibleIds(host)).toEqual(['live']);
  });

  it('LF2 witness: the harness can show more than one row, so LF2 is not passing on an empty screen', async () => {
    h.rows = [row('live'), row('live-2', { created_at: '2026-09-02' })];
    const host = await mountHome();
    expect(visibleIds(host).sort()).toEqual(['live', 'live-2']);
  });
});

describe('Explore and a public profile filter by ends_at too', () => {
  const read = async (path: string) => (await import('node:fs')).readFileSync(path, 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

  it("LF3: explore's search read has ends_at > now and an id tie-breaker after ends_at", async () => {
    const src = await read('app/(tabs)/explore.tsx');
    // One expression for the one search read, so the filter and the tie-breaker cannot come from different queries.
    expect(src).toMatch(/\.from\('listings'\)\s*\.select\('\*'\)\s*\.eq\('status', 'active'\)\s*\.eq\('auction_status', 'active'\)\s*\.gt\('ends_at', new Date\(\)\.toISOString\(\)\)\s*\.or\([^)]*\)\s*\.order\('ends_at', \{ ascending: true \}\)\s*\.order\('id', \{ ascending: false \}\)\s*\.limit\(40\)/);
  });

  it("LF4: a seller's public profile reads active listings with ends_at > now and an id tie-breaker", async () => {
    const src = await read('app/profile/[id].tsx');
    expect(src).toMatch(/\.from\('listings'\)\.select\('\*'\)\.eq\('seller_id', sellerId\)\.eq\('status', 'active'\)\.eq\('auction_status', 'active'\)\s*\.gt\('ends_at', new Date\(\)\.toISOString\(\)\)\s*\.order\('ends_at', \{ ascending: true \}\)\s*\.order\('id', \{ ascending: false \}\)/);
  });
});

describe('Home: a listing cancelled while on screen leaves the live feed', () => {
  it('LF5: a realtime UPDATE to auction_status = cancelled hides the listing under "all" and "buy_now"', async () => {
    h.rows = [row('live'), row('live-2', { created_at: '2026-09-02' })];
    const host = await mountHome();
    expect(visibleIds(host).sort()).toEqual(['live', 'live-2']);
    const update = h.realtime.UPDATE;
    expect(update, 'the screen did not subscribe to listing UPDATEs').toBeTypeOf('function');
    // What the server sends when a seller cancels: status stays 'active', auction_status changes, ends_at is in the future.
    update({ new: { id: 'live', seller_id: 'seller-1', status: 'active', auction_status: 'cancelled', ends_at: '2099-01-01T00:00:00Z' } });
    for (let i = 0; i < 4; i++) { await Promise.resolve(); host.flush(); }
    expect(visibleIds(host)).toEqual(['live-2']);
    await applyChip(host, 'buy_now');
    expect(visibleIds(host)).toEqual(['live-2']);
  });
});

describe('Home: the App Review seed sellers are out of "Recently sold", and nowhere else', () => {
  it('LF6: the Sold read excludes exactly the two seed sellers before limit(30); the default and Ended reads do not', async () => {
    const { APP_REVIEW_SEED_SELLER_IDS } = await import('@/src/lib/home/appReviewSeedAccounts');
    expect([...APP_REVIEW_SEED_SELLER_IDS].sort()).toEqual([
      '09f1ec06-2bd5-45de-8851-2dd8af08d4eb',
      'c0b2d630-b48e-43e2-b749-d5dcbc907067',
    ]);
    const host = await mountHome();
    await applyChip(host, 'recently_sold');
    await applyChip(host, 'ended');
    const isSeedExclusion = (c: Call) => c[0] === 'not' && c[1] === 'seller_id' && c[2] === 'in'
      && String(c[3]) === `(${APP_REVIEW_SEED_SELLER_IDS.join(',')})`;
    const sold = h.queries.find((q) => q.calls.some(([m, c, v]) => m === 'eq' && c === 'status' && v === 'sold'));
    expect(sold, 'the Sold read was not made').toBeTruthy();
    const soldCalls = sold!.calls as Call[];
    const exclAt = idx(soldCalls, isSeedExclusion);
    expect(exclAt, JSON.stringify(soldCalls)).toBeGreaterThanOrEqual(0);
    expect(exclAt).toBeLessThan(idx(soldCalls, isLimit(30)));
    for (const q of h.queries.filter((x) => x !== sold)) {
      expect((q.calls as Call[]).some(isSeedExclusion), JSON.stringify(q.calls)).toBe(false);
    }
  });

  const strip = (src: string) => src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
  const read = async (path: string) => strip((await import('node:fs')).readFileSync(path, 'utf8'));

  it("LF7: the seed constant is used only by Home's Sold read; every user-history screen reads by the user's own id and filters no seller", async () => {
    // Every folder the app can import from ('@/*' maps to the repo root). A filesystem walk, so untracked files
    // count and no git checkout is needed. web/ is a separate app and is not part of this binary.
    const fs = await import('node:fs');
    const path = await import('node:path');
    const roots = ['app', 'src', 'components', 'hooks', 'constants'].filter((r) => fs.existsSync(r));
    const needles = [/APP_REVIEW_SEED_SELLER_IDS/, /appReviewSeedAccounts/, /09f1ec06-2bd5-45de-8851-2dd8af08d4eb/i, /c0b2d630-b48e-43e2-b749-d5dcbc907067/i];
    const users: string[] = [];
    const walk = (dir: string) => {
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) { if (e.name !== 'node_modules') walk(p); continue; }
        if (!/\.(ts|tsx|js|jsx|json)$/.test(e.name)) continue;
        const src = fs.readFileSync(p, 'utf8');
        if (needles.some((n) => n.test(src))) users.push(p);
      }
    };
    roots.forEach(walk);
    expect(users.sort()).toEqual(['app/(tabs)/home.tsx', 'src/lib/home/appReviewSeedAccounts.ts']);
    const home = await read('app/(tabs)/home.tsx');
    expect(home.match(/APP_REVIEW_SEED_SELLER_IDS/g)?.length).toBe(2); // the import and the Sold read

    // The seller's own listings (sold included), the own-profile sold stats, the buyer's bids and purchases,
    // and the tickets RPC (bound to auth.uid() on the server). None narrows by seller.
    const myListings = await read('app/my-listings.tsx');
    expect(myListings).toMatch(/from\('listings'\)\s*\.select\('\*'\)\s*\.eq\('seller_id', userId\)/);
    expect(myListings).not.toMatch(/\.not\(/);
    const profile = await read('app/(tabs)/profile.tsx');
    expect(profile).toMatch(/\.eq\('seller_id', user\.id\)\s*\.or\('status\.eq\.sold,auction_status\.eq\.ended'\)/);
    const bids = await read('app/(tabs)/bids.tsx');
    expect(bids).toMatch(/\.eq\('bidder_id', userId\)/);
    expect(bids).toMatch(/\.eq\('buyer_id', userId\)/);
    const tickets = await read('src/lib/tickets/api.ts');
    expect(tickets).toMatch(/supabase\.rpc\('get_my_tickets'\)/);
    for (const src of [myListings, profile, bids, tickets]) expect(src).not.toMatch(/not\('seller_id'/);
  });
});

describe('N3 — Sold and Ended are re-read, so a list loaded before the cleanup cannot linger', () => {
  const soldReads = () => h.queries.filter((q) => q.calls.some(([m, c, v]) => m === 'eq' && c === 'status' && v === 'sold')).length;
  const endedReads = () => h.queries.filter((q) => q.calls.some(([m, c, v]) => m === 'eq' && c === 'auction_status' && v === 'ended')).length;
  const liveReads = () => h.queries.filter((q) => q.calls.some(([m, c, v]) => m === 'eq' && c === 'status' && v === 'active')).length;

  it('N3a: choosing Recently sold a second time reads it again (builds 25/27 read it once per session)', async () => {
    const host = await mountHome();
    await applyChip(host, 'recently_sold');
    await applyChip(host, 'all');
    await applyChip(host, 'recently_sold');
    expect(soldReads()).toBe(2);
    await applyChip(host, 'ended');
    await applyChip(host, 'ended');
    expect(endedReads()).toBe(2);
  });

  it('N3b: returning to the app on Recently sold re-reads the live feed AND Recently sold', async () => {
    const host = await mountHome();
    await applyChip(host, 'recently_sold');
    const [live0, sold0] = [liveReads(), soldReads()];
    h.appState.current!('background');
    h.appState.current!('active');
    for (let i = 0; i < 8; i++) { await Promise.resolve(); host.flush(); }
    expect(liveReads()).toBe(live0 + 1);
    expect(soldReads()).toBe(sold0 + 1);
  });

  it('N3c: returning to the Home tab on Ended re-reads the live feed AND Ended', async () => {
    const host = await mountHome();
    await applyChip(host, 'ended');
    const [live0, ended0] = [liveReads(), endedReads()];
    h.focus.current!();
    for (let i = 0; i < 8; i++) { await Promise.resolve(); host.flush(); }
    expect(liveReads()).toBe(live0 + 1);
    expect(endedReads()).toBe(ended0 + 1);
  });

  it('N3d: an "active" event without having been away (e.g. a notification banner) does not re-read', async () => {
    const host = await mountHome();
    const live0 = liveReads();
    h.appState.current!('active');
    for (let i = 0; i < 8; i++) { await Promise.resolve(); host.flush(); }
    expect(liveReads()).toBe(live0);
  });
});
