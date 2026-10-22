/**
 * CFT-703 (A's refusal catalogue, 2026-10-21, §5b CRE-404 / CRE-500; A→C item 2): confirm-and-release
 * can answer 404 or 500 AFTER the buyer's confirmation is recorded. The screen showed the raw `error`
 * and offered "I have my tickets" again on a confirmed order. Now, on ANY non-2xx or a thrown call, it
 * re-reads the order first: a buyer_confirmed or auto_released row is the success it is (the same
 * haptic, state and "Receipt confirmed" as a 200); anything else gets the mapped copy, never raw text.
 *
 * Runs the REAL app/transfer/receive/[id].tsx through the hook dispatcher (harness from
 * receive-reread-after-confirm.test.ts). Not a device result.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';

import { HookHost } from './helpers/nav-stack-harness';
import { buttonByLabel } from './helpers/screen-view';

(globalThis as Record<string, unknown>).__DEV__ = false;

type AlertButton = { text: string; style?: string; onPress?: () => void };
type Reply = { data: unknown; error: unknown };

const h = vi.hoisted(() => {
  const deferred = <T,>() => {
    let resolve!: (v: T) => void;
    let reject!: (e: unknown) => void;
    const promise = new Promise<T>((ok, no) => { resolve = ok; reject = no; });
    return { promise, resolve, reject };
  };
  return {
    deferred,
    transfer: {} as Record<string, unknown>,
    focus: { current: null as null | (() => void) },
    readFails: false,
    reads: 0,
    haptics: 0,
    warns: [] as unknown[][],
    alerts: [] as { title: string; message?: string; buttons?: AlertButton[] }[],
    invokes: [] as { name: string; d: ReturnType<typeof deferred<{ data: unknown; error: unknown }>> }[],
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
vi.mock('@/src/components/ui', () => ({ Badge: 'Badge', Button: 'Button', IconButton: 'IconButton', Spinner: 'Spinner' }));
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
    q.single = async () => { h.reads++; return h.readFails ? { data: null, error: { message: 'Network request failed' } } : { data: h.transfer, error: null }; };
    q.maybeSingle = async () => ({ data: h.transfer, error: null });
    return q;
  };
  return {
    supabase: {
      from: () => table(),
      auth: { getUser: async () => ({ data: { user: { id: 'buyer-1' } } }) },
      rpc: async () => ({ data: null, error: null }),
      functions: {
        invoke: (name: string) => {
          const d = h.deferred<{ data: unknown; error: unknown }>();
          h.invokes.push({ name, d });
          return d.promise;
        },
      },
      storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }) }) },
    },
  };
});

const flush = async () => { for (let i = 0; i < 8; i++) await new Promise((r) => setImmediate(r)); };

const CONFIRM = 'I have my tickets';
const RELEASE = 'Confirm and release payment';
const RECEIPT = 'Receipt confirmed';
// Literal, not imported: the copy is pinned verbatim (and the file runs RED on the parent, not as an import error).
const REFUSAL_TITLE = "Couldn't confirm receipt";

function transfer(extra: Record<string, unknown> = {}) {
  return {
    id: 't-1', status: 'seller_sent', seller_id: 'seller-1', buyer_id: 'buyer-1', listing_id: 'l-1',
    listing: { id: 'l-1', event_name: 'Sandbox S9', ticket_platform: 'ticketmaster' },
    delivery_email: 'buyer@example.test', delivery_phone: null,
    expires_at: null, auto_release_at: null, transfer_evidence_path: null,
    transfer_method: 'mobile_transfer',
    seller: { display_name: 'Seller One' }, ...extra,
  };
}
const confirmedRow = () => transfer({ status: 'buyer_confirmed', buyer_confirmed_at: '2026-10-21T16:05:48Z', payout_released_at: null });

/** A FunctionsHttpError as supabase-js builds it: the raw Response in `.context`. */
const httpError = (status: number, body: Record<string, unknown>): Reply => ({
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

/** Tap, confirm in the dialog, then let the edge answer with `settle`. */
async function confirmWith(host: HookHost, settle: (d: (typeof h.invokes)[number]['d']) => void): Promise<void> {
  (buttonByLabel(host.output, CONFIRM)?.props.onPress as () => void)();
  await flush();
  h.alerts[0]?.buttons?.find((b) => b.text === RELEASE)?.onPress?.();
  await flush();
  expect(h.invokes).toHaveLength(1);
  settle(h.invokes[0].d);
  await flush();
  host.flush();
}

const titles = () => h.alerts.map((a) => a.title);
const lastAlert = () => h.alerts[h.alerts.length - 1];

beforeEach(() => {
  h.transfer = transfer();
  h.focus.current = null;
  h.readFails = false;
  h.reads = 0;
  h.haptics = 0;
  h.alerts.length = 0; h.invokes.length = 0; h.warns.length = 0;
  vi.spyOn(console, 'warn').mockImplementation((...a: unknown[]) => { h.warns.push(a); });
  vi.resetModules();
});

describe('CF: a non-2xx re-reads the order before it says anything', () => {
  it('CF1: CRE-500 after the confirmation landed → the re-read shows buyer_confirmed → "Receipt confirmed"', async () => {
    const host = await mountReceive();
    const before = h.reads;
    h.transfer = confirmedRow();                         // what the server holds when the 500 comes back
    await confirmWith(host, (d) => d.resolve(httpError(500, { error: 'Internal server error' })));
    expect(h.reads).toBeGreaterThan(before);             // it re-read
    expect(titles()).toContain(RECEIPT);
    expect(titles()).not.toContain('Error');
    expect(titles()).not.toContain(REFUSAL_TITLE);
    expect(h.haptics).toBe(1);                           // the same success haptic as a 200
    expect(buttonByLabel(host.output, CONFIRM)).toBeUndefined();
  });

  it('CF2: CRE-404 and the re-read shows auto_released → success', async () => {
    const host = await mountReceive();
    h.transfer = transfer({ status: 'auto_released', buyer_confirmed_at: null });
    await confirmWith(host, (d) => d.resolve(httpError(404, { error: 'Transfer not found' })));
    expect(titles()).toContain(RECEIPT);
    expect(h.haptics).toBe(1);
  });

  it('CF3: a thrown call and a confirmed re-read → success', async () => {
    const host = await mountReceive();
    h.transfer = confirmedRow();
    await confirmWith(host, (d) => d.reject(new TypeError('Network request failed')));
    expect(titles()).toContain(RECEIPT);
    expect(h.haptics).toBe(1);
  });

  it('CF4: after a success-by-re-read, a stale seller_sent read never offers the confirm again (confirmedHereRef)', async () => {
    const host = await mountReceive();
    h.transfer = confirmedRow();
    await confirmWith(host, (d) => d.resolve(httpError(500, { error: 'Internal server error' })));
    h.transfer = transfer();                             // a lagging replica answers the old row
    h.focus.current?.(); h.focus.current?.();
    await flush();
    host.flush();
    expect(buttonByLabel(host.output, CONFIRM)).toBeUndefined();
  });

  it('CF5: CNF-1 (400, disputed) and the re-read agrees → the mapped line, never the server text', async () => {
    const host = await mountReceive();
    const raw = 'Transfer cannot be confirmed from current status: disputed.';
    h.transfer = transfer({ status: 'disputed' });
    await confirmWith(host, (d) => d.resolve(httpError(400, { error: raw })));
    expect(lastAlert()).toMatchObject({ title: REFUSAL_TITLE, message: 'This order is under review. Pull down to refresh.' });
    expect(h.alerts.some((a) => a.message === raw)).toBe(false);
    expect(h.haptics).toBe(0);
    expect(h.warns.some((w) => w.includes(raw))).toBe(true);   // the raw text goes to the log
  });

  it('CF6: CRE-500 and a re-read that still shows seller_sent → the internal line; the confirm stays offered', async () => {
    const host = await mountReceive();
    await confirmWith(host, (d) => d.resolve(httpError(500, { error: 'Internal server error' })));
    expect(lastAlert()).toMatchObject({ title: REFUSAL_TITLE, message: "We couldn't confirm receipt. Pull down to refresh before trying again." });
    expect(titles()).not.toContain(RECEIPT);
    expect(h.haptics).toBe(0);
    expect(buttonByLabel(host.output, CONFIRM)?.props.disabled).toBe(false);
  });

  it('CF7: CRE-429 with a failed re-read → the rate-limit line', async () => {
    const host = await mountReceive();
    h.readFails = true;
    await confirmWith(host, (d) => d.resolve(httpError(429, { error: 'Too many requests. Please try again later.' })));
    expect(lastAlert()).toMatchObject({ title: REFUSAL_TITLE, message: 'Please wait a few minutes and try again.' });
  });

  it('CF8: a 200 is unchanged — success, then a quiet re-read', async () => {
    const host = await mountReceive();
    const before = h.reads;
    await confirmWith(host, (d) => d.resolve({ data: { success: true }, error: null }));
    expect(titles()).toContain(RECEIPT);
    expect(h.haptics).toBe(1);
    expect(h.reads).toBeGreaterThan(before);
  });
});

// ── Source pins anchored to confirmReceipt ──────────────────────────────────────────────────────
const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const RECEIVE = strip(readFileSync('app/transfer/receive/[id].tsx', 'utf8'));
const confirmBody = (src: string) => {
  const i = src.indexOf('async function confirmReceipt()');
  return i < 0 ? '' : src.slice(i, src.indexOf('function handleDispute()', i));
};
const PIN_REREAD = 'try { fresh = await fetchTransfer({ quiet: true }); } catch { fresh = null; }';
const PIN_LANDED = 'if (fresh && confirmationLanded(fresh.status)) { receiptConfirmed(true); return; }';
const PIN_COPY = 'Alert.alert(CONFIRM_REFUSAL_COPY.title, confirmRefusalCopy(failure));';

function pinConfirm(src: string): void {
  const b = confirmBody(src);
  expect(b, 'confirmReceipt body').not.toBe('');
  expect(b).not.toMatch(/Alert\.alert\('Error', (message|body\.error)\)/);
  expect(b).not.toContain('body.error');
  const reread = b.indexOf(PIN_REREAD);
  const landed = b.indexOf(PIN_LANDED);
  const copy = b.indexOf(PIN_COPY);
  expect(reread, 're-read on failure').toBeGreaterThan(0);
  expect(landed).toBeGreaterThan(reread);              // the re-read decides before any error is shown
  expect(copy).toBeGreaterThan(landed);
}

describe('CF-pins: confirmReceipt', () => {
  it('re-reads, then succeeds or maps — never the raw body', () => { pinConfirm(RECEIVE); });

  it('negative controls: each mutation fails the pin', () => {
    const b = confirmBody(RECEIVE);
    expect(() => pinConfirm(RECEIVE.replace(PIN_REREAD, ''))).toThrow();
    expect(() => pinConfirm(RECEIVE.replace(PIN_LANDED, ''))).toThrow();
    expect(() => pinConfirm(RECEIVE.replace(PIN_COPY, "Alert.alert('Error', message);"))).toThrow();
    // The error shown BEFORE the re-read (the old order) fails it too.
    expect(() => pinConfirm(RECEIVE.replace(b, b.replace(PIN_COPY, '').replace(PIN_REREAD, `${PIN_COPY}\n${PIN_REREAD}`)))).toThrow();
  });
});
