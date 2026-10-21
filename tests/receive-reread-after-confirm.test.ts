/**
 * Capture finding 2 (TEST-MODE sale, 2026-10-19; A's GO 2026-10-21): the buyer order didn't re-read after
 * "I have my tickets". The screen set the confirmed state locally and kept "Payout to seller: not released"
 * until it was reopened, though the payout was released seconds later. It now re-reads quietly after the
 * confirmation succeeds, and on every return to the screen. A quiet re-read that fails keeps the last good
 * state: it never undoes the confirmation and shows no error.
 *
 * Runs the REAL app/transfer/receive/[id].tsx through the hook dispatcher. Not a device result.
 */
// Harness copied from receive-transfer-confirm-dialog.test.ts, plus a captured focus callback and a
// switchable read failure.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';

import { RETURN_PROMPT } from '@/src/lib/transfer/providerHandoff';
import { transferStatusCopy } from '@/src/lib/transfer/transferState';
import { findElement, HookHost } from './helpers/nav-stack-harness';
import { buttonByLabel, screenText } from './helpers/screen-view';

(globalThis as Record<string, unknown>).__DEV__ = false;

type AlertButton = { text: string; style?: string; onPress?: () => void };

const h = vi.hoisted(() => {
  const deferred = <T,>() => {
    let resolve!: (v: T) => void;
    const promise = new Promise<T>((ok) => { resolve = ok; });
    return { promise, resolve };
  };
  return {
    deferred,
    transfer: {} as Record<string, unknown>,
    appState: { current: null as null | ((s: string) => void) },
    focus: { current: null as null | (() => void) },
    readFails: false,
    reads: 0,
    alerts: [] as { title: string; message?: string; buttons?: AlertButton[]; options?: { cancelable?: boolean } }[],
    invokes: [] as { name: string; body: unknown; d: ReturnType<typeof deferred<{ data: unknown; error: unknown }>> }[],
  };
});

// V3 appearance: the shared transfer-state blocks read the palette; pin the shipped dark one here.
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('react-native', () => ({
  // B-D7: the screens read fontScale for the shared stacking rule; the default window keeps the unstacked branch.
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: 1 }),
  Alert: {
    alert: (title: string, message?: string, buttons?: AlertButton[], options?: { cancelable?: boolean }) => {
      h.alerts.push({ title, message, buttons, options });
    },
  },
  AppState: {
    addEventListener: (_e: string, cb: (s: string) => void) => { h.appState.current = cb; return { remove: () => {} }; },
    currentState: 'active',
  },
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
vi.mock('@/src/components/ui', () => ({
  Badge: 'Badge', Button: 'Button', IconButton: 'IconButton', Spinner: 'Spinner',
}));
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
        invoke: (name: string, opts: { body: unknown }) => {
          const d = h.deferred<{ data: unknown; error: unknown }>();
          h.invokes.push({ name, body: opts.body, d });
          return d.promise;
        },
      },
      storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }) }) },
    },
  };
});

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

const CONFIRM = 'I have my tickets';
// The copy is pinned literally: a change to what this dialog says about money must change this file too.
const DIALOG = {
  title: 'Confirm you received the tickets?',
  body: 'Confirming receipt releases payment to the seller. Only confirm if you can see the tickets in your ticket account.',
  cancel: 'Cancel',
  confirm: 'Confirm and release payment',
};

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

