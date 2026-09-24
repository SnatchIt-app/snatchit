/**
 * The seller's expired-window messaging (owner, 2026-09-19, direct).
 *
 * Owner: "Remove 'send now if you still can.' A phone-clock deadline alone must not encourage sending tickets or
 * assert that a refund occurred. Use neutral wording while the order's current status is being checked. Where the
 * server confirms cancellation, expiry or refund, clearly tell the seller not to transfer tickets for that order. …
 * Don't change payment rules or treat a successful status refresh as a guarantee against a later expiry race."
 *
 * WHY (A, from main's edge source; production not read): the every-2-minutes expiry cron moves a pending transfer past
 * `expires_at` to `expired` and the edge then fully refunds the payment, after which `mark_transfer_sent` raises. A
 * seller told "send now if you still can" could transfer tickets for an order already refunded. On the sandbox the
 * cron is refused, so transfers never expire there: sandbox behaviour is not evidence of production's.
 *
 * The states, all on the Send Transfer screen:
 *   countdown       pending, device clock before `expires_at` — unchanged
 *   checking        pending, device clock past `expires_at`, no server read since — neutral; one quiet re-read fires
 *   last-checked    pending on a read taken after the device deadline — neutral, and it can still close any time
 *   closed          server-confirmed: transfer `expired` — "Don't transfer the tickets for this order"; the sending
 *                   instructions are hidden
 *
 * Owner (2026-09-19): keep this deadline-copy correction separately reviewable, and "don't infer cancellation or a full
 * refund from payment status alone": this change reads no payment data (V10). The refund-recorded screen is held on its
 * own branch at the wording-only stage while A resolves the payment lifecycle. Buyer phone/email are fulfilment details
 * whose display follows the final fulfilment policy, so they are unchanged here (V14).
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import {
  SELLER_ORDER_CLOSED_COPY,
  sellerWindowView,
  TRANSFER_EXPIRY_COPY,
} from '@/src/lib/transfer/transferState';
import { expandTree, findElement, HookHost, type Element } from './helpers/nav-stack-harness';

(globalThis as Record<string, unknown>).__DEV__ = false;

const ENCOURAGES_SENDING = /send now|still can|you can (still )?send|go ahead|safe to send/i;
const GUARANTEES = /guarantee|won'?t (expire|close)|will not (expire|close)|\bsafe\b/i;
const OLD_SELLER_LINE = 'Send window has passed — send now if you still can';

// ── The rule ────────────────────────────────────────────────────────────────────────────────────────────────────
describe('sellerWindowView — what the seller may be told', () => {
  it('V0 (witness): the old line is what the patterns catch', () => {
    expect(OLD_SELLER_LINE).toMatch(ENCOURAGES_SENDING);
  });

  it('V1: before the device deadline the countdown is unchanged', () => {
    expect(sellerWindowView({ status: 'pending', countdown: '3h 10m remaining', checkedSincePassed: false }))
      .toEqual({ kind: 'countdown', line: '3h 10m remaining to send' });
  });

  it('V2: the device clock alone gives the neutral "checking" line — no encouragement, no refund, no expiry claim', () => {
    const v = sellerWindowView({ status: 'pending', countdown: 'Expired', checkedSincePassed: false });
    expect(v).toEqual({ kind: 'checking', line: TRANSFER_EXPIRY_COPY.seller });
    expect(TRANSFER_EXPIRY_COPY.seller).toBe("Send window has passed — checking this order's status");
    expect(TRANSFER_EXPIRY_COPY.seller).not.toMatch(ENCOURAGES_SENDING);
    expect(TRANSFER_EXPIRY_COPY.seller.toLowerCase()).not.toMatch(/refund|expired|cancel/);
  });

  it('V3: still pending on a read after the deadline — neutral, and no guarantee against a later expiry', () => {
    const v = sellerWindowView({ status: 'pending', countdown: 'Expired', checkedSincePassed: true });
    expect(v).toEqual({ kind: 'last_checked_open', line: TRANSFER_EXPIRY_COPY.sellerLastCheckedOpen });
    expect(TRANSFER_EXPIRY_COPY.sellerLastCheckedOpen)
      .toBe('Send window has passed — this order was still open when last checked, but it can close at any time');
    expect(TRANSFER_EXPIRY_COPY.sellerLastCheckedOpen).not.toMatch(ENCOURAGES_SENDING);
    expect(TRANSFER_EXPIRY_COPY.sellerLastCheckedOpen).not.toMatch(GUARANTEES);
    expect(TRANSFER_EXPIRY_COPY.sellerLastCheckedOpen.toLowerCase()).not.toMatch(/refund|expired/);
  });

  it('V4: the server says expired — tell the seller not to transfer, whatever the device clock says', () => {
    for (const countdown of ['Expired', '2h 0m remaining', null]) {
      expect(sellerWindowView({ status: 'expired', countdown, checkedSincePassed: false }))
        .toEqual({ kind: 'closed', ...SELLER_ORDER_CLOSED_COPY.expired });
    }
    expect(SELLER_ORDER_CLOSED_COPY.expired).toEqual({
      title: 'Order expired',
      body: "This order expired before it was marked as sent. Don't transfer the tickets for this order.",
    });
  });

  it('V8: states past sending keep their own blocks — nothing from this rule', () => {
    for (const status of ['seller_sent', 'buyer_confirmed', 'auto_released', 'disputed', 'reversed']) {
      expect(sellerWindowView({ status, countdown: 'Expired', checkedSincePassed: true }), status)
        .toEqual({ kind: 'none' });
    }
    expect(sellerWindowView({ status: 'pending', countdown: null, checkedSincePassed: false }))
      .toEqual({ kind: 'none' });
  });

  it('V9: every closed body tells the seller not to transfer; none encourages it', () => {
    for (const [k, c] of Object.entries(SELLER_ORDER_CLOSED_COPY)) {
      expect(c.body, k).toContain("Don't transfer the tickets for this order.");
      expect(c.body, k).not.toMatch(ENCOURAGES_SENDING);
    }
  });
});

// ── The screen ──────────────────────────────────────────────────────────────────────────────────────────────────
const h = vi.hoisted(() => ({
  transfer: {} as Record<string, unknown>,
  selects: [] as string[],
  tables: [] as string[],
  rpcs: [] as string[],
  reads: 0,
}));

// V3 appearance: the shared transfer-state blocks read the palette; pin the shipped dark one here.
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('react-native', () => ({
  Alert: { alert: () => {} },
  ActivityIndicator: 'ActivityIndicator', Pressable: 'Pressable', RefreshControl: 'RefreshControl',
  ScrollView: 'ScrollView', Text: 'Text', View: 'View', Linking: { openURL: () => {} },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Image: 'Image', Modal: 'Modal', KeyboardAvoidingView: 'KeyboardAvoidingView',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {} }, useLocalSearchParams: () => ({ id: 't-1' }) }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: () => {} }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'seller-1' }, session: { user: { id: 'seller-1' } } }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }), isNetworkError: () => false }));
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
  const table = (name: string) => {
    h.tables.push(name);
    if (name === 'transfers') h.reads += 1;
    const q: Record<string, unknown> = {};
    for (const m of ['order', 'limit', 'in', 'neq', 'or', 'update', 'eq']) q[m] = () => q;
    q.select = (c: string) => { h.selects.push(c); return q; };
    q.single = async () => ({ data: h.transfer, error: null });
    q.maybeSingle = async () => ({ data: h.transfer, error: null });
    return q;
  };
  return {
    supabase: {
      from: (name: string) => table(name),
      auth: { getUser: async () => ({ data: { user: { id: 'seller-1' } } }) },
      rpc: async (fn: string) => { h.rpcs.push(fn); return { data: null, error: null }; },
      storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }) }) },
    },
  };
});

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };
const HOUR = 3_600_000;

function transfer(extra: Record<string, unknown> = {}) {
  return {
    id: 't-1', status: 'pending', seller_id: 'seller-1', buyer_id: 'buyer-1', listing_id: 'l-1',
    listing: { event_name: 'Sandbox L6', ticket_platform: 'ticketmaster' },
    delivery_email: 'buyer@example.test', delivery_phone: null,
    expires_at: new Date(Date.now() + 5 * HOUR).toISOString(),
    auto_release_at: null, payout_released_at: null, payout_review_status: null, transfer_evidence_path: null,
    transfer_method: 'app_transfer', buyer: { display_name: 'Buyer One' },
    ...extra,
  };
}

function texts(host: HookHost): string {
  const out: string[] = [];
  const walk = (node: unknown) => {
    if (Array.isArray(node)) { node.forEach(walk); return; }
    const el = node as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    if (typeof el.props.children === 'string') out.push(el.props.children);
    walk(el.props.children);
  };
  walk(expandTree(host.output));
  return out.join(' | ');
}
const block = (host: HookHost, title: string) => findElement(host.output, (el) => el.props.title === title);
const instructions = (host: HookHost) => findElement(host.output, (el) => el.type === 'PlatformInstructions');
/** The delivery target is a local Row: its value is a prop, never flattened text (so assert on the prop). */
const deliveryRow = (host: HookHost) => findElement(host.output, (el) => el.props.label === 'Email' && el.props.value === 'buyer@example.test');
const markAsSent = (host: HookHost) =>
  findElement(host.output, (el) => el.type === 'Button' && (el.props.label === 'Mark as sent' || el.props.label === 'Try again'));

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
  h.selects.length = 0;
  h.tables.length = 0;
  h.rpcs.length = 0;
  h.reads = 0;
  vi.resetModules();
});

