/**
 * A blocked seller's listings must not be on Home (A's finding, 2026-09-24).
 *
 * THE BUG. `fetchListings` filtered with the `blockedIds` STATE it closed over, and both callers keep
 * the first render's copy of the function: the mount effect has `deps: []` and the focus refetch
 * `deps: [expand]`. At first render `useBlockedUserIds` has not answered, so its value is the initial
 * empty Set. Nothing refetched when the real set arrived. So a blocked seller's rows were on Home on
 * every load and every return to the tab, and only pull-to-refresh — whose handler is re-created each
 * render — ever applied the block.
 *
 * The screen already maintained `blockedIdsRef` for exactly this reason, and used it in the realtime
 * handlers; the three reads did not. Now they do, and a set that arrives after the first read
 * triggers one corrective refetch, so the block applies without the user doing anything.
 *
 * Explore was already correct: its `runSearch` lists `blockedIds` in its deps.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { HookHost } from './helpers/nav-stack-harness';

type Reply = { data: unknown; error: { message: string } | null };

const h = vi.hoisted(() => ({
  /** What `useBlockedUserIds` currently answers — empty until the "read" lands. */
  blocked: new Set<string>(),
  /** The set every `applyBlockedSellerFilter` call was given, in order. */
  applied: [] as string[][],
  rows: [] as Record<string, unknown>[],
  focus: { current: null as null | (() => void) },
}));

vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return {
    useTheme: () => ({ scheme: 'dark', palette: dark }),
    useAppearancePreference: () => ({ preference: 'system', setPreference: () => {} }),
  };
});
vi.mock('react-native', () => ({
  FlatList: 'FlatList', Pressable: 'Pressable', RefreshControl: 'RefreshControl',
  Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1 },
}));
vi.mock('expo-router', () => ({ router: { push: () => {} } }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: (cb: () => void) => { h.focus.current = cb; } }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }) }));
vi.mock('@/src/hooks/useBlockedUserIds', () => ({
  useBlockedUserIds: () => ({ blockedIds: h.blocked }),
  // The real one appends a PostgREST `not.in` filter; here it records what it was given and applies
  // the same rule to the fixture rows, so the assertion is about the rows a user would see.
  applyBlockedSellerFilter: (q: unknown, ids: Set<string>) => {
    h.applied.push([...ids]);
    return q;
  },
}));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({ Chip: 'Chip', EmptyState: 'EmptyState' }));
vi.mock('@/src/components/discovery/DiscoveryGridSkeleton', () => ({ DiscoveryGridSkeleton: 'DiscoveryGridSkeleton' }));
vi.mock('@/src/components/discovery/FilterSheet', () => ({ FilterSheet: 'FilterSheet' }));
vi.mock('@/src/components/discovery/HomeHeader', () => ({ HomeHeader: 'HomeHeader' }));
vi.mock('@/src/components/discovery/HomeFeature', () => ({ HomeFeature: 'HomeFeature' }));
vi.mock('@/src/components/discovery/FeedRow', () => ({ FeedRow: 'FeedRow' }));
vi.mock('@/src/lib/listing/cardHandoff', () => ({ stageCardHandoff: () => {} }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
vi.mock('@/src/components/nav/dockContext', () => ({ useDockScroll: () => ({ onScroll: () => {}, expand: () => {} }) }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/lib/nav/dockAvatar', () => ({ setDockAvatar: () => {} }));
vi.mock('@/src/lib/supabase', () => {
  const query = () => {
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'eq', 'neq', 'order', 'limit']) q[m] = () => q;
    q.then = (ok: (v: Reply) => unknown) => Promise.resolve({ data: h.rows, error: null } as Reply).then(ok);
    return q;
  };
  return {
    supabase: {
      from: () => query(),
      auth: { getUser: async () => ({ data: { user: null } }) },
      rpc: () => ({ returns: () => ({ maybeSingle: async () => ({ data: null }) }) }),
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

const row = (id: string, seller: string) => ({
  id, seller_id: seller, event_name: `Event ${id}`, venue: 'Lantern Room',
  event_date: '2026-10-24', event_time: '19:30:00', quantity: 1, ticket_type: 'GA',
  status: 'active', auction_status: 'active', buy_now_enabled: false, buy_now_price: null,
  current_bid: 5000, starting_bid: 5000, bid_count: 0, ends_at: '2026-10-20T00:00:00Z',
  neighborhood: 'Wynwood', category: 'nightlife', cover_image_path: null, created_at: '2026-09-01',
});

async function mountHome() {
  const mod = await import('@/app/(tabs)/home');
  const Home = mod.default as (p: unknown) => unknown;
  const host = new HookHost(() => Home({}), new Map());
  host.mount();
  // Several microtask turns: the mount read resolves, then its `.finally` marks the initial load
  // done, and only then can a later set trigger the corrective read.
  for (let i = 0; i < 6; i++) { await Promise.resolve(); host.flush(); }
  return host;
}

beforeEach(() => {
  h.blocked = new Set();
  h.applied = [];
  h.rows = [row('r1', 'good-seller'), row('r2', 'blocked-seller')];
  h.focus.current = null;
  vi.resetModules();
});

describe('the block set reaches every Home read, including the first ones', () => {
  it('HB1: a set that arrives AFTER the first read is applied without a pull-to-refresh', async () => {
    const host = await mountHome();
    // The first read ran before the hook answered, which is legitimate — nothing is known yet.
    expect(h.applied[0]).toEqual([]);

    // The block set lands, and the hook's next value re-renders the screen. Nothing else happens:
    // no focus event, no refresh gesture.
    h.blocked = new Set(['blocked-seller']);
    for (let i = 0; i < 6; i++) { host.flush(); await Promise.resolve(); }

    // A read has now been made WITH the real set. Before the fix the screen made none: both callers
    // held the first render's closure over an empty Set, so only pull-to-refresh ever applied it.
    expect(h.applied.some((ids) => ids.includes('blocked-seller')), h.applied.map((a) => a.join('|')).join(' / ')).toBe(true);
  });

  it('HB2 (witness): the recorded sets are real — an empty block list stays empty across the same sequence', async () => {
    // Without this, HB1 could pass on a harness that invents a non-empty set from nowhere.
    const host = await mountHome();
    for (let i = 0; i < 6; i++) { host.flush(); await Promise.resolve(); }
    expect(h.applied.length).toBeGreaterThan(0);
    for (const ids of h.applied) expect(ids).toEqual([]);
  });

  it('HB3: every read filters through the ref, so no read can hold a stale set', async () => {
    const src = (await import('node:fs')).readFileSync('app/(tabs)/home.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    // All three reads, and the realtime handlers that already did this.
    expect(src.match(/applyBlockedSellerFilter\(baseQuery, blockedIdsRef\.current\)/g)?.length).toBe(3);
    expect(src).not.toMatch(/applyBlockedSellerFilter\(baseQuery, blockedIds\)/);
    // And the corrective refetch, so a set arriving after the first read fixes what is on screen.
    expect(src).toMatch(/useEffect\(\(\) => \{[\s\S]*?blockedIds[\s\S]*?fetchListings\(\)/);
  });
});
