/**
 * The Send screen's "Delivery info not yet provided" box is gated on the order still being sendable
 * (C30-09b item 3). A disputed order that was never sent — freeze_transfer_for_dispute can set
 * `disputed` on a pending row (A, 2026-10-21) — still told the seller "The buyer must provide their
 * delivery info before you can send tickets", an instruction for a send that can no longer happen.
 * The box now needs `buyerDeliveryMissing && !orderClosed && !sendHalted`, the same halt the platform
 * instructions and the heading already use (tests/send-halted-states.test.ts).
 *
 * Runs the REAL app/transfer/send/[id].tsx through the hook dispatcher (harness from
 * send-transfer-expiry-truth.test.ts). Not a device result.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { readFileSync } from 'node:fs';
import { expandTree, findElement, HookHost, type Element } from './helpers/nav-stack-harness';

// The screen reads __DEV__ for its dev-only fixtures; these tests assert the release path.
(globalThis as Record<string, unknown>).__DEV__ = false;

const h = vi.hoisted(() => ({
  transfer: {} as Record<string, unknown>,
  focus: { current: null as null | (() => void) },
}));

// V3 appearance: the shared transfer-state blocks read the palette; pin the shipped dark one here.
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('react-native', () => ({
  // B-D7: the screens read fontScale for the shared stacking rule; the default window keeps the unstacked branch.
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: 1 }),
  Alert: { alert: () => {} },
  ActivityIndicator: 'ActivityIndicator', Pressable: 'Pressable', RefreshControl: 'RefreshControl',
  ScrollView: 'ScrollView', Text: 'Text', View: 'View', Linking: { openURL: () => {} },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Image: 'Image', Modal: 'Modal', KeyboardAvoidingView: 'KeyboardAvoidingView',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {} }, useLocalSearchParams: () => ({ id: 't-1' }) }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: (cb: () => void) => { h.focus.current = cb; } }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'seller-1' }, session: { user: { id: 'seller-1' } } }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }) }));
// The send summary now renders the event poster (owner's 4:5 direction, 2026-09-24). These suites
// mock `react-native` down to the handful of exports they need, which does not include PixelRatio,
// and EventMedia is not what they are testing — so it is stubbed the way the receive-screen suites
// already stub it (tests/v3-transfer-cells.test.ts).
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({
  Badge: 'Badge', Button: 'Button', IconButton: 'IconButton', Spinner: 'Spinner', StickyBar: 'StickyBar',
  Tappable: 'Tappable', Chip: 'Chip', MediaUpload: 'MediaUpload',
}));
vi.mock('@/src/components/PlatformInstructions', () => ({ default: 'PlatformInstructions' }));
vi.mock('@/src/hooks/useImageUpload', () => ({ useImageUpload: () => ({ pick: async () => null, uploading: false }) }));
vi.mock('@/src/lib/media/uploadFlow', () => ({
  REQUEST_TIMEOUT_MS: 30000,
  UPLOAD_COPY: { failed: 'Upload failed', timeout: 'Upload timed out' },
  withUploadTimeout: async <T,>(p: Promise<T>) => p,
}));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6 }));
vi.mock('@/src/lib/supabase', () => {
  const table = () => {
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'order', 'limit', 'in', 'neq', 'or', 'update', 'eq']) q[m] = () => q;
    q.single = async () => ({ data: h.transfer, error: null });
    q.maybeSingle = async () => ({ data: h.transfer, error: null });
    q.then = (ok: (v: unknown) => unknown) => Promise.resolve({ data: h.transfer, error: null }).then(ok);
    return q;
  };
  return {
    supabase: {
      from: () => table(),
      auth: { getUser: async () => ({ data: { user: { id: 'seller-1' } } }) },
      rpc: async () => ({ data: null, error: null }),
      storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }) }) },
    },
  };
});

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

const HOUR = 3_600_000;
function transfer(extra: Record<string, unknown> = {}) {
  return {
    id: 't-1', status: 'pending', seller_id: 'seller-1', buyer_id: 'buyer-1',
    listing_id: 'l-1', listing: { id: 'l-1', event_name: 'Sandbox L6', venue: 'Club Device' },
    delivery_email: 'buyer@example.test', delivery_phone: null,
    expires_at: new Date(Date.now() + 5 * HOUR).toISOString(),
    auto_release_at: null, transfer_evidence_path: null, platform: 'ticketmaster',
    transfer_method: 'app_transfer', ticket_platform: 'ticketmaster',
    buyer: { display_name: 'Buyer One' }, ...extra,
  };
}

/** Every string the screen renders, flattened. */
function texts(host: HookHost): string[] {
  const out: string[] = [];
  const walk = (node: unknown) => {
    if (Array.isArray(node)) { node.forEach(walk); return; }
    const el = node as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    if (typeof el.props.children === 'string') out.push(el.props.children);
    walk(el.props.children);
  };
  walk(expandTree(host.output));
  return out;
}

