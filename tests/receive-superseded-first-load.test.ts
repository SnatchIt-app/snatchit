/**
 * The buyer's order screen painted "Transfer not found" after a superseded first load and a failed
 * quiet read (C30-09b item 4). The trace, in app/transfer/receive/[id].tsx `fetchTransfer`:
 *   1. the mount read starts (visible: loading = true), gen 1;
 *   2. before it lands, a quiet read starts (a focus return or a foreground), gen 2;
 *   3. the mount read lands, sees `gen !== readGenRef.current` and returns — its result, row or error,
 *      is dropped, and it neither sets the error nor clears loading;
 *   4. the quiet read FAILS: being quiet, it sets no error ("keep the order on screen"), then clears
 *      loading.
 * Now loading = false, transfer = null, error = '' — and the render's `error || !transfer` fallback
 * is the row-less "Transfer not found" with only a Back button. A temporary failure said the order
 * did not exist (owner, 2026-09-19: a failed read is never "not found").
 *
 * Fixed: a quiet read that fails while no row has ever been read sets the neutral error state
 * (offline or error, both with Retry). A quiet read never sets not_found.
 *
 * Runs the REAL screen through the hook dispatcher (harness style of receive-reread-after-confirm).
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { findElement, HookHost } from './helpers/nav-stack-harness';
import { screenText } from './helpers/screen-view';

(globalThis as Record<string, unknown>).__DEV__ = false;

type Reply = { data: unknown; error: unknown };

const h = vi.hoisted(() => {
  const deferred = <T,>() => {
    let resolve!: (v: T) => void;
    const promise = new Promise<T>((ok) => { resolve = ok; });
    return { promise, resolve };
  };
  return {
    deferred,
    reads: [] as ReturnType<typeof deferred<{ data: unknown; error: unknown }>>[],
    focus: { current: null as null | (() => void) },
    networkErrors: false,
  };
});

vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('react-native', () => ({
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: 1 }),
  Alert: { alert: () => {} },
  AppState: { addEventListener: () => ({ remove: () => {} }), currentState: 'active' },
  Image: 'Image', KeyboardAvoidingView: 'KeyboardAvoidingView', Linking: { openURL: async () => true },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Pressable: 'Pressable', ScrollView: 'ScrollView', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {} }, useLocalSearchParams: () => ({ id: 't-1' }) }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: (cb: () => void) => { h.focus.current = cb; } }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'buyer-1' }, session: { user: { id: 'buyer-1' } } }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }), isNetworkError: () => h.networkErrors }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({ Badge: 'Badge', Button: 'Button', EmptyState: 'EmptyState', IconButton: 'IconButton', Spinner: 'Spinner' }));
vi.mock('@/src/components/DeliveryInfoForm', () => ({ default: 'DeliveryInfoForm' }));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/NameText', () => ({ NameText: 'NameText' }));
vi.mock('@/src/components/ProofImageViewer', () => ({ ProofImageViewer: 'ProofImageViewer' }));
vi.mock('@/src/components/PlatformInstructions', () => ({ default: 'PlatformInstructions' }));
vi.mock('@/src/lib/feedback/haptics', () => ({ hapticSuccess: () => {} }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6 }));
vi.mock('@/src/lib/supabase', () => {
  const table = () => {
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'order', 'limit', 'in', 'neq', 'or', 'update', 'eq']) q[m] = () => q;
    // Each transfer read is answered by hand, in whatever order the test chooses.
    q.single = () => { const d = h.deferred<{ data: unknown; error: unknown }>(); h.reads.push(d); return d.promise; };
    q.maybeSingle = async () => ({ data: null, error: null });
    return q;
  };
  return {
    supabase: {
      from: () => table(),
      auth: { getUser: async () => ({ data: { user: { id: 'buyer-1' } } }) },
      rpc: async () => ({ data: null, error: null }),
      functions: { invoke: async () => ({ data: null, error: null }) },
      storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }) }) },
    },
  };
});

const flush = async () => { for (let i = 0; i < 8; i++) await new Promise((r) => setImmediate(r)); };

const ROW = {
  id: 't-1', status: 'seller_sent', seller_id: 'seller-1', buyer_id: 'buyer-1', listing_id: 'l-1',
  listing: { id: 'l-1', event_name: 'Sandbox S9', ticket_platform: 'ticketmaster' },
  delivery_email: 'buyer@example.test', delivery_phone: null, expires_at: null, auto_release_at: null,
  transfer_evidence_path: null, transfer_method: 'mobile_transfer', seller: { display_name: 'Seller One' },
};
const FAIL: Reply = { data: null, error: { message: 'Network request failed' } };
const NO_ROW: Reply = { data: null, error: { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned' } };

async function mount(): Promise<HookHost> {
  const mod = await import('@/app/transfer/receive/[id]');
  const Screen = (mod.default ?? mod) as () => unknown;
  const host = new HookHost(() => Screen(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

/** Start a quiet re-read the way a return to the screen does (the first focus is the mount read). */
async function quietRead(host: HookHost): Promise<void> {
  h.focus.current?.(); h.focus.current?.();
  await flush();
  host.flush();
}

