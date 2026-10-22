/**
 * The Sell tab's form belongs to one account (A's integration review of b5884efa, #132 blocker).
 *
 * Account A types into the Sell form, signs out from Settings, and account B signs in on the same
 * device. The route rendered the same CreateListingScreen instance for both, so A's unsaved text,
 * cover and proof were still in the form, and the draft autosave then wrote them under B's key and
 * offered them to B as "Continue your listing".
 *
 * The route now renders `<CreateListingScreen key={user?.id ?? 'signed-out'} />`. A key change is a
 * remount in React: the previous instance (its state, its uploads, its autosave effect) is discarded
 * and a fresh one mounts for the new account. The persisted drafts were already keyed by account
 * (listingDraftKey); the leak was the LIVE form state, which this closes.
 *
 * No test renderer is installed, so the remount leg pins the element React is handed (type and key)
 * for each account state, and the store leg proves that a draft saved under A is not read under B.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';

import { HookHost } from './helpers/nav-stack-harness';

const h = vi.hoisted(() => ({ user: { id: 'u-A' } as { id: string } | null, store: new Map<string, string>() }));

vi.mock('@/src/screens/CreateListingScreen', () => ({ default: 'CreateListingScreen' }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: h.user }) }));
// The draft store module reaches the supabase client for its sign-out purge; the client itself is not under test.
vi.mock('@/src/lib/supabase', () => ({ supabase: { auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) } } }));
vi.mock('@react-native-async-storage/async-storage', () => ({
  default: {
    getItem: async (k: string) => h.store.get(k) ?? null,
    setItem: async (k: string, v: string) => { h.store.set(k, v); },
    removeItem: async (k: string) => { h.store.delete(k); },
    getAllKeys: async () => [...h.store.keys()],
    multiRemove: async (ks: string[]) => { ks.forEach((k) => h.store.delete(k)); },
  },
}));

async function renderRoute(): Promise<{ type: unknown; key: unknown }> {
  const mod = await import('@/app/(tabs)/create');
  const Route = mod.default as () => unknown;
  const host = new HookHost(() => Route(), new Map());
  host.mount();
  host.flush();
  const el = host.output as { type: unknown; key: unknown };
  return { type: el.type, key: el.key };
}

beforeEach(() => { h.user = { id: 'u-A' }; h.store.clear(); vi.resetModules(); });

describe('the Sell route is keyed by the signed-in account', () => {
  it('CK1: account A gets a CreateListingScreen keyed by A', async () => {
    expect(await renderRoute()).toEqual({ type: 'CreateListingScreen', key: 'u-A' });
  });

  it('CK2: A signs out, B signs in → a different key, so React mounts a fresh form for B', async () => {
    expect((await renderRoute()).key).toBe('u-A');
    h.user = null;                                    // signed out
    expect((await renderRoute()).key).toBe('signed-out');
    h.user = { id: 'u-B' };                           // B signs in
    expect((await renderRoute()).key).toBe('u-B');
  });

  it('CK3: a draft A saved is not read under B — the real store, per-account keys', async () => {
    const { createListingDraftStore, listingDraftKey } = await import('@/src/lib/sell/listingDraftStore');
    const storage = {
      getItem: async (k: string) => h.store.get(k) ?? null,
      setItem: async (k: string, v: string) => { h.store.set(k, v); },
      removeItem: async (k: string) => { h.store.delete(k); },
      getAllKeys: async () => [...h.store.keys()],
      multiRemove: async (ks: readonly string[]) => { ks.forEach((k) => h.store.delete(k)); },
    };
    const store = createListingDraftStore(storage);
    const fields = {
      eventName: "A's unsaved listing", venue: 'LIV Miami', neighborhood: 'wynwood', category: 'nightlife',
      eventDate: new Date(2026, 9, 25), eventTime: new Date(2026, 9, 25, 22), dateChosen: true,
      ticketType: 'VIP', quantity: 2, transferMethod: null, restrictions: '', startingBid: '40',
      buyNowEnabled: false, buyNowPrice: '', durationHours: 24, ticketPlatform: 'other', coverUri: null,
    } as const;
    expect(await store.save('u-A', fields as never)).toBe(true);
    await store.idle();
    expect(listingDraftKey('u-A')).not.toBe(listingDraftKey('u-B'));
    expect(await store.read('u-B')).toEqual({ status: 'none' });       // B is offered nothing of A's
    expect((await store.read('u-A')).status).toBe('draft');            // A's own draft is still A's
  });

  it('CK4: the route source renders the screen under the account key', () => {
    const src = readFileSync('app/(tabs)/create.tsx', 'utf8');
    expect(src).toContain("<CreateListingScreen key={user?.id ?? 'signed-out'} />");
  });
});
