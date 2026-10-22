/**
 * tests/listing-draft-wiring.test.ts — CFT-608: the REAL CreateListingScreen with drafts wired in.
 *
 * Run under the suite's hook harness with the real useListingDraft, the real draft store over an
 * in-memory AsyncStorage, and the screen's own state. The upload hook, the client and the native
 * primitives are stand-ins; the publish gate chain is driven through to the insert.
 *
 *  W1  a stored draft is offered above the form; Continue puts every field back, the cover through
 *      the upload hook's restore, and neither the proof nor the attestation.
 *  W2  the harness fixture keeps drafts inert: no offer, no read, no write, no subscription.
 *  W3  edits autosave; the attestation and the proof never reach storage.
 *  W4  a publish the server confirmed clears the draft; W5 a refused insert keeps it.
 *  W6  Discard clears the draft and leaves the form as it was.
 *  W8  only a date the seller picked expires a draft: the date row's default (today) is not their
 *      choice, so a draft saved with it is still offered the next day (review LD-R2).
 *  W9  typing under an undecided offer asks which listing to keep, and Continue over typed input asks
 *      before replacing it, so autosave never sits paused while the seller types (review LD-R3).
 *  W10 a tick or a proof chosen before Continue, and the field errors of a publish tried then, do not
 *      survive the restore (review m1).
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { NEIGHBORHOOD_LABELS } from '@/src/constants/neighborhoods';
import { serializeListingDraft, type ListingDraftFields } from '@/src/lib/sell/listingDraft';
import { listingDraftKey } from '@/src/lib/sell/listingDraftStore';
import { findElement, HookHost, REPO_ROOT, type Element } from './helpers/nav-stack-harness';

const h = vi.hoisted(() => ({
  mem: new Map<string, string>(),
  ops: [] as string[],
  subscriptions: 0,
  pushes: [] as string[],
  alerts: [] as string[],
  alertCalls: [] as { title: string; body?: string; buttons?: { text: string; style?: string; onPress?: () => void }[] }[],
  inserts: [] as Record<string, unknown>[],
  insertResult: { data: { id: 'L1' } as { id: string } | null, error: null as null | { message: string; code?: string; hint?: string } },
  uploads: {
    covers: { localUri: null as string | null, restored: [] as string[], resets: 0 },
    proofs: { localUri: null as string | null, restored: [] as string[], resets: 0 },
  },
}));

vi.mock('@react-native-async-storage/async-storage', () => ({
  default: {
    getItem: async (k: string) => { h.ops.push(`get ${k}`); return h.mem.get(k) ?? null; },
    setItem: async (k: string, v: string) => { h.ops.push(`set ${k}`); h.mem.set(k, v); },
    removeItem: async (k: string) => { h.ops.push(`remove ${k}`); h.mem.delete(k); },
    getAllKeys: async () => { h.ops.push('keys'); return [...h.mem.keys()]; },
    multiRemove: async (ks: string[]) => { h.ops.push('multiRemove'); for (const k of ks) h.mem.delete(k); },
  },
}));
vi.mock('@/src/lib/supabase', () => {
  const rpc = (name: string) => {
    const result = name === 'can_create_listing'
      ? { data: [{ allowed: true, reason: 'ok', risk_tier: null }], error: null }
      : { data: null, error: null };
    return {
      returns: () => ({ maybeSingle: async () => ({ data: { stripe_onboarding_complete: true }, error: null }) }),
      then: (ok: (v: unknown) => unknown, bad?: (e: unknown) => unknown) => Promise.resolve(result).then(ok, bad),
    };
  };
  return {
    supabase: {
      auth: {
        getUser: async () => ({ data: { user: { id: 'u-1', phone_confirmed_at: '2026-01-01T00:00:00Z' } } }),
        onAuthStateChange: (cb: (e: string, s: unknown) => unknown) => {
          h.subscriptions += 1;
          queueMicrotask(() => { cb('INITIAL_SESSION', { user: { id: 'u-1' } }); });
          return { data: { subscription: { unsubscribe() {} } } };
        },
      },
      rpc,
      functions: { invoke: async () => ({ data: null, error: null }) },
      from: () => ({
        insert: (payload: Record<string, unknown>) => {
          h.inserts.push(payload);
          return { select: () => ({ single: async () => h.insertResult }) };
        },
      }),
    },
  };
});
vi.mock('@/src/hooks/useImageUpload', () => ({
  useImageUpload: (o: { folder: 'covers' | 'proofs' }) => {
    const u = h.uploads[o.folder];
    return {
      localUri: u.localUri, publicUrl: null, storagePath: null, status: u.localUri ? 'ready' : 'idle', error: null, busy: false,
      pickImage: async () => {},
      uploadImage: async () => (u.localUri ? `u-1/${o.folder}/1.jpg` : null),
      reset: () => { u.localUri = null; u.resets += 1; },
      readError: () => null,
      restore: (uri: string) => { u.restored.push(uri); u.localUri = uri; },
    };
  },
}));
vi.mock('react-native', () => ({
  AccessibilityInfo: { announceForAccessibility: () => {} },
  Alert: {
    alert: (t: string, body?: string, buttons?: { text: string; style?: string; onPress?: () => void }[]) => {
      h.alerts.push(t); h.alertCalls.push({ title: t, body, buttons });
    },
  },
  AppState: { addEventListener: () => ({ remove: () => {} }) },
  Image: { getSize: (_u: string, ok: (w: number, hh: number) => void) => { ok(800, 1000); } },
  KeyboardAvoidingView: 'KeyboardAvoidingView',
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Pressable: 'Pressable', ScrollView: 'ScrollView', Switch: 'Switch', Text: 'Text', TextInput: 'TextInput', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('@react-native-community/datetimepicker', () => ({ default: 'DateTimePicker' }));
vi.mock('expo-router', () => ({ router: { push: (p: string) => { h.pushes.push(p); }, back: () => {}, replace: () => {} } }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'u-1' } }) }));
vi.mock('@/src/hooks/useKeyboardUp', () => ({ useKeyboardUp: () => false }));
vi.mock('@/src/lib/nav/keyboardLift', () => ({ ctaLift: () => 0 }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useCtaDockOffset: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/components/nav/dockContext', () => ({ useDockScroll: () => ({ onScroll: undefined }) }));
vi.mock('@/src/components/ui', () => ({
  Button: 'Button', Chip: 'Chip', Input: 'Input', MediaUpload: 'MediaUpload', Sheet: 'Sheet', StickyBar: 'StickyBar',
}));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}) }));
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});

const NOW = new Date(2026, 9, 21, 12, 0, 0);
const COVER = 'file:///var/mobile/Containers/Data/Application/0A1B/Library/Caches/ImagePicker/5E6F.jpeg';
const PROOF = 'file:///var/mobile/Containers/Data/Application/0A1B/Library/Caches/ImagePicker/PROOF.jpeg';
const KEY = listingDraftKey('u-1');

const stored = (over: Partial<ListingDraftFields> = {}): ListingDraftFields => ({
  eventName: 'Weekend pool party', venue: 'LIV Miami', neighborhood: 'wynwood', category: 'concerts',
  eventDate: new Date(2026, 9, 25), eventTime: new Date(2026, 9, 21, 22), dateChosen: true, ticketType: 'VIP', quantity: 2,
  transferMethod: 'email', restrictions: '21+', startingBid: '40', buyNowEnabled: true, buyNowPrice: '90',
  durationHours: 24, ticketPlatform: 'dice', coverUri: COVER, ...over,
});

const settle = async () => { for (let i = 0; i < 12; i++) await new Promise((r) => setImmediate(r)); };

async function mountScreen(fixture?: object) {
  const mod = await import('@/src/screens/CreateListingScreen');
  const Screen = mod.default as (p: { fixture?: object }) => unknown;
  const host = new HookHost(() => Screen(fixture ? { fixture } : {}), new Map());
  host.mount();
  await settle();
  host.flush();
  const step = async (ms = 0) => { if (ms) await vi.advanceTimersByTimeAsync(ms); await settle(); host.flush(); };
  return { host, step };
}

const find = (host: HookHost, match: (el: Element) => boolean) => findElement(host.output, match);
const byLabel = (host: HookHost, label: string) => find(host, (el) => el.props.label === label);
const banner = (host: HookHost) => find(host, (el) => typeof el.props.onContinue === 'function' && 'offer' in el.props);
const checkbox = (host: HookHost) => find(host, (el) => el.type === 'Pressable' && el.props.accessibilityRole === 'checkbox')!;
const chip = (host: HookHost, label: string) => find(host, (el) => el.type === 'Chip' && el.props.label === label);
const publishButton = (host: HookHost) => find(host, (el) => el.type === 'Button' && el.props.size === 'lg')!;
const storedJson = () => JSON.parse(h.mem.get(KEY) ?? 'null') as { fields: Record<string, unknown> } | null;
const type = (host: HookHost, label: string, text: string) => {
  const field = byLabel(host, label)!;
  ((field.props.onChangeText ?? field.props.onChange) as (t: string) => void)(text);    // Input, or the screen's MoneyField
};
const dateRow = (d: Date) => d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });

/**
 * The quantity the stepper shows — its rendered number, and the number in its accessible name or value,
 * whichever wording the control uses: 'Quantity 2' (this branch) or 'Quantity' with accessibilityValue
 * { text: '2' } (C's adjustable control). The draft's restore is under test here, not that wording (LD-R4).
 */