async function mountReceive(): Promise<HookHost> {
  const mod = await import('@/app/transfer/receive/[id]');
  const Screen = (mod.default ?? mod) as () => unknown;
  const host = new HookHost(() => Screen(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

const dialogs = () => h.alerts.filter((a) => a.title === DIALOG.title);
const action = (i: number, text: string) => h.alerts[i]?.buttons?.find((b) => b.text === text);

/** Tap "I have my tickets" once, as a person would. */
async function tapConfirm(host: HookHost): Promise<void> {
  const confirm = buttonByLabel(host.output, CONFIRM);
  expect(confirm, 'the confirm-received control').toBeDefined();
  (confirm?.props.onPress as () => void)();
  await flush();
  host.flush();
}

beforeEach(() => {
  h.transfer = transfer();
  h.appState.current = null;
  h.focus.current = null;
  h.readFails = false;
  h.reads = 0;
  h.alerts.length = 0; h.invokes.length = 0;
  vi.resetModules();
});


const released = (host: HookHost) => screenText(host.output).includes('released') && !screenText(host.output).includes('not released');

async function confirmAndSucceed(host: HookHost) {
  await tapConfirm(host);
  action(0, DIALOG.confirm)?.onPress?.();
  await flush();
  h.invokes[0].d.resolve({ data: { ok: true }, error: null });
  await flush();
  host.flush();
}

describe('the order re-reads after confirming, and on return', () => {
  it('RR1: payout_released_at on the re-read after confirming flips the payout row without a reopen', async () => {
    const host = await mountReceive();
    const before = h.reads;
    // What the server holds by the time the re-read lands.
    h.transfer = transfer({ status: 'buyer_confirmed', buyer_confirmed_at: '2026-10-19T16:05:48Z', payout_released_at: '2026-10-19T16:05:52Z' });
    await confirmAndSucceed(host);
    expect(h.reads).toBeGreaterThan(before);
    expect(screenText(host.output)).not.toContain('not released');
    expect(released(host)).toBe(true);
  });

  it('RR2: a return to the screen re-reads quietly (the payout released after the first re-read)', async () => {
    const host = await mountReceive();
    h.transfer = transfer({ status: 'buyer_confirmed', buyer_confirmed_at: '2026-10-19T16:05:48Z', payout_released_at: null });
    await confirmAndSucceed(host);
    expect(screenText(host.output)).toContain('not released');

    h.transfer = transfer({ status: 'buyer_confirmed', buyer_confirmed_at: '2026-10-19T16:05:48Z', payout_released_at: '2026-10-19T16:05:52Z' });
    h.focus.current?.();          // first focus after mount is the mount read
    h.focus.current?.();
    await flush();
    host.flush();
    expect(released(host)).toBe(true);
  });

  it('RR3: a failed quiet re-read keeps the confirmed state and shows no error', async () => {
    const host = await mountReceive();
    h.readFails = true;
    await confirmAndSucceed(host);
    const text = screenText(host.output);
    expect(text).not.toContain(CONFIRM);                 // still confirmed: no "I have my tickets" again
    expect(findElement(host.output, (el) => el.type === 'ScreenState')).toBeUndefined();
    expect(text).toContain('not released');              // last good state, not a claim of release
  });

  it('RR4: a re-read that still shows seller_sent after a successful confirmation is stale, never a step back', async () => {
    const host = await mountReceive();
    // h.transfer stays seller_sent: the re-read lands on the old row.
    await confirmAndSucceed(host);
    expect(buttonByLabel(host.output, CONFIRM)).toBeUndefined();
    h.focus.current?.(); h.focus.current?.();
    await flush();
    host.flush();
    expect(buttonByLabel(host.output, CONFIRM)).toBeUndefined();
  });

  it('RR5: an older re-read that lands after a newer one changes nothing (review m6)', async () => {
    const host = await mountReceive();
    h.transfer = transfer({ status: 'buyer_confirmed', buyer_confirmed_at: '2026-10-19T16:05:48Z', payout_released_at: '2026-10-19T16:05:52Z' });
    await confirmAndSucceed(host);
    expect(released(host)).toBe(true);
    const src = readFileSync('app/transfer/receive/[id].tsx', 'utf8');
    expect(src).toMatch(/const gen = \+\+readGenRef\.current;[\s\S]{0,900}if \(gen !== readGenRef\.current\) return null;/);
  });

  it('RR6: a refused stale row is not returned to callers (review m7)', () => {
    const src = readFileSync('app/transfer/receive/[id].tsx', 'utf8');
    expect(src).toMatch(/if \(stale\) fresh = null;/);
  });
});
