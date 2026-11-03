/**
 * Home's section headings on the REAL screen turn at New York midnight, whatever the phone's zone (owner,
 * 2026-11-02: Snatch It operates in Eastern Time). app/(tabs)/home.tsx keys its grouping to New York's day —
 * not to the device's midnight — and src/lib/home/sections.ts buckets on it.
 *
 * The real app/(tabs)/home.tsx runs through the hook dispatcher (same harness and mocks as
 * home-live-feed-filter.test.ts) with the clock faked at each anchor and the process zone set to UTC,
 * America/Los_Angeles and America/New_York in turn; the order and the headings must be the same in all nine.
 *
 * Why three anchors. A device-midnight epoch handed to the Eastern rule is wrong only where the device's midnight
 * falls on New York's PREVIOUS day: a UTC phone in New York's daytime (17:00Z, its midnight is 19:00 EST the day
 * before). An LA phone's midnight is 03:00 in New York, the same day, so the evening anchor (02:14Z) and the
 * just-after-midnight anchor (05:30Z) are there for a fully device-zone screen, which they catch on the UTC and
 * LA phones respectively.
 *
 * Negative control (run by hand; must FAIL): home.tsx's grouping key back on `new Date(now).setHours(0,0,0,0)`.
 * Not a device result.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

type Reply = { data: unknown; error: { message: string } | null };

const h = vi.hoisted(() => ({
  rows: [] as Record<string, unknown>[],
}));

vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return {
    useTheme: () => ({ scheme: 'dark', palette: dark }),
    useAppearancePreference: () => ({ preference: 'system', setPreference: () => {} }),
  };
});
vi.mock('react-native', () => ({
  AppState: { currentState: 'active', addEventListener: () => ({ remove: () => {} }) },
  FlatList: 'FlatList', Pressable: 'Pressable', RefreshControl: 'RefreshControl',
  Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1 },
}));
vi.mock('expo-router', () => ({ router: { push: () => {} } }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: () => {} }));
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
  const chain = () => {
    const q: Record<string | symbol, unknown> = new Proxy({}, {
      get(_t, prop) {
        if (prop === 'then') {
          return (ok: (v: Reply) => unknown, bad?: (e: unknown) => unknown) =>
            Promise.resolve({ data: h.rows, error: null } as Reply).then(ok, bad);
        }
        if (typeof prop !== 'string') return undefined;
        return () => q;
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
        ch.on = () => ch;
        ch.subscribe = () => ch;
        return ch;
      },
      removeChannel: () => {},
    },
  };
});

const row = (id: string, event_date: string) => ({
  id, seller_id: 'seller-1', event_name: `Event ${id}`, venue: 'Lantern Room',
  event_date, event_time: '22:00:00', quantity: 1, ticket_type: 'GA',
  status: 'active', auction_status: 'active', buy_now_enabled: true, buy_now_price: 5000,
  current_bid: 5000, starting_bid: 5000, bid_count: 0, ends_at: '2099-01-01T00:00:00Z',
  neighborhood: 'Wynwood', category: 'nightlife', cover_image_path: null, created_at: '2026-09-01',
  reserved_until: null, reserved_by: null, winner_user_id: null, winning_bid_amount: null,
});

/** New York's Monday 2 Nov: tonight, one day on, eight days on — fed in the "wrong" order. */
const FIXTURE = [row('later', '2026-11-10'), row('week', '2026-11-03'), row('tonight', '2026-11-02')];

const ZONES = ['UTC', 'America/Los_Angeles', 'America/New_York'] as const;
const originalTz = process.env.TZ;

let host: HookHost | null = null;
beforeEach(() => { h.rows = FIXTURE; });
afterEach(() => {
  host?.unmount();
  host = null;
  vi.useRealTimers();
  if (originalTz === undefined) delete process.env.TZ; else process.env.TZ = originalTz;
});

/** Mounts the real Home at `iso` in `zone`; returns the rows in screen order with the heading drawn over each. */
async function homeAt(iso: string, zone: string): Promise<[string, string | null][]> {
  host?.unmount();
  process.env.TZ = zone;
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date(iso));
  vi.resetModules();
  const mod = await import('@/app/(tabs)/home');
  const Home = mod.default as (p: unknown) => unknown;
  host = new HookHost(() => Home({}), new Map());
  host.mount();
  for (let i = 0; i < 8; i++) { await Promise.resolve(); host.flush(); }
  const list = findElement(host.output, (el) => el.type === 'FlatList') as Element;
  const data = (list.props.data ?? []) as { id: string }[];
  const renderItem = list.props.renderItem as (a: { item: unknown; index: number }) => unknown;
  return data.map((item, index) => {
    const header = findElement(renderItem({ item, index }), (el) => el.type === 'Text' && el.props.accessibilityRole === 'header');
    return [item.id, header ? String(header.props.children) : null];
  });
}

const EXPECTED: [string, string | null][] = [['tonight', 'Tonight'], ['week', 'This week'], ['later', 'Later']];

/** The day a device-midnight epoch for `iso` in `zone` lands on in New York (the witness). */
function deviceMidnightInNewYork(iso: string, zone: string): string {
  process.env.TZ = zone;
  const d = new Date(iso);
  d.setHours(0, 0, 0, 0);
  const t = d.getTime();
  process.env.TZ = 'UTC';
  const ny = new Date(t - 5 * 3_600_000);   // EST all of 2 Nov after 06:00Z on the 1st
  return ny.toISOString().slice(0, 10);
}

describe('Home — Tonight / This week / Later on New York\'s day, on every phone', () => {
  for (const [iso, what] of [
    ['2026-11-02T17:00:00Z', 'Mon 2 Nov 12:00 EST (a UTC phone\'s midnight is New York\'s Sunday)'],
    ['2026-11-03T02:14:00Z', 'Mon 2 Nov 21:14 EST (a UTC phone is already on Tuesday)'],
    ['2026-11-02T05:30:00Z', 'Mon 2 Nov 00:30 EST (an LA phone is still on Sunday)'],
  ] as const) {
    it(`EH: ${what}`, async () => {
      for (const zone of ZONES) {
        expect(await homeAt(iso, zone), `${zone} at ${iso}`).toEqual(EXPECTED);
      }
    });
  }

  it('EH witness: at each anchor some phone\'s own calendar disagrees with New York\'s Monday', () => {
    // A device-midnight key handed to the Eastern rule lands on New York's Sunday for a UTC phone at noon EST.
    expect(deviceMidnightInNewYork('2026-11-02T17:00:00Z', 'UTC')).toBe('2026-11-01');
    process.env.TZ = 'UTC';
    expect(new Date('2026-11-03T02:14:00Z').getDate()).toBe(3);                 // a UTC phone's Tuesday
    process.env.TZ = 'America/Los_Angeles';
    expect(new Date('2026-11-02T05:30:00Z').getDate()).toBe(1);                 // an LA phone's Sunday
  });
});
