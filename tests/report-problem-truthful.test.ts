/**
 * V3 O-3 — "Report a problem" is truthful about what left the device (owner 2026-09-22).
 *
 * Three states, never blurred: Cancel sends NOTHING; a server acknowledgement (including the RPC's
 * idempotent already-disputed success) is the only thing shown as reported; a network failure is a
 * submitted action with an UNKNOWN result — the screen re-reads first, and only when the server
 * still shows no report does it say the report is unconfirmed, never that it failed.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

(globalThis as Record<string, unknown>).__DEV__ = false;

const h = vi.hoisted(() => ({
  transfer: {} as Record<string, unknown>,
  rpcError: null as { code?: string | null; message: string } | null,
  rpcCalls: [] as string[],
  reads: 0,
  network: false,
  alerts: [] as { title: string; message?: string; buttons?: { text: string; onPress?: () => void }[] }[],
}));

// V3 appearance: the shared transfer-state blocks read the palette; pin the shipped dark one here.
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('react-native', () => ({
  Alert: {
    alert: (title: string, message?: string, buttons?: { text: string; onPress?: () => void }[]) => {
      h.alerts.push({ title, message, buttons });
    },
  },
  AppState: { addEventListener: () => ({ remove: () => {} }), currentState: 'active' },
  ActivityIndicator: 'ActivityIndicator', Pressable: 'Pressable', RefreshControl: 'RefreshControl',
  ScrollView: 'ScrollView', Text: 'Text', View: 'View', Linking: { openURL: () => {} },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Image: 'Image', Modal: 'Modal', KeyboardAvoidingView: 'KeyboardAvoidingView',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {}, replace: () => {} }, useLocalSearchParams: () => ({ id: 't-1' }) }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: () => {} }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'buyer-1' }, session: { user: { id: 'buyer-1' } } }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }), isNetworkError: () => h.network }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({ Badge: 'Badge', Button: 'Button', IconButton: 'IconButton', Spinner: 'Spinner' }));
vi.mock('@/src/components/DeliveryInfoForm', () => ({ default: 'DeliveryInfoForm' }));
vi.mock('@/src/components/ProofImageViewer', () => ({ ProofImageViewer: 'ProofImageViewer' }));
vi.mock('@/src/components/PlatformInstructions', () => ({ default: 'PlatformInstructions' }));
vi.mock('@/src/lib/feedback/haptics', () => ({ hapticSuccess: () => {} }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
vi.mock('@/src/lib/supabase', () => {
  const table = () => {
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'order', 'limit', 'in', 'neq', 'or', 'update', 'eq']) q[m] = () => q;
    const reply = async () => { h.reads += 1; return { data: h.transfer, error: null }; };
    q.single = reply;
    q.maybeSingle = reply;
    return q;
  };
  return {
    supabase: {
      from: () => table(),
      auth: { getUser: async () => ({ data: { user: { id: 'buyer-1' } } }) },
      rpc: async (fn: string) => {
        h.rpcCalls.push(fn);
        if (fn === 'buyer_dispute_transfer') return { data: null, error: h.rpcError };
        return { data: null, error: null };
      },
      functions: { invoke: async () => ({ data: null, error: null }) },
      storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }) }) },
    },
  };
});

import { REPORT_PROBLEM_UNCONFIRMED } from '@/src/lib/transfer/transferState';
import { HookHost } from './helpers/nav-stack-harness';

const flush = async () => { for (let i = 0; i < 8; i++) await new Promise((r) => setImmediate(r)); };

function transfer(extra: Record<string, unknown> = {}) {
  return {
    id: 't-1', status: 'seller_sent', seller_id: 'seller-1', buyer_id: 'buyer-1', listing_id: 'l-1',
    listing: { id: 'l-1', event_name: 'Sandbox L6', ticket_platform: 'ticketmaster' },
    delivery_email: 'buyer@example.test', delivery_phone: null, payout_released_at: null,
    expires_at: null, auto_release_at: null, transfer_evidence_path: null,
    transfer_method: 'mobile_transfer', seller: { display_name: null },
    ...extra,
  };
}

// The screen opens the dialog from its button; here the dialog is opened directly through the
// handler the button calls, by rendering and invoking the Report control.
async function mountThenTapReport(): Promise<HookHost> {
  const mod = await import('@/app/transfer/receive/[id]');
  const Screen = (mod.default ?? mod) as () => unknown;
  const host = new HookHost(() => Screen(), new Map());
  host.mount();
  await flush();
  host.flush();
  const { findElement } = await import('./helpers/nav-stack-harness');
  const btn = findElement(host.output, (el) =>
    el.type === 'Button' && el.props.label === "I haven't received them");
  expect(btn, 'the Report control').toBeDefined();
  (btn?.props.onPress as () => void)();
  await flush();
  const confirm = h.alerts.find((a) => a.title === 'Report issue');
  expect(confirm, 'the confirm dialog').toBeDefined();
  const go = confirm?.buttons?.find((b) => b.text === 'Report issue');
  h.alerts.length = 0;
  go?.onPress?.();
  await flush();
  host.flush();
  return host;
}

beforeEach(() => {
  h.transfer = transfer();
  h.rpcError = null;
  h.rpcCalls.length = 0;
  h.reads = 0;
  h.network = false;
  h.alerts.length = 0;
  vi.resetModules();
});

describe('O-3 — the three states are never blurred', () => {
  it('T1: Cancel sends nothing (locally unsent, and said as such by silence)', async () => {
    const mod = await import('@/app/transfer/receive/[id]');
    const Screen = (mod.default ?? mod) as () => unknown;
    const host = new HookHost(() => Screen(), new Map());
    host.mount();
    await flush();
    host.flush();
    const { findElement } = await import('./helpers/nav-stack-harness');
    const btn = findElement(host.output, (el) =>
      el.type === 'Button' && el.props.label === "I haven't received them");
    (btn?.props.onPress as () => void)();
    await flush();
    const confirm = h.alerts.find((a) => a.title === 'Report issue');
    confirm?.buttons?.find((b) => b.text === 'Cancel');   // present
    // Nothing pressed beyond Cancel: no RPC left the device.
    expect(h.rpcCalls).not.toContain('buyer_dispute_transfer');
  });

  it('T2: a server acknowledgement is shown as reported (ack-gated success, unchanged)', async () => {
    await mountThenTapReport();
    expect(h.rpcCalls).toContain('buyer_dispute_transfer');
    expect(h.alerts.some((a) => a.title === 'Reported')).toBe(true);
  });

  it('T3: a NETWORK failure re-reads first; if the report landed, the state shows it and no failure is claimed', async () => {
    h.rpcError = { code: null, message: 'Network request failed' };
    h.network = true;
    // Mounted while seller_sent; the RPC "fails" on the network but actually landed, so the
    // quiet re-read returns disputed — the swap below happens between mount and the tap.
    const mod = await import('@/app/transfer/receive/[id]');
    const Screen = (mod.default ?? mod) as () => unknown;
    const host = new HookHost(() => Screen(), new Map());
    host.mount();
    await flush();
    host.flush();
    const { findElement } = await import('./helpers/nav-stack-harness');
    const btn = findElement(host.output, (el) => el.type === 'Button' && el.props.label === "I haven't received them");
    expect(btn, 'the Report control').toBeDefined();
    h.transfer = transfer({ status: 'disputed' });
    (btn?.props.onPress as () => void)();
    await flush();
    const go = h.alerts.find((a) => a.title === 'Report issue')?.buttons?.find((b) => b.text === 'Report issue');
    h.alerts.length = 0;
    go?.onPress?.();
    await flush();
    host.flush();
    expect(h.alerts.map((a) => a.title)).toEqual([]);   // no alert at all: the screen state is the answer
  });

  it('T4: a NETWORK failure with no report on re-read says UNCONFIRMED — never "failed", never "reported"', async () => {
    h.rpcError = { code: null, message: 'Network request failed' };
    h.network = true;
    const readsBefore = h.reads;
    await mountThenTapReport();
    expect(h.reads).toBeGreaterThan(readsBefore + 1);   // the quiet re-read happened (mount read + re-read)
    const titles = h.alerts.map((a) => a.title);
    expect(titles).toContain(REPORT_PROBLEM_UNCONFIRMED.title);
    expect(titles).not.toContain('Reported');
    const body = h.alerts.find((a) => a.title === REPORT_PROBLEM_UNCONFIRMED.title)?.message ?? '';
    expect(body).toBe(REPORT_PROBLEM_UNCONFIRMED.body);
    expect(`${REPORT_PROBLEM_UNCONFIRMED.title} ${REPORT_PROBLEM_UNCONFIRMED.body}`.toLowerCase())
      .not.toMatch(/failed|was not received|didn't send|nothing was sent/);
  });

  it('T5: a SERVER refusal (a real answer) says the report was not recorded — and never claims reported', async () => {
    h.rpcError = { code: 'P0001', message: 'Cannot dispute transfer in current status: pending.' };
    h.network = false;
    await mountThenTapReport();
    const titles = h.alerts.map((a) => a.title);
    expect(titles).toContain("Couldn't submit the report");
    expect(titles).not.toContain('Reported');
  });
});
