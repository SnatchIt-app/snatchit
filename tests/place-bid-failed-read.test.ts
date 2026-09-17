/**
 * F-BID-1 — Place bid never renders a bid form built on a floor it does not know.
 *
 * B's audit (frontend design audit, §3a), verified by C in Build 19's own tree (f412d10):
 * `src/screens/PlaceBidScreen.tsx` read the listing with `.then(({ data }) => …)` — `error` was never
 * destructured and there was no `.catch`. Two failures followed:
 *   1. a resolved-with-error read (supabase-js's normal shape for a failed query) left `listing` null with
 *      `loading` false, so the screen rendered the full bid form with `minNextBid(listing?.current_bid ?? 0)`
 *      — a minimum derived from nothing, a "Current bid" of $0, and no event name;
 *   2. a rejected read never ran the handler, so `setLoading(false)` never fired and the spinner never cleared.
 *
 * The server still validates the bid, so this was never a money defect. It is the app stating a price it does
 * not know on the screen where a user commits money, which the product truths forbid outright.
 *
 * These tests run the REAL screen through the hook dispatcher with the listing read under test control, and
 * assert on what the bidder would see. Not a device result.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { STATE_COPY } from '@/src/lib/ui/loadState';
import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';
import { BLANK, buttonByLabel, screenText, textsOf, type Blank } from './helpers/screen-view';

type Reply = { data: unknown; error: { message: string } | null };

const h = vi.hoisted(() => {
  const deferred = () => {
    let resolve!: (r: Reply) => void;
    let reject!: (e: unknown) => void;
    const promise = new Promise<Reply>((ok, bad) => { resolve = ok; reject = bad; });
    return { promise, resolve, reject };
  };
  return {
    deferred,
    reads: [] as ReturnType<typeof deferred>[],
    user: { id: 'bidder-1' },
    network: { isOffline: false },
  };
});

vi.mock('react-native', () => ({
  Alert: { alert: () => {} },
  ScrollView: 'ScrollView', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {} } }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: h.user }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => h.network }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({
  Button: 'Button', IconButton: 'IconButton', Spinner: 'Spinner', StickyBar: 'StickyBar', Tappable: 'Tappable',
}));
vi.mock('@/src/lib/feedback/haptics', () => ({ hapticConfirm: () => {} }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
// v2 tokens are pure values — the real module, so the screen's styles resolve exactly as they ship.
vi.mock('@/src/lib/supabase', () => {
  const chain = () => {
    const d = h.deferred();
    h.reads.push(d);
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'eq']) q[m] = () => q;
    q.single = () => q;
    q.then = (ok: (v: Reply) => unknown, bad?: (e: unknown) => unknown) => d.promise.then(ok, bad);
    q.catch = (bad: (e: unknown) => unknown) => d.promise.catch(bad);
    return q;
  };
  return { supabase: { from: () => chain() } };
});

const flush = async () => { for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r)); };

const LISTING = {
  id: 'l-1', event_name: 'Sandbox L6', venue: 'The Venue', current_bid: 100, starting_bid: 50,
  ends_at: '2099-01-01T00:00:00Z',
};
const OK: Reply = { data: LISTING, error: null };
const FAILED_READ: Reply = { data: null, error: { message: 'upstream timeout' } };

type View =
  | 'loading'
  | Blank                       // nothing rendered — never an expected verdict
  | { state: unknown }
  | { form: true; texts: string[] };

/**
 * What the bidder sees. Every verdict needs something to positively identify it: the form is only reported
 * when the "Place bid" action is actually on screen. The old helper returned `{ form: true }` for anything
 * that was neither a state nor a spinner, so an empty tree read as "the form rendered" — the very outcome
 * this fix exists to prevent (D's review).
 */
function view(host: HookHost): View {
  const tree = host.output;
  const screen = findElement(tree, (el) => el.type === 'ScreenState');
  if (screen) return { state: screen.props.state };
  if (findElement(tree, (el) => el.type === 'Spinner')) return 'loading';
  if (buttonByLabel(tree, 'Place bid')) return { form: true, texts: textsOf(tree) };
  return BLANK;
}