function quantityShown(host: HookHost): { shown: unknown; spoken: string | undefined } {
  const el = find(host, (e) => typeof e.props.accessibilityLabel === 'string' && /^Quantity(?: \d+)?$/.test(e.props.accessibilityLabel));
  if (!el) return { shown: undefined, spoken: undefined };
  const label = el.props.accessibilityLabel as string;
  const value = (el.props.accessibilityValue as { text?: string } | undefined)?.text;
  return { shown: el.props.children, spoken: value ?? label.replace(/^Quantity ?/, '') };
}

/**
 * Every field-level error the screen shows: an error line (Text with role alert, the validation summary
 * included), a field whose `error` prop is set, an upload drawn with `hasError` — and the sticky bar's
 * own "Fix the highlighted fields" summary, which sits in its `left` prop.
 */
function shownErrors(host: HookHost): string[] {
  const out: string[] = [];
  const collect = (el: Element) => {
    const p = el.props;
    if (el.type === 'Text' && p.accessibilityRole === 'alert') out.push(String(p.children));
    else if (typeof p.error === 'string' && p.error !== '' && typeof p.label === 'string') out.push(`${p.label}: ${p.error}`);
    else if (p.hasError === true) out.push(`${String(p.label)}: hasError`);
    else if (el.type === 'Text' && p.children === 'Fix the highlighted fields before listing.') out.push(`sticky: ${p.children}`);
    return false;                                           // visit everything
  };
  findElement(host.output, collect);
  findElement(find(host, (el) => el.type === 'StickyBar')?.props.left, collect);
  return out;
}

