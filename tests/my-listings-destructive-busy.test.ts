/**
 * F-DESTRUCT-1 — delete and cancel a listing are one-at-a-time, and say so while they run.
 *
 * B's audit (§P4), verified by C at Build 19's commit f412d10: `performDelete` and `performCancel` carried no
 * busy flag and nothing disabled the row while the request was in flight, so a second tap re-opened the
 * confirmation and could fire a second destructive request against the same listing. Each sits behind a
 * confirm dialog, which is why this is in the batch rather than gating a release — but "destructive and
 * re-entrant" is not a state to leave in.
 *
 * The rules themselves are untouched: the same bid_count / auction_status precondition, the same
 * `listings.delete` and the same `cancel_listing` RPC, with the same arguments.
 *
 * These tests run the REAL app/my-listings.tsx through the hook dispatcher with the destructive calls under
 * test control. Not a device result.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

const h = vi.hoisted(() => {
  const deferred = <T,>() => {
    let resolve!: (v: T) => void;
    const promise = new Promise<T>((r) => { resolve = r; });
    return { promise, resolve };
  };
  return {
    deferred,
    deletes: [] as ReturnType<typeof deferred<{ error: unknown }>>[],
    cancels: [] as ReturnType<typeof deferred<{ error: unknown }>>[],
    rows: [] as Record<string, unknown>[],
    /** Every Alert shown, with the destructive button captured so the test can confirm. */
    alerts: [] as { title: string; confirm?: () => void }[],
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
  Alert: {
    alert: (title: string, _body?: string, buttons?: { text: string; style?: string; onPress?: () => void }[]) => {
      const destructive = buttons?.find((b) => b.style === 'destructive');
      h.alerts.push({ title, confirm: destructive?.onPress });
    },
  },
  FlatList: 'FlatList', Pressable: 'Pressable', RefreshControl: 'RefreshControl', ScrollView: 'ScrollView',
  Text: 'Text', View: 'View', StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-image', () => ({ Image: 'Image' }));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {} }, useLocalSearchParams: () => ({}) }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: (cb: () => void) => { h.focus.current = cb; } }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'seller-1' }, session: { user: { id: 'seller-1' } } }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }) }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({
  Chip: 'Chip', EmptyState: 'EmptyState', Skeleton: 'Skeleton', Spinner: 'Spinner', Button: 'Button',
  Tappable: 'Tappable', Badge: 'Badge', IconButton: 'IconButton',
}));
vi.mock('@/src/components/nav/dockContext', () => ({ useDockScroll: () => ({ onScroll: () => {}, expand: () => {} }) }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
vi.mock('@/src/lib/coverImage', () => ({ getCoverImageUrl: () => null }));
// Presentation only, and the legacy-theme badge pulls .ttf assets vitest cannot parse.
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/VerifiedSellerBadge', () => ({ default: 'VerifiedSellerBadge' }));
vi.mock('@/src/lib/supabase', () => {
  const table = (name: string) => {
    const q: Record<string, unknown> = {};
    let deleting = false;
    q.delete = () => { deleting = true; return q; };
    q.update = () => q;
    for (const m of ['select', 'order', 'limit', 'in', 'neq', 'or', 'gte', 'lte', 'maybeSingle', 'single']) q[m] = () => q;
    let eqs = 0;
    q.eq = () => {
      if (!deleting) return q;
      eqs += 1;
      // `.delete().eq('id').eq('seller_id')` — the request is the second eq.
      if (eqs < 2) return q;
      const d = h.deferred<{ error: unknown }>();
      h.deletes.push(d);
      return d.promise;
    };
    q.then = (ok: (v: unknown) => unknown) =>
      Promise.resolve({ data: name === 'listings' ? h.rows : [], error: null }).then(ok);
    return q;
  };
  return {
    supabase: {
      from: (name: string) => table(name),
      auth: { getUser: async () => ({ data: { user: { id: 'seller-1' } } }) },
      storage: { from: () => ({ remove: async () => ({ error: null }) }) },
      rpc: (fn: string) => {
        if (fn !== 'cancel_listing') {
          return { returns: () => ({ maybeSingle: async () => ({ data: null, error: null }) }) };
        }
        const d = h.deferred<{ error: unknown }>();
        h.cancels.push(d);
        return d.promise;
      },
    },
  };
});

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

const listing = (id: string, extra: Record<string, unknown> = {}) => ({
  id, event_name: `Event ${id}`, venue: 'Club Device', status: 'active', auction_status: 'active',
  bid_count: 0, current_bid: 0, starting_bid: 50, ends_at: '2099-01-01T00:00:00Z', sold_at: null,
  cover_image_path: null, seller_id: 'seller-1', created_at: '2026-09-01T00:00:00Z', event_date: '2026-10-08',
  event_time: '21:00', ticket_type: 'GA', neighborhood: 'Wynwood', ...extra,
});

/** The props the screen hands its row for `index` — FlatList is a stub, so renderItem is called here. */
function rowProps(host: HookHost, index = 0): Record<string, unknown> {
  const list = findElement(host.output, (el) => el.type === 'FlatList') as Element;
  const data = (list.props.data ?? []) as unknown[];
  const render = list.props.renderItem as (a: { item: unknown }) => unknown;
  const element = render({ item: data[index] }) as Element;
  return element.props;
}

function rowCount(host: HookHost): number {
  const list = findElement(host.output, (el) => el.type === 'FlatList') as Element;
  return ((list.props.data ?? []) as unknown[]).length;
}

/** Tap the row's destructive affordance. A busy row ignores the tap, exactly as a disabled control does. */
function tapDestructive(host: HookHost, index = 0): void {
  const props = rowProps(host, index);
  if (props.busy === true) return;
  (props.onDelete as () => void)();
  host.flush();
}

/** Confirm the most recent destructive dialog. */
function confirmLast(host: HookHost): void {
  const last = h.alerts[h.alerts.length - 1];
  last?.confirm?.();
  host.flush();
}

async function mountMyListings(): Promise<HookHost> {
  const mod = await import('@/app/my-listings');
  const Screen = (mod.default ?? mod) as () => unknown;
  const host = new HookHost(() => Screen(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

beforeEach(() => {
  h.deletes.length = 0; h.cancels.length = 0; h.alerts.length = 0;
  h.rows = [listing('l-1')];
  h.focus.current = null;
  vi.resetModules();
});

describe('F-DESTRUCT-1 — destructive listing actions are one-at-a-time', () => {
  it('D1: a second confirmed delete while the first is in flight sends only one request', async () => {
    const host = await mountMyListings();
    tapDestructive(host);
    confirmLast(host);
    await flush();
    host.flush();
    expect(h.deletes.length).toBe(1);

    // Tap and confirm again before the first request settles.
    tapDestructive(host);
    confirmLast(host);
    await flush();
    host.flush();

    expect(h.deletes.length).toBe(1);
  });

  it('D2: the row action is disabled while the delete is in flight', async () => {
    const host = await mountMyListings();
    tapDestructive(host);
    confirmLast(host);
    await flush();
    host.flush();

    expect(rowProps(host).busy).toBe(true);
  });

  it('D3: a failed delete re-enables the action so the seller can try again', async () => {
    const host = await mountMyListings();
    tapDestructive(host);
    confirmLast(host);
    await flush();
    host.flush();

    h.deletes[0].resolve({ error: { message: 'delete rejected' } });
    await flush();
    host.flush();

    expect(rowProps(host).busy).toBeFalsy();
    expect(h.alerts.some((a) => a.title === 'Delete failed')).toBe(true);
  });

  it('D4: cancel is guarded the same way — one RPC, not two', async () => {
    h.rows = [listing('l-1', { bid_count: 3 })];   // with bids, the action is Cancel
    const host = await mountMyListings();
    tapDestructive(host);
    confirmLast(host);
    await flush();
    host.flush();
    expect(h.cancels.length).toBe(1);

    tapDestructive(host);
    confirmLast(host);
    await flush();
    host.flush();

    expect(h.cancels.length).toBe(1);
  });

  it('D8: the lock is per listing — a second row is still actionable while the first is in flight', async () => {
    // Nothing in D1-D7 distinguished the id-keyed lock from a single global boolean, which would freeze the
    // whole list during one delete (D's review).
    h.rows = [listing('l-1'), listing('l-2')];
    const host = await mountMyListings();

    tapDestructive(host, 0);
    confirmLast(host);
    await flush();
    host.flush();
    expect(h.deletes.length).toBe(1);
    expect(rowProps(host, 0).busy).toBe(true);

    // Row two belongs to no in-flight request and must behave normally.
    expect(rowProps(host, 1).busy).toBeFalsy();
    tapDestructive(host, 1);
    confirmLast(host);
    await flush();
    host.flush();

    expect(h.deletes.length).toBe(2);
  });

  it('D5: a successful delete still removes the row (regression guard)', async () => {
    const host = await mountMyListings();
    tapDestructive(host);
    confirmLast(host);
    await flush();
    h.deletes[0].resolve({ error: null });
    await flush();
    host.flush();

    expect(rowCount(host)).toBe(0);
  });

  it('D6: the precondition is unchanged — a listing with bids is never deleted', async () => {
    h.rows = [listing('l-1', { bid_count: 3 })];
    const host = await mountMyListings();
    tapDestructive(host);
    confirmLast(host);
    await flush();
    host.flush();

    expect(h.deletes.length).toBe(0);
  });
});

describe('F-DESTRUCT-1 — the row itself stands down while busy', () => {
  it('D7: SellerListingCard disables its destructive affordance when busy', async () => {
    const { default: SellerListingCard } = await import('@/src/components/SellerListingCard');
    const render = (busy: boolean) => {
      const host = new HookHost(
        () => (SellerListingCard as (p: Record<string, unknown>) => unknown)({
          listing: listing('l-1'), onDelete: () => {}, onEdit: () => {}, onPress: () => {}, busy,
        }),
        new Map(),
      );
      host.mount();
      return findElement(host.output, (el) => el.props.accessibilityLabel === 'Delete listing') as Element;
    };

    expect(render(true).props.disabled).toBe(true);
    expect(render(false).props.disabled).toBeFalsy();   // regression guard: not disabled by default
  });
});
