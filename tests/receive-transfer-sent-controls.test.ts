/**
 * F-XFER-3 — on a transfer the seller has marked sent, missing delivery details never hide the buyer's
 * confirm-received or report-a-problem controls.
 *
 * `buyerNeedsDelivery` is true for `pending` OR `seller_sent` with no email and no phone, and the receive screen
 * rendered the whole `seller_sent` block — the seller's claim, the release warning, "I got my tickets" and
 * "I haven't received them" — only when that was false. So a sent transfer with no delivery info showed the
 * buyer a delivery form and nothing to confirm or dispute with. The server does not require delivery info to
 * mark a transfer sent (`mark_transfer_sent` in 0553 and 140 gates on status alone), and marking sent starts
 * `auto_release_at = now() + 72h` (0553:37). The owner's device report on "Sandbox S8only" (Build 20, 11:58) is
 * what surfaced it. How often real users could reach it is not established here: the seller app's send screen
 * refuses without delivery info, so reaching this state takes a direct call.
 *
 * The owner's ruling: the controls must show; their existing safeguards and the server rules stay as they are.
 * So these tests pin that the controls are present in exactly this state, that the delivery form is NOT traded
 * away to make room for them, and that every existing safeguard on the two controls still holds — the release
 * warning, the dispute confirmation, the single-flight lock, and no success before the server says so.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { transferStatusCopy } from '@/src/lib/transfer/transferState';
import { expandTree, findElement, HookHost } from './helpers/nav-stack-harness';
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
    alerts: [] as { title: string; message?: string; buttons?: AlertButton[] }[],
    /** Every rpc except the mount-time view stamp, so "called once" is counted, not assumed. */
    rpcs: [] as { name: string; args: unknown }[],
    /** Every edge-function call, each held open until the test answers it. */
    invokes: [] as { name: string; body: unknown; d: ReturnType<typeof deferred<{ data: unknown; error: unknown }>> }[],
  };
});

