/**
 * tests/listing-draft-store.test.ts — CFT-608: where a sell-form draft lives and when it goes.
 *
 * One draft per account, under a key that names the account. A read returns only the asking
 * account's draft. Every sign-out, and any change of account, removes the other drafts. The store
 * learns of both through its OWN auth-state subscription, so neither the A-gated sign-out path nor
 * the shared root layout carries a line for it.
 *
 * That subscription carries the Build 17 constraint (src/lib/auth/authStateHandler.ts): auth-js runs
 * signOut() inside its lock and awaits whatever each onAuthStateChange callback returns. So the
 * listener returns undefined before anything is awaited, never calls getSession/getUser, takes the
 * uid from the callback's own session argument, and fires the storage purge without returning it.
 * DS6 drives the REAL GoTrueClient (as tests/auth-signout-deadlock.test.ts does) to show that a
 * sign-out with the listener armed still resolves, and that the draft is gone afterwards.
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { describe, expect, it, vi } from 'vitest';

import { serializeListingDraft, type ListingDraftFields } from '@/src/lib/sell/listingDraft';
import {
  createListingDraftStore,
  LISTING_DRAFT_KEY_PREFIX,
  listingDraftKey,
  type DraftStorage,
} from '@/src/lib/sell/listingDraftStore';
import { REPO_ROOT } from './helpers/nav-stack-harness';

// Hoisted by vitest above the imports: the store module imports AsyncStorage and the app client.
vi.mock('@react-native-async-storage/async-storage', () => ({
  default: {
    getItem: async () => null, setItem: async () => {}, removeItem: async () => {},
    getAllKeys: async () => [], multiRemove: async () => {},
  },
}));
vi.mock('@/src/lib/supabase', () => ({ supabase: { auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) } } }));

const NOW = new Date(2026, 9, 21, 12, 0, 0);
const fields = (over: Partial<ListingDraftFields> = {}): ListingDraftFields => ({
  eventName: 'Weekend pool party', venue: 'LIV Miami', neighborhood: 'south beach', category: 'nightlife',
  eventDate: new Date(2026, 9, 25), eventTime: new Date(2026, 9, 21, 22), dateChosen: true, ticketType: 'GA', quantity: 1,
  transferMethod: 'email', restrictions: '', startingBid: '40', buyNowEnabled: false, buyNowPrice: '',
  durationHours: 24, ticketPlatform: 'other', coverUri: null, ...over,
});

function memStorage(seed: Record<string, string> = {}) {
  const mem = new Map<string, string>(Object.entries(seed));
  const ops: string[] = [];
  const storage: DraftStorage = {
    getItem: async (k) => { ops.push(`get ${k}`); return mem.get(k) ?? null; },
    setItem: async (k, v) => { ops.push(`set ${k}`); mem.set(k, v); },
    removeItem: async (k) => { ops.push(`remove ${k}`); mem.delete(k); },
    getAllKeys: async () => { ops.push('keys'); return [...mem.keys()]; },
    multiRemove: async (ks) => { ops.push(`multiRemove ${[...ks].sort().join(',')}`); for (const k of ks) mem.delete(k); },
  };
  return { mem, ops, storage };
}

const session = (uid: string) => ({ user: { id: uid } }) as never;
const KEY_A = listingDraftKey('user-a');
const KEY_B = listingDraftKey('user-b');

describe('DS1 · one key per account', () => {
  it('DS1a: the key names the account under a versioned prefix', () => {
    expect(LISTING_DRAFT_KEY_PREFIX).toBe('snatchit.sell.draft.v1:');
    expect(KEY_A).toBe('snatchit.sell.draft.v1:user-a');
    expect(KEY_A).not.toBe(KEY_B);
  });

  it('DS1b: a save lands under the saving account’s key and reads back for that account', async () => {
    const { mem, storage } = memStorage();
    const store = createListingDraftStore(storage, { now: () => NOW });
    store.handleAuthChange('SIGNED_IN', session('user-a'));
    expect(await store.save('user-a', fields())).toBe(true);
    expect([...mem.keys()]).toEqual([KEY_A]);
    const d = await store.load('user-a');
    expect(d?.fields.eventName).toBe('Weekend pool party');
  });

  it('DS1c (negative control): another account’s draft is never returned', async () => {
    const { storage } = memStorage({ [KEY_A]: serializeListingDraft(fields(), NOW) });
    const store = createListingDraftStore(storage, { now: () => NOW });
    expect(await store.load('user-b')).toBeNull();
    store.handleAuthChange('SIGNED_IN', session('user-b'));
    expect(await store.load('user-a')).toBeNull();     // signed in as B: A's key is not even read back
  });

  it('DS1d: an empty form removes the stored draft instead of writing one', async () => {
    const { mem, storage } = memStorage({ [KEY_A]: serializeListingDraft(fields(), NOW) });
    const store = createListingDraftStore(storage, { now: () => NOW });
    store.handleAuthChange('INITIAL_SESSION', session('user-a'));
    const blank = fields({ eventName: '', venue: '', neighborhood: null, ticketType: null, transferMethod: null, startingBid: '', durationHours: null });
    expect(await store.save('user-a', blank)).toBe(true);
    expect(mem.has(KEY_A)).toBe(false);
  });

  it('DS1e: clear removes only that account’s draft', async () => {
    const { mem, storage } = memStorage({ [KEY_A]: serializeListingDraft(fields(), NOW), 'snatchit.appearance.v1': 'dark' });
    const store = createListingDraftStore(storage, { now: () => NOW });
    await store.clear('user-a');
    expect([...mem.keys()]).toEqual(['snatchit.appearance.v1']);
  });
});

describe('DS2 · what is refused on read is also removed', () => {
  for (const [name, raw] of [
    ['corrupt JSON', '{"v":1,"fields":'],
    ['an older version', JSON.stringify({ v: 0, savedAt: NOW.toISOString(), fields: {} })],
    ['a newer version', serializeListingDraft(fields(), NOW).replace('"v":1', '"v":2')],
  ] as const) {
    it(`DS2: ${name} is discarded`, async () => {
      const { mem, storage } = memStorage({ [KEY_A]: raw });
      const store = createListingDraftStore(storage, { now: () => NOW });
      expect(await store.load('user-a')).toBeNull();
      expect(mem.has(KEY_A)).toBe(false);
    });
  }

  it('DS2d: a draft whose event date has passed is discarded on load', async () => {
    const { mem, storage } = memStorage({ [KEY_A]: serializeListingDraft(fields({ eventDate: new Date(2026, 9, 20) }), NOW) });
    const store = createListingDraftStore(storage, { now: () => NOW });
    expect(await store.load('user-a')).toBeNull();
    expect(mem.has(KEY_A)).toBe(false);
  });

  it('DS2d2 (LD-R2): a draft saved with the screen’s default date is still offered the next day — and kept', async () => {
    // The seller typed a name, a venue and a price on the 21st and never touched the date row, which
    // starts at today. After midnight that default is "yesterday", but it was never their choice.
    const { mem, storage } = memStorage();
    let clock = NOW;
    const store = createListingDraftStore(storage, { now: () => clock });
    store.handleAuthChange('INITIAL_SESSION', session('user-a'));
    expect(await store.save('user-a', fields({ eventName: 'Rolling Loud Saturday', eventDate: new Date(2026, 9, 21), dateChosen: false }))).toBe(true);
    clock = new Date(2026, 9, 22, 9, 0);
    const d = await store.load('user-a');
    expect(d?.fields.eventName).toBe('Rolling Loud Saturday');
    expect(mem.has(KEY_A)).toBe(true);
    // the same draft with the date picked is a past event, and goes
    expect(await store.save('user-a', fields({ eventDate: new Date(2026, 9, 21), dateChosen: true }))).toBe(true);
    expect(await store.load('user-a')).toBeNull();
    expect(mem.has(KEY_A)).toBe(false);
  });

  it('DS2e: storage that throws is "no draft", never a crash', async () => {
    const broken: DraftStorage = {
      getItem: async () => { throw new Error('disk'); }, setItem: async () => { throw new Error('disk'); },
      removeItem: async () => { throw new Error('disk'); }, getAllKeys: async () => { throw new Error('disk'); },
      multiRemove: async () => { throw new Error('disk'); },
    };
    const store = createListingDraftStore(broken, { now: () => NOW });
    store.handleAuthChange('SIGNED_IN', session('user-a'));
    expect(await store.load('user-a')).toBeNull();
    expect(await store.save('user-a', fields())).toBe(false);
    await expect(store.clear('user-a')).resolves.toBeUndefined();
    store.handleAuthChange('SIGNED_OUT', null);
    await expect(store.idle()).resolves.toBeUndefined();
  });
});

describe('DS3 · the auth listener is synchronous (Build 17)', () => {
  it('DS3a: SIGNED_OUT returns undefined at once and purges afterwards, fire-and-forget', async () => {
    const { mem, storage, ops } = memStorage({
      [KEY_A]: serializeListingDraft(fields(), NOW), [KEY_B]: serializeListingDraft(fields(), NOW), 'snatchit.appearance.v1': 'dark',
    });
    const store = createListingDraftStore(storage, { now: () => NOW });
    const ret = store.handleAuthChange('SIGNED_OUT', null);
    expect(ret).toBeUndefined();
    expect(ops).toEqual([]);                          // nothing touched storage inside the callback
    await store.idle();
    expect([...mem.keys()]).toEqual(['snatchit.appearance.v1']);   // every draft gone, nothing else
  });

  it('DS3b: the listener reads the uid from its session argument and never asks the auth client', () => {
    const src = readFileSync(join(REPO_ROOT, 'src/lib/sell/listingDraftStore.ts'), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    const start = src.indexOf('function handleAuthChange(');
    expect(start).toBeGreaterThan(-1);
    const body = src.slice(start, src.indexOf('\n  }', start));
    expect(body.length).toBeGreaterThan(80);
    // and the callback handed to auth-js is a block that returns nothing
    expect(src).toContain('auth.onAuthStateChange((event, session) => { handleAuthChange(event, session); });');
    expect(body).toContain('session?.user?.id');
    expect(body).not.toMatch(/\bawait\b|getSession|getUser|refreshSession|\.then\(/);
    expect(body).not.toMatch(/\breturn\s+[^;\s]/);   // returns nothing auth-js could await
    expect(body).toMatch(/void /);                    // the purge is fired, not returned
    expect(src).not.toMatch(/getSession\(|getUser\(/);
  });

  it('DS3c: a change of account removes the previous account’s draft and keeps the new one’s', async () => {
    const { mem, storage } = memStorage({ [KEY_A]: serializeListingDraft(fields(), NOW), [KEY_B]: serializeListingDraft(fields(), NOW) });
    const store = createListingDraftStore(storage, { now: () => NOW });
    store.handleAuthChange('SIGNED_IN', session('user-b'));
    await store.idle();
    expect([...mem.keys()]).toEqual([KEY_B]);
  });

  it('DS3d: a token refresh for the same account purges nothing', async () => {
    const { ops, storage } = memStorage({ [KEY_A]: serializeListingDraft(fields(), NOW) });
    const store = createListingDraftStore(storage, { now: () => NOW });
    store.handleAuthChange('SIGNED_IN', session('user-a'));
    await store.idle();
    ops.length = 0;
    store.handleAuthChange('TOKEN_REFRESHED', session('user-a'));
    store.handleAuthChange('USER_UPDATED', session('user-a'));
    await store.idle();
    expect(ops).toEqual([]);
  });

  it('DS3e: no session WITHOUT a sign-out (an offline launch whose token expired) deletes nothing and reads or writes nothing', async () => {
    // auth-js 2.98 hands INITIAL_SESSION a null session when the stored token has expired and the
    // refresh cannot reach the server, yet it keeps the stored session: the seller is still signed
    // in, and the next refresh brings them back (DS6c drives the real client through exactly this).
    // Only SIGNED_OUT — which auth-js emits on every real removal of a session — ends an account here.
    const { mem, storage } = memStorage({ [KEY_A]: serializeListingDraft(fields(), NOW) });
    const store = createListingDraftStore(storage, { now: () => NOW });
    store.handleAuthChange('INITIAL_SESSION', null);
    await store.idle();
    expect(mem.has(KEY_A)).toBe(true);
    expect(await store.load('user-a')).toBeNull();                              // nobody is current: nothing is read
    expect(await store.save('user-a', fields({ eventName: 'late' }))).toBe(false); // ...or written
    store.handleAuthChange('TOKEN_REFRESHED', session('user-a'));
    expect((await store.load('user-a'))?.fields.eventName).toBe('Weekend pool party');
  });

  it('DS3f: a draft left behind while nobody is signed in goes the moment a different account signs in', async () => {
    const { mem, storage } = memStorage({ [KEY_A]: serializeListingDraft(fields(), NOW) });
    const store = createListingDraftStore(storage, { now: () => NOW });
    store.handleAuthChange('INITIAL_SESSION', null);
    store.handleAuthChange('SIGNED_IN', session('user-b'));
    await store.idle();
    expect(mem.size).toBe(0);
    expect(await store.load('user-a')).toBeNull();
  });
});

describe('DS9 · a read already queued when the account changes returns nothing', () => {
  // The account is checked again INSIDE the queue: a read accepted for A, still waiting its turn when
  // B signs in (or A signs out), must not hand A's draft to anyone afterwards.
  it('DS9a: a change of account lands while the read is queued', async () => {
    const { storage } = memStorage({ [KEY_A]: serializeListingDraft(fields(), NOW) });
    const store = createListingDraftStore(storage, { now: () => NOW });
    store.handleAuthChange('SIGNED_IN', session('user-a'));
    const reading = store.load('user-a');
    store.handleAuthChange('SIGNED_IN', session('user-b'));
    expect(await reading).toBeNull();
  });

  it('DS9b: a sign-out lands while the read is queued', async () => {
    const { mem, storage } = memStorage({ [KEY_A]: serializeListingDraft(fields(), NOW) });
    const store = createListingDraftStore(storage, { now: () => NOW });
    store.handleAuthChange('SIGNED_IN', session('user-a'));
    const reading = store.load('user-a');
    store.handleAuthChange('SIGNED_OUT', null);
    expect(await reading).toBeNull();
    await store.idle();
    expect(mem.size).toBe(0);
  });
});

describe('DS4 · nothing is written for an account that is no longer signed in', () => {
  it('DS4a: after sign-out a late save for the old account is refused', async () => {
    const { mem, storage } = memStorage();
    const store = createListingDraftStore(storage, { now: () => NOW });
    store.handleAuthChange('SIGNED_IN', session('user-a'));
    store.handleAuthChange('SIGNED_OUT', null);
    expect(await store.save('user-a', fields())).toBe(false);
    await store.idle();
    expect(mem.size).toBe(0);
  });

  it('DS4b: a save for an account other than the signed-in one is refused', async () => {
    const { mem, storage } = memStorage();
    const store = createListingDraftStore(storage, { now: () => NOW });
    store.handleAuthChange('SIGNED_IN', session('user-b'));
    expect(await store.save('user-a', fields())).toBe(false);
    expect(mem.size).toBe(0);
  });

  it('DS4c: a save already under way when sign-out lands is still purged — operations run in order', async () => {
    const { mem, storage } = memStorage();
    const store = createListingDraftStore(storage, { now: () => NOW });
    store.handleAuthChange('SIGNED_IN', session('user-a'));
    const saving = store.save('user-a', fields());
    store.handleAuthChange('SIGNED_OUT', null);
    await saving;
    await store.idle();
    expect(mem.size).toBe(0);
  });
});

describe('DS5 · arming', () => {
  it('DS5a: arm subscribes once, however many times it is called', () => {
    const { storage } = memStorage();
    const store = createListingDraftStore(storage, { now: () => NOW });
    const onAuthStateChange = vi.fn(() => ({ data: { subscription: { unsubscribe() {} } } }));
    store.arm({ onAuthStateChange });
    store.arm({ onAuthStateChange });
    expect(onAuthStateChange).toHaveBeenCalledTimes(1);
  });

  it('DS5b: the callback handed to auth-js returns undefined', () => {
    const { storage } = memStorage();
    const store = createListingDraftStore(storage, { now: () => NOW });
    let cb: ((e: string, s: unknown) => unknown) | null = null;
    store.arm({ onAuthStateChange: (fn: (e: string, s: unknown) => unknown) => { cb = fn; return { data: { subscription: { unsubscribe() {} } } }; } } as never);
    expect(cb).not.toBeNull();
    expect(cb!('SIGNED_OUT', null)).toBeUndefined();
  });
});

describe('DS7 · armed from the signed-in shell — not from the sign-out path or the root layout', () => {
  const read = (rel: string) => readFileSync(join(REPO_ROOT, rel), 'utf8');
  const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

  it('DS7a: the tabs layout arms the purge on mount, so a sign-out clears drafts even if Sell was never opened', () => {
    const tabs = strip(read('app/(tabs)/_layout.tsx'));
    expect(tabs).toContain("import { armListingDraftPurge } from '@/src/lib/sell/listingDraftStore';");
    expect(tabs).toMatch(/useEffect\(\(\) => \{ armListingDraftPurge\(\); \}, \[\]\);/);
  });

  it('DS7b: the hook arms it too (idempotent), and the A-gated sign-out path and the root layout carry nothing for drafts', () => {
    expect(strip(read('src/hooks/useListingDraft.ts'))).toContain('armListingDraftPurge()');
    for (const f of ['src/lib/auth/signOut.ts', 'app/_layout.tsx', 'src/hooks/useAuth.ts', 'src/lib/auth/authStateHandler.ts']) {
      expect(read(f), f).not.toMatch(/listingDraft|ListingDraft/);
    }
  });
});

describe('DS6 · against the real auth client', () => {
  const HANG_MS = 1_500;
  const race = <T,>(p: PromiseLike<T>): Promise<'resolved' | 'hung'> =>
    Promise.race([Promise.resolve(p).then(() => 'resolved' as const, () => 'resolved' as const), new Promise<'hung'>((r) => setTimeout(() => r('hung'), HANG_MS))]);

  function fakeSession(userId: string): Record<string, unknown> {
    const payload = Buffer.from(JSON.stringify({ sub: userId, aud: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600, role: 'authenticated' })).toString('base64url');
    return {
      access_token: `eyJhbGciOiJIUzI1NiJ9.${payload}.sig`, token_type: 'bearer', expires_in: 3600,
      expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: `rt-${userId}`,
      user: { id: userId, aud: 'authenticated', role: 'authenticated', email: `${userId}@snatchit.test`, app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() },
    };
  }

  function makeClient(opts: { authMem?: Map<string, string>; online?: () => boolean } = {}) {
    const authMem = opts.authMem ?? new Map<string, string>();
    const fetchImpl: typeof fetch = async (input, init) => {
      if (opts.online && !opts.online()) throw new TypeError('Network request failed');
      const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
      const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
      if (url.includes('/auth/v1/token')) {
        const b = JSON.parse(String(init?.body ?? '{}')) as { email?: string };
        return json(fakeSession(b.email?.startsWith('b') ? 'user-b' : 'user-a'));
      }
      if (url.includes('/auth/v1/logout')) return new Response(null, { status: 204 });
      if (url.includes('/rest/v1/')) return json([]);
      return json({ message: `unexpected ${url}` }, 500);
    };
    return createClient('http://sandbox.test', 'anon-key', {
      auth: {
        storage: { getItem: async (k: string) => authMem.get(k) ?? null, setItem: async (k: string, v: string) => { authMem.set(k, v); }, removeItem: async (k: string) => { authMem.delete(k); } },
        autoRefreshToken: false, persistSession: true, detectSessionInUrl: false, storageKey: 'test-auth',
      },
      global: { fetch: fetchImpl },
    });
  }

  it('DS6a: sign-out resolves with the listener armed, data loads after, and the draft is gone', async () => {
    const client = makeClient();
    const { mem, storage } = memStorage();
    const store = createListingDraftStore(storage, { now: () => NOW });
    store.arm(client.auth);
    await client.auth.signInWithPassword({ email: 'a@snatchit.test', password: 'x' });
    await store.idle();
    expect(await store.save('user-a', fields())).toBe(true);
    expect(mem.has(KEY_A)).toBe(true);

    expect(await race(client.auth.signOut())).toBe('resolved');
    await store.idle();
    expect(mem.has(KEY_A)).toBe(false);

    await client.auth.signInWithPassword({ email: 'a@snatchit.test', password: 'x' });
    expect(await race(client.from('listings').select('id'))).toBe('resolved');
  });

  it('DS6b: account switch — B signs in on the same device and never sees A’s draft', async () => {
    const client = makeClient();
    const { mem, storage } = memStorage();
    const store = createListingDraftStore(storage, { now: () => NOW });
    store.arm(client.auth);
    await client.auth.signInWithPassword({ email: 'a@snatchit.test', password: 'x' });
    await store.idle();
    await store.save('user-a', fields({ eventName: 'A only' }));
    void client.auth.signOut();
    await new Promise((r) => setTimeout(r, 50));
    await client.auth.signInWithPassword({ email: 'b@snatchit.test', password: 'x' });
    await store.idle();
    expect(await store.load('user-b')).toBeNull();
    expect(await store.load('user-a')).toBeNull();
    expect(mem.size).toBe(0);
    expect(await race(client.from('listings').select('id'))).toBe('resolved');
  });

  it('DS6c: an offline launch with an expired token is not a sign-out — the draft survives and comes back once the token refreshes', async () => {
    // The interruption a draft exists for: the app was killed, and is opened again more than an hour
    // later where the signal is poor. The tabs layout (the launch route) has armed the purge before
    // auth-js reports the launch session, so the store hears INITIAL_SESSION with no session.
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
    vi.setSystemTime(new Date(2026, 9, 21, 12, 0, 0));
    const quiet = vi.spyOn(console, 'error').mockImplementation(() => {});
    try {
      let online = false;
      const authMem = new Map<string, string>();
      authMem.set('test-auth', JSON.stringify({ ...fakeSession('user-a'), expires_at: Math.floor(Date.now() / 1000) - 60 }));
      const client = makeClient({ authMem, online: () => online });
      const { mem, storage } = memStorage({ [KEY_A]: serializeListingDraft(fields(), NOW) });
      const store = createListingDraftStore(storage, { now: () => NOW });
      const events: [string, string | null][] = [];
      client.auth.onAuthStateChange((e, s) => { events.push([e, s?.user?.id ?? null]); });
      store.arm(client.auth);
      await vi.advanceTimersByTimeAsync(40_000);           // auth-js retries the refresh for up to 30 s
      await store.idle();

      expect(events).toContainEqual(['INITIAL_SESSION', null]);   // auth-js reports no session...
      expect(events.map(([e]) => e)).not.toContain('SIGNED_OUT');
      expect(authMem.has('test-auth')).toBe(true);                 // ...but keeps it: still signed in
      expect(mem.has(KEY_A)).toBe(true);                           // so the draft is not purged
      expect(await store.load('user-a')).toBeNull();               // though nothing is read meanwhile

      online = true;                                              // the signal comes back
      await client.auth.refreshSession();
      await store.idle();
      expect(events.map(([e]) => e)).toContain('TOKEN_REFRESHED');
      expect((await store.load('user-a'))?.fields.eventName).toBe('Weekend pool party');

      // and a real sign-out afterwards still purges it
      expect(await race(client.auth.signOut())).toBe('resolved');
      await store.idle();
      expect(mem.has(KEY_A)).toBe(false);
    } finally {
      quiet.mockRestore();
      vi.useRealTimers();
    }
  });
});
