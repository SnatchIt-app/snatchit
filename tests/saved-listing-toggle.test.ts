/**
 * tests/saved-listing-toggle.test.ts — the native Save listing toggle (saved-listings; CFT-204, checklist
 * item 11: "Saving ... can update immediately and sync in the background. If saving fails, restore the
 * previous state and explain briefly").
 *
 * Backed by the EXISTING public.saved_listings table (migration 040: RLS owner select / insert / delete,
 * no UPDATE policy, UNIQUE (user_id, listing_id)). Nothing here adds a table, a policy or an RPC. The
 * behaviour mirrors live web (web/src/lib/favorites-actions.ts): save = insert {user_id, listing_id}, and
 * a unique violation (23505) means the row is already there, which IS the outcome asked for; remove =
 * delete by user_id AND listing_id. Web reverts silently on failure; native says so briefly (item 11),
 * in web's own words.
 *
 * Runs the REAL modules (data layer over a mocked PostgREST chain, the store, the hook under the
 * nav-stack-harness dispatcher, the control and the glyph). Not a device result.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { findElement, HookHost, REPO_ROOT } from './helpers/nav-stack-harness';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });

type Reply = { data?: unknown; error?: { code?: string; message: string } | null };
type Call = {
  table: string;
  op: 'select' | 'insert' | 'delete';
  columns?: unknown;
  payload?: unknown;
  filters: unknown[][];
  orders: unknown[][];
  single: boolean;
};

const h = vi.hoisted(() => ({
  calls: [] as Call[],
  reply: (_c: Call): Promise<Reply> | Reply => ({ data: null, error: null }),
  announced: [] as string[],
  authCb: null as null | ((event: string, session: unknown) => void),
}));

vi.mock('@/src/lib/supabase', () => ({
  supabase: {
    from: (table: string) => {
      const call: Call = { table, op: 'select', filters: [], orders: [], single: false };
      h.calls.push(call);
      const q: Record<string, unknown> = {};
      q.select = (cols: unknown) => { if (call.op === 'select') call.columns = cols; return q; };
      q.insert = (payload: unknown) => { call.op = 'insert'; call.payload = payload; return q; };
      q.delete = () => { call.op = 'delete'; return q; };
      q.eq = (col: unknown, val: unknown) => { call.filters.push(['eq', col, val]); return q; };
      q.order = (col: unknown, opts: unknown) => { call.orders.push([col, opts]); return q; };
      q.maybeSingle = () => { call.single = true; return q; };
      q.then = (ok: (v: unknown) => unknown, bad: (e: unknown) => unknown) =>
        Promise.resolve().then(() => h.reply(call)).then(ok, bad);
      return q;
    },
    auth: {
      onAuthStateChange: (cb: (event: string, session: unknown) => void) => {
        h.authCb = cb;
        return { data: { subscription: { unsubscribe: () => {} } } };
      },
    },
  },
}));
vi.mock('react-native', () => ({
  AccessibilityInfo: { announceForAccessibility: (m: string) => { h.announced.push(m); } },
  Animated: {
    View: 'Animated.View',
    Value: class { v: number; constructor(v: number) { this.v = v; } setValue(v: number) { this.v = v; } },
    timing: () => ({ start: (cb?: () => void) => cb?.() }),
  },
  Easing: { bezier: () => () => 0 },
  Pressable: 'Pressable', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('@/src/theme/appearance', async () => {
  const { light } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'light', palette: light }) };
});
vi.mock('@/components/ui/icon-symbol', () => ({ IconSymbol: 'IconSymbol' }));
// The same narrow barrel the ListingHero suites use (rc10, v3-listing-stage): SaveControl must live with it.
vi.mock('@/src/components/ui', () => ({ IconButton: 'IconButton' }));
vi.mock('@/src/hooks/useReducedMotion', () => ({ useReducedMotion: () => true }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MIN_TOUCH_TARGET: 44, EASING_BEZIER: [0.2, 0, 0, 1] }));

const read = (rel: string) => readFileSync(join(REPO_ROOT, rel), 'utf8');
const code = (rel: string) => read(rel).replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const tick = () => new Promise<void>((r) => setTimeout(r, 0));

function deferred<T>() {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((r) => { resolve = r; });
  return { promise, resolve };
}

const LISTING = '11111111-1111-4111-8111-111111111111';
const USER_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const USER_B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

beforeEach(() => {
  vi.resetModules();
  h.calls = [];
  h.reply = () => ({ data: null, error: null });
  h.announced = [];
  h.authCb = null;
});

// ── Data: the existing table, through PostgREST ─────────────────────────────

describe('data — public.saved_listings exactly as migration 040 shaped it', () => {
  it('D1: Save inserts {user_id, listing_id} into saved_listings and nothing else; success is true', async () => {
    const { writeListingSaved } = await import('@/src/lib/saved/savedListings');
    expect(await writeListingSaved(USER_A, LISTING, true)).toBe(true);
    expect(h.calls).toHaveLength(1);
    expect(h.calls[0].table).toBe('saved_listings');
    expect(h.calls[0].op).toBe('insert');
    expect(h.calls[0].payload).toEqual({ user_id: USER_A, listing_id: LISTING });
  });

  it('D2: a unique violation (23505) means it is already saved — success; any other error is a failure', async () => {
    const { writeListingSaved } = await import('@/src/lib/saved/savedListings');
    h.reply = () => ({ data: null, error: { code: '23505', message: 'duplicate key value violates unique constraint' } });
    expect(await writeListingSaved(USER_A, LISTING, true)).toBe(true);
    h.reply = () => ({ data: null, error: { code: '42501', message: 'new row violates row-level security policy' } });
    expect(await writeListingSaved(USER_A, LISTING, true)).toBe(false);
    h.reply = () => ({ data: null, error: { code: '23503', message: 'violates foreign key constraint' } });
    expect(await writeListingSaved(USER_A, LISTING, true)).toBe(false);
    h.reply = () => { throw new Error('Network request failed'); };
    expect(await writeListingSaved(USER_A, LISTING, true)).toBe(false);
  });

  it('D3: Remove deletes by user_id AND listing_id; an error or a throw is a failure', async () => {
    const { writeListingSaved } = await import('@/src/lib/saved/savedListings');
    expect(await writeListingSaved(USER_A, LISTING, false)).toBe(true);
    expect(h.calls[0].table).toBe('saved_listings');
    expect(h.calls[0].op).toBe('delete');
    expect(h.calls[0].filters).toEqual(expect.arrayContaining([['eq', 'user_id', USER_A], ['eq', 'listing_id', LISTING]]));
    expect(h.calls[0].filters).toHaveLength(2);
    h.reply = () => ({ data: null, error: { code: '57014', message: 'canceling statement due to statement timeout' } });
    expect(await writeListingSaved(USER_A, LISTING, false)).toBe(false);
    h.reply = () => { throw new Error('Network request failed'); };
    expect(await writeListingSaved(USER_A, LISTING, false)).toBe(false);
  });

  it('D4: one listing\'s state: a row is saved, no row is not, a failed read says it failed (never throws)', async () => {
    const { readListingSaved } = await import('@/src/lib/saved/savedListings');
    h.reply = () => ({ data: { id: 'row-1' }, error: null });
    // `stamp` is the store's read stamp taken when the request went out (0: no tap yet).
    expect(await readListingSaved(USER_A, LISTING)).toEqual({ ok: true, saved: true, stamp: 0 });
    expect(h.calls[0].table).toBe('saved_listings');
    expect(h.calls[0].columns).toBe('id');
    expect(h.calls[0].filters).toEqual(expect.arrayContaining([['eq', 'user_id', USER_A], ['eq', 'listing_id', LISTING]]));
    expect(h.calls[0].single).toBe(true);
    h.reply = () => ({ data: null, error: null });
    expect(await readListingSaved(USER_A, LISTING)).toEqual({ ok: true, saved: false, stamp: 0 });
    h.reply = () => ({ data: null, error: { code: 'PGRST301', message: 'JWT expired' } });
    expect(await readListingSaved(USER_A, LISTING)).toEqual({ ok: false });
    h.reply = () => { throw new Error('Network request failed'); };
    expect(await readListingSaved(USER_A, LISTING)).toEqual({ ok: false });
  });
});

// ── Store: instant, latest wins, rollback to what the server holds ───────────

describe('store — instant toggle, latest tap wins, rollback to the confirmed state', () => {
  it('S1: the tap shows at once, before the server has answered', async () => {
    const store = await import('@/src/lib/saved/savedStore');
    store.bindSavedOwner(USER_A);
    store.primeSaved(USER_A, LISTING, false, store.savedReadStamp());
    const gate = deferred<boolean>();
    const write = vi.fn(() => gate.promise);
    store.toggleSaved(USER_A, LISTING, write);
    expect(store.savedShownFor(USER_A, LISTING)).toBe(true);
    expect(write).toHaveBeenCalledWith(USER_A, LISTING, true);
    gate.resolve(true);
    await tick();
    expect(store.savedShownFor(USER_A, LISTING)).toBe(true);
  });

  it('S2: a failed save returns to the last confirmed state and says which change failed', async () => {
    const store = await import('@/src/lib/saved/savedStore');
    const events: { listingId: string; failed: boolean; committed: boolean }[] = [];
    store.subscribeSavedRollback((e) => events.push({ listingId: e.listingId, failed: e.failed, committed: e.committed }));
    store.bindSavedOwner(USER_A);
    store.primeSaved(USER_A, LISTING, false, store.savedReadStamp());
    store.toggleSaved(USER_A, LISTING, async () => false);
    expect(store.savedShownFor(USER_A, LISTING)).toBe(true);
    await tick();
    expect(store.savedShownFor(USER_A, LISTING), 'back to unsaved').toBe(false);
    expect(events).toEqual([{ listingId: LISTING, failed: true, committed: false }]);

    // The other direction: a failed REMOVE puts the bookmark back.
    store.primeSaved(USER_A, LISTING, true, store.savedReadStamp());
    store.toggleSaved(USER_A, LISTING, async () => { throw new Error('offline'); });
    expect(store.savedShownFor(USER_A, LISTING)).toBe(false);
    await tick();
    expect(store.savedShownFor(USER_A, LISTING), 'back to saved').toBe(true);
    expect(events[1]).toEqual({ listingId: LISTING, failed: false, committed: true });

    const { rollbackNote, SAVED_COPY } = await import('@/src/lib/saved/savedState');
    // Web's own strings (web/src/lib/favorites-actions.ts), one per direction.
    expect(SAVED_COPY.saveFailed).toBe("Couldn't save this listing. Try again.");
    expect(SAVED_COPY.removeFailed).toBe("Couldn't remove this listing. Try again.");
    expect(rollbackNote(true)).toBe(SAVED_COPY.saveFailed);
    expect(rollbackNote(false)).toBe(SAVED_COPY.removeFailed);
  });

  it('S3: latest tap wins — taps during a save collapse to one follow-up, and a superseded failure does not roll back', async () => {
    const store = await import('@/src/lib/saved/savedStore');
    const rollbacks: unknown[] = [];
    store.subscribeSavedRollback((e) => rollbacks.push(e));
    store.bindSavedOwner(USER_A);
    store.primeSaved(USER_A, LISTING, false, store.savedReadStamp());
    const first = deferred<boolean>();
    const second = deferred<boolean>();
    const gates = [first, second];
    const write = vi.fn((_u: string, _l: string, _v: boolean) => gates.shift()!.promise);
    store.toggleSaved(USER_A, LISTING, write); // -> true (in flight)
    store.toggleSaved(USER_A, LISTING, write); // -> false (queued)
    store.toggleSaved(USER_A, LISTING, write); // -> true (replaces the queued false)
    expect(store.savedShownFor(USER_A, LISTING)).toBe(true);
    expect(write).toHaveBeenCalledTimes(1);
    first.resolve(false); // the superseded save fails: no rollback, the newest value is tried next
    await tick();
    expect(rollbacks).toHaveLength(0);
    expect(write).toHaveBeenCalledTimes(2);
    expect(write.mock.calls[1][2]).toBe(true);
    second.resolve(true);
    await tick();
    expect(store.savedShownFor(USER_A, LISTING)).toBe(true);
    expect(rollbacks).toHaveLength(0);
  });

  it('S4: an account switch clears everything; the old account\'s late result neither lands nor is reported', async () => {
    const store = await import('@/src/lib/saved/savedStore');
    const rollbacks: unknown[] = [];
    store.subscribeSavedRollback((e) => rollbacks.push(e));
    store.bindSavedOwner(USER_A);
    store.primeSaved(USER_A, LISTING, true, store.savedReadStamp());
    const gate = deferred<boolean>();
    store.toggleSaved(USER_A, LISTING, () => gate.promise); // A removes, in flight
    store.bindSavedOwner(USER_B);
    expect(store.savedShownFor(USER_A, LISTING), 'A is no longer answered for').toBeUndefined();
    expect(store.savedShownFor(USER_B, LISTING), 'B starts empty').toBeUndefined();
    expect(store._savedStoreState()).toEqual({ owner: USER_B, shown: {} });
    gate.resolve(false); // A's remove fails after the switch
    await tick();
    expect(rollbacks).toHaveLength(0);
    expect(store.savedShownFor(USER_B, LISTING)).toBeUndefined();
    // A toggle for anyone but the bound owner is refused outright.
    const write = vi.fn(async () => true);
    expect(store.toggleSaved(USER_A, LISTING, write)).toBeUndefined();
    expect(write).not.toHaveBeenCalled();
    // Signing out binds nobody.
    store.bindSavedOwner(null);
    expect(store._savedStoreState()).toEqual({ owner: null, shown: {} });
  });

  it('S5: a server read never overwrites a tap in flight; an idle saver is refreshed by a newer read', async () => {
    const store = await import('@/src/lib/saved/savedStore');
    store.bindSavedOwner(USER_A);
    store.primeSaved(USER_A, LISTING, false, store.savedReadStamp());
    const gate = deferred<boolean>();
    store.toggleSaved(USER_A, LISTING, () => gate.promise); // -> true, in flight
    // A read sent after the tap but answered while its write is still out may have seen the row
    // before the write: the pending tap decides.
    store.primeSaved(USER_A, LISTING, false, store.savedReadStamp());
    expect(store.savedShownFor(USER_A, LISTING), 'the tap decides, not the stale read').toBe(true);
    gate.resolve(true);
    await tick();
    // Later the row is removed elsewhere (web) and a fresh read says so.
    store.primeSaved(USER_A, LISTING, false, store.savedReadStamp());
    expect(store.savedShownFor(USER_A, LISTING)).toBe(false);
    // A save that now fails returns to what the fresh read said, not to the old committed `true`.
    store.toggleSaved(USER_A, LISTING, async () => false);
    await tick();
    expect(store.savedShownFor(USER_A, LISTING)).toBe(false);
  });

  it('S6: the Saved list is authoritative: listed ids are saved, a remembered save missing from it is not', async () => {
    const store = await import('@/src/lib/saved/savedStore');
    store.bindSavedOwner(USER_A);
    store.primeSaved(USER_A, 'gone', true, store.savedReadStamp());
    store.primeSavedList(USER_A, [LISTING], store.savedReadStamp());
    expect(store.savedShownFor(USER_A, LISTING)).toBe(true);
    expect(store.savedShownFor(USER_A, 'gone')).toBe(false);
    // Another account's list is ignored.
    store.primeSavedList(USER_B, ['x'], store.savedReadStamp());
    expect(store.savedShownFor(USER_A, 'x')).toBeUndefined();
  });

  it('S7: a write still queued when the account changes is never sent for the old account', async () => {
    const store = await import('@/src/lib/saved/savedStore');
    store.bindSavedOwner(USER_A);
    store.primeSaved(USER_A, LISTING, false, store.savedReadStamp());
    const first = deferred<boolean>();
    const write = vi.fn((_u: string, _l: string, _v: boolean) => first.promise);
    store.toggleSaved(USER_A, LISTING, write); // -> true, in flight
    store.toggleSaved(USER_A, LISTING, write); // -> false, queued behind it
    expect(write).toHaveBeenCalledTimes(1);
    store.bindSavedOwner(USER_B);
    first.resolve(true); // A's save lands after the switch; the queue would send A's remove next
    await tick();
    await tick();
    expect(write, "A's queued remove is dropped, not sent").toHaveBeenCalledTimes(1);
    expect(store._savedStoreState()).toEqual({ owner: USER_B, shown: {} });
  });

  it('S8: a read sent before a tap never undoes it, even when it answers after the tap has committed', async () => {
    const store = await import('@/src/lib/saved/savedStore');
    store.bindSavedOwner(USER_A);
    store.primeSaved(USER_A, LISTING, true, store.savedReadStamp()); // the Saved list said saved
    const sentBefore = store.savedReadStamp(); // the detail screen's mount read goes out now
    store.toggleSaved(USER_A, LISTING, async () => true); // a quick unsave; the DELETE commits
    await tick();
    expect(store.savedShownFor(USER_A, LISTING)).toBe(false);
    store.primeSaved(USER_A, LISTING, true, sentBefore); // the older SELECT answers last
    expect(store.savedShownFor(USER_A, LISTING), 'the committed remove stands').toBe(false);
    store.primeSavedList(USER_A, [LISTING], sentBefore); // so does an older Saved-list read
    expect(store.savedShownFor(USER_A, LISTING)).toBe(false);
    // A read sent after the tap is believed (saved again on web, say).
    store.primeSaved(USER_A, LISTING, true, store.savedReadStamp());
    expect(store.savedShownFor(USER_A, LISTING)).toBe(true);
    // One listing's tap holds back nothing about another.
    store.primeSaved(USER_A, 'other', true, sentBefore);
    expect(store.savedShownFor(USER_A, 'other')).toBe(true);
  });

  it('S9: a failure whose value the server already holds is not a rollback (offline double tap, either way)', async () => {
    const store = await import('@/src/lib/saved/savedStore');
    const rollbacks: unknown[] = [];
    store.subscribeSavedRollback((e) => rollbacks.push(e));
    store.bindSavedOwner(USER_A);
    for (const start of [false, true]) {
      store.primeSaved(USER_A, LISTING, start, store.savedReadStamp());
      const first = deferred<boolean>();
      const replies = [first.promise, Promise.resolve(false)];
      const write = vi.fn((_u: string, _l: string, _v: boolean) => replies.shift()!);
      store.toggleSaved(USER_A, LISTING, write); // in flight
      store.toggleSaved(USER_A, LISTING, write); // back to `start`, queued
      first.resolve(false); // superseded: no rollback, the queued value is tried
      await tick();
      await tick();
      expect(write).toHaveBeenCalledTimes(2);
      expect(store.savedShownFor(USER_A, LISTING), 'shows what the server holds').toBe(start);
      expect(rollbacks, 'nothing to undo or explain').toEqual([]);
    }
  });
});

// ── The hook: when the control exists, and what a rollback says ─────────────

type HookProps = { userId: string | null | undefined; listingId: string | null | undefined; enabled: boolean };
type Control = { saved: boolean; note: string | null; onToggle: () => void } | null;

async function mountHook(initial: HookProps) {
  const mod = await import('@/src/hooks/useSavedListing');
  const props = { ...initial };
  let result: Control = null;
  const host = new HookHost(() => { result = mod.useSavedListing(props) as Control; return null; }, new Map());
  host.mount();
  return {
    host,
    props,
    get value() { return result; },
    set(next: Partial<HookProps>) { Object.assign(props, next); host.flush(); },
  };
}

describe('hook — the control exists only when it can be true', () => {
  it('H1: hidden while auth or the listing is loading, when signed out, and until the first read answers', async () => {
    const read = deferred<Reply>();
    h.reply = () => read.promise;
    const m = await mountHook({ userId: USER_A, listingId: LISTING, enabled: false });
    expect(m.value, 'disabled (auth/listing loading)').toBeNull();
    expect(h.calls, 'nothing is read before it is enabled').toHaveLength(0);
    m.set({ enabled: true });
    expect(m.value, 'first read still out').toBeNull();
    expect(h.calls).toHaveLength(1);
    read.resolve({ data: { id: 'row-1' }, error: null });
    await tick();
    expect(m.value?.saved).toBe(true);
    expect(m.value?.note).toBeNull();

    const out = await mountHook({ userId: null, listingId: LISTING, enabled: true });
    expect(out.value, 'signed out').toBeNull();
  });

  it('H2: a failed first read shows the control unsaved (fails closed), and a tap then saves', async () => {
    h.reply = () => ({ data: null, error: { code: 'PGRST000', message: 'timeout' } });
    const m = await mountHook({ userId: USER_A, listingId: LISTING, enabled: true });
    await tick();
    expect(m.value?.saved).toBe(false);
    h.reply = () => ({ data: null, error: { code: '23505', message: 'duplicate key' } });
    m.value!.onToggle();
    expect(m.value?.saved, 'instant').toBe(true);
    await tick();
    expect(m.value?.saved).toBe(true);
    expect(h.calls.at(-1)?.op).toBe('insert');
    expect(h.announced).toEqual([]);
  });

  it('H3: a failed tap rolls back, shows the short note and announces it once; the next tap clears it', async () => {
    h.reply = () => ({ data: null, error: null });
    const m = await mountHook({ userId: USER_A, listingId: LISTING, enabled: true });
    await tick();
    expect(m.value?.saved).toBe(false);
    h.reply = () => ({ data: null, error: { code: '08006', message: 'connection failure' } });
    m.value!.onToggle();
    expect(m.value?.saved).toBe(true);
    await tick();
    expect(m.value?.saved, 'rolled back').toBe(false);
    expect(m.value?.note).toBe("Couldn't save this listing. Try again.");
    expect(h.announced).toEqual(["Couldn't save this listing. Try again."]);
    h.reply = () => ({ data: null, error: null });
    m.value!.onToggle();
    expect(m.value?.note).toBeNull();
    await tick();
    expect(m.value?.saved).toBe(true);
    expect(h.announced).toHaveLength(1);
  });

  it('H4: a different account resets the control and reads again for that account', async () => {
    h.reply = (c) => ({ data: c.filters.some((f) => f[2] === USER_A) ? { id: 'a-row' } : null, error: null });
    const m = await mountHook({ userId: USER_A, listingId: LISTING, enabled: true });
    await tick();
    expect(m.value?.saved).toBe(true);
    m.set({ userId: USER_B });
    await tick();
    expect(m.value?.saved, "B has not saved it; A's state is gone").toBe(false);
    const store = await import('@/src/lib/saved/savedStore');
    expect(store._savedStoreState().owner).toBe(USER_B);
    expect(store.savedShownFor(USER_A, LISTING)).toBeUndefined();
  });

  it('H5: signing out anywhere clears the in-memory store inside the auth callback, synchronously (nothing is ever written to disk)', async () => {
    h.reply = () => ({ data: { id: 'row-1' }, error: null });
    const store = await import('@/src/lib/saved/savedStore');
    const m = await mountHook({ userId: USER_A, listingId: LISTING, enabled: true });
    await tick();
    expect(m.value?.saved).toBe(true);
    expect(h.authCb, 'the store watches for a sign-out').toBeTypeOf('function');
    // auth-js awaits every listener while it holds its lock (the Build 17 sign-out deadlock): the
    // callback returns nothing to await, and the store is already empty when it returns.
    const ret: unknown = h.authCb!('SIGNED_OUT', null);
    expect(ret).toBeUndefined();
    expect(store._savedStoreState()).toEqual({ owner: null, shown: {} });
    // The auth-signout-deadlock convention: no async auth listener.
    expect(code('src/lib/saved/savedListings.ts')).not.toMatch(/onAuthStateChange\(\s*async/);
    // No storage module anywhere in the feature.
    for (const rel of ['src/lib/saved/savedStore.ts', 'src/lib/saved/savedListings.ts', 'src/lib/saved/savedState.ts', 'src/hooks/useSavedListing.ts']) {
      expect(code(rel), rel).not.toMatch(/AsyncStorage|SecureStore|localStorage|sessionStore|secureStorage/);
    }
  });
});

describe('hook — auth events, owner changes and late answers', () => {
  it('H6: INITIAL_SESSION with no session (token expired, refresh failed offline) is not a sign-out; the control keeps working', async () => {
    h.reply = () => ({ data: { id: 'row-1' }, error: null });
    const store = await import('@/src/lib/saved/savedStore');
    const m = await mountHook({ userId: USER_A, listingId: LISTING, enabled: true });
    await tick();
    expect(m.value?.saved).toBe(true);
    // What auth-js hands a NEW subscriber in that case, while useAuth (subscribed earlier) keeps A.
    h.authCb!('INITIAL_SESSION', null);
    expect(store._savedStoreState(), 'still bound to A, still knows the save').toEqual({ owner: USER_A, shown: { [LISTING]: true } });
    expect(m.value?.saved).toBe(true);
    // The refresh succeeds later: same account, nothing emptied, nothing to read again.
    h.authCb!('TOKEN_REFRESHED', { user: { id: USER_A } });
    expect(m.value?.saved).toBe(true);
    expect(h.calls.filter((c) => c.op === 'select')).toHaveLength(1);
    // And a tap still writes, with nothing rolled back or announced.
    m.value!.onToggle();
    await tick();
    expect(h.calls.filter((c) => c.op === 'delete')).toHaveLength(1);
    expect(m.value?.saved).toBe(false);
    expect(h.announced).toEqual([]);
    // A session for a different account replaces the store; a real sign-out empties it.
    h.authCb!('SIGNED_IN', { user: { id: USER_B } });
    expect(store._savedStoreState()).toEqual({ owner: USER_B, shown: {} });
    expect(m.value, 'no dead control for A on B\'s store').toBeNull();
    h.authCb!('SIGNED_OUT', null);
    expect(store._savedStoreState()).toEqual({ owner: null, shown: {} });
  });

  it('H7: any owner rebind — even back to the same account — hides the control and reads this listing again', async () => {
    // Counted when the request is built (synchronous), not when the mock answers.
    const reads = () => h.calls.filter((c) => c.op === 'select').length;
    h.reply = () => ({ data: { id: 'row-1' }, error: null });
    const store = await import('@/src/lib/saved/savedStore');
    const m = await mountHook({ userId: USER_A, listingId: LISTING, enabled: true });
    await tick();
    expect(m.value?.saved).toBe(true);
    expect(reads()).toBe(1);
    const again = deferred<Reply>();
    h.reply = () => again.promise;
    store.bindSavedOwner(null);
    expect(m.value, 'no control on a store that is not A\'s').toBeNull();
    expect(reads(), 'nothing read for a store that could not record it').toBe(1);
    store.bindSavedOwner(USER_A); // emptied, then A again
    expect(m.value, 'hidden until the new read answers').toBeNull();
    expect(reads(), 'one new read, for A').toBe(2);
    expect(h.calls.at(-1)?.filters).toEqual(expect.arrayContaining([['eq', 'user_id', USER_A], ['eq', 'listing_id', LISTING]]));
    again.resolve({ data: { id: 'row-1' }, error: null });
    await tick();
    expect(m.value?.saved, 'the saved listing shows saved again').toBe(true);
  });

  it('H8: while auth or the row is loading (enabled false) the hook binds nobody, so another screen\'s state survives', async () => {
    const store = await import('@/src/lib/saved/savedStore');
    store.bindSavedOwner(USER_A);
    store.primeSaved(USER_A, LISTING, true, store.savedReadStamp());
    const m = await mountHook({ userId: undefined, listingId: LISTING, enabled: false });
    expect(m.value).toBeNull();
    expect(store._savedStoreState()).toEqual({ owner: USER_A, shown: { [LISTING]: true } });
    m.set({ userId: USER_B }); // still not enabled
    expect(store._savedStoreState()).toEqual({ owner: USER_A, shown: { [LISTING]: true } });
    expect(h.calls).toHaveLength(0);
  });

  it('H9: the mount read answering after a quick tap has committed does not undo the tap', async () => {
    const store = await import('@/src/lib/saved/savedStore');
    // The Saved list already told the store, so the control shows before the mount read answers.
    store.bindSavedOwner(USER_A);
    store.primeSaved(USER_A, LISTING, true, store.savedReadStamp());
    const mountRead = deferred<Reply>();
    h.reply = (c) => (c.op === 'select' ? mountRead.promise : { data: null, error: null });
    const m = await mountHook({ userId: USER_A, listingId: LISTING, enabled: true });
    expect(m.value?.saved).toBe(true);
    m.value!.onToggle(); // unsave; the DELETE answers first
    await tick();
    expect(h.calls.filter((c) => c.op === 'delete')).toHaveLength(1);
    mountRead.resolve({ data: { id: 'row-1' }, error: null }); // the older SELECT lands last
    await tick();
    expect(m.value?.saved).toBe(false);
  });

  it('H10: an offline double tap (save fails, then the remove fails) shows "not saved" with no note and no announcement', async () => {
    h.reply = () => ({ data: null, error: null });
    const m = await mountHook({ userId: USER_A, listingId: LISTING, enabled: true });
    await tick();
    expect(m.value?.saved).toBe(false);
    h.reply = (c) => (c.op === 'select' ? { data: null, error: null } : { data: null, error: { code: '08006', message: 'connection failure' } });
    m.value!.onToggle();
    m.value!.onToggle();
    await tick();
    await tick();
    expect(h.calls.filter((c) => c.op !== 'select')).toHaveLength(2);
    expect(m.value?.saved).toBe(false);
    expect(m.value?.note).toBeNull();
    expect(h.announced).toEqual([]);
  });
});

// ── The control and the glyph ───────────────────────────────────────────────

describe('control — a bookmark with a selected state', () => {
  it('C1: SaveControl draws the bookmark IconButton, selected when saved, with one spoken name', async () => {
    const { SaveControl } = await import('@/src/components/listing/SaveControl');
    const onToggle = () => {};
    const on = SaveControl({ saved: true, onToggle }) as unknown as { props: Record<string, unknown> };
    const off = SaveControl({ saved: false, onToggle }) as unknown as { props: Record<string, unknown> };
    expect(on.props.glyph).toBe('bookmark');
    expect(on.props.selected).toBe(true);
    expect(off.props.selected).toBe(false);
    expect(on.props.onPress).toBe(onToggle);
    expect(on.props.accessibilityLabel).toBe('Save listing');
    expect(off.props.accessibilityLabel).toBe('Save listing');
    // Prop-driven: no data, store or hook import, and only IconButton from the ui barrel — so a test
    // that mounts ListingHero under a narrow '@/src/components/ui' mock keeps working.
    const src = code('src/components/listing/SaveControl.tsx');
    expect(src).not.toMatch(/supabase|savedStore|savedListings|useSavedListing/);
    expect(src).toMatch(/import \{ IconButton \} from '@\/src\/components\/ui';/);
  });

  it('C2: SaveNote is the short note, announced by role', async () => {
    const { SaveNote } = await import('@/src/components/listing/SaveControl');
    const host = new HookHost(() => SaveNote({ text: "Couldn't save this listing. Try again." }), new Map());
    host.mount();
    const text = findElement(host.output, (el) => el.type === 'Text');
    expect(text?.props.children).toBe("Couldn't save this listing. Try again.");
    expect(text?.props.accessibilityRole).toBe('alert');
  });

  it('C3: IconButton draws bookmark / bookmark.fill and reports the selected state; other marks are unchanged', async () => {
    const { IconButton } = await import('@/src/components/ui/IconButton');
    const render = (p: Record<string, unknown>) => {
      const host = new HookHost(() => IconButton({ onPress: () => {}, accessibilityLabel: 'x', ...p } as never), new Map());
      host.mount();
      return {
        symbol: findElement(host.output, (el) => el.type === 'IconSymbol')?.props.name,
        state: findElement(host.output, (el) => el.type === 'Pressable')?.props.accessibilityState as Record<string, unknown>,
      };
    };
    expect(render({ glyph: 'bookmark', selected: false })).toEqual({ symbol: 'bookmark', state: { disabled: false, selected: false } });
    expect(render({ glyph: 'bookmark', selected: true })).toEqual({ symbol: 'bookmark.fill', state: { disabled: false, selected: true } });
    // A control that is not a toggle reports no selected state at all.
    expect(render({ glyph: 'back' })).toEqual({ symbol: 'chevron.left', state: { disabled: false } });
    // The SYMBOL map keeps the two-space `key: 'symbol',` lines other suites parse (home-header H1c).
    expect(read('src/components/ui/IconButton.tsx')).toMatch(/^ {2}bookmark: 'bookmark',$/m);
  });

  it('C4: the non-iOS fallback maps both bookmark symbols (a missing entry is a blank square)', () => {
    const mapping = read('components/ui/icon-symbol.tsx');
    expect(mapping).toMatch(/'bookmark':\s*'bookmark-border'/);
    expect(mapping).toMatch(/'bookmark\.fill':\s*'bookmark'/);
  });
});
