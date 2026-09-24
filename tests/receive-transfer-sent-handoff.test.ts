/**
 * F-XFER-3 follow-up, owner's decision 1 — on a transfer already marked sent, missing delivery details no longer
 * hide the provider handoff.
 *
 * Owner (2026-09-18): "Show 'Open [provider]' on a sent transfer even without delivery details, provided there is a
 * valid provider destination. Show useful general instructions, but omit empty contact fields."
 *
 * Before this, the receive screen rendered the buyer's platform instructions and "Open <provider>" only when
 * delivery details were on file, and `returnPrompt` refused to ask "Did the tickets arrive?" while they were missing.
 * F-XFER-3 (cf9b75b) made confirm/report visible in that state; this makes the way to CHECK the tickets visible too,
 * and lets the return question be asked. Opening the provider changes no state and releases nothing; the return
 * question only asks.
 *
 * "Valid provider destination" = `providerLink(platform)` is non-null: no destination, no button (never a dead one).
 * "Omit empty contact fields" = no buyer-facing instruction ever carries a contact placeholder, so nothing like
 * "(email not yet provided)", "null" or "undefined" can reach the buyer — pinned over every platform below.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { interpolateStep, PLATFORM_INSTRUCTIONS } from '@/src/lib/platformInstructions';
import { RETURN_PROMPT } from '@/src/lib/transfer/providerHandoff';
import { findElement, HookHost } from './helpers/nav-stack-harness';
import { buttonByLabel, screenText } from './helpers/screen-view';

(globalThis as Record<string, unknown>).__DEV__ = false;

const h = vi.hoisted(() => ({
  transfer: {} as Record<string, unknown>,
  appState: { current: null as null | ((s: string) => void) },
  opened: [] as string[],
  invokes: [] as string[],
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
  Image: 'Image', KeyboardAvoidingView: 'KeyboardAvoidingView',
  Linking: { openURL: async (u: string) => { h.opened.push(u); return true; } },
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
      functions: { invoke: async (name: string) => { h.invokes.push(name); return { data: null, error: null }; } },
      storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }) }) },
    },
  };
});

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

function transfer(extra: Record<string, unknown> = {}) {
  return {
    id: 't-1', status: 'seller_sent', seller_id: 'seller-1', buyer_id: 'buyer-1', listing_id: 'l-1',
    listing: { id: 'l-1', event_name: 'Sandbox S8only', ticket_platform: 'ticketmaster' },
    delivery_email: null, delivery_phone: null,
    expires_at: null, auto_release_at: null, transfer_evidence_path: null,
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

/** Positive anchor on THIS transfer's details (Row props; Row's text is not in the flattened output). */
const renderedTransfer = (host: HookHost) =>
  findElement(host.output, (el) => el.props.label === 'Event' && el.props.value === 'Sandbox S8only') !== undefined;
const openButton = (host: HookHost) =>
  findElement(host.output, (el) => el.type === 'Button' && typeof el.props.label === 'string' && (el.props.label as string).startsWith('Open '));
const instructions = (host: HookHost) => findElement(host.output, (el) => el.type === 'PlatformInstructions');
const deliveryForm = (host: HookHost) => findElement(host.output, (el) => el.type === 'DeliveryInfoForm');

/** Open the provider, stay away past MIN_AWAY_MS, come back: the screen's real return path. */
async function goAndReturn(host: HookHost): Promise<void> {
  (openButton(host)?.props.onPress as () => void)();
  host.flush();
  const realNow = Date.now();
  const clock = vi.spyOn(Date, 'now').mockReturnValue(realNow + 60_000);
  try {
    expect(h.appState.current).toBeTypeOf('function');   // a silent no-op would fake the return
    h.appState.current?.('active');
    await flush();
    host.flush();
  } finally {
    clock.mockRestore();
  }
}

beforeEach(() => {
  h.transfer = transfer();
  h.appState.current = null;
  h.opened.length = 0; h.invokes.length = 0;
  vi.resetModules();
});

