/**
 * Profile SELLER counts must not turn a failed read into zeros (TEST-MODE capture finding 1, 2026-10-19).
 *
 * On a cold launch the seller saw "Sold 0, Proceeds —" and no Payouts row; a retry seconds later showed
 * Sold 50 and a Stripe connection. `loadData` read `count`/`data` from the two listings queries and never
 * looked at `error`, so `activeCount ?? 0` and `soldData?.length ?? 0` made a failed read a claim of no
 * activity, and the zero counts then hid the Payouts row.
 *
 * These run the REAL app/(tabs)/profile.tsx through the hook dispatcher with the listings reads under test
 * control. Not a device result.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { expandTree, findElement, HookHost } from './helpers/nav-stack-harness';
import { byLabel } from './helpers/screen-view';

type Read = { data: unknown; count: number | null; error: { message: string } | null };

const h = vi.hoisted(() => ({
  // One entry per `from('listings')` chain, in call order: [active count, sold rows].
  reads: [] as Read[][],
  focus: { current: null as null | (() => void) },
  round: { current: 0 },
}));

vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return {
    useTheme: () => ({ scheme: 'dark', palette: dark }),
    useAppearancePreference: () => ({ preference: 'system', setPreference: () => {} }),
  };
});
vi.mock('react-native', () => ({
  Alert: { alert: () => {} },
  Pressable: 'Pressable', RefreshControl: 'RefreshControl', ScrollView: 'ScrollView', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-image', () => ({ Image: 'Image' }));
vi.mock('expo-router', () => ({ router: { push: () => {}, replace: () => {} } }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: (cb: () => void) => { h.focus.current = cb; } }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'u-1', email: 'seller@example.test' } }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }) }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({ Badge: 'Badge', Button: 'Button', Spinner: 'Spinner' }));
vi.mock('@/src/components/account/AccountSection', () => ({ AccountSection: 'AccountSection' }));
vi.mock('@/src/components/account/SettingsRow', () => ({ SettingsRow: 'SettingsRow' }));
vi.mock('@/src/components/nav/dockContext', () => ({ useDockScroll: () => ({ onScroll: () => {}, expand: () => {} }) }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6 }));
vi.mock('@/src/lib/auth/signOut', () => ({ SIGN_OUT_FAILED_COPY: 'x', signOutThisDevice: async () => ({ ok: true }) }));
vi.mock('@/src/lib/avatarImage', () => ({ getAvatarUrl: () => null, pickAndUploadAvatar: async () => ({ ok: false }) }));
vi.mock('@/src/lib/supabase', () => {
  const table = () => {
    const q: Record<string, unknown> = {};
    let call = -1;
    for (const m of ['select', 'order', 'limit', 'in', 'neq', 'or', 'eq', 'gte', 'lte', 'maybeSingle', 'single']) q[m] = () => q;
    q.then = (ok: (v: unknown) => unknown) => {
      if (call < 0) call = h.round.current++;
      const round = h.reads[Math.floor(call / 2)] ?? h.reads[h.reads.length - 1];
      return Promise.resolve(round[call % 2]).then(ok);
    };
    return q;
  };
  return {
    supabase: {
      from: () => table(),
      functions: { invoke: async () => ({ data: null, error: { message: 'no' } }) },
      auth: { getUser: async () => ({ data: { user: { id: 'u-1' } } }) },
      rpc: () => ({ returns: () => ({ maybeSingle: async () => ({ data: { id: 'u-1', display_name: 'Seller', stripe_connect_id: null }, error: null }) }) }),
    },
  };
});

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

const FAILED: Read = { data: null, count: null, error: { message: 'Network request failed' } };
const ok = (active: number, sold: unknown[]): Read[] => [
  { data: null, count: active, error: null },
  { data: sold, count: null, error: null },
];

async function mountProfile(): Promise<HookHost> {
  const { default: ProfileScreen } = await import('@/app/(tabs)/profile');
  const host = new HookHost(() => (ProfileScreen as () => unknown)(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

const view = (host: HookHost) => expandTree(host.output);

beforeEach(() => {
  h.reads.length = 0;
  h.round.current = 0;
  h.focus.current = null;
  vi.resetModules();
});

describe('Profile seller counts on a failed read', () => {
  it('S1: a failed first read shows the counts as unknown, never "0"', async () => {
    h.reads.push([FAILED, FAILED]);
    const host = await mountProfile();
    const tree = view(host);
    expect(byLabel(tree, 'Active, 0')).toBeUndefined();
    expect(byLabel(tree, 'Sold, 0')).toBeUndefined();
    expect(byLabel(tree, 'Active, unknown')).toBeDefined();
    expect(byLabel(tree, 'Sold, unknown')).toBeDefined();
  });

  it('S2: one failed read of the two is enough to keep the counts unknown', async () => {
    h.reads.push([{ data: null, count: 3, error: null }, FAILED]);
    const host = await mountProfile();
    const tree = view(host);
    expect(byLabel(tree, 'Sold, 0')).toBeUndefined();
    expect(byLabel(tree, 'Sold, unknown')).toBeDefined();
  });

  it('S3: unknown counts do not hide the Payouts row', async () => {
    h.reads.push([FAILED, FAILED]);
    const host = await mountProfile();
    const payouts = findElement(view(host), (el) => el.type === 'AccountSection' && el.props.title === 'Payouts');
    expect(payouts).toBeDefined();
  });

  it('S4: a successful read shows real zeros (regression guard: a new seller has 0, not "—")', async () => {
    h.reads.push(ok(0, []));
    const host = await mountProfile();
    const tree = view(host);
    expect(byLabel(tree, 'Active, 0')).toBeDefined();
    expect(byLabel(tree, 'Sold, 0')).toBeDefined();
  });

  it('S5: a failed refetch keeps the last good counts instead of dropping to zero', async () => {
    h.reads.push(ok(2, [{ status: 'sold', auction_status: 'ended', winning_bid_amount: 50 }]));
    h.reads.push([FAILED, FAILED]);
    const host = await mountProfile();
    expect(byLabel(view(host), 'Active, 2')).toBeDefined();

    h.focus.current?.();
    await flush();
    host.flush();

    const tree = view(host);
    expect(byLabel(tree, 'Active, 2')).toBeDefined();
    expect(byLabel(tree, 'Sold, 1')).toBeDefined();
    expect(byLabel(tree, 'Active, 0')).toBeUndefined();
  });

  it('S6: a user change resets the counts to unknown before the new read (review m8)', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('app/(tabs)/profile.tsx', 'utf8');
    expect(src).toMatch(/setStats\(null\);\s*loadData\(\)\.finally\(\(\) => setPageLoading\(false\)\);\s*\}, \[user\?\.id\]\);/);
  });
});