// V3 appearance: the shared transfer-state blocks read the palette; pin the shipped dark one here.
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('react-native', () => ({
  Alert: {
    alert: (title: string, message?: string, buttons?: AlertButton[]) => { h.alerts.push({ title, message, buttons }); },
  },
  AppState: { addEventListener: () => ({ remove: () => {} }), currentState: 'active' },
  Image: 'Image', KeyboardAvoidingView: 'KeyboardAvoidingView', Linking: { openURL: async () => true },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Pressable: 'Pressable', ScrollView: 'ScrollView', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {} }, useLocalSearchParams: () => ({ id: 't-1' }) }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: () => {} }));
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
    return q;
  };
  return {
    supabase: {
      from: () => table(),
      auth: { getUser: async () => ({ data: { user: { id: 'buyer-1' } } }) },
      rpc: async (name: string, args: unknown) => {
        if (name !== 'mark_transfer_viewed') h.rpcs.push({ name, args });
        return { data: null, error: null };
      },
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

const CONFIRM = 'I got my tickets';
const DISPUTE = "I haven't received them";
const RELEASE_WARNING = 'By confirming, you release payment to the seller.';
const DELIVERY_PROMPT = 'Please provide your delivery info so the seller knows where to send your tickets.';

function transfer(extra: Record<string, unknown> = {}) {
  return {
    id: 't-1', status: 'seller_sent', seller_id: 'seller-1', buyer_id: 'buyer-1', listing_id: 'l-1',
    listing: { id: 'l-1', event_name: 'Sandbox S8only', ticket_platform: 'ticketmaster' },
    // The state under test: marked sent, and the buyer never gave delivery details.
    delivery_email: null, delivery_phone: null,
    expires_at: new Date(Date.now() - 3_600_000).toISOString(), auto_release_at: null, transfer_evidence_path: null,
    transfer_method: 'mobile_transfer',
    seller: { display_name: null }, ...extra,
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

/**
 * A positive anchor: the screen really rendered THIS transfer's details, so an absence assertion means something.
 * Read from the details Row's props — `Row` is a local component, and its text is not in the flattened output.
 */
function renderedTransfer(host: HookHost): boolean {
  return findElement(host.output, (el) => el.props.label === 'Event' && el.props.value === 'Sandbox S8only') !== undefined;
}

const deliveryForm = (host: HookHost) => findElement(host.output, (el) => el.type === 'DeliveryInfoForm');

beforeEach(() => {
  h.transfer = transfer();
  h.alerts.length = 0; h.rpcs.length = 0; h.invokes.length = 0;
  vi.resetModules();
});

describe('F-XFER-3 — sent without delivery details: the buyer can still confirm or report', () => {
  it('X1: both controls are on screen', async () => {
    const host = await mountReceive();

    expect(renderedTransfer(host)).toBe(true);
    expect(buttonByLabel(host.output, CONFIRM), 'confirm-received').toBeDefined();
    expect(buttonByLabel(host.output, DISPUTE), 'report-a-problem').toBeDefined();
  });

  it("X2: the seller's claim and the release warning come with them — confirming is never offered bare", async () => {
    const host = await mountReceive();
    const text = screenText(expandTree(host.output));

    expect(text).toContain(transferStatusCopy('seller_sent', 'buyer').title);
    expect(text).toContain(RELEASE_WARNING);
  });

  it('X3: the delivery form is not traded away — it stays alongside the controls', async () => {
    const host = await mountReceive();

    expect(renderedTransfer(host)).toBe(true);
    expect(screenText(expandTree(host.output))).toContain(DELIVERY_PROMPT);
    expect(deliveryForm(host)).toBeDefined();
  });

  it('X4: reporting still asks first — nothing is sent until the buyer confirms the report', async () => {
    const host = await mountReceive();
    const dispute = buttonByLabel(host.output, DISPUTE);
    expect(dispute).toBeDefined();

    (dispute?.props.onPress as () => void)();
    await flush();
    expect(h.alerts.map((a) => a.title)).toEqual(['Report issue']);
    expect(h.rpcs).toEqual([]);

    const buttons = h.alerts[0].buttons ?? [];
    buttons.find((b) => b.style === 'cancel')?.onPress?.();
    await flush();
    expect(h.rpcs).toEqual([]);                       // Cancel sends nothing

    (dispute?.props.onPress as () => void)();
    h.alerts[1].buttons?.find((b) => b.style === 'destructive')?.onPress?.();
    await flush();
    expect(h.rpcs).toEqual([{ name: 'buyer_dispute_transfer', args: { p_transfer_id: 't-1' } }]);
  });

  // X5/X6 CHANGED ON PURPOSE with the owner's decision 2: they used to pin ONE-TAP release (tap → confirm-and-release).
  // Their new form — tap → dialog → explicit action → one release call — is the evidence that one-tap release is gone.
  const RELEASE = 'Confirm and release payment';
  const DIALOG_TITLE = 'Confirm you received the tickets?';

  it('X5: confirming asks first, then stays single-flight — one release call; both controls stand down', async () => {
    const host = await mountReceive();
    const confirm = buttonByLabel(host.output, CONFIRM);
    expect(confirm).toBeDefined();
    (confirm?.props.onPress as () => void)();
    await flush();

    expect(h.invokes).toEqual([]);                  // the tap alone sends nothing
    const release = h.alerts[0]?.buttons?.find((b) => b.text === RELEASE)?.onPress;
    expect(release).toBeTypeOf('function');
    release?.();
    release?.();                                    // captured once, pressed twice
    await flush();
    host.flush();

    expect(h.invokes.map((i) => [i.name, i.body])).toEqual([['confirm-and-release', { transfer_id: 't-1' }]]);
    expect(buttonByLabel(host.output, CONFIRM)?.props.disabled).toBe(true);
    expect(buttonByLabel(host.output, DISPUTE)?.props.disabled).toBe(true);
  });

  it('X6: a failed confirm is not shown as a success, and the controls come back', async () => {
    const host = await mountReceive();
    const confirm = buttonByLabel(host.output, CONFIRM);
    expect(confirm).toBeDefined();
    (confirm?.props.onPress as () => void)();
    await flush();
    h.alerts[0]?.buttons?.find((b) => b.text === RELEASE)?.onPress?.();
    await flush();
    host.flush();

    expect(h.alerts.map((a) => a.title)).toEqual([DIALOG_TITLE]);   // nothing claimed while the server has not answered
    h.invokes[0].d.resolve({ data: null, error: { message: 'Edge Function returned a non-2xx status code' } });
    await flush();
    host.flush();

    expect(h.alerts.map((a) => a.title)).toEqual([DIALOG_TITLE, 'Error']);
    expect(screenText(expandTree(host.output))).not.toContain(transferStatusCopy('buyer_confirmed', 'buyer').body);
    expect(buttonByLabel(host.output, CONFIRM)?.props.disabled).toBe(false);
    expect(buttonByLabel(host.output, DISPUTE)?.props.disabled).toBe(false);
  });
});

describe('F-XFER-3 — negative controls: every other state (all five statuses, with and without delivery) is as before', () => {
  it('X7: pending without delivery details — the form gates as before; no confirm, no report, no pending copy', async () => {
    h.transfer = transfer({ status: 'pending' });
    const host = await mountReceive();

    expect(renderedTransfer(host)).toBe(true);
    expect(deliveryForm(host)).toBeDefined();
    expect(buttonByLabel(host.output, CONFIRM)).toBeUndefined();
    expect(buttonByLabel(host.output, DISPUTE)).toBeUndefined();
    expect(screenText(expandTree(host.output))).not.toContain(transferStatusCopy('pending', 'buyer').body);
  });

  it('X8: sent WITH delivery details — controls present, no delivery form (regression guard)', async () => {
    h.transfer = transfer({ delivery_email: 'buyer@example.test' });
    const host = await mountReceive();

    expect(buttonByLabel(host.output, CONFIRM)).toBeDefined();
    expect(buttonByLabel(host.output, DISPUTE)).toBeDefined();
    expect(deliveryForm(host)).toBeUndefined();
  });

  it('X10: pending WITH delivery details — the normal pre-send state shows no confirm and no report', async () => {
    // D's review: a leak conditioned on delivery being PRESENT (XM9) passed every suite, because X7 only covers
    // pending WITHOUT it. This is the commonest state a transfer is ever in, and it was the one not pinned.
    h.transfer = transfer({ status: 'pending', delivery_email: 'buyer@example.test' });
    const host = await mountReceive();

    expect(renderedTransfer(host)).toBe(true);
    expect(deliveryForm(host)).toBeUndefined();   // anchored: delivery satisfied, so this IS the normal state
    expect(buttonByLabel(host.output, CONFIRM)).toBeUndefined();
    expect(buttonByLabel(host.output, DISPUTE)).toBeUndefined();
  });

  // Each finished status both without and WITH delivery details (D's review): the title below claims both, and a
  // leak conditioned on delivery being present (XM11) passed when only the "without" half was run.
  it.each([
    ['buyer_confirmed', 'without', null], ['buyer_confirmed', 'with', 'buyer@example.test'],
    ['disputed', 'without', null], ['disputed', 'with', 'buyer@example.test'],
    ['auto_released', 'without', null], ['auto_released', 'with', 'buyer@example.test'],
  ])(
    'X9: %s %s delivery details — no confirm or report controls leak into a finished transfer',
    async (status, _label, email) => {
      h.transfer = transfer({ status, delivery_email: email });
      const host = await mountReceive();

      expect(renderedTransfer(host)).toBe(true);
      expect(buttonByLabel(host.output, CONFIRM)).toBeUndefined();
      expect(buttonByLabel(host.output, DISPUTE)).toBeUndefined();
    },
  );
});