/** Runs the REAL banner the screen rendered, with the props the screen gave it (the harness renders one level). */
function runBanner(host: HookHost): HookHost {
  const el = banner(host)!;
  const component = el.type as (p: Record<string, unknown>) => unknown;
  const props = el.props;
  const bh = new HookHost(() => component(props), new Map());
  bh.mount();
  return bh;
}

let AUTOSAVE = 1000;
beforeEach(async () => {
  vi.resetModules();
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
  vi.setSystemTime(NOW);
  h.mem.clear(); h.ops.length = 0; h.subscriptions = 0; h.pushes.length = 0; h.alerts.length = 0; h.alertCalls.length = 0; h.inserts.length = 0;
  h.insertResult = { data: { id: 'L1' }, error: null };
  for (const u of Object.values(h.uploads)) { u.localUri = null; u.restored.length = 0; u.resets = 0; }
  AUTOSAVE = (await import('@/src/hooks/useListingDraft')).AUTOSAVE_DELAY_MS;
});
afterEach(() => { vi.useRealTimers(); });

describe('W1 · a stored draft is offered, and Continue restores it', () => {
  it('W1a: the offer sits at the top of the form, before the Event section', async () => {
    h.mem.set(KEY, serializeListingDraft(stored(), NOW));
    const { host } = await mountScreen();
    const b = banner(host);
    expect(b).toBeDefined();
    const scroll = find(host, (el) => el.type === 'ScrollView' && Array.isArray(el.props.children))!;
    const kids = (scroll.props.children as unknown[]).filter(Boolean) as Element[];
    expect(kids[0]).toBe(b);
    expect((kids[1].props as { title?: string }).title).toBe('Event');
  });

  it('W1b: Continue puts every field back; the cover through restore; not the proof; not the attestation', async () => {
    h.mem.set(KEY, serializeListingDraft(stored(), NOW));
    const { host, step } = await mountScreen();
    expect(byLabel(host, 'Event name')!.props.value).toBe('');
    (banner(host)!.props.onContinue as () => void)();
    await step();
    expect(banner(host)).toBeUndefined();
    expect(byLabel(host, 'Event name')!.props.value).toBe('Weekend pool party');
    expect(byLabel(host, 'Venue')!.props.value).toBe('LIV Miami');
    expect(byLabel(host, 'Neighborhood')!.props.value).toBe(NEIGHBORHOOD_LABELS.wynwood);
    expect(chip(host, 'Concerts')!.props.selected).toBe(true);
    expect(chip(host, 'VIP')!.props.selected).toBe(true);
    expect(quantityShown(host)).toEqual({ shown: 2, spoken: '2' });
    expect(byLabel(host, 'Transfer method')!.props.value).toBe('Email');
    expect(byLabel(host, 'Ticket platform')!.props.value).toBe('DICE');
    expect(byLabel(host, 'Restrictions (optional)')!.props.value).toBe('21+');
    expect(byLabel(host, 'Starting bid')!.props.value).toBe('40');
    expect(find(host, (el) => el.type === 'Switch')!.props.value).toBe(true);
    expect(byLabel(host, 'Buy Now price')!.props.value).toBe('90');
    expect(chip(host, '1d')!.props.selected).toBe(true);
    expect(byLabel(host, 'Date')!.props.value).toBe(new Date(2026, 9, 25).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }));
    expect(h.uploads.covers.restored).toEqual([COVER]);
    expect(h.uploads.proofs.restored).toEqual([]);
    expect(checkbox(host).props.accessibilityState).toEqual({ checked: false });
  });
});