async function mountScreen(): Promise<HookHost> {
  const { default: PlaceBidScreen } = await import('@/src/screens/PlaceBidScreen');
  const host = new HookHost(() => (PlaceBidScreen as (p: { id: string }) => unknown)({ id: 'l-1' }), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

beforeEach(() => {
  h.reads.length = 0;
  h.network.isOffline = false;
  vi.resetModules();
});

describe('F-BID-1 — a failed listing read never becomes a bid form', () => {
  it('B1: a resolved-with-error read shows the error state, not the form', async () => {
    const host = await mountScreen();
    expect(view(host)).toBe('loading');

    h.reads[0].resolve(FAILED_READ);
    await flush();
    host.flush();

    expect(view(host)).toEqual({ state: 'error' });
  });

  it('B2: a failed read never renders a $0 current bid or a floor derived from nothing', async () => {
    const host = await mountScreen();
    h.reads[0].resolve(FAILED_READ);
    await flush();
    host.flush();

    // The defect rendered the whole form: "$0" current bid and a "$5" minimum out of nowhere.
    expect(view(host)).not.toHaveProperty('form');
    // Unconditional on purpose: the old version guarded this behind `'texts' in shown`, which is false for
    // every passing verdict, so the $0 pin never executed (D's review).
    expect(screenText(host.output)).not.toContain('$0');
  });

  it('B3: a rejected read ends loading and shows the error state — the spinner never sticks', async () => {
    const host = await mountScreen();
    expect(view(host)).toBe('loading');

    h.reads[0].reject(new Error('network request failed'));
    await flush();
    host.flush();

    expect(view(host)).not.toBe('loading');
    expect(view(host)).toEqual({ state: 'offline' });
  });

  it('B4: offline at the time of failure is classified offline, not a generic error', async () => {
    h.network.isOffline = true;
    const host = await mountScreen();
    h.reads[0].resolve(FAILED_READ);
    await flush();
    host.flush();

    expect(view(host)).toEqual({ state: 'offline' });
  });

  it('B5: a successful read still renders the form on the real floor (regression guard)', async () => {
    const host = await mountScreen();
    h.reads[0].resolve(OK);
    await flush();
    host.flush();

    expect(view(host)).toHaveProperty('form', true);
    const joined = screenText(host.output);
    expect(joined).toContain('Sandbox L6');
    expect(joined).toContain('$100');   // the current bid the server reported
    expect(joined).toContain('$105');   // floor = current + MIN_BID_INCREMENT
    expect(joined).not.toContain('$0');
  });

  it('B6: Retry from the error state re-reads, and a good read renders the form', async () => {
    const host = await mountScreen();
    h.reads[0].resolve(FAILED_READ);
    await flush();
    host.flush();
    expect(view(host)).toEqual({ state: 'error' });

    const state = findElement(host.output, (el) => el.type === 'ScreenState') as Element;
    void (state.props.onRetry as () => void | Promise<void>)();
    await flush();
    host.flush();

    expect(h.reads.length).toBe(2);
    h.reads[1].resolve(OK);
    await flush();
    host.flush();

    expect(view(host)).toEqual({ form: true, texts: expect.any(Array) });
    expect(screenText(host.output)).toContain('Sandbox L6');
  });

  it('B8: a read that returns no row and no error is still not a bid form', async () => {
    // supabase-js can resolve `{ data: null, error: null }` — a listing that is gone. The old code took that
    // branch as "nothing to set" and rendered the form anyway, on the same invented floor.
    const host = await mountScreen();
    h.reads[0].resolve({ data: null, error: null });
    await flush();
    host.flush();

    const shown = view(host);
    expect(shown).not.toHaveProperty('form');
    expect(shown).toEqual({ state: 'error' });
  });

  it('B7: the failure state uses the shared copy, not a screen-local message', async () => {
    const host = await mountScreen();
    h.reads[0].resolve(FAILED_READ);
    await flush();
    host.flush();

    // ScreenState owns STATE_COPY; the screen must not hand-roll its own wording.
    const shown = view(host);
    expect(shown).toEqual({ state: 'error' });
    expect(STATE_COPY.error.title).toBeTruthy();
  });
});
