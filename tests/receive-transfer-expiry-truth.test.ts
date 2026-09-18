/**
 * F-XFER-2 — the BUYER's screen must not claim an expiry the server does not enforce.
 *
 * Batch 1 fixed this on the seller's screen and left it standing on the counterparty's. A found it reviewing
 * that batch; C verified at the batch head and found the gate looser than reported:
 *   - `receive/[id].tsx:341` rendered the literal "Transfer window expired" from the same device-clock
 *     `formatCountdown(transfer.expires_at)`;
 *   - `:338` gated the render on `status !== 'buyer_confirmed'` — wider than the send screen's `=== 'pending'`;
 *   - `:165-170` the countdown effect had **no status condition at all**, where the send screen's also
 *     required `status === 'pending'`.
 * So a buyer could be told the window expired on a **seller_sent** transfer: the tickets are already on their
 * way, and the screen announces an expiry about a window that no longer applies, for an enforcement that does
 * not exist (`mark_transfer_sent`, migration 140, reads status only).
 *
 * Client-only, as authorised. No server enforcement, no status rules, no CTA gating changes — the buyer's
 * actions are pinned here precisely so the fix cannot quietly move them.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { TRANSFER_EXPIRY_COPY } from '@/src/lib/transfer/transferState';
import { findElement, HookHost } from './helpers/nav-stack-harness';
import { screenText } from './helpers/screen-view';

(globalThis as Record<string, unknown>).__DEV__ = false;

const h = vi.hoisted(() => ({
  transfer: {} as Record<string, unknown>,
  focus: { current: null as null | (() => void) },
  /** The screen re-reads on an AppState change, not on navigation focus — that is the path to drive. */
  appState: { current: null as null | ((s: string) => void) },
}));

vi.mock('react-native', () => ({
  Alert: { alert: () => {} },
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
vi.mock('@/src/components/ProofImageViewer', () => ({ ProofImageViewer: 'ProofImageViewer' }));
vi.mock('@/src/components/PlatformInstructions', () => ({ default: 'PlatformInstructions' }));
vi.mock('@/src/lib/feedback/haptics', () => ({ hapticSuccess: () => {} }));
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
      auth: { getUser: async () => ({ data: { user: { id: 'buyer-1' } } }) },
      rpc: async () => ({ data: null, error: null }),
      storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }) }) },
    },
  };
});

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

const HOUR = 3_600_000;
const PAST = () => new Date(Date.now() - HOUR).toISOString();
const FUTURE = () => new Date(Date.now() + 5 * HOUR).toISOString();

function transfer(extra: Record<string, unknown> = {}) {
  return {
    id: 't-1', status: 'pending', seller_id: 'seller-1', buyer_id: 'buyer-1',
    listing_id: 'l-1',
    // ticket_platform lives on the listing — that is where the screen reads it for the provider link.
    listing: { id: 'l-1', event_name: 'Sandbox L6', venue: 'Club Device', ticket_platform: 'ticketmaster' },
    delivery_email: 'buyer@example.test', delivery_phone: null,
    expires_at: FUTURE(), auto_release_at: null, transfer_evidence_path: null,
    transfer_method: 'app_transfer', ticket_platform: 'ticketmaster',
    seller: { display_name: 'Seller One' }, ...extra,
  };
}

/** The countdown row, identified by the copy it can carry. */
function windowLine(host: HookHost): string | undefined {
  const text = screenText(host.output);
  if (text.includes(TRANSFER_EXPIRY_COPY.passed)) return TRANSFER_EXPIRY_COPY.passed;
  if (text.includes('Transfer window expired')) return 'Transfer window expired';
  const remaining = screenText(host.output).split(' | ').find((t) => /remaining/.test(t));
  return remaining;
}

