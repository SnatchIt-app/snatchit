/**
 * Failed or missing reads must not become claims (owner, 2026-09-19).
 *
 * Owner: "Review the affected buyer/seller screens against their final contract. Ensure failed or missing reads cannot
 * produce unsupported claims about refunds, cancellation, transfer eligibility or payment release."
 *
 * Two defects this pins:
 *  1. BOTH transfer screens mapped every non-network read failure to "Transfer not found" — a claim that the order does
 *     not exist, made from a failed read (a 500, a timeout classified as non-network, an RLS change). Only "no row"
 *     supports it. Anything else is now the app's neutral error state ("Couldn't load this…" + Retry), which claims
 *     nothing about the order.
 *  2. The seller's auto_released block claimed "Your payout has been released" from the transfer status alone, while
 *     the buyer_confirmed block beside it already gated the same claim on `payout_released_at`. A payout can be
 *     skipped (the deployed job requires payment 'succeeded' — A's F-PAYOUT-PARTIAL-1) and Phase 2b then retries for
 *     ever, so auto_released alone does not establish that money moved. `payout_released_at` is written only after the
 *     Stripe transfer succeeds.
 *
 * Nothing here infers a refund, a cancellation or an eligibility to send: the refund-recorded state stays held with A
 * and D's safeguards.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { transferReadOutcome } from '@/src/lib/transfer/transferState';
import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

(globalThis as Record<string, unknown>).__DEV__ = false;

// ── The rule ────────────────────────────────────────────────────────────────────────────────────────────────────
describe('transferReadOutcome — what a read failure may be called', () => {
  it('N1: a network failure is offline', () => {
    expect(transferReadOutcome({ isNetwork: true, code: null, hasRow: false })).toBe('offline');
    expect(transferReadOutcome({ isNetwork: true, code: 'PGRST116', hasRow: false })).toBe('offline');
  });

  it('N2: only "no row" is "not found" — PostgREST\'s no-row code, or a row-less success', () => {
    expect(transferReadOutcome({ isNetwork: false, code: 'PGRST116', hasRow: false })).toBe('not_found');
    expect(transferReadOutcome({ isNetwork: false, code: null, hasRow: false })).toBe('not_found');
  });

  it('N3: any other failure is unavailable — never "not found"', () => {
    for (const code of ['PGRST000', '500', '42501', 'PGRST301', undefined]) {
      expect(transferReadOutcome({ isNetwork: false, code, hasRow: false, failed: true }), String(code)).toBe('unavailable');
    }
  });

  it('N4: a successful read with a row is neither', () => {
    expect(transferReadOutcome({ isNetwork: false, code: null, hasRow: true })).toBe('ok');
  });
});

// ── The screens ─────────────────────────────────────────────────────────────────────────────────────────────────
const h = vi.hoisted(() => ({
  transfer: null as Record<string, unknown> | null,
  error: null as { code?: string | null; message: string } | null,
  network: false,
}));

vi.mock('react-native', () => ({
  Alert: { alert: () => {} },
  AppState: { addEventListener: () => ({ remove: () => {} }), currentState: 'active' },
  ActivityIndicator: 'ActivityIndicator', Pressable: 'Pressable', RefreshControl: 'RefreshControl',
  ScrollView: 'ScrollView', Text: 'Text', View: 'View', Linking: { openURL: () => {} },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Image: 'Image', Modal: 'Modal', KeyboardAvoidingView: 'KeyboardAvoidingView',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {}, replace: () => {} }, useLocalSearchParams: () => ({ id: 't-1' }) }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: () => {} }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'u-1' }, session: { user: { id: 'u-1' } } }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }), isNetworkError: () => h.network }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({
  Badge: 'Badge', Button: 'Button', IconButton: 'IconButton', Spinner: 'Spinner', StickyBar: 'StickyBar',
  Tappable: 'Tappable', Chip: 'Chip', MediaUpload: 'MediaUpload',
}));
vi.mock('@/src/components/PlatformInstructions', () => ({ default: 'PlatformInstructions' }));
vi.mock('@/src/components/DeliveryInfoForm', () => ({ default: 'DeliveryInfoForm' }));
vi.mock('@/src/components/ProofImageViewer', () => ({ ProofImageViewer: 'ProofImageViewer' }));
vi.mock('@/src/hooks/useImageUpload', () => ({ useImageUpload: () => ({ pick: async () => null, uploading: false }) }));
vi.mock('@/src/lib/feedback/haptics', () => ({ hapticSuccess: () => {} }));
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
    const reply = async () => ({ data: h.transfer, error: h.error });
    q.single = reply;
    q.maybeSingle = reply;
    return q;
  };
  return {
    supabase: {
      from: () => table(),
      auth: { getUser: async () => ({ data: { user: { id: 'u-1' } } }) },
      rpc: async () => ({ data: null, error: null }),
      functions: { invoke: async () => ({ data: null, error: null }) },
      storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }) }) },
    },
  };
});

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

function transfer(extra: Record<string, unknown> = {}) {
  return {
    id: 't-1', status: 'pending', seller_id: 'u-1', buyer_id: 'u-1', listing_id: 'l-1',
    listing: { event_name: 'Sandbox L6', ticket_platform: 'ticketmaster' },
    delivery_email: 'buyer@example.test', delivery_phone: null,
    expires_at: new Date(Date.now() + 3_600_000).toISOString(),
    auto_release_at: null, payout_released_at: null, payout_review_status: null, transfer_evidence_path: null,
    transfer_method: 'app_transfer', buyer: { display_name: 'Buyer One' }, seller: { display_name: 'Seller One' },
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
  walk(host.output);
  return out.join(' | ');
}
const screenState = (host: HookHost) => findElement(host.output, (el) => el.type === 'ScreenState');

async function mount(which: 'send' | 'receive'): Promise<HookHost> {
  const mod = which === 'send'
    ? await import('@/app/transfer/send/[id]')
    : await import('@/app/transfer/receive/[id]');
  const Screen = (mod.default ?? mod) as () => unknown;
  const host = new HookHost(() => Screen(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

beforeEach(() => {
  h.transfer = transfer();
  h.error = null;
  h.network = false;
  vi.resetModules();
});

describe.each(['send', 'receive'] as const)('the %s screen never calls a failed read "not found"', (which) => {
  it(`F1 (${which}): an unknown read failure shows the neutral error state, not "Transfer not found"`, async () => {
    h.transfer = null;
    h.error = { code: 'PGRST000', message: 'Could not connect to the database' };
    const host = await mount(which);

    expect(screenState(host)?.props.state).toBe('error');           // "Couldn't load this…" + Retry; claims nothing
    expect(screenState(host)?.props.onRetry).toBeTypeOf('function');
    expect(texts(host)).not.toContain('Transfer not found');        // witness: F2 shows the screen can say it
  });

  it(`F2 (${which}): a row-less read still says "Transfer not found"`, async () => {
    h.transfer = null;
    h.error = { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned' };
    const host = await mount(which);

    expect(texts(host)).toContain('Transfer not found');
    expect(screenState(host)).toBeUndefined();
  });

  it(`F3 (${which}): a network failure is still the offline state (unchanged)`, async () => {
    h.transfer = null;
    h.error = { code: null, message: 'Network request failed' };
    h.network = true;
    const host = await mount(which);

    expect(screenState(host)?.props.state).toBe('offline');
    expect(texts(host)).not.toContain('Transfer not found');
  });

  it(`F4 (${which}, witness): a good read renders the transfer, so F1-F3 are not empty screens`, async () => {
    const host = await mount(which);
    expect(screenState(host)).toBeUndefined();
    // The event is a local Row: its value is a prop, never flattened text.
    expect(findElement(host.output, (el) => el.props.label === 'Event' && el.props.value === 'Sandbox L6')).toBeDefined();
  });
});

describe('the seller is told a payout moved only when the payout itself was recorded', () => {
  const RELEASED = 'Your payout has been released.';

  it('P1 (witness): auto_released WITH payout_released_at says the payout has been released', async () => {
    h.transfer = transfer({ status: 'auto_released', payout_released_at: new Date().toISOString() });
    const host = await mount('send');
    expect(texts(host)).toContain(RELEASED);
  });

  it('P2: auto_released WITHOUT it claims no release — the job can skip the payout and retry for ever', async () => {
    h.transfer = transfer({ status: 'auto_released', payout_released_at: null });
    const host = await mount('send');
    const shown = texts(host);

    expect(shown).toContain('The buyer review window passed without a dispute.');   // the status IS established
    expect(shown).not.toContain(RELEASED);
    expect(shown).toContain('has not been recorded as released yet');
    expect(shown.toLowerCase()).not.toMatch(/refund|cancel/);                        // and no refund/cancellation claim
  });

  it('P3 (regression): buyer_confirmed keeps its existing gate on the same field', async () => {
    h.transfer = transfer({ status: 'buyer_confirmed', payout_released_at: new Date().toISOString() });
    expect(texts(await mount('send'))).toContain(RELEASED);
    vi.resetModules();
    h.transfer = transfer({ status: 'buyer_confirmed', payout_released_at: null });
    const shown = texts(await mount('send'));
    expect(shown).not.toContain(RELEASED);
    expect(shown).toContain('Your payout is being processed');
  });
});
