/**
 * tests/auth-signout-deadlock.test.ts — Build 17 blocking finding (owner,
 * 2026-09-16): sign out online, sign back in, and Home/Profile load forever
 * until a force-quit.
 *
 * Root cause under test: `signOut()` runs inside the auth-js lock and awaits
 * every onAuthStateChange callback; the app's callback awaited
 * `supabase.auth.getSession()`, which queues behind the sign-out that is
 * waiting on it. The lock is never released, so every later data request
 * (which awaits the session for its bearer token) hangs for the life of the
 * process. This test drives the REAL GoTrueClient through the real
 * supabase-js client with an in-memory storage and a fake fetch, wires the
 * app's handler exactly as useAuth does, and asserts nothing hangs.
 */

import { createClient, type Session } from '@supabase/supabase-js';
import { describe, expect, it } from 'vitest';

import { handleAuthStateChange, type AuthStateDeps } from '@/src/lib/auth/authStateHandler';

const HANG_MS = 1_500;
// Accepts thenables too: a PostgREST query builder is a PromiseLike, not a Promise.
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

function makeClient(seed?: Record<string, string>) {
  const mem = new Map<string, string>(Object.entries(seed ?? {}));
  const storage = {
    getItem: async (k: string) => mem.get(k) ?? null,
    setItem: async (k: string, v: string) => { mem.set(k, v); },
    removeItem: async (k: string) => { mem.delete(k); },
  };
  const calls: string[] = [];
  const fetchImpl: typeof fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    calls.push(`${init?.method ?? 'GET'} ${new URL(url).pathname}`);
    const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
    if (url.includes('/auth/v1/token')) {
      const b = JSON.parse(String(init?.body ?? '{}')) as { email?: string };
      return json(fakeSession(b.email?.startsWith('b') ? 'user-b' : 'user-a'));
    }
    if (url.includes('/auth/v1/logout')) return new Response(null, { status: 204 });
    if (url.includes('/auth/v1/user')) return json(fakeSession('user-a').user);
    if (url.includes('/rest/v1/')) return json([]);
    return json({ message: `unexpected ${url}` }, 500);
  };
  const client = createClient('http://sandbox.test', 'anon-key', {
    auth: { storage, autoRefreshToken: false, persistSession: true, detectSessionInUrl: false, storageKey: 'test-auth' },
    global: { fetch: fetchImpl },
  });
  return { client, calls, mem };
}

function wire(client: ReturnType<typeof makeClient>['client']) {
  const seen: Array<[string, string | null]> = [];
  const staleHandled = { current: false };
  const deps: AuthStateDeps = {
    setSession: () => {},
    markExpired: () => {},
    getSessionError: async () => (await client.auth.getSession()).error?.message ?? null,
    isStaleTokenError: (m) => m.includes('Invalid Refresh Token') || m.includes('Refresh Token Not Found'),
    clearStaleSession: async () => {},
    staleHandled,
    warnEmitted: () => false,
    defer: (fn) => { setTimeout(fn, 0); },
  };
  // Wired exactly as useAuth wires it: whatever the handler returns is what
  // auth-js awaits inside its lock (a Promise from an async handler is awaited).
  client.auth.onAuthStateChange((event, session: Session | null) => {
    seen.push([event, session?.user?.id ?? null]);
    return handleAuthStateChange(event, session, deps) as unknown as void;
  });
  return { seen };
}

describe('sign out → sign in must not leave the auth lock held (Home/Profile stuck loading)', () => {
  it('a normal online sign-out resolves', async () => {
    const { client } = makeClient();
    wire(client);
    await client.auth.signInWithPassword({ email: 'a@snatchit.test', password: 'x' });
    expect(await race(client.from('listings').select('id'))).toBe('resolved');
    expect(await race(client.auth.signOut())).toBe('resolved');
  });

  it('after sign-out then sign-in with the same account, a data request resolves (no permanent spinner)', async () => {
    const { client, calls } = makeClient();
    const { seen } = wire(client);
    await client.auth.signInWithPassword({ email: 'a@snatchit.test', password: 'x' });
    void client.auth.signOut(); // the app does not wait for this before the user signs in again
    await new Promise((r) => setTimeout(r, 50));
    await client.auth.signInWithPassword({ email: 'a@snatchit.test', password: 'x' });
    expect(await race(client.from('listings').select('id'))).toBe('resolved');
    expect(await race(client.rpc('get_my_profile'))).toBe('resolved');
    // exact auth event sequence the app sees (INITIAL_SESSION is emitted to every new subscriber)
    expect(seen.map(([e]) => e).filter((e) => e !== 'INITIAL_SESSION')).toEqual(['SIGNED_IN', 'SIGNED_OUT', 'SIGNED_IN']);
    // no duplicate data requests: one listings read, one rpc
    expect(calls.filter((c) => c.includes('/rest/v1/listings')).length).toBe(1);
    expect(calls.filter((c) => c.includes('/rest/v1/rpc/get_my_profile')).length).toBe(1);
  });

  it('account switch: sign out, sign in as another user, data request resolves', async () => {
    const { client } = makeClient();
    wire(client);
    await client.auth.signInWithPassword({ email: 'a@snatchit.test', password: 'x' });
    void client.auth.signOut();
    await new Promise((r) => setTimeout(r, 50));
    await client.auth.signInWithPassword({ email: 'b@snatchit.test', password: 'x' });
    expect(await race(client.from('listings').select('id'))).toBe('resolved');
    expect((await client.auth.getSession()).data.session?.user.id).toBe('user-b');
  });

  it('restored session (cold launch): the callback is not involved and data loads', async () => {
    const { client } = makeClient({ 'test-auth': JSON.stringify(fakeSession('user-a')) });
    wire(client);
    expect(await race(client.from('listings').select('id'))).toBe('resolved');
    expect((await client.auth.getSession()).data.session?.user.id).toBe('user-a');
  });
});

describe('the handler never awaits another auth call inside the callback', () => {
  it('SIGNED_OUT returns before the stale diagnostic runs; the diagnostic runs deferred', async () => {
    const order: string[] = [];
    const deps: AuthStateDeps = {
      setSession: () => order.push('setSession'),
      markExpired: () => order.push('markExpired'),
      getSessionError: async () => { order.push('getSession'); return null; },
      isStaleTokenError: () => false,
      clearStaleSession: async () => {},
      staleHandled: { current: false },
      warnEmitted: () => false,
      defer: (fn) => { order.push('defer'); setTimeout(fn, 0); },
    };
    const ret = handleAuthStateChange('SIGNED_OUT', null, deps);
    expect(ret).toBeUndefined();                    // synchronous: nothing awaited inside the lock
    expect(order).toEqual(['setSession', 'markExpired', 'defer']);
    await new Promise((r) => setTimeout(r, 5));
    expect(order).toEqual(['setSession', 'markExpired', 'defer', 'getSession']);
  });

  it('useAuth wires the handler and the callback body contains no awaited auth call', () => {
    const { readFileSync } = require('node:fs') as typeof import('node:fs');
    const { resolve } = require('node:path') as typeof import('node:path');
    const s = readFileSync(resolve(__dirname, '..', 'src/hooks/useAuth.ts'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    expect(s).toContain('handleAuthStateChange(event, newSession,');
    const cb = s.slice(s.indexOf('onAuthStateChange('), s.indexOf('subscription.unsubscribe'));
    expect(cb).not.toMatch(/await supabase\.auth\./);
    expect(cb).not.toMatch(/onAuthStateChange\(async/);
    expect(s).toContain('defer: (fn) => { setTimeout(fn, 0); }');
  });
});
