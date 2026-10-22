/**
 * tests/listing-draft-hook.test.ts — CFT-608: the REAL useListingDraft hook and the REAL
 * ContinueListingBanner, run under the suite's hook harness against an in-memory AsyncStorage
 * and a stand-in auth client that behaves like supabase-js (INITIAL_SESSION to each new subscriber).
 *
 *  - A stored draft becomes an offer; autosave waits while the offer is undecided, so nothing the
 *    seller has not yet seen is overwritten.
 *  - Continue hands the fields back; Discard removes the draft; clear() (after a publish the server
 *    confirmed) removes it.
 *  - Autosave is debounced, flushes when the app leaves the foreground, and is cancelled on unmount
 *    (sign-out unmounts the tabs).
 *  - Disabled (the harness fixture) the hook is inert: no read, no write, no subscription.
 *  - The cover comes back only if the picker's cache file still answers.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { serializeListingDraft, type ListingDraftFields, type ListingDraftOffer } from '@/src/lib/sell/listingDraft';
import { listingDraftKey } from '@/src/lib/sell/listingDraftStore';
import { findElement, HookHost } from './helpers/nav-stack-harness';
import { buttonByLabel, screenText } from './helpers/screen-view';

const h = vi.hoisted(() => ({
  mem: new Map<string, string>(),
  ops: [] as string[],
  subscriptions: 0,
  authSession: null as null | { user: { id: string } },
  authListener: null as null | ((e: string, s: unknown) => unknown),
  appState: null as null | ((s: string) => void),
  appStateRemoved: 0,
  getSize: 'ok' as 'ok' | 'fail' | 'hang',
  sized: [] as string[],
  alerts: [] as { title: string; body?: string; buttons?: { text: string; style?: string; onPress?: () => void }[] }[],
  announced: [] as string[],
  platform: 'ios',
  confirms: [] as string[],
  confirmAnswer: true,
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
vi.mock('@/src/lib/supabase', () => ({
  supabase: {
    auth: {
      onAuthStateChange: (cb: (e: string, s: unknown) => unknown) => {
        h.subscriptions += 1;
        h.authListener = cb;
        queueMicrotask(() => { cb('INITIAL_SESSION', h.authSession); });
        return { data: { subscription: { unsubscribe() {} } } };
      },
    },
  },
}));
vi.mock('react-native', () => ({
  AppState: {
    addEventListener: (_t: string, fn: (s: string) => void) => { h.appState = fn; return { remove: () => { h.appStateRemoved += 1; } }; },
  },
  Image: {
    getSize: (uri: string, ok: (w: number, hh: number) => void, fail: (e: Error) => void) => {
      h.sized.push(uri);
      if (h.getSize === 'ok') ok(800, 1000);
      else if (h.getSize === 'fail') fail(new Error('ENOENT'));
    },
  },
  Alert: {
    alert: (title: string, body?: string, buttons?: { text: string; style?: string; onPress?: () => void }[], options?: { cancelable?: boolean }) => {
      h.alerts.push(options ? { title, body, buttons, options } as never : { title, body, buttons });
    },
  },
  AccessibilityInfo: { announceForAccessibility: (m: string) => { h.announced.push(m); } },
  Platform: { get OS() { return h.platform; }, select: (o: Record<string, unknown>) => o.ios },
  StyleSheet: { create: <T,>(s: T) => s },
  View: 'View',
  Text: 'Text',
}));
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}) }));
vi.mock('@/src/components/ui', () => ({ Button: 'Button' }));

const NOW = new Date(2026, 9, 21, 12, 0, 0);
const COVER = 'file:///var/mobile/Containers/Data/Application/0A1B/Library/Caches/ImagePicker/5E6F.jpeg';
const KEY = listingDraftKey('u-1');

function empty(): ListingDraftFields {
  return {
    eventName: '', venue: '', neighborhood: null, category: 'nightlife', eventDate: new Date(2026, 9, 21), eventTime: new Date(2026, 9, 21, 13),
    dateChosen: false, ticketType: null, quantity: 1, transferMethod: null, restrictions: '', startingBid: '', buyNowEnabled: false, buyNowPrice: '',
    durationHours: null, ticketPlatform: 'other', coverUri: null,
  };
}
const draft = (over: Partial<ListingDraftFields> = {}): ListingDraftFields => ({
  ...empty(), eventName: 'Weekend pool party', venue: 'LIV Miami', neighborhood: 'wynwood', eventDate: new Date(2026, 9, 25), dateChosen: true,
  ticketType: 'VIP', quantity: 2, startingBid: '40', durationHours: 24, coverUri: COVER, ...over,
});

interface Opts { userId: string | null; enabled: boolean; fields: ListingDraftFields; onRestore: (f: ListingDraftFields) => void }
type Ret = { offer: ListingDraftOffer | null; formHasInput: boolean; accept(): void; discard(): void; clear(): void };

const settle = async () => { for (let i = 0; i < 12; i++) await new Promise((r) => setImmediate(r)); };

async function mountHook(over: Partial<Opts> = {}) {
  const { useListingDraft, AUTOSAVE_DELAY_MS, COVER_PROBE_TIMEOUT_MS } = await import('@/src/hooks/useListingDraft');
  const restored: ListingDraftFields[] = [];
  const state: { opts: Opts; ret: Ret | null } = {
    opts: { userId: 'u-1', enabled: true, fields: empty(), onRestore: (f) => { restored.push(f); state.opts = { ...state.opts, fields: f }; }, ...over },
    ret: null,
  };
  const host = new HookHost(() => { state.ret = useListingDraft(state.opts) as Ret; return null; }, new Map());
  host.mount();
  await settle();
  host.flush();
  const step = async (ms = 0) => { if (ms) await vi.advanceTimersByTimeAsync(ms); await settle(); host.flush(); };
  const setFields = async (f: ListingDraftFields) => { state.opts = { ...state.opts, fields: f }; host.flush(); await settle(); };
  return { host, state, restored, step, setFields, AUTOSAVE_DELAY_MS, COVER_PROBE_TIMEOUT_MS };
}

const writes = () => h.ops.filter((o) => o.startsWith('set '));

beforeEach(() => {
  vi.resetModules();
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
  vi.setSystemTime(NOW);
  h.mem.clear(); h.ops.length = 0; h.subscriptions = 0; h.authListener = null; h.appState = null; h.appStateRemoved = 0;
  h.authSession = { user: { id: 'u-1' } }; h.getSize = 'ok'; h.sized.length = 0; h.alerts.length = 0; h.announced.length = 0;
  h.platform = 'ios'; h.confirms.length = 0; h.confirmAnswer = true;
});
afterEach(() => { vi.useRealTimers(); });

describe('UH1 · a stored draft is offered, and nothing overwrites it until the seller decides', () => {
  it('UH1a: the offer carries the event name and whether the cover is still on the device', async () => {
    h.mem.set(KEY, serializeListingDraft(draft(), NOW));
    const { state } = await mountHook();
    expect(state.ret!.offer).not.toBeNull();
    expect(state.ret!.offer!.eventName).toBe('Weekend pool party');
    expect(state.ret!.offer!.coverKept).toBe(true);
    expect(h.sized).toEqual([COVER]);
  });

  it('UH1b: typing while the offer is up does not autosave over the stored draft', async () => {
    const stored = serializeListingDraft(draft(), NOW);
    h.mem.set(KEY, stored);
    const { setFields, step, AUTOSAVE_DELAY_MS } = await mountHook();
    await setFields({ ...empty(), eventName: 'Something else' });
    await step(AUTOSAVE_DELAY_MS * 5);
    expect(writes()).toEqual([]);
    expect(h.mem.get(KEY)).toBe(stored);
  });

  it('UH1b2 (LD-R3): formHasInput says when the form holds the seller’s input while the offer is up — so the banner can ask', async () => {
    h.mem.set(KEY, serializeListingDraft(draft(), NOW));
    const { state, setFields, step } = await mountHook();
    expect(state.ret!.offer).not.toBeNull();
    expect(state.ret!.formHasInput).toBe(false);                       // untouched form
    await setFields({ ...empty(), category: 'concerts', eventDate: new Date(2026, 9, 30), dateChosen: true });
    expect(state.ret!.formHasInput).toBe(false);                       // a category or a date alone is not work to lose
    await setFields({ ...empty(), eventName: 'A different show' });
    expect(state.ret!.formHasInput).toBe(true);
    state.ret!.discard();
    await step();
    expect(state.ret!.offer).toBeNull();
    expect(state.ret!.formHasInput).toBe(false);                       // no offer, nothing to ask
  });

  it('UH1c: Continue hands back the stored fields, closes the offer, and autosave resumes', async () => {
    h.mem.set(KEY, serializeListingDraft(draft(), NOW));
    const { state, restored, step, setFields, AUTOSAVE_DELAY_MS } = await mountHook();
    state.ret!.accept();
    await step();
    expect(restored).toHaveLength(1);
    expect(restored[0].eventName).toBe('Weekend pool party');
    expect(restored[0].eventDate).toBeInstanceOf(Date);
    expect(restored[0].eventDate.getTime()).toBe(new Date(2026, 9, 25).getTime());
    expect(restored[0].coverUri).toBe(COVER);
    expect(state.ret!.offer).toBeNull();
    await setFields({ ...restored[0], venue: 'E11EVEN' });
    await step(AUTOSAVE_DELAY_MS);
    expect(JSON.parse(h.mem.get(KEY)!).fields.venue).toBe('E11EVEN');
  });

  it('UH1d: Discard removes the stored draft and closes the offer', async () => {
    h.mem.set(KEY, serializeListingDraft(draft(), NOW));
    const { state, restored, step } = await mountHook();
    state.ret!.discard();
    await step();
    expect(h.mem.has(KEY)).toBe(false);
    expect(state.ret!.offer).toBeNull();
    expect(restored).toEqual([]);
  });

  it('UH1e: a draft for an event that has passed is not offered and is removed', async () => {
    h.mem.set(KEY, serializeListingDraft(draft({ eventDate: new Date(2026, 9, 20) }), NOW));
    const { state } = await mountHook();
    expect(state.ret!.offer).toBeNull();
    expect(h.mem.has(KEY)).toBe(false);
  });

  it('UH1f (LD-R2): a draft whose date row was left at its default is offered the next day, and comes back dated today', async () => {
    h.mem.set(KEY, serializeListingDraft(draft({ eventDate: new Date(2026, 9, 20), dateChosen: false }), new Date(2026, 9, 20, 23)));
    const { state, restored, step } = await mountHook();
    expect(state.ret!.offer?.eventName).toBe('Weekend pool party');
    expect(h.mem.has(KEY)).toBe(true);
    state.ret!.accept();
    await step();
    expect(restored[0].eventDate.getTime()).toBe(new Date(2026, 9, 21).getTime());
    expect(restored[0].dateChosen).toBe(false);
  });
});

describe('UH1g · Continue re-checks the picked date (E, D-2.4 L1)', () => {
  it('UH1g: an offer held open past midnight whose picked event day has passed is removed, not restored', async () => {
    vi.setSystemTime(new Date(2026, 9, 21, 23, 59));
    h.mem.set(KEY, serializeListingDraft(draft({ eventDate: new Date(2026, 9, 21), dateChosen: true }), new Date(2026, 9, 21, 22)));
    const { state, restored, step } = await mountHook();
    expect(state.ret!.offer?.eventName).toBe('Weekend pool party');   // today's event: offered
    vi.setSystemTime(new Date(2026, 9, 22, 0, 1));                   // the offer sits across midnight
    state.ret!.accept();
    await step();
    expect(restored).toEqual([]);                 // a past event date never reaches the form
    expect(state.ret!.offer).toBeNull();
    expect(h.mem.has(KEY)).toBe(false);
  });

  it('UH1g2: the same offer accepted before midnight restores as usual (the check is not a blanket refusal)', async () => {
    vi.setSystemTime(new Date(2026, 9, 21, 23, 0));
    h.mem.set(KEY, serializeListingDraft(draft({ eventDate: new Date(2026, 9, 21), dateChosen: true }), new Date(2026, 9, 21, 22)));
    const { state, restored, step } = await mountHook();
    state.ret!.accept();
    await step();
    expect(restored).toHaveLength(1);
    expect(restored[0].eventDate.getTime()).toBe(new Date(2026, 9, 21).getTime());
  });
});

describe('UH2 · the cover comes back only if the cached file still answers', () => {
  it('UH2a: a missing file drops the cover from what is restored', async () => {
    h.getSize = 'fail';
    h.mem.set(KEY, serializeListingDraft(draft(), NOW));
    const { state, restored, step } = await mountHook();
    expect(state.ret!.offer!.coverKept).toBe(false);
    state.ret!.accept();
    await step();
    expect(restored[0].coverUri).toBeNull();
    expect(restored[0].eventName).toBe('Weekend pool party');
  });

  it('UH2b: a probe that never answers counts as missing after the timeout', async () => {
    h.getSize = 'hang';
    h.mem.set(KEY, serializeListingDraft(draft(), NOW));
    const { state, step, COVER_PROBE_TIMEOUT_MS } = await mountHook();
    expect(state.ret!.offer).toBeNull();
    await step(COVER_PROBE_TIMEOUT_MS);
    expect(state.ret!.offer).not.toBeNull();
    expect(state.ret!.offer!.coverKept).toBe(false);
  });
});

describe('UH3 · autosave', () => {
  it('UH3a: debounced — several quick changes make one write, of the last value', async () => {
    const { setFields, step, AUTOSAVE_DELAY_MS } = await mountHook();
    await setFields({ ...empty(), eventName: 'W' });
    await setFields({ ...empty(), eventName: 'We' });
    await setFields({ ...empty(), eventName: 'Wee' });
    await step(AUTOSAVE_DELAY_MS - 1);
    expect(writes()).toEqual([]);
    await step(1);
    expect(writes()).toEqual([`set ${KEY}`]);
    expect(JSON.parse(h.mem.get(KEY)!).fields.eventName).toBe('Wee');
  });

  it('UH3b: leaving the foreground writes at once', async () => {
    const { setFields, step } = await mountHook();
    await setFields({ ...empty(), venue: 'LIV' });
    expect(writes()).toEqual([]);
    h.appState!('background');
    await step();
    expect(writes()).toEqual([`set ${KEY}`]);
  });

  it('UH3c: an unchanged form re-rendering does not keep pushing the write back', async () => {
    const { host, setFields, step, AUTOSAVE_DELAY_MS } = await mountHook();
    await setFields({ ...empty(), venue: 'LIV' });
    await step(AUTOSAVE_DELAY_MS / 2);
    host.flush();
    await setFields({ ...empty(), venue: 'LIV' });      // a new object with the same content
    await step(AUTOSAVE_DELAY_MS / 2);
    expect(writes()).toEqual([`set ${KEY}`]);
  });

  it('UH3d: unmounting (sign-out unmounts the tabs) cancels a pending write', async () => {
    const { host, setFields, step, AUTOSAVE_DELAY_MS } = await mountHook();
    await setFields({ ...empty(), venue: 'LIV' });
    host.unmount();
    await step(AUTOSAVE_DELAY_MS * 3);
    expect(writes()).toEqual([]);
    expect(h.appStateRemoved).toBe(1);
  });

  it('UH3e: clear() — after a publish the server confirmed — removes the draft and drops the pending write', async () => {
    h.mem.set(KEY, serializeListingDraft(draft(), NOW));
    const { state, setFields, step, AUTOSAVE_DELAY_MS } = await mountHook();
    state.ret!.accept();
    await step();
    await setFields({ ...draft(), venue: 'pending' });
    state.ret!.clear();
    await step(AUTOSAVE_DELAY_MS * 2);
    expect(h.mem.has(KEY)).toBe(false);
  });

  it('UH3f: after a sign-out the store refuses the old account’s write even if one fires', async () => {
    const { setFields, step, AUTOSAVE_DELAY_MS } = await mountHook();
    await setFields({ ...empty(), venue: 'LIV' });
    h.authListener!('SIGNED_OUT', null);
    await step(AUTOSAVE_DELAY_MS);
    expect(writes()).toEqual([]);
    expect(h.mem.size).toBe(0);
  });
});

describe('UH4 · disabled (harness fixture) or signed out, the hook is inert', () => {
  it('UH4a (negative control for fixture mode): no read, no write, no auth subscription, no offer', async () => {
    h.mem.set(KEY, serializeListingDraft(draft(), NOW));
    const { state, setFields, step, AUTOSAVE_DELAY_MS } = await mountHook({ enabled: false });
    await setFields({ ...empty(), eventName: 'fixture' });
    await step(AUTOSAVE_DELAY_MS * 3);
    h.appState?.('background');
    await step();
    expect(h.ops).toEqual([]);
    expect(h.subscriptions).toBe(0);
    expect(state.ret!.offer).toBeNull();
  });

  it('UH4b: no signed-in account, no storage', async () => {
    h.authSession = null;
    const { setFields, step, AUTOSAVE_DELAY_MS } = await mountHook({ userId: null });
    await setFields({ ...empty(), eventName: 'x' });
    await step(AUTOSAVE_DELAY_MS * 2);
    expect(writes()).toEqual([]);
    expect(h.ops.filter((o) => o.startsWith('get '))).toEqual([]);
  });
});

describe('UH5 · the offer belongs to the account it was read for, and to no listing but its own', () => {
  it('UH5a: a change of account while mounted — no render under the new account shows the old account’s offer, and Continue there restores nothing', async () => {
    h.mem.set(KEY, serializeListingDraft(draft(), NOW));
    const { useListingDraft } = await import('@/src/hooks/useListingDraft');
    const restored: ListingDraftFields[] = [];
    const opts: Opts = { userId: 'u-1', enabled: true, fields: empty(), onRestore: (f) => { restored.push(f); } };
    const seen: { uid: string | null; offer: ListingDraftOffer | null; accept: () => void }[] = [];
    const host = new HookHost(() => {
      const r = useListingDraft(opts) as Ret;
      seen.push({ uid: opts.userId, offer: r.offer, accept: r.accept });
      return null;
    }, new Map());
    host.mount();
    await settle();
    host.flush();
    expect(seen.at(-1)!.offer?.eventName).toBe('Weekend pool party');   // u-1's own draft is offered to u-1

    h.authListener!('SIGNED_IN', { user: { id: 'u-2' } });
    opts.userId = 'u-2';
    seen.length = 0;
    host.flush();
    await settle();
    host.flush();
    const underU2 = seen.filter((s) => s.uid === 'u-2');
    expect(underU2.length).toBeGreaterThan(0);
    expect(underU2.map((s) => s.offer)).toEqual(underU2.map(() => null));
    underU2[0].accept();                                               // even the very first render's Continue
    expect(restored).toEqual([]);
  });

  it('UH5b: a publish while an older draft is still on offer leaves that draft, and its offer, alone', async () => {
    // The seller ignored the banner, filled in a different listing and published it. The stored draft
    // is not that listing, and nobody chose Discard: clear() removes only the draft this form wrote.
    const stored = serializeListingDraft(draft(), NOW);
    h.mem.set(KEY, stored);
    const { state, setFields, step, AUTOSAVE_DELAY_MS } = await mountHook();
    expect(state.ret!.offer).not.toBeNull();
    await setFields({ ...empty(), eventName: 'A different listing' });
    state.ret!.clear();
    await step(AUTOSAVE_DELAY_MS * 2);
    expect(h.mem.get(KEY)).toBe(stored);
    expect(state.ret!.offer?.eventName).toBe('Weekend pool party');
  });
});

describe('UH6 · a read the store refuses is not "no draft" (LD-R6)', () => {
  // The screen's useAuth user and the store's last auth event can disagree (INITIAL_SESSION is
  // evaluated per subscriber). Then the store refuses the read; the hook must wait — no autosave, no
  // clear() — and read again when the store hears the account, not unlock autosave for good.
  it('UH6a: refused while the store has no account — nothing is written or removed, and the draft is offered once the account is current', async () => {
    const stored = serializeListingDraft(draft(), NOW);
    h.mem.set(KEY, stored);
    h.authSession = null;                                    // the store hears INITIAL_SESSION with no session…
    const { state, step, setFields, AUTOSAVE_DELAY_MS } = await mountHook({ userId: 'u-1' });   // …the screen has u-1
    expect(state.ret!.offer).toBeNull();
    await setFields({ ...empty(), eventName: 'x' });
    await step(AUTOSAVE_DELAY_MS * 3);
    h.appState!('background');
    await step();
    expect(h.mem.get(KEY)).toBe(stored);                     // no keystroke overwrote the draft nobody was shown
    state.ret!.clear();                                      // nor does a publish confirmed meanwhile remove it
    await step();
    expect(h.mem.get(KEY)).toBe(stored);
    h.authListener!('TOKEN_REFRESHED', { user: { id: 'u-1' } });   // the same account is current again
    await step();
    expect(state.ret!.offer?.eventName).toBe('Weekend pool party');
    expect(h.mem.get(KEY)).toBe(stored);
  });

  it('UH6b: refused, then the account comes back with nothing stored — autosave starts with what was typed', async () => {
    h.authSession = null;
    const { state, step, setFields, AUTOSAVE_DELAY_MS } = await mountHook({ userId: 'u-1' });
    await setFields({ ...empty(), venue: 'LIV' });
    await step(AUTOSAVE_DELAY_MS * 2);
    expect(writes()).toEqual([]);
    h.authListener!('TOKEN_REFRESHED', { user: { id: 'u-1' } });
    await step();
    await step(AUTOSAVE_DELAY_MS);
    expect(state.ret!.offer).toBeNull();
    expect(JSON.parse(h.mem.get(KEY)!).fields.venue).toBe('LIV');
  });

  it('UH6d: the account comes back while the refused read is still settling — it reads again at once, not on some later event', async () => {
    h.mem.set(KEY, serializeListingDraft(draft(), NOW));
    const { listingDraftStore } = await import('@/src/lib/sell/listingDraftStore');
    listingDraftStore.handleAuthChange('INITIAL_SESSION', null);   // the store has no account when the hook reads…
    h.authSession = { user: { id: 'u-1' } };                        // …and the arm's INITIAL_SESSION brings u-1 back mid-read
    const { state } = await mountHook({ userId: 'u-1' });
    expect(state.ret!.offer?.eventName).toBe('Weekend pool party');
  });

  it('UH6c: unmounted while waiting, it reads nothing more when the account comes back', async () => {
    h.mem.set(KEY, serializeListingDraft(draft(), NOW));
    h.authSession = null;
    const { host, step } = await mountHook({ userId: 'u-1' });
    host.unmount();
    h.ops.length = 0;
    h.authListener!('TOKEN_REFRESHED', { user: { id: 'u-1' } });
    await step();
    expect(h.ops.filter((o) => o.startsWith('get '))).toEqual([]);
  });
});

describe('UB · the banner', () => {
  async function renderBanner(offer: Partial<ListingDraftOffer> = {}, start: { formHasInput?: boolean } = {}) {
    const { ContinueListingBanner } = await import('@/src/components/sell/ContinueListingBanner');
    const calls = { continue: 0, discard: 0 };
    const full: ListingDraftOffer = { fields: draft(), eventName: 'Weekend pool party', coverKept: true, ...offer };
    const props = { formHasInput: start.formHasInput };
    const host = new HookHost(() => ContinueListingBanner({
      offer: full, formHasInput: props.formHasInput,
      onContinue: () => { calls.continue += 1; }, onDiscard: () => { calls.discard += 1; },
    }), new Map());
    host.mount();
    const setFormHasInput = (v: boolean) => { props.formHasInput = v; host.flush(); };
    return { host, calls, setFormHasInput };
  }

  it('UB1: says what is kept, where, and what still has to be added — with a header and two named actions', async () => {
    const { host } = await renderBanner();
    const text = screenText(host.output);
    expect(text).toContain('Unfinished listing');
    expect(text).toContain('"Weekend pool party" is saved on this device.');
    expect(text).toContain('Add proof of ownership before listing.');
    const header = findElement(host.output, (el) => el.props.accessibilityRole === 'header');
    expect(header?.props.children).toBe('Unfinished listing');
    expect(buttonByLabel(host.output, 'Continue your listing')).toBeDefined();
    expect(buttonByLabel(host.output, 'Discard')).toBeDefined();
  });

  it('UB2: a dropped cover is named among the things to add', async () => {
    const { host } = await renderBanner({ coverKept: false });
    expect(screenText(host.output)).toContain('Add the cover image and proof of ownership before listing.');
  });

  it('UB3: Continue continues', async () => {
    const { host, calls } = await renderBanner();
    (buttonByLabel(host.output, 'Continue your listing')!.props.onPress as () => void)();
    expect(calls).toEqual({ continue: 1, discard: 0 });
  });

  it('UB4: Discard asks first; Keep keeps, Discard discards', async () => {
    const { host, calls } = await renderBanner();
    (buttonByLabel(host.output, 'Discard')!.props.onPress as () => void)();
    expect(calls.discard).toBe(0);
    expect(h.alerts).toHaveLength(1);
    const a = h.alerts[0];
    expect(a.title).toBe('Discard this listing?');
    expect(a.body).toBe('The details saved on this device will be deleted.');
    const keep = a.buttons!.find((b) => b.text === 'Keep')!;
    expect(keep.style).toBe('cancel');
    keep.onPress?.();
    expect(calls.discard).toBe(0);
    const del = a.buttons!.find((b) => b.text === 'Discard')!;
    expect(del.style).toBe('destructive');
    del.onPress!();
    expect(calls.discard).toBe(1);
  });

  it('UB5: on web the same question is asked with window.confirm', async () => {
    h.platform = 'web';
    const g = globalThis as { window?: { confirm(m: string): boolean } };
    const prev = g.window;
    g.window = { confirm: (m: string) => { h.confirms.push(m); return h.confirmAnswer; } };
    try {
      const { host, calls } = await renderBanner();
      h.confirmAnswer = false;
      (buttonByLabel(host.output, 'Discard')!.props.onPress as () => void)();
      expect(calls.discard).toBe(0);
      h.confirmAnswer = true;
      (buttonByLabel(host.output, 'Discard')!.props.onPress as () => void)();
      expect(calls.discard).toBe(1);
      expect(h.confirms[0]).toBe('Discard this listing?\n\nThe details saved on this device will be deleted.');
      expect(h.alerts).toEqual([]);
    } finally {
      g.window = prev;
    }
  });

  it('UB7 (LD-R3): the first input while the offer is undecided asks at once which listing to keep — and only once', async () => {
    const { host, calls, setFormHasInput } = await renderBanner();
    expect(h.alerts).toEqual([]);
    setFormHasInput(true);
    expect(h.alerts).toHaveLength(1);
    const a = h.alerts[0] as { title: string; body?: string; buttons?: { text: string; style?: string; onPress?: () => void }[]; options?: { cancelable?: boolean } };
    expect(a.title).toBe('Start a new listing?');
    expect(a.body).toBe('The details saved on this device will be deleted.');
    expect(a.buttons!.map((b) => [b.text, b.style])).toEqual([['Continue saved listing', undefined], ['Start new listing', 'destructive']]);
    expect(a.options).toEqual({ cancelable: false });                 // a choice, not a dismissal: autosave must not stay paused
    host.flush();
    setFormHasInput(true);
    expect(h.alerts).toHaveLength(1);                                   // asked once
    a.buttons![1].onPress!();
    expect(calls).toEqual({ continue: 0, discard: 1 });
    a.buttons![0].onPress!();
    expect(calls).toEqual({ continue: 1, discard: 1 });
  });

  it('UB7b (LD-R3): input already in the form when the offer arrives is asked about as the banner appears', async () => {
    await renderBanner({}, { formHasInput: true });
    expect(h.alerts.map((a) => a.title)).toEqual(['Start a new listing?']);
  });

  it('UB8 (LD-R3): Continue over the seller’s input asks before replacing it; Cancel keeps it', async () => {
    const { host, calls } = await renderBanner({}, { formHasInput: true });
    h.alerts.length = 0;                                                // the start-new question, already covered by UB7b
    (buttonByLabel(host.output, 'Continue your listing')!.props.onPress as () => void)();
    expect(calls.continue).toBe(0);
    expect(h.alerts).toHaveLength(1);
    const a = h.alerts[0];
    expect(a.title).toBe("Replace what you've typed?");
    expect(a.body).toBe('The saved listing will replace the details in the form now.');
    const cancel = a.buttons!.find((b) => b.text === 'Cancel')!;
    expect(cancel.style).toBe('cancel');
    cancel.onPress?.();
    expect(calls.continue).toBe(0);
    const replace = a.buttons!.find((b) => b.text === 'Replace')!;
    expect(replace.style).toBe('destructive');
    replace.onPress!();
    expect(calls.continue).toBe(1);
  });

  it('UB9 (LD-R3): on web both questions go through window.confirm', async () => {
    h.platform = 'web';
    const g = globalThis as { window?: { confirm(m: string): boolean } };
    const prev = g.window;
    g.window = { confirm: (m: string) => { h.confirms.push(m); return h.confirmAnswer; } };
    try {
      h.confirmAnswer = true;                                           // OK: start a new listing
      const first = await renderBanner({}, { formHasInput: true });
      expect(first.calls).toEqual({ continue: 0, discard: 1 });
      expect(h.confirms[0]).toBe('Start a new listing?\n\nThe details saved on this device will be deleted.\n\nCancel to continue the saved listing instead.');
      h.confirmAnswer = false;                                          // Cancel: continue the saved one
      const second = await renderBanner({}, { formHasInput: true });
      expect(second.calls).toEqual({ continue: 1, discard: 0 });
      h.confirmAnswer = false;
      (buttonByLabel(second.host.output, 'Continue your listing')!.props.onPress as () => void)();
      expect(second.calls.continue).toBe(1);                            // the replace question, refused
      expect(h.confirms.at(-1)).toBe("Replace what you've typed?\n\nThe saved listing will replace the details in the form now.");
      expect(h.alerts).toEqual([]);
    } finally {
      g.window = prev;
    }
  });

  it('UB6: on iOS it is announced once when it appears (it arrives after the screen has rendered)', async () => {
    h.platform = 'ios';
    const { host } = await renderBanner();
    host.flush();
    host.flush();
    expect(h.announced).toEqual(['Unfinished listing. "Weekend pool party" is saved on this device.']);
  });

  it('UB6b (review m2): on Android it is not announced — its polite live region speaks it, and announcing too would say it twice', async () => {
    h.platform = 'android';
    const { host } = await renderBanner();
    host.flush();
    host.flush();
    expect(h.announced).toEqual([]);
    expect((host.output as { props: Record<string, unknown> }).props.accessibilityLiveRegion).toBe('polite');
  });
});
