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

// V3 appearance: the shared transfer-state blocks read the palette; pin the shipped dark one here.
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
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
  if (text.includes(TRANSFER_EXPIRY_COPY.buyer)) return TRANSFER_EXPIRY_COPY.buyer;
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
    expect(windowLine(host)).toBe(TRANSFER_EXPIRY_COPY.buyer);
  });

  it('R2: seller_sent and past the window — no window line at all; the tickets are already on their way', async () => {
    h.transfer = transfer({ status: 'seller_sent', expires_at: PAST() });
    const host = await mountReceive();

    expect(rendered(host)).toBe(true);
    expect(screenText(host.output)).not.toContain('Transfer window expired');
    expect(screenText(host.output)).not.toContain(TRANSFER_EXPIRY_COPY.buyer);
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
    expect(screenText(host.output)).not.toContain(TRANSFER_EXPIRY_COPY.buyer);
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
    // screen re-reads. The countdown state keeps its last value across the status change — the RENDER gate is
    // what stops it being shown, which is why RM2 (widening that gate) kills this test and nothing else.
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

  it('R9: the buyer is never told to send — that instruction is the seller\'s', async () => {
    // F-XFER-2-A (A's wording review): batch 1b gave both screens one string, and its second clause —
    // "send now if you still can" — is addressed to the seller. The buyer cannot send and it is not their
    // action. The old literal was wrong for asserting an unenforced rule; this was wrong for addressing the
    // wrong party.
    h.transfer = transfer({ expires_at: PAST() });
    const host = await mountReceive();

    const shown = screenText(host.output);
    expect(rendered(host)).toBe(true);
    expect(shown).toContain(TRANSFER_EXPIRY_COPY.buyer);
    expect(shown).not.toContain(TRANSFER_EXPIRY_COPY.seller);
    expect(shown.toLowerCase()).not.toMatch(/send now|you (can |still )?send/);
  });

  it('R10: the two roles carry different words, and neither asserts a block', async () => {
    expect(TRANSFER_EXPIRY_COPY.buyer).not.toBe(TRANSFER_EXPIRY_COPY.seller);
    for (const [role, copy] of Object.entries(TRANSFER_EXPIRY_COPY)) {
      expect(copy.toLowerCase(), role).not.toContain('expired');
      expect(copy.toLowerCase(), role).not.toMatch(/can(no|')?t send|blocked|too late/);
    }
  });

  it('R11: a pending transfer starts exactly one countdown timer', async () => {
    const setInt = vi.spyOn(globalThis, 'setInterval');
    try {
      await mountReceive();
      expect(setInt.mock.calls.length).toBe(1);
      expect(setInt.mock.calls[0][1]).toBe(60_000);
    } finally {
      setInt.mockRestore();
    }
  });

  it('R12: a transfer the window no longer applies to starts NO timer, and a live one is cleared', async () => {
    // D's review: the effect's status gate was invisible to every assertion on rendered output, because what
    // it stops is a `setInterval` that fires `setCountdown` once a minute for as long as the screen is open —
    // a re-render per minute that changes nothing on screen. "Unobservable" has to include resource
    // behaviour, or the rule that deleted the redundant reset would eat a guard that does real work.
    const setInt = vi.spyOn(globalThis, 'setInterval');
    const clearInt = vi.spyOn(globalThis, 'clearInterval');
    try {
      h.transfer = transfer({ status: 'seller_sent', expires_at: PAST() });
      await mountReceive();
      expect(setInt.mock.calls.length).toBe(0);

      // And through the live transition: whatever was started while pending must be stopped, not left running.
      setInt.mockClear();
      clearInt.mockClear();
      h.transfer = transfer();                       // pending, inside the window
      const host = await mountReceive();
      expect(setInt.mock.calls.length).toBe(1);

      const open = findElement(
        host.output,
        (el) => el.type === 'Button' && typeof el.props.label === 'string' && (el.props.label as string).startsWith('Open '),
      );
      (open?.props.onPress as () => void)();
      host.flush();

      const realNow = Date.now();
      const clock = vi.spyOn(Date, 'now').mockReturnValue(realNow + 60_000);
      try {
        h.transfer = transfer({ status: 'seller_sent', expires_at: new Date(realNow - HOUR).toISOString() });
        h.appState.current?.('active');
        await flush();
        host.flush();
      } finally {
        clock.mockRestore();
      }

      expect(clearInt.mock.calls.length).toBeGreaterThanOrEqual(1);   // the pending timer was stopped
      expect(setInt.mock.calls.length).toBe(1);                        // and no new one took its place
    } finally {
      setInt.mockRestore();
      clearInt.mockRestore();
    }
  });

  it('R7: neither transfer screen carries the literal any more — one pinned source, not two strings', async () => {
    // Asserted on the source rather than by importing both screens: the send screen pulls native modules that
    // vitest cannot load, and what matters here is that no third copy of the string reappears later.
    const { readFileSync } = await import('node:fs');
    const send = readFileSync('app/transfer/send/[id].tsx', 'utf8');
    const receive = readFileSync('app/transfer/receive/[id].tsx', 'utf8');

    // Updated 2026-09-19: the send screen now takes its window line from sellerWindowView (which carries
    // TRANSFER_EXPIRY_COPY) — still one pinned source (owner's seller-window correction).
    expect(receive, 'receive').toContain('TRANSFER_EXPIRY_COPY');
    expect(send, 'send').toContain('sellerWindowView');
    for (const [name, src] of [['send', send], ['receive', receive]] as const) {
      expect(src, name).not.toContain("'Transfer window expired'");
      expect(src, name).not.toContain('send now if you still can');
    }
    expect(TRANSFER_EXPIRY_COPY.buyer.toLowerCase()).not.toContain('expired');
  });
});
