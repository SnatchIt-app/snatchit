/**
 * V3 order/transfer cells — implemented against A's PAYMENT_STATE_WORDING_TABLE_20260924 (fbbe0440):
 * three facts from three columns, never derived from one another — ORDER = transfers.status,
 * RECORDED REFUND = payments.{amount_refunded_cents, refunded_at, status}, CONFIRMED PAYOUT =
 * transfers.payout_released_at — with the precedence rules: reversed > payout_released_at;
 * disputed > any deadline; a NULL amount > the word "refunded"; server timestamp > device clock.
 *
 * Buyer cells: expired / reversed. Seller cells: expired (existing) / reversed. Deadline: the buyer's
 * review window from auto_release_at (omitted when absent — never assumed), the seller's release
 * decision line.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

(globalThis as Record<string, unknown>).__DEV__ = false;

const h = vi.hoisted(() => ({
  transfer: {} as Record<string, unknown>,
  payments: [] as Record<string, unknown>[],
  reads: 0,
  alerts: [] as { title: string; message?: string }[],
}));

vi.mock('react-native', () => ({
  Alert: { alert: (title: string, message?: string) => { h.alerts.push({ title, message }); } },
  AppState: { addEventListener: () => ({ remove: () => {} }), currentState: 'active' },
  AccessibilityInfo: { announceForAccessibility: () => {} },
  ActivityIndicator: 'ActivityIndicator', Pressable: 'Pressable', RefreshControl: 'RefreshControl',
  ScrollView: 'ScrollView', Text: 'Text', View: 'View', Linking: { openURL: () => {} },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Image: 'Image', Modal: 'Modal', KeyboardAvoidingView: 'KeyboardAvoidingView',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {}, replace: () => {} }, useLocalSearchParams: () => ({ id: 't-1' }) }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: () => {} }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'buyer-1' }, session: { user: { id: 'buyer-1' } } }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }), isNetworkError: () => false }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({ Badge: 'Badge', Button: 'Button', IconButton: 'IconButton', MediaUpload: 'MediaUpload', Spinner: 'Spinner' }));
vi.mock('@/src/components/DeliveryInfoForm', () => ({ default: 'DeliveryInfoForm' }));
vi.mock('@/src/components/ProofImageViewer', () => ({ ProofImageViewer: 'ProofImageViewer' }));
vi.mock('@/src/components/PlatformInstructions', () => ({ default: 'PlatformInstructions' }));
vi.mock('@/src/lib/feedback/haptics', () => ({ hapticSuccess: () => {} }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
// The shared transfer-state blocks read the palette; pin the shipped dark one at the boundary.
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
// The send screen's upload hook and single-flight guard: inert here — nothing is picked or sent.
vi.mock('@/src/hooks/useImageUpload', () => ({
  useImageUpload: () => ({ localUri: null, status: 'idle', error: null, busy: false, pickImage: () => {}, reset: () => {}, readError: () => null, uploadImage: async () => null }),
}));
vi.mock('@/src/lib/supabase', () => {
  const transfers = () => {
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'order', 'limit', 'in', 'neq', 'or', 'update', 'eq']) q[m] = () => q;
    const reply = async () => { h.reads += 1; return { data: h.transfer, error: null }; };
    q.single = reply; q.maybeSingle = reply;
    return q;
  };
  const payments = () => {
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'order', 'limit', 'eq', 'in']) q[m] = () => q;   // the real read filters with .in('status', …)
    q.then = (ok: (v: unknown) => unknown) => Promise.resolve({ data: h.payments, error: null }).then(ok);
    return q;
  };
  return {
    supabase: {
      from: (table: string) => (table === 'payments' ? payments() : transfers()),
      auth: { getUser: async () => ({ data: { user: { id: 'buyer-1' } } }) },
      rpc: async () => ({ data: null, error: null }),
      functions: { invoke: async () => ({ data: null, error: null }) },
      storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }) }) },
    },
  };
});

import {
  BUYER_ORDER_CLOSED_COPY,
  buyerReviewDeadlineLine,
  REFUND_DUE_POLICY,
  REFUND_PENDING_LINE,
  refundLine,
  SELLER_NO_PAYOUT_LINE,
  SELLER_REVERSED_COPY,
  sellerHoldLine,
  sellerReleaseLine,
  transferStatusMeta,
} from '@/src/lib/transfer/transferState';
import { rowWhenLabel } from '@/src/lib/listing/feedRowState';
import { expandTree, findElement, HookHost, type Element } from './helpers/nav-stack-harness';

const flush = async () => { for (let i = 0; i < 8; i++) await new Promise((r) => setImmediate(r)); };

function transfer(extra: Record<string, unknown> = {}) {
  return {
    id: 't-1', status: 'expired', seller_id: 'seller-1', buyer_id: 'buyer-1', listing_id: 'l-1',
    listing: { id: 'l-1', event_name: 'Sandbox L6', ticket_platform: 'ticketmaster' },
    delivery_email: 'buyer@example.test', delivery_phone: null, payout_released_at: null,
    expires_at: null, auto_release_at: null, transfer_evidence_path: null,
    transfer_method: 'mobile_transfer', seller: { display_name: null },
    ...extra,
  };
}

async function mount(): Promise<HookHost> {
  const mod = await import('@/app/transfer/receive/[id]');
  const Screen = (mod.default ?? mod) as () => unknown;
  const host = new HookHost(() => Screen(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

/** The REAL send screen, driven by the same mocked row (A's gap, 2026-09-24: the held branch was never rendered). */
async function mountSend(): Promise<HookHost> {
  const mod = await import('@/app/transfer/send/[id]');
  const Screen = (mod.default ?? mod) as () => unknown;
  const host = new HookHost(() => Screen(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

const collect = (node: unknown, out: string[]) => {
  if (Array.isArray(node)) { node.forEach((n) => collect(n, out)); return; }
  const el = node as Element | null;
  if (!el || typeof el !== 'object' || !('props' in el)) return;
  if (typeof el.props.children === 'string') out.push(el.props.children);
  if (typeof el.props.label === 'string') out.push(el.props.label);
  if (typeof el.props.title === 'string') out.push(el.props.title);
  collect(el.props.children, out);
};
// The screens compose shared block components; expand them so their text is asserted through the screen.
const texts = (host: HookHost) => { const out: string[] = []; collect(expandTree(host.output), out); return out; };

// The deadline line formats the server timestamp in LOCAL time through the shared row formatter.
function expectedDeadline(iso: string): string {
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return rowWhenLabel(`${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`, `${pad(d.getHours())}:${pad(d.getMinutes())}`);
}

beforeEach(() => {
  h.transfer = transfer();
  h.payments = [];
  h.reads = 0;
  h.alerts.length = 0;
  vi.resetModules();
});

describe('refundLine — the recorded refund, from the payment row alone (§3)', () => {
  it('TC1: full only with a known amount equal to total; partial states both; date/status without amount = "recorded"; nothing = null', () => {
    expect(refundLine({ status: 'refunded', amount_refunded_cents: 9900, refunded_at: '2026-09-24T00:00:00Z', total: 9900 })).toBe('Refunded $99');
    expect(refundLine({ status: 'succeeded', amount_refunded_cents: 4000, refunded_at: null, total: 9900 })).toBe('Partly refunded $40 of $99');
    expect(refundLine({ status: 'refunded', amount_refunded_cents: null, refunded_at: '2026-09-24T00:00:00Z', total: 9900 })).toBe('Refund recorded');
    expect(refundLine({ status: 'succeeded', amount_refunded_cents: null, refunded_at: '2026-09-24T00:00:00Z', total: 9900 })).toBe('Refund recorded');
    // An amount without a known total can never be called "in full".
    expect(refundLine({ status: 'refunded', amount_refunded_cents: 9900, refunded_at: null, total: null })).toBe('Refund recorded');
    expect(refundLine({ status: 'succeeded', amount_refunded_cents: null, refunded_at: null, total: 9900 })).toBeNull();
    expect(refundLine(null)).toBeNull();
  });
});

describe('status words and copy per role', () => {
  it('TC2: buyer never sees "reversed" as a money fact; the seller sees "Payout reversed"', () => {
    expect(transferStatusMeta('expired', 'buyer')).toEqual({ label: 'Expired', tone: 'neutral' });
    expect(transferStatusMeta('reversed', 'buyer').label).toBe('Closed');
    expect(transferStatusMeta('reversed', 'buyer').label.toLowerCase()).not.toContain('revers');
    expect(transferStatusMeta('reversed', 'seller')).toEqual({ label: 'Payout reversed', tone: 'warning' });
    expect(transferStatusMeta('expired', 'seller').label).toBe('Expired');
    expect(transferStatusMeta('pending', 'buyer').label).toBe('Pending');   // unchanged
  });

  it('TC3: the closed-order copy claims only what the status establishes', () => {
    expect(BUYER_ORDER_CLOSED_COPY.expired).toEqual({ title: 'Order expired', body: "The seller didn't send the tickets in time." });
    expect(REFUND_DUE_POLICY).toBe("A refund is due; it will show here once it's confirmed.");
    expect(BUYER_ORDER_CLOSED_COPY.reversed).toEqual({ title: 'Order closed', body: 'This order is closed.' });
    expect(REFUND_PENDING_LINE).toBe("If a refund is issued, it will show here.");   // A: strictly conditional — a reversal implies no refund by itself
    expect(SELLER_REVERSED_COPY).toEqual({ title: 'Payout reversed', body: "This order's payout was reversed after a dispute or operator review." });
    expect(SELLER_NO_PAYOUT_LINE).toBe('No payout for this order.');
    for (const s of [BUYER_ORDER_CLOSED_COPY.expired.body, BUYER_ORDER_CLOSED_COPY.reversed.body, SELLER_REVERSED_COPY.body]) {
      expect(s.toLowerCase()).not.toMatch(/refunded|\$|released/);
    }
  });

  it('TC4: the buyer\'s review deadline is the server timestamp, or nothing — never assumed', () => {
    const iso = '2026-09-26T21:00:00Z';
    expect(buyerReviewDeadlineLine(iso)).toBe(`Confirm you received the tickets, or report a problem, before ${expectedDeadline(iso)}.`);
    expect(buyerReviewDeadlineLine(null)).toBeNull();
    expect(buyerReviewDeadlineLine('not-a-date')).toBeNull();
    expect(buyerReviewDeadlineLine(iso)!.toLowerCase()).not.toMatch(/payout|released/);
  });

  it('TC6: the hold line only when held AND the server gives the date — a hold, never a payout, never derived', () => {
    const iso = '2026-09-28T12:00:00Z';
    expect(sellerHoldLine('held', iso)).toBe(`Payout held until ${expectedDeadline(iso)}.`);
    expect(sellerHoldLine('held', null)).toBeNull();
    expect(sellerHoldLine('manual_review', iso)).toBeNull();
    expect(sellerHoldLine(null, iso)).toBeNull();
    expect(sellerHoldLine('held', iso)!.toLowerCase()).not.toMatch(/released|paid out/);
  });

  it('TC5: the seller\'s line names a release DECISION time, never a payout', () => {
    const iso = '2026-09-26T21:00:00Z';
    expect(sellerReleaseLine(iso)).toBe(`Release decision at ${expectedDeadline(iso)}.`);
    expect(sellerReleaseLine(null)).toBeNull();
  });
});

describe('the buyer\'s receive screen — expired and reversed cells', () => {
  it('TR1: expired with no payment row — the order fact, the refund POLICY, the Expired word; no amount', async () => {
    const host = await mount();
    const t = texts(host);
    expect(t).toContain('Order expired');
    expect(t).toContain("The seller didn't send the tickets in time.");
    expect(t).toContain(REFUND_DUE_POLICY);
    expect(t).toContain('Expired');
    expect(t.some((x) => /Refunded|\$/.test(x))).toBe(false);
  });

  it('TR2: expired with a full refund recorded — "Refunded $99", and the policy line steps aside', async () => {
    h.payments = [{ status: 'refunded', amount_refunded_cents: 9900, refunded_at: '2026-09-24T00:00:00Z', total: 9900 }];
    const host = await mount();
    const t = texts(host);
    expect(t).toContain('Refunded $99');
    expect(t).not.toContain(REFUND_DUE_POLICY);
  });

  it('TR3: a partial refund is stated as partial, with both figures', async () => {
    h.payments = [{ status: 'succeeded', amount_refunded_cents: 4000, refunded_at: null, total: 9900 }];
    const host = await mount();
    expect(texts(host)).toContain('Partly refunded $40 of $99');
  });

  it('TR4: a refund with no recorded amount is "Refund recorded" — never a figure, never "in full"', async () => {
    h.payments = [{ status: 'refunded', amount_refunded_cents: null, refunded_at: '2026-09-24T00:00:00Z', total: 9900 }];
    const host = await mount();
    const t = texts(host);
    expect(t).toContain('Refund recorded');
    expect(t.some((x) => /\$/.test(x))).toBe(false);
  });

  it('TR5: reversed — "Order closed", the pending line, and the word "reversed" nowhere on the buyer\'s screen', async () => {
    h.transfer = transfer({ status: 'reversed', payout_released_at: '2026-09-20T00:00:00Z' });
    const host = await mount();
    const t = texts(host);
    expect(t).toContain('Order closed');
    expect(t).toContain(REFUND_PENDING_LINE);
    expect(t.some((x) => /revers/i.test(x))).toBe(false);
    expect(t.some((x) => /released/i.test(x))).toBe(false);   // payout_released_at is the SELLER's history here
  });

  it('TR6: the review deadline shows while seller_sent when the server gives it, and is absent when it does not', async () => {
    const iso = '2026-09-26T21:00:00Z';
    h.transfer = transfer({ status: 'seller_sent', auto_release_at: iso });
    const withIt = await mount();
    expect(texts(withIt)).toContain(`Confirm you received the tickets, or report a problem, before ${expectedDeadline(iso)}.`);
    h.transfer = transfer({ status: 'seller_sent', auto_release_at: null });
    const without = await mount();
    expect(texts(without).some((x) => x.startsWith('Confirm you received the tickets, or report a problem, before'))).toBe(false);
  });

  it('TR7: the select list carries the two new columns; the payment row is read only through readSettledPayments (source pins)', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('app/transfer/receive/[id].tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src).toMatch(/'id, listing_id, status, transfer_method, expires_at, auto_release_at, payout_released_at,/);
    expect(src).toContain('readSettledPayments(');
    expect(src).not.toMatch(/from\('payments'\)/);
  });
});

describe('the seller\'s send screen — reversed cell and the release line (source pins)', () => {
  it('TS1: a reversed block named "Payout reversed", checked BEFORE any payout claim; the badge speaks the seller role', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('app/transfer/send/[id].tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    const reversed = src.indexOf("transfer.status === 'reversed'");
    const released = src.indexOf("transfer.status === 'auto_released'");
    expect(reversed).toBeGreaterThan(-1);
    expect(reversed).toBeLessThan(released);
    // The reversed cell is the shared block (owner 2026-09-24: one implementation for the screens and
    // the sandbox gallery); the copy lives with the block.
    expect(src).toContain('<SellerReversedBlock />');
    const blocks = readFileSync('src/components/transfer/TransferStateBlocks.tsx', 'utf8');
    expect(blocks).toContain('SELLER_REVERSED_COPY.title');
    expect(src).toContain("transferStatusMeta(transfer.status, 'seller')");
  });

  it('TS2: the seller_sent line names the release DECISION time from the server, replacing the old "releases once it clears review" sentence', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('app/transfer/send/[id].tsx', 'utf8');
    const blocks = readFileSync('src/components/transfer/TransferStateBlocks.tsx', 'utf8');
    // The screen wires the server's columns into the shared block; the block names the lines.
    expect(src).toMatch(/<SellerSentBlock[\s\S]*?autoReleaseAt=\{transfer\.auto_release_at\}[\s\S]*?\/>/);
    expect(blocks).toContain('sellerReleaseLine(autoReleaseAt)');
    expect(blocks).not.toContain('Your payout releases once it clears review');
    expect(src).not.toContain('Your payout releases once it clears review');
    // A (2026-09-24): payout_hold_until is read and shown only in the held branch.
    expect(src).toMatch(/payout_review_status, payout_hold_until, /);
    expect(src).toMatch(/<SellerSentBlock[\s\S]*?payoutHoldUntil=\{transfer\.payout_hold_until\}[\s\S]*?\/>/);
    expect(blocks).toContain('sellerHoldLine(payoutReviewStatus, payoutHoldUntil)');
  });

  it('TS3: RENDERED through the real send screen — held with a date shows the hold line and neither countdown line (A\'s gap, 2026-09-24)', async () => {
    h.transfer = transfer({
      status: 'seller_sent', seller_id: 'buyer-1', buyer_id: 'other-1',
      payout_review_status: 'held', payout_hold_until: '2026-10-02T12:00:00Z',
      auto_release_at: '2026-09-30T12:00:00Z', buyer: { display_name: 'DV buyer' },
    });
    const host = await mountSend();
    const t = texts(host);
    expect(t).toContain(sellerHoldLine('held', '2026-10-02T12:00:00Z'));
    expect(t).not.toContain(sellerReleaseLine('2026-09-30T12:00:00Z'));
    expect(t.join(' ')).not.toMatch(/review window has passed/);
    expect(t.join(' ')).not.toMatch(/funds are held until shortly after the event/);   // the dated line, not the fallback
    expect(t).toContain('Marked sent');                                                 // the badge carries the status
  });
});