/** A positive anchor: the screen really rendered, so an absence assertion means something. */
function rendered(host: HookHost): boolean {
  return findElement(host.output, (el) => el.type === 'ScrollView') !== undefined
    && screenText(host.output).length > 0;
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

beforeEach(() => {
  h.transfer = transfer();
  h.focus.current = null;
  h.appState.current = null;
  vi.resetModules();
});

describe('F-XFER-2 — the buyer is never told a window expired that nothing enforces', () => {
  it('R1: pending and past the window — no "expired" claim, the honest line instead', async () => {
    h.transfer = transfer({ expires_at: PAST() });
    const host = await mountReceive();

    expect(rendered(host)).toBe(true);
    expect(screenText(host.output)).not.toContain('Transfer window expired');
    expect(windowLine(host)).toBe(TRANSFER_EXPIRY_COPY.passed);
  });

  it('R2: seller_sent and past the window — no window line at all; the tickets are already on their way', async () => {
    h.transfer = transfer({ status: 'seller_sent', expires_at: PAST() });
    const host = await mountReceive();

    expect(rendered(host)).toBe(true);
    expect(screenText(host.output)).not.toContain('Transfer window expired');
    expect(screenText(host.output)).not.toContain(TRANSFER_EXPIRY_COPY.passed);
    expect(windowLine(host)).toBeUndefined();
  });

  it('R3: seller_sent inside the window — still no window line; the send window stopped mattering', async () => {
    h.transfer = transfer({ status: 'seller_sent', expires_at: FUTURE() });
    const host = await mountReceive();

    expect(rendered(host)).toBe(true);
    expect(windowLine(host)).toBeUndefined();
  });

  it('R4: pending inside the window — the countdown is unchanged (regression guard)', async () => {
    const host = await mountReceive();

    expect(windowLine(host)).toMatch(/remaining/);
    expect(screenText(host.output)).not.toContain(TRANSFER_EXPIRY_COPY.passed);
  });

  it('R5: buyer_confirmed — no window line, as before', async () => {
    h.transfer = transfer({ status: 'buyer_confirmed', expires_at: PAST() });
    const host = await mountReceive();

    expect(rendered(host)).toBe(true);
    expect(windowLine(host)).toBeUndefined();
  });

  it('R6: the buyer keeps the same status blocks — this fix moves no status rule', async () => {
    // seller_sent is where the buyer confirms or disputes; that block must be untouched by the window change.
    h.transfer = transfer({ status: 'seller_sent', expires_at: PAST() });
    const host = await mountReceive();

    const buttons = ['Confirm receipt', 'I have the tickets', 'Report a problem', 'Dispute'];
    const anyAction = findElement(
      host.output,
      (el) => el.type === 'Button' && typeof el.props.label === 'string' && buttons.some((b) => (el.props.label as string).includes(b.split(' ')[0])),
    );
    expect(anyAction).toBeDefined();
  });

  it('R8: the seller sends while the buyer is away — the countdown clears with the status', async () => {
    // The only in-screen transition this screen has: the buyer opens the ticket provider, comes back, and the
    // screen re-reads. Without the explicit reset the last countdown string would survive the status change
    // and go on claiming a window that has stopped applying.
    const host = await mountReceive();
    expect(windowLine(host)).toMatch(/remaining/);

    const open = findElement(
      host.output,
      (el) => el.type === 'Button' && typeof el.props.label === 'string' && (el.props.label as string).startsWith('Open '),
    );
    expect(open, 'the provider handoff control').toBeDefined();
    (open?.props.onPress as () => void)();
    host.flush();

    // Away long enough for the return to count as a real handoff (MIN_AWAY_MS), then the seller has sent.
    const realNow = Date.now();
    const clock = vi.spyOn(Date, 'now').mockReturnValue(realNow + 60_000);
    try {
      h.transfer = transfer({ status: 'seller_sent', expires_at: new Date(realNow - HOUR).toISOString() });
      expect(h.appState.current).toBeTypeOf('function');   // a silent no-op would fake this test
      h.appState.current?.('active');
      await flush();
      host.flush();
    } finally {
      clock.mockRestore();
    }

    expect(rendered(host)).toBe(true);
    expect(windowLine(host)).toBeUndefined();
  });

  it('R7: neither transfer screen carries the literal any more — one pinned source, not two strings', async () => {
    // Asserted on the source rather than by importing both screens: the send screen pulls native modules that
    // vitest cannot load, and what matters here is that no third copy of the string reappears later.
    const { readFileSync } = await import('node:fs');
    const send = readFileSync('app/transfer/send/[id].tsx', 'utf8');
    const receive = readFileSync('app/transfer/receive/[id].tsx', 'utf8');

    for (const [name, src] of [['send', send], ['receive', receive]] as const) {
      expect(src, name).toContain('TRANSFER_EXPIRY_COPY');
      expect(src, name).not.toContain("'Transfer window expired'");
    }
    expect(TRANSFER_EXPIRY_COPY.passed.toLowerCase()).not.toContain('expired');
  });
});