async function answer(host: HookHost, i: number, reply: Reply): Promise<void> {
  h.reads[i].resolve(reply);
  await flush();
  host.flush();
}

const screenState = (host: HookHost) => findElement(host.output, (el) => el.type === 'ScreenState');
const notFound = (host: HookHost) =>
  !!findElement(host.output, (el) => el.type === 'EmptyState' && el.props.title === 'Transfer not found') ||
  screenText(host.output).includes('Transfer not found');

beforeEach(() => {
  h.reads.length = 0;
  h.focus.current = null;
  h.networkErrors = false;
  vi.resetModules();
});

describe('SF: a superseded first load never ends on "Transfer not found"', () => {
  it('SF1: first load superseded (its row dropped), then the quiet read fails → the error state, not "not found"', async () => {
    const host = await mount();
    expect(h.reads).toHaveLength(1);              // the mount read, in flight
    await quietRead(host);
    expect(h.reads).toHaveLength(2);              // the quiet read, in flight
    await answer(host, 0, { data: ROW, error: null });   // superseded: dropped
    await answer(host, 1, FAIL);                          // the quiet read fails
    expect(notFound(host)).toBe(false);
    expect(screenState(host)?.props.state).toBe('error');
  });

  it('SF2: the same sequence offline → the offline state', async () => {
    h.networkErrors = true;
    const host = await mount();
    await quietRead(host);
    await answer(host, 0, FAIL);
    await answer(host, 1, FAIL);
    expect(notFound(host)).toBe(false);
    expect(screenState(host)?.props.state).toBe('offline');
  });

  it('SF3: a quiet read never becomes not_found, even on a row-less answer', async () => {
    const host = await mount();
    await quietRead(host);
    await answer(host, 0, NO_ROW);
    await answer(host, 1, NO_ROW);
    expect(notFound(host)).toBe(false);
    expect(screenState(host)?.props.state).toBe('error');
  });

  it('SF4: Retry from that state is a visible read, which may then say not found (control)', async () => {
    const host = await mount();
    await quietRead(host);
    await answer(host, 0, FAIL);
    await answer(host, 1, FAIL);
    (screenState(host)?.props.onRetry as () => void)();
    await flush();
    await answer(host, h.reads.length - 1, NO_ROW);
    expect(notFound(host)).toBe(true);
  });

  it('SF5: a quiet read that fails after a row was shown keeps the order (unchanged)', async () => {
    const host = await mount();
    await answer(host, 0, { data: ROW, error: null });
    await quietRead(host);
    await answer(host, 1, FAIL);
    expect(screenState(host)).toBeUndefined();
    expect(notFound(host)).toBe(false);
    expect(screenText(host.output)).toContain('Sandbox S9');
  });

  it('SF6: a visible first load answered row-less still says not found (unchanged)', async () => {
    const host = await mount();
    await answer(host, 0, NO_ROW);
    expect(notFound(host)).toBe(true);
  });
});
