/**
 * Owner's decision 2 (2026-09-18) — confirming receipt asks first.
 *
 * Owner: "Add confirmation before 'I got my tickets': clearly explain that confirming receipt releases payment, with
 * Cancel and an explicit confirmation action. Preserve existing payment and server rules."
 *
 * Before this, one tap on "I got my tickets" invoked `confirm-and-release` straight away (guarded only against a
 * double tap); "I haven't received them" already asked first. Now the tap opens a dialog that says what confirming
 * does, and ONLY its explicit action sends anything. What that action sends — `confirm-and-release` with the transfer
 * id, inside the same single-flight lock — and every server rule behind it are unchanged.
 *
 * These run on the NORMAL sent state (delivery details on file) so they stand without decision 1; X5/X6 in
 * receive-transfer-sent-controls.test.ts cover the same path on sent-WITHOUT-delivery.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

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
    alerts: [] as { title: string; message?: string; buttons?: AlertButton[]; options?: { cancelable?: boolean } }[],
    invokes: [] as { name: string; body: unknown; d: ReturnType<typeof deferred<{ data: unknown; error: unknown }>> }[],
  };
});

vi.mock('react-native', () => ({
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

const CONFIRM = 'I got my tickets';
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

/** Tap "I got my tickets" once, as a person would. */
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
  h.alerts.length = 0; h.invokes.length = 0;
  vi.resetModules();
});

describe('Decision 2 — "I got my tickets" asks before it releases', () => {
  it('C1: the first tap sends nothing; it opens one dialog that says confirming releases payment', async () => {
    const host = await mountReceive();
    await tapConfirm(host);

    expect(h.invokes).toEqual([]);
    expect(h.alerts).toHaveLength(1);
    expect(h.alerts[0].title).toBe(DIALOG.title);
    expect(h.alerts[0].message).toBe(DIALOG.body);
  });

  it('C2: the dialog offers exactly Cancel and an explicit release action, and must be answered', async () => {
    const host = await mountReceive();
    await tapConfirm(host);

    expect(h.alerts[0].buttons?.map((b) => [b.text, b.style ?? 'default'])).toEqual([
      [DIALOG.cancel, 'cancel'],
      [DIALOG.confirm, 'default'],
    ]);
    expect(h.alerts[0].options?.cancelable).toBe(false);
  });

  it('C3: Cancel sends nothing', async () => {
    const host = await mountReceive();
    await tapConfirm(host);

    action(0, DIALOG.cancel)?.onPress?.();
    await flush();

    expect(action(0, DIALOG.cancel)).toBeDefined();
    expect(h.invokes).toEqual([]);
  });

  it('C4: only the explicit action sends confirm-and-release, once, for this transfer', async () => {
    const host = await mountReceive();
    await tapConfirm(host);
    expect(h.invokes).toEqual([]);

    action(0, DIALOG.confirm)?.onPress?.();
    await flush();

    expect(action(0, DIALOG.confirm)).toBeDefined();
    expect(h.invokes.map((i) => [i.name, i.body])).toEqual([['confirm-and-release', { transfer_id: 't-1' }]]);
  });

  it('C5: a same-tick double tap opens ONE dialog', async () => {
    const host = await mountReceive();
    const press = buttonByLabel(host.output, CONFIRM)?.props.onPress as () => void;   // captured once
    expect(press).toBeTypeOf('function');

    press();
    press();
    await flush();

    expect(dialogs()).toHaveLength(1);
    expect(h.invokes).toEqual([]);
  });

  it('C6: the release action pressed twice still sends once — single-flight survives the dialog', async () => {
    const host = await mountReceive();
    await tapConfirm(host);
    const release = action(0, DIALOG.confirm)?.onPress;
    expect(release).toBeTypeOf('function');

    release?.();
    release?.();
    await flush();

    expect(h.invokes).toHaveLength(1);
  });

  it('C7: nothing claims success until the server answers; then "Receipt confirmed"', async () => {
    const host = await mountReceive();
    await tapConfirm(host);
    action(0, DIALOG.confirm)?.onPress?.();
    await flush();
    host.flush();

    expect(h.alerts.map((a) => a.title)).toEqual([DIALOG.title]);
    expect(screenText(host.output)).not.toContain(transferStatusCopy('buyer_confirmed', 'buyer').body);

    h.invokes[0].d.resolve({ data: { ok: true }, error: null });
    await flush();
    host.flush();

    expect(h.alerts.map((a) => a.title)).toEqual([DIALOG.title, 'Receipt confirmed']);
    expect(screenText(host.output)).toContain(transferStatusCopy('buyer_confirmed', 'buyer').body);
  });

  it('C8: the return question never releases — "They\'re here" sends nothing and opens no dialog', async () => {
    // Pins the invariant, not a bypass that exists today: handleConfirm has one call site, the confirm button.
    const host = await mountReceive();
    const open = findElement(host.output, (el) => el.type === 'Button' && String(el.props.label).startsWith('Open '));
    expect(open).toBeDefined();
    (open?.props.onPress as () => void)();
    host.flush();
    const realNow = Date.now();
    const clock = vi.spyOn(Date, 'now').mockReturnValue(realNow + 60_000);
    try {
      expect(h.appState.current).toBeTypeOf('function');
      h.appState.current?.('active');
      await flush();
      host.flush();
    } finally {
      clock.mockRestore();
    }
    const here = buttonByLabel(host.output, RETURN_PROMPT.here);
    expect(here, 'the return question').toBeDefined();

    (here?.props.onPress as () => void)();
    await flush();
    host.flush();

    expect(h.invokes).toEqual([]);
    expect(dialogs()).toEqual([]);
  });

  it('C10: after a FAILED release, a later tap asks again — the lock re-arms on the confirm path too', async () => {
    // D's review: C9 pinned the re-arm after Cancel only. Dropping answered() from the explicit action left
    // "I got my tickets" enabled but dead after a failed release, and passed every suite.
    const host = await mountReceive();
    await tapConfirm(host);
    action(0, DIALOG.confirm)?.onPress?.();
    await flush();
    host.flush();
    expect(h.invokes).toHaveLength(1);                 // witness: the release really went out
    h.invokes[0].d.resolve({ data: null, error: { message: 'Edge Function returned a non-2xx status code' } });
    await flush();
    host.flush();

    await tapConfirm(host);

    expect(dialogs()).toHaveLength(2);                 // it asks again, rather than doing nothing
    expect(h.invokes).toHaveLength(1);                 // and asking sends nothing on its own
  });

  it('C9: after Cancel, a later tap asks again', async () => {
    const host = await mountReceive();
    await tapConfirm(host);
    action(0, DIALOG.cancel)?.onPress?.();
    await flush();

    await tapConfirm(host);

    expect(dialogs()).toHaveLength(2);
    expect(h.invokes).toEqual([]);
  });
});