describe('W2 · the harness fixture keeps drafts inert', () => {
  it('W2 (negative control): no offer, no storage read or write, no auth subscription — even with a stored draft', async () => {
    h.mem.set(KEY, serializeListingDraft(stored(), NOW));
    const { host, step } = await mountScreen({ form: { eventName: 'Harness' } });
    expect(banner(host)).toBeUndefined();
    (byLabel(host, 'Event name')!.props.onChangeText as (t: string) => void)('Harness edit');
    await step(AUTOSAVE * 3);
    expect(h.ops).toEqual([]);
    expect(h.subscriptions).toBe(0);
  });
});

describe('W3 · autosave on change, form fields only', () => {
  it('W3: an edit is saved after the quiet period; the attestation and the proof never are', async () => {
    const { host, step } = await mountScreen();
    expect(banner(host)).toBeUndefined();
    h.uploads.proofs.localUri = PROOF;
    (byLabel(host, 'Event name')!.props.onChangeText as (t: string) => void)('Weekend');
    (checkbox(host).props.onPress as () => void)();
    await step(AUTOSAVE);
    const raw = h.mem.get(KEY)!;
    expect(storedJson()!.fields.eventName).toBe('Weekend');
    expect(checkbox(host).props.accessibilityState).toEqual({ checked: true });
    expect(raw).not.toMatch(/ommitment|PROOF|proof/);
  });
});

