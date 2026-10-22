/**
 * Delta review m1 (2026-10-21): after confirm-and-release failed, the re-read that decides between
 * "the confirmation landed anyway" and a refusal dialog could be OVERTAKEN by a focus or foreground
 * read. The overtaken read returns null without having failed (readGenRef), so the screen showed the
 * refusal while the newer read was about to paint buyer_confirmed, and confirmedHereRef stayed false.
 *
 * Now a null re-read is read once more, and the decision looks at the newest row on screen as well
 * (transferRef), so it is made on a landed row. Runs the REAL screen with hand-answered reads.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { HookHost } from './helpers/nav-stack-harness';
import { buttonByLabel } from './helpers/screen-view';

(globalThis as Record<string, unknown>).__DEV__ = false;

type AlertButton = { text: string; style?: string; onPress?: () => void };
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
    invokes: [] as ReturnType<typeof deferred<{ data: unknown; error: unknown }>>[],
    focus: { current: null as null | (() => void) },
    haptics: 0,
    alerts: [] as { title: string; message?: string; buttons?: AlertButton[] }[],
  };
});

vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('react-native', () => ({
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: 1 }),
  Alert: { alert: (title: string, message?: string, buttons?: AlertButton[]) => { h.alerts.push({ title, message, buttons }); } },
  AppState: { addEventListener: () => ({ remove: () => {} }), currentState: 'active' },
  Image: 'Image', KeyboardAvoidingView: 'KeyboardAvoidingView', Linking: { openURL: async () => true },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Pressable: 'Pressable', ScrollView: 'ScrollView', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {} }, useLocalSearchParams: () => ({ id: 't-1' }) }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: (cb: () => void) => { h.focus.current = cb; } }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'buyer-1' }, session: { user: { id: 'buyer-1' } } }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }), isNetworkError: () => false }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({ Badge: 'Badge', Button: 'Button', EmptyState: 'EmptyState', IconButton: 'IconButton', Spinner: 'Spinner' }));
vi.mock('@/src/components/DeliveryInfoForm', () => ({ default: 'DeliveryInfoForm' }));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/NameText', () => ({ NameText: 'NameText' }));
vi.mock('@/src/components/ProofImageViewer', () => ({ ProofImageViewer: 'ProofImageViewer' }));
vi.mock('@/src/components/PlatformInstructions', () => ({ default: 'PlatformInstructions' }));
vi.mock('@/src/lib/feedback/haptics', () => ({ hapticSuccess: () => { h.haptics++; } }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6 }));
vi.mock('@/src/lib/supabase', () => {
  const table = () => {
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'order', 'limit', 'in', 'neq', 'or', 'update', 'eq']) q[m] = () => q;
    q.single = () => { const d = h.deferred<{ data: unknown; error: unknown }>(); h.reads.push(d); return d.promise; };
    q.maybeSingle = async () => ({ data: null, error: null });
    return q;
  };
  return {
    supabase: {
      from: () => table(),
      auth: { getUser: async () => ({ data: { user: { id: 'buyer-1' } } }) },
      rpc: async () => ({ data: null, error: null }),
      functions: { invoke: () => { const d = h.deferred<{ data: unknown; error: unknown }>(); h.invokes.push(d); return d.promise; } },
      storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }) }) },
    },
  };
});

const flush = async () => { for (let i = 0; i < 8; i++) await new Promise((r) => setImmediate(r)); };

const CONFIRM = 'I have my tickets';
const RELEASE = 'Confirm and release payment';
const RECEIPT = 'Receipt confirmed';
const REFUSAL_TITLE = "Couldn't confirm receipt";

const ROW = {
  id: 't-1', status: 'seller_sent', seller_id: 'seller-1', buyer_id: 'buyer-1', listing_id: 'l-1',
  listing: { id: 'l-1', event_name: 'Sandbox S9', ticket_platform: 'ticketmaster' },
  delivery_email: 'buyer@example.test', delivery_phone: null, expires_at: null, auto_release_at: null,
  payout_released_at: null, buyer_confirmed_at: null,
  transfer_evidence_path: null, transfer_method: 'mobile_transfer', seller: { display_name: 'Seller One' },
};
const CONFIRMED = { ...ROW, status: 'buyer_confirmed', buyer_confirmed_at: '2026-10-21T20:00:00Z' };

/** A FunctionsHttpError as supabase-js builds it: the raw Response in `.context`. */
const httpError = (status: number, body: unknown): Reply => ({
  data: null,
  error: { name: 'FunctionsHttpError', message: 'Edge Function returned a non-2xx status code', context: { status, json: async () => body } },
});

async function mountReceive(): Promise<HookHost> {
  const mod = await import('@/app/transfer/receive/[id]');
  const Screen = (mod.default ?? mod) as () => unknown;
  const host = new HookHost(() => Screen(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

async function answer(host: HookHost, i: number, reply: Reply): Promise<void> {
  h.reads[i].resolve(reply);
  await flush();
  host.flush();
}

const titles = () => h.alerts.map((a) => a.title);

beforeEach(() => {
  h.reads.length = 0; h.invokes.length = 0; h.alerts.length = 0;
  h.focus.current = null; h.haptics = 0;
  vi.resetModules();
});

describe('m1: the post-failure re-read is overtaken by a newer read', () => {
  it('CS1: the decision waits for a landed row and says "Receipt confirmed", never the refusal', async () => {
    const host = await mountReceive();
    await answer(host, 0, { data: ROW, error: null });

    (buttonByLabel(host.output, CONFIRM)?.props.onPress as () => void)();
    await flush();
    h.alerts[0]?.buttons?.find((b) => b.text === RELEASE)?.onPress?.();
    await flush();
    expect(h.invokes).toHaveLength(1);
    h.invokes[0].resolve(httpError(500, { error: 'Internal server error' }));   // after recording the confirmation
    await flush();
    host.flush();
    expect(h.reads).toHaveLength(2);                 // the post-failure quiet re-read, in flight

    // A return to the screen starts a newer read before that one lands (the first focus is the mount's).
    h.focus.current?.();
    h.focus.current?.();
    await flush();
    expect(h.reads).toHaveLength(3);

    // The older re-read lands: superseded, so it is dropped. The fix reads once more.
    await answer(host, 1, { data: CONFIRMED, error: null });
    expect(titles()).not.toContain(REFUSAL_TITLE);
    expect(h.reads).toHaveLength(4);

    await answer(host, 2, { data: CONFIRMED, error: null });   // the focus read, now itself superseded
    await answer(host, 3, { data: CONFIRMED, error: null });   // the retry lands

    expect(titles()).toContain(RECEIPT);
    expect(titles()).not.toContain(REFUSAL_TITLE);
    expect(h.haptics).toBe(1);
  });

  it('CS2: a re-read that lands and shows no confirmation still refuses (control)', async () => {
    const host = await mountReceive();
    await answer(host, 0, { data: ROW, error: null });
    (buttonByLabel(host.output, CONFIRM)?.props.onPress as () => void)();
    await flush();
    h.alerts[0]?.buttons?.find((b) => b.text === RELEASE)?.onPress?.();
    await flush();
    h.invokes[0].resolve(httpError(500, { error: 'Internal server error' }));
    await flush();
    host.flush();
    await answer(host, 1, { data: ROW, error: null });        // the server still says seller_sent
    expect(titles()).toContain(REFUSAL_TITLE);
    expect(titles()).not.toContain(RECEIPT);
    expect(h.haptics).toBe(0);
  });
});