describe('the Send Transfer screen', () => {
  it('V10: the screen reads no payment data — no payments table, embed or RPC (owner: nothing inferred from payment status)', async () => {
    // D's review: the first version saw only select strings, so a direct from('payments') or an RPC slipped past it.
    h.transfer = transfer({ expires_at: new Date(Date.now() - HOUR).toISOString() });   // past the deadline: all read paths run
    await mountSend();
    expect(h.tables).toContain('transfers');                                             // witness: table reads are recorded
    expect(h.tables).not.toContain('payments');
    expect(h.selects.some((c) => c.includes('listing:listings!listing_id('))).toBe(true);   // witness: embeds are visible here
    expect(h.selects.some((c) => /payments?[:!(]/.test(c))).toBe(false);
    // The screen's only RPCs are its two actions; none runs on open, and none may read payment state.
    expect(h.rpcs.every((fn) => fn === 'mark_transfer_sent' || fn === 'attach_transfer_evidence')).toBe(true);
    expect(h.rpcs).toEqual([]);
  });

  it('V11 (witness): an open order shows the instructions and the delivery target', async () => {
    const host = await mountSend();
    expect(instructions(host)).toBeDefined();
    expect(texts(host)).toContain('Send tickets to');          // witness: the sending heading stays on an open order
    expect(texts(host)).not.toContain("Buyer's delivery details");
    expect(deliveryRow(host)).toBeDefined();
    expect(texts(host)).toMatch(/\d+m remaining to send/);
  });

  it('V12: opened past the device deadline — the open read is a fresh check, so the neutral last-checked line', async () => {
    h.transfer = transfer({ expires_at: new Date(Date.now() - HOUR).toISOString() });
    const host = await mountSend();
    const shown = texts(host);
    expect(shown).toContain(TRANSFER_EXPIRY_COPY.sellerLastCheckedOpen);
    expect(shown).not.toMatch(ENCOURAGES_SENDING);
    expect(h.reads).toBe(1);
    expect(markAsSent(host)?.props.disabled).toBeFalsy();   // the server still decides; the action is unchanged
  });

  it('V13: the deadline passes on screen — "checking", ONE quiet re-read, then what the server said', async () => {
    const start = Date.now();
    h.transfer = transfer({ expires_at: new Date(start + 30_000).toISOString() });
    const setInt = vi.spyOn(globalThis, 'setInterval');
    let host: HookHost;
    let tick: () => void;
    try {
      host = await mountSend();
      tick = setInt.mock.calls[0]?.[0] as () => void;   // read before restore: mockRestore clears the calls
    } finally {
      setInt.mockRestore();
    }
    expect(tick).toBeTypeOf('function');
    expect(h.reads).toBe(1);

    const clock = vi.spyOn(Date, 'now').mockReturnValue(start + 60_000);
    try {
      h.transfer = transfer({ status: 'expired', expires_at: new Date(start + 30_000).toISOString() });
      tick();
      host.flush();
      expect(texts(host)).toContain(TRANSFER_EXPIRY_COPY.seller);           // the device clock alone: neutral
      await flush();
      host.flush();
      expect(h.reads).toBe(2);                                              // exactly one re-read
      expect(block(host, SELLER_ORDER_CLOSED_COPY.expired.title)).toBeDefined();
      expect(texts(host)).toContain(SELLER_ORDER_CLOSED_COPY.expired.body);
      tick();
      host.flush();
      await flush();
      expect(h.reads).toBe(2);                                              // and not again
    } finally {
      clock.mockRestore();
    }
  });

  it('V14: the server says expired — "don\'t transfer", no sending instructions, no window line; fulfilment details unchanged', async () => {
    h.transfer = transfer({ status: 'expired', expires_at: new Date(Date.now() - HOUR).toISOString() });
    const host = await mountSend();
    const shown = texts(host);
    expect(block(host, SELLER_ORDER_CLOSED_COPY.expired.title)).toBeDefined();
    expect(shown).toContain(SELLER_ORDER_CLOSED_COPY.expired.body);
    expect(instructions(host)).toBeUndefined();             // witness: V11 finds it on an open order
    // Unchanged by this correction: phone/email display follows the final fulfilment policy (owner, 2026-09-19).
    expect(deliveryRow(host)).toBeDefined();
    // Owner (2026-09-19): a neutral heading here — "Send tickets to" would instruct the opposite of the block above.
    expect(shown).toContain("Buyer's delivery details");
    expect(shown).not.toContain('Send tickets to');
    expect(shown).not.toContain('Send window has passed');
    expect(shown).not.toMatch(ENCOURAGES_SENDING);
  });

  it('V17: the old line is gone from the screen and the copy module', async () => {
    h.transfer = transfer({ expires_at: new Date(Date.now() - HOUR).toISOString() });
    const host = await mountSend();
    expect(texts(host)).not.toContain('send now');
    for (const line of Object.values(TRANSFER_EXPIRY_COPY)) expect(line).not.toContain('send now');
  });

  it('V18: A\'s timing (cron every 2 min): still open at the crossing → ONE more quiet read ~150 s later, then none', async () => {
    const start = Date.now();
    h.transfer = transfer({ expires_at: new Date(start + 30_000).toISOString() });
    const setInt = vi.spyOn(globalThis, 'setInterval');
    const setTo = vi.spyOn(globalThis, 'setTimeout');
    let host: HookHost;
    let tick: () => void;
    try {
      host = await mountSend();
      tick = setInt.mock.calls[0]?.[0] as () => void;
    } finally {
      setInt.mockRestore();
    }
    const clock = vi.spyOn(Date, 'now').mockReturnValue(start + 60_000);
    try {
      setTo.mockClear();
      tick();                                   // the deadline passes on screen; the server still says pending
      host.flush();
      await flush();
      host.flush();
      expect(h.reads).toBe(2);
      expect(texts(host)).toContain(TRANSFER_EXPIRY_COPY.sellerLastCheckedOpen);
      const follow = setTo.mock.calls.find((c) => c[1] === 150_000);
      expect(follow, 'a 150 s follow-up read is scheduled').toBeDefined();

      h.transfer = transfer({ status: 'expired', expires_at: new Date(start + 30_000).toISOString() });
      (follow?.[0] as () => void)();
      await flush();
      host.flush();
      expect(h.reads).toBe(3);
      expect(block(host, SELLER_ORDER_CLOSED_COPY.expired.title)).toBeDefined();
      expect(setTo.mock.calls.filter((c) => c[1] === 150_000).length).toBe(1);   // at most two automatic reads
    } finally {
      clock.mockRestore();
      setTo.mockRestore();
    }
  });
});