describe('Decision 1 — sent without delivery details: the buyer can go and check', () => {
  it('O1: "Open Ticketmaster" and the buyer\'s instructions are on screen, and the button is live', async () => {
    const host = await mountReceive();

    expect(renderedTransfer(host)).toBe(true);
    expect(buttonByLabel(host.output, 'Open Ticketmaster')?.props.disabled).toBe(false);
    expect(instructions(host)?.props.role).toBe('buyer');
    expect(instructions(host)?.props.platform).toBe('ticketmaster');
  });

  it('O2: pressing it opens the official destination and records nothing else', async () => {
    const host = await mountReceive();
    (buttonByLabel(host.output, 'Open Ticketmaster')?.props.onPress as () => void)();
    await flush();

    expect(h.opened).toEqual(['https://www.ticketmaster.com/']);
    expect(h.invokes).toEqual([]);
  });

  it('O3: no platform\'s buyer instructions can show an empty contact field', () => {
    // The owner's "omit empty contact fields", pinned on the data every buyer screen renders: steps, tips and
    // warnings, interpolated with NO contact on file, never carry a placeholder, its fallback, or a null.
    const leaks = /\{buyer_|not yet provided|\bnull\b|\bundefined\b/;
    for (const [platform, ins] of Object.entries(PLATFORM_INSTRUCTIONS)) {
      expect(ins.buyer.steps.length, `${platform} has general steps`).toBeGreaterThan(0);
      for (const line of [ins.buyer.title, ins.buyer.estimatedTime, ...ins.buyer.steps, ...ins.buyer.tips, ...ins.warnings]) {
        expect(interpolateStep(line, null, null), platform).not.toMatch(leaks);
        expect(interpolateStep(line, '', ''), platform).not.toMatch(leaks);
      }
    }
  });

  it('O4: no valid destination, no button — but the general instructions still show', async () => {
    h.transfer = transfer({ listing: { id: 'l-1', event_name: 'Sandbox S8only', ticket_platform: 'other' } });
    const host = await mountReceive();

    expect(renderedTransfer(host)).toBe(true);
    expect(openButton(host)).toBeUndefined();
    expect(instructions(host)?.props.platform).toBe('other');
  });

  it('O5: coming back from the provider asks "Did the tickets arrive?"', async () => {
    const host = await mountReceive();
    expect(openButton(host)).toBeDefined();
    await goAndReturn(host);

    expect(screenText(host.output)).toContain(RETURN_PROMPT.title);
  });

  it('O6: "They\'re here" releases nothing — it only points at the confirm control', async () => {
    const host = await mountReceive();
    expect(openButton(host)).toBeDefined();
    await goAndReturn(host);
    const here = buttonByLabel(host.output, RETURN_PROMPT.here);
    expect(here).toBeDefined();

    (here?.props.onPress as () => void)();
    await flush();
    host.flush();

    expect(h.invokes).toEqual([]);
    expect(screenText(host.output)).not.toContain(RETURN_PROMPT.title);   // the question is answered
  });

  it('O10: no contact field is rendered at all — not an empty one', async () => {
    // D's criterion: on sent-without-delivery the screen shows NO delivery email/phone row and no placeholder text,
    // rather than an empty or "not provided" field.
    const host = await mountReceive();

    expect(renderedTransfer(host)).toBe(true);
    expect(findElement(host.output, (el) => el.props.label === 'Delivery email')).toBeUndefined();
    expect(findElement(host.output, (el) => el.props.label === 'Delivery phone')).toBeUndefined();
    expect(screenText(host.output)).not.toMatch(/not yet provided|\bnull\b|\bundefined\b/);
  });
});

describe('Decision 1 — negative controls: other states unchanged', () => {
  it('O7: PENDING without delivery details — still the form first; no instructions, no handoff', async () => {
    h.transfer = transfer({ status: 'pending' });
    const host = await mountReceive();

    expect(renderedTransfer(host)).toBe(true);
    expect(deliveryForm(host)).toBeDefined();
    expect(openButton(host)).toBeUndefined();
    expect(instructions(host)).toBeUndefined();
  });

  it('O8: pending WITH delivery details — instructions and handoff, as before', async () => {
    h.transfer = transfer({ status: 'pending', delivery_email: 'buyer@example.test' });
    const host = await mountReceive();

    expect(openButton(host)).toBeDefined();
    expect(instructions(host)?.props.buyerEmail).toBe('buyer@example.test');
  });

  it.each([
    ['buyer_confirmed', null], ['buyer_confirmed', 'buyer@example.test'],
    ['disputed', null], ['disputed', 'buyer@example.test'],
    ['auto_released', null], ['auto_released', 'buyer@example.test'],
  ])('O9: %s (email %s) — no handoff on a finished transfer', async (status, email) => {
    h.transfer = transfer({ status, delivery_email: email });
    const host = await mountReceive();

    expect(renderedTransfer(host)).toBe(true);
    expect(openButton(host)).toBeUndefined();
    expect(instructions(host)).toBeUndefined();
  });
});