describe('W4/W5 · publish', () => {
  async function restoredAndReady() {
    h.mem.set(KEY, serializeListingDraft(stored(), NOW));
    const m = await mountScreen();
    (banner(m.host)!.props.onContinue as () => void)();
    await m.step();
    h.uploads.proofs.localUri = PROOF;      // the proof is picked again
    (checkbox(m.host).props.onPress as () => void)();
    await m.step(AUTOSAVE);
    expect(h.mem.has(KEY)).toBe(true);
    return m;
  }

  it('W4: the server confirmed the insert — the draft is cleared and the seller goes to the listing', async () => {
    const { host, step } = await restoredAndReady();
    (publishButton(host).props.onPress as () => void)();
    await step();
    // At once — not left to the autosave of the reset form, which an app kill could pre-empt.
    expect(h.pushes).toEqual(['/listing/L1']);
    expect(h.mem.has(KEY)).toBe(false);
    await step(AUTOSAVE * 2);
    expect(h.inserts).toHaveLength(1);
    expect(h.inserts[0].event_name).toBe('Weekend pool party');
    expect(h.inserts[0].cover_image_path).toBe('u-1/covers/1.jpg');
    expect(h.pushes).toEqual(['/listing/L1']);
    expect(h.mem.has(KEY)).toBe(false);
  });

  it('W5: a refused insert keeps the draft — nothing is cleared before the server confirms', async () => {
    h.insertResult = { data: null, error: { message: 'boom' } };
    const { host, step } = await restoredAndReady();
    (publishButton(host).props.onPress as () => void)();
    await step();
    expect(h.alerts).toContain('Error');
    expect(storedJson()!.fields.eventName).toBe('Weekend pool party');   // never removed, not merely re-saved
    await step(AUTOSAVE * 2);
    expect(h.inserts).toHaveLength(1);
    expect(h.pushes).toEqual([]);
    expect(storedJson()!.fields.eventName).toBe('Weekend pool party');
  });

  it('W5b: a server refusal (152 ACCOUNT_SUSPENDED) shows its own alert AND keeps the draft (E, D-2.4 D1)', async () => {
    h.insertResult = { data: null, error: { message: 'Account suspended', hint: 'ACCOUNT_SUSPENDED' } };
    const { host, step } = await restoredAndReady();
    (publishButton(host).props.onPress as () => void)();
    await step();
    expect(h.alerts).toContain('Account suspended');   // the refusal branch ran, not the generic error
    expect(h.alerts).not.toContain('Error');
    expect(storedJson()!.fields.eventName).toBe('Weekend pool party');
    await step(AUTOSAVE * 2);
    expect(h.pushes).toEqual([]);
    expect(storedJson()!.fields.eventName).toBe('Weekend pool party');
  });
});

describe('W6 · Discard', () => {
  it('W6: the draft is removed, the offer closes, the form is left as it was', async () => {
    h.mem.set(KEY, serializeListingDraft(stored(), NOW));
    const { host, step } = await mountScreen();
    (banner(host)!.props.onDiscard as () => void)();
    await step(AUTOSAVE * 2);
    expect(banner(host)).toBeUndefined();
    expect(h.mem.has(KEY)).toBe(false);
    expect(byLabel(host, 'Event name')!.props.value).toBe('');
    expect(h.uploads.covers.restored).toEqual([]);
  });
});

describe('W8 · only a date the seller picked expires a draft (LD-R2)', () => {
  it('W8a: typed on the 21st with the date row left at its default — offered on the 22nd, and it comes back dated the 22nd', async () => {
    const first = await mountScreen();
    type(first.host, 'Event name', 'Rolling Loud Saturday');
    type(first.host, 'Venue', 'Hard Rock Stadium');
    type(first.host, 'Starting bid', '120');
    await first.step(AUTOSAVE);
    expect(storedJson()!.fields).toMatchObject({ eventName: 'Rolling Loud Saturday', eventDate: '2026-10-21', dateChosen: false });
    first.host.unmount();

    vi.setSystemTime(new Date(2026, 9, 22, 9, 0));            // the next morning: a relaunch
    vi.resetModules();
    const { host, step } = await mountScreen();
    expect(banner(host)).toBeDefined();
    expect(h.mem.has(KEY)).toBe(true);
    (banner(host)!.props.onContinue as () => void)();
    await step();
    expect(byLabel(host, 'Event name')!.props.value).toBe('Rolling Loud Saturday');
    expect(byLabel(host, 'Starting bid')!.props.value).toBe('120');
    expect(byLabel(host, 'Date')!.props.value).toBe(dateRow(new Date(2026, 9, 22)));
  });

  it('W8b: a date the seller picked is recorded as picked, and once it has passed the draft is not offered and is removed', async () => {
    const first = await mountScreen();
    type(first.host, 'Event name', 'Tonight only');
    const picker = find(first.host, (el) => el.type === 'DateTimePicker')!;
    (picker.props.onChange as (e: unknown, d?: Date) => void)({ type: 'set' }, new Date(2026, 9, 21));
    await first.step(AUTOSAVE);
    expect(storedJson()!.fields).toMatchObject({ eventName: 'Tonight only', eventDate: '2026-10-21', dateChosen: true });
    first.host.unmount();

    vi.setSystemTime(new Date(2026, 9, 22, 9, 0));
    vi.resetModules();
    const { host } = await mountScreen();
    expect(banner(host)).toBeUndefined();
    expect(h.mem.has(KEY)).toBe(false);
  });

  it('W8c: Continue keeps a picked date picked, and a confirmed publish resets it to unpicked', async () => {
    h.mem.set(KEY, serializeListingDraft(stored(), NOW));
    const { host, step } = await mountScreen();
    (banner(host)!.props.onContinue as () => void)();
    await step();
    type(host, 'Venue', 'E11EVEN');
    await step(AUTOSAVE);
    expect(storedJson()!.fields).toMatchObject({ venue: 'E11EVEN', eventDate: '2026-10-25', dateChosen: true });
    h.uploads.proofs.localUri = PROOF;
    (checkbox(host).props.onPress as () => void)();
    (publishButton(host).props.onPress as () => void)();
    await step();
    expect(h.pushes).toEqual(['/listing/L1']);
    type(host, 'Event name', 'Next one');
    await step(AUTOSAVE);
    expect(storedJson()!.fields).toMatchObject({ eventName: 'Next one', dateChosen: false });
  });
});

