/**
 * F-XFER-1 (client half) — Send Transfer never asserts an expiry the server does not enforce.
 *
 * Owner, Build 19, "Device D1": the screen showed "Transfer window expired" while the real blocker was
 * something else. C verified the shape at f412d10 and A confirmed the layer under it:
 *   - the chip is `formatCountdown(transfer.expires_at)` on a 60-second interval — computed on the DEVICE,
 *     from the device's clock;
 *   - the CTA is `disabled={busy || refreshing || buyerDeliveryMissing}` and has never included expiry;
 *   - `mark_transfer_sent` (migration 140) gates on STATUS only and never reads `expires_at`.
 * So the words claimed an enforcement that no layer performs: a seller could read "expired" and still send
 * successfully. Once the sweep moves the row off `pending` the send fails, but as a status conflict.
 *
 * This fixes only the client's claim. Whether the window should be enforced server-side is a product
 * decision on a stop-and-ask surface: A has taken it to the owner, and nothing here anticipates the answer.
 * The CTA's enablement is deliberately UNCHANGED — matching the server is the whole point.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { TRANSFER_EXPIRY_COPY } from '@/src/lib/transfer/transferState';
import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

// The screen reads __DEV__ for its dev-only fixtures; these tests assert the release path.
(globalThis as Record<string, unknown>).__DEV__ = false;

const h = vi.hoisted(() => ({
  transfer: {} as Record<string, unknown>,
  focus: { current: null as null | (() => void) },
}));

vi.mock('react-native', () => ({
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
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
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
  walk(host.output);
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

describe('F-XFER-1 (client half) — the screen says what the server actually does', () => {
  it('X1: past the window, the screen does not claim the transfer is blocked', async () => {
    h.transfer = transfer({ expires_at: new Date(Date.now() - HOUR).toISOString() });
    const host = await mountSend();

    const shown = texts(host).join(' | ');
    expect(shown).not.toContain('Transfer window expired');
    expect(shown).toContain(TRANSFER_EXPIRY_COPY.passed);
  });

  it('X2: past the window, Mark as sent stays enabled — the server still accepts it', async () => {
    h.transfer = transfer({ expires_at: new Date(Date.now() - HOUR).toISOString() });
    const host = await mountSend();

    const cta = markAsSent(host);
    expect(cta).toBeDefined();
    expect(cta?.props.disabled).toBeFalsy();
  });

  it('X3: missing delivery info still disables the CTA (the real blocker, unchanged)', async () => {
    h.transfer = transfer({ delivery_email: null, delivery_phone: null });
    const host = await mountSend();

    expect(markAsSent(host)?.props.disabled).toBe(true);
  });

  it('X4: inside the window the countdown is unchanged (regression guard)', async () => {
    const host = await mountSend();
    const shown = texts(host).join(' | ');

    expect(shown).toMatch(/to send/);
    expect(shown).not.toContain(TRANSFER_EXPIRY_COPY.passed);
  });

  it('X5: once the server has moved the row off pending, the window line is gone entirely', async () => {
    h.transfer = transfer({ status: 'expired', expires_at: new Date(Date.now() - HOUR).toISOString() });
    const host = await mountSend();

    const shown = texts(host).join(' | ');
    expect(shown).not.toContain(TRANSFER_EXPIRY_COPY.passed);
    expect(shown).not.toContain('Transfer window expired');
  });

  it('X6: the copy is pinned in one place and never asserts a block', async () => {
    expect(TRANSFER_EXPIRY_COPY.passed.length).toBeGreaterThan(0);
    expect(TRANSFER_EXPIRY_COPY.passed.toLowerCase()).not.toContain('expired');
    expect(TRANSFER_EXPIRY_COPY.passed.toLowerCase()).not.toMatch(/can(no|')?t send|blocked|too late/);
  });
});