function markAsSent(host: HookHost): Element | undefined {
  return findElement(
    host.output,
    (el) => el.type === 'Button' && typeof el.props.label === 'string' &&
      (el.props.label === 'Mark as sent' || el.props.label === 'Try again'),
  );
}

async function mountSend(): Promise<HookHost> {
  const mod = await import('@/app/transfer/send/[id]');
  const Screen = (mod.default ?? mod) as () => unknown;
  const host = new HookHost(() => Screen(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

beforeEach(() => {
  h.transfer = transfer();
  h.focus.current = null;
  vi.resetModules();
});

const WARN = 'Delivery info not yet provided';
const noDelivery = { delivery_email: null, delivery_phone: null };

describe('WB: the delivery-missing box only shows on an order that can still be sent', () => {
  it('WB1: pending, no delivery details → the box shows (control)', async () => {
    h.transfer = transfer(noDelivery);
    expect(texts(await mountSend())).toContain(WARN);
  });

  it.each(['disputed', 'reversed', 'expired'])('WB2: %s and never sent, no delivery details → no box', async (status) => {
    h.transfer = transfer({ ...noDelivery, status, expires_at: new Date(Date.now() - HOUR).toISOString() });
    const t = texts(await mountSend());
    expect(t).not.toContain(WARN);
    expect(t.some((x) => /must provide their delivery info/.test(x))).toBe(false);
  });

  it('WB3: pending with delivery details → no box (unchanged)', async () => {
    expect(texts(await mountSend())).not.toContain(WARN);
  });
});

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const SEND = strip(readFileSync('app/transfer/send/[id].tsx', 'utf8'));
const GATE = '{buyerDeliveryMissing && !orderClosed && !sendHalted ? (';
/** The gate sits on the warnBox itself, inside the "Send tickets to" panel. */
function pinGate(src: string): void {
  const panel = src.slice(src.indexOf('s.sendToPanel'), src.indexOf('<PlatformInstructions'));
  const at = panel.indexOf(GATE);
  expect(at, 'gate on the warn box').toBeGreaterThan(0);
  expect(panel.indexOf('<View style={s.warnBox}>', at)).toBeGreaterThan(at);
  expect(panel.indexOf('<View style={s.warnBox}>', at) - at).toBeLessThan(80);
}

describe('WB-pin', () => {
  it('the warn box is gated on the halt and the close', () => { pinGate(SEND); });
  it('negative controls: the parent gate, or either half dropped, fails the pin', () => {
    expect(() => pinGate(SEND.replace(GATE, '{buyerDeliveryMissing ? ('))).toThrow();
    expect(() => pinGate(SEND.replace(GATE, '{buyerDeliveryMissing && !orderClosed ? ('))).toThrow();
    expect(() => pinGate(SEND.replace(GATE, '{buyerDeliveryMissing && !sendHalted ? ('))).toThrow();
  });
  it('the Mark as sent CTA enablement is unchanged', () => {
    expect(SEND).toContain('disabled={busy || refreshing || buyerDeliveryMissing}');
  });
});