describe('W9 · typing under an undecided offer asks which listing to keep (LD-R3)', () => {
  it('W9a: the first keystroke asks; "Start new listing" discards the saved draft and the typed listing autosaves', async () => {
    h.mem.set(KEY, serializeListingDraft(stored(), NOW));
    const { host, step } = await mountScreen();
    expect(banner(host)!.props.formHasInput).toBe(false);
    type(host, 'Event name', 'A');
    await step();
    expect(banner(host)!.props.formHasInput).toBe(true);
    runBanner(host);
    const ask = h.alertCalls.at(-1)!;
    expect(ask.title).toBe('Start a new listing?');
    ask.buttons!.find((b) => b.text === 'Start new listing')!.onPress!();
    await step();
    expect(banner(host)).toBeUndefined();
    type(host, 'Event name', 'A different show I just typed');
    await step(AUTOSAVE);
    expect(byLabel(host, 'Event name')!.props.value).toBe('A different show I just typed');
    expect(storedJson()!.fields.eventName).toBe('A different show I just typed');   // saved, not paused
    expect(h.uploads.covers.restored).toEqual([]);
  });

  it('W9b: "Continue saved listing" puts the saved one back in place of the keystroke', async () => {
    h.mem.set(KEY, serializeListingDraft(stored(), NOW));
    const { host, step } = await mountScreen();
    type(host, 'Event name', 'A');
    await step();
    runBanner(host);
    h.alertCalls.at(-1)!.buttons!.find((b) => b.text === 'Continue saved listing')!.onPress!();
    await step();
    expect(banner(host)).toBeUndefined();
    expect(byLabel(host, 'Event name')!.props.value).toBe('Weekend pool party');
    expect(h.uploads.covers.restored).toEqual([COVER]);
  });

  it('W9c: Continue over typed input — and over a newly picked cover — asks first; Cancel keeps them, Replace restores', async () => {
    h.mem.set(KEY, serializeListingDraft(stored(), NOW));
    const { host, step } = await mountScreen();
    const NEW_COVER = COVER.replace('5E6F', 'NEW1');
    h.uploads.covers.localUri = NEW_COVER;                  // picked while the offer was up
    type(host, 'Event name', 'Mine');
    await step();
    const bh = runBanner(host);
    h.alertCalls.length = 0;                                // the start-new question (W9a) is set aside here
    (findElement(bh.output, (el) => el.type === 'Button' && el.props.label === 'Continue your listing')!.props.onPress as () => void)();
    const ask = h.alertCalls.at(-1)!;
    expect(ask.title).toBe("Replace what you've typed?");
    ask.buttons!.find((b) => b.text === 'Cancel')!.onPress?.();
    await step();
    expect(byLabel(host, 'Event name')!.props.value).toBe('Mine');
    expect(h.uploads.covers.localUri).toBe(NEW_COVER);
    expect(h.uploads.covers.restored).toEqual([]);
    ask.buttons!.find((b) => b.text === 'Replace')!.onPress!();
    await step();
    expect(byLabel(host, 'Event name')!.props.value).toBe('Weekend pool party');
    expect(h.uploads.covers.restored).toEqual([COVER]);
  });

  it('W9d: with nothing typed, Continue restores at once — no question', async () => {
    h.mem.set(KEY, serializeListingDraft(stored(), NOW));
    const { host, step } = await mountScreen();
    const bh = runBanner(host);
    (findElement(bh.output, (el) => el.type === 'Button' && el.props.label === 'Continue your listing')!.props.onPress as () => void)();
    await step();
    expect(h.alertCalls).toEqual([]);
    expect(byLabel(host, 'Event name')!.props.value).toBe('Weekend pool party');
  });
});

describe('W10 · Continue starts the attestation, the proof and the field errors over (review m1)', () => {
  it('W10a: a tick and a proof chosen before Continue — and the errors of a publish tried then — do not survive the restore', async () => {
    h.mem.set(KEY, serializeListingDraft(stored(), NOW));
    const { host, step } = await mountScreen();
    h.uploads.proofs.localUri = PROOF;                      // a proof picked while the offer was up
    (checkbox(host).props.onPress as () => void)();         // the attestation ticked
    (publishButton(host).props.onPress as () => void)();    // and a publish tried on the still-empty form
    await step();
    expect(checkbox(host).props.accessibilityState).toEqual({ checked: true });
    expect(find(host, (el) => el.type === 'MediaUpload' && el.props.label === 'Proof of ownership')!.props.localUri).toBe(PROOF);
    expect(shownErrors(host)).toContain('Event name: Event name is required.');   // the fields are speaking
    expect(banner(host)!.props.formHasInput).toBe(false);   // neither counts as input, so nothing asks first
    const bh = runBanner(host);
    (findElement(bh.output, (el) => el.type === 'Button' && el.props.label === 'Continue your listing')!.props.onPress as () => void)();
    await step();
    expect(h.alertCalls).toEqual([]);                       // restored at once, no replace question
    expect(banner(host)).toBeUndefined();
    expect(byLabel(host, 'Event name')!.props.value).toBe('Weekend pool party');
    expect(checkbox(host).props.accessibilityState).toEqual({ checked: false });
    expect(h.uploads.proofs.localUri).toBeNull();
    expect(h.uploads.proofs.resets).toBe(1);
    expect(find(host, (el) => el.type === 'MediaUpload' && el.props.label === 'Proof of ownership')!.props.localUri).toBeNull();
    expect(h.uploads.covers.restored).toEqual([COVER]);     // the cover still comes back
    expect(shownErrors(host)).toEqual([]);                  // no error left over from before the restore
  });
});

describe('W7 · the wiring, as source', () => {
  const src = readFileSync(join(REPO_ROOT, 'src/screens/CreateListingScreen.tsx'), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

  it('W7a: drafts are disabled whenever a fixture is mounted', () => {
    expect(src).toMatch(/useListingDraft\(\{[^}]*enabled: !fixture,/s);
  });

  it('W7b: the draft is cleared only on the success path — after the insert error branch, before navigating', () => {
    const clear = src.indexOf('listingDraft.clear()');
    expect(clear).toBeGreaterThan(src.indexOf('const refusal = readServerRefusal(error);'));
    expect(clear).toBeGreaterThan(src.indexOf("throw new Error(error.message);"));
    expect(clear).toBeLessThan(src.indexOf('router.push(`/listing/${data.id}`)'));
    expect(src.match(/listingDraft\.clear\(\)/g)).toHaveLength(1);
  });

  it('W7c: the restore never brings back the attestation or the proof — it only clears them (review m1)', () => {
    const start = src.indexOf('function restoreDraft(');
    const body = src.slice(start, src.indexOf('\n  }', start));
    expect(body.length).toBeGreaterThan(100);
    expect(body).toContain('setSellerCommitmentAccepted(false)');
    expect(body).toContain('proofUpload.reset()');
    expect(body.match(/setSellerCommitmentAccepted\(/g)).toHaveLength(1);
    expect(body.match(/proofUpload\./g)).toHaveLength(1);
    expect(body).toContain('coverUpload.restore(d.coverUri)');
  });
});
