/**
 * N7 — a password-recovery email opened on this installation reaches "New password".
 *
 * Builds 25 and 27 (C's audit, 2026-10-15): the app requests recovery with PKCE and
 * redirectTo 'snatchit://'. GoTrue's redirect after /verify is `snatchit://?code=…` — no `type` —
 * so dispatchDeepLink never raised the recovery hold, exchangeCodeForSession emitted SIGNED_IN,
 * and the root route sent the person to Home signed in, password unchanged. The Redirect URL
 * allowlist holds only the literal `snatchit://` (F's read-back, 2026-10-14), so the redirect
 * cannot carry a marker without an owner-gated auth-config change.
 *
 * The device's own evidence is the verifier auth-js stored when resetPasswordForEmail ran. These
 * tests drive the REAL GoTrueClient (supabase-js + auth-js as installed) with in-memory storage
 * and a fake fetch, so an auth-js upgrade that changes the verifier format or the exchange's
 * events fails here instead of on a phone. Mocked network: NOT device evidence.
 */
import { createClient } from '@supabase/supabase-js';
import { describe, expect, it, vi } from 'vitest';

import { dispatchDeepLink } from '../src/lib/auth/deepLinkDispatch';
import { exchangeWasRecovery, pendingCodeIsRecovery, verifierIsRecovery } from '../src/lib/auth/recoveryClaim';

function makeClient() {
  const mem = new Map<string, string>();
  const storage = {
    getItem: async (k: string) => mem.get(k) ?? null,
    setItem: async (k: string, v: string) => { mem.set(k, v); },
    removeItem: async (k: string) => { mem.delete(k); },
  };
  const calls: Array<{ path: string; body: Record<string, unknown> }> = [];
  const fetchImpl: typeof fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    const u = new URL(url);
    const body = init?.body ? (JSON.parse(String(init.body)) as Record<string, unknown>) : {};
    calls.push({ path: `${u.pathname}${u.search}`, body });
    const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { 'content-type': 'application/json' } });
    if (u.pathname.endsWith('/recover') || u.pathname.endsWith('/otp')) return json({});
    if (u.pathname.endsWith('/token') && u.searchParams.get('grant_type') === 'pkce') {
      return json({
        access_token: 'at', token_type: 'bearer', expires_in: 3600,
        expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'rt',
        user: { id: 'user-1', aud: 'authenticated', role: 'authenticated', email: 'owner@snatchit.test', app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() },
      });
    }
    return json({ message: `unexpected ${url}` }, 500);
  };
  const client = createClient('http://sandbox.test', 'anon-key', {
    auth: { storage, autoRefreshToken: false, persistSession: true, detectSessionInUrl: false, flowType: 'pkce', storageKey: 'test-auth' },
    global: { fetch: fetchImpl },
  });
  return { client, calls, mem };
}

describe('N7 — the stored verifier tells a recovery code from any other code (real auth-js)', () => {
  it('RC1: after resetPasswordForEmail on this installation, the pending code is a recovery code', async () => {
    const { client, calls } = makeClient();
    const { error } = await client.auth.resetPasswordForEmail('owner@snatchit.test', { redirectTo: 'snatchit://' });
    expect(error).toBeNull();
    const recover = calls.find((c) => c.path.startsWith('/auth/v1/recover'));
    expect(recover?.path).toContain('redirect_to=snatchit%3A%2F%2F');
    expect(recover?.body.code_challenge).toEqual(expect.any(String));   // a PKCE link, so the redirect carries ?code=
    expect(await pendingCodeIsRecovery(client.auth)).toBe(true);
  });

  it('RC2: a non-recovery PKCE request (magic link) is not mistaken for recovery', async () => {
    const { client } = makeClient();
    await client.auth.signInWithOtp({ email: 'owner@snatchit.test', options: { emailRedirectTo: 'snatchit://' } });
    expect(await pendingCodeIsRecovery(client.auth)).toBe(false);
  });

  it('RC3: the NEWEST request decides — a magic link after a reset replaces the recovery verifier', async () => {
    const { client } = makeClient();
    await client.auth.resetPasswordForEmail('owner@snatchit.test', { redirectTo: 'snatchit://' });
    await client.auth.signInWithOtp({ email: 'owner@snatchit.test', options: { emailRedirectTo: 'snatchit://' } });
    expect(await pendingCodeIsRecovery(client.auth)).toBe(false);
  });

  it('RC4: nothing stored, unreadable storage or a non-client never claims recovery', async () => {
    const { client } = makeClient();
    expect(await pendingCodeIsRecovery(client.auth)).toBe(false);
    expect(await pendingCodeIsRecovery({ storageKey: 'k', storage: { getItem: async () => { throw new Error('keychain locked'); } } })).toBe(false);
    expect(await pendingCodeIsRecovery(null)).toBe(false);
    expect(await pendingCodeIsRecovery({})).toBe(false);
    expect(verifierIsRecovery('"abc/PASSWORD_RECOVERY"')).toBe(true);   // auth-js stores JSON.stringify(verifier)
    expect(verifierIsRecovery('abc/PASSWORD_RECOVERY')).toBe(true);
    expect(verifierIsRecovery('"abc"')).toBe(false);
    expect(verifierIsRecovery('"abc/SOMETHING_ELSE"')).toBe(false);
    expect(verifierIsRecovery('')).toBe(false);
    expect(verifierIsRecovery(null)).toBe(false);
  });

  it('RC5: why the pre-check exists — the exchange itself emits SIGNED_IN, never PASSWORD_RECOVERY', async () => {
    const { client } = makeClient();
    await client.auth.resetPasswordForEmail('owner@snatchit.test', { redirectTo: 'snatchit://' });
    const events: string[] = [];
    client.auth.onAuthStateChange((e) => { events.push(e); });
    const { data, error } = await client.auth.exchangeCodeForSession('code-1');
    expect(error).toBeNull();
    expect(events).toContain('SIGNED_IN');
    expect(events).not.toContain('PASSWORD_RECOVERY');
    // The late signal, used only as a fallback: auth-js hands back the stored redirect type.
    expect(exchangeWasRecovery(data)).toBe(true);
    // The verifier is spent: a second look finds nothing.
    expect(await pendingCodeIsRecovery(client.auth)).toBe(false);
  });
});

describe('N7 — the real link shape through the real dispatch raises the hold BEFORE the session appears', () => {
  it('RC6: snatchit://?code=… after a reset → onRecovery first, then /token, then SIGNED_IN', async () => {
    const { client, calls } = makeClient();
    await client.auth.resetPasswordForEmail('owner@snatchit.test', { redirectTo: 'snatchit://' });
    const order: string[] = [];
    client.auth.onAuthStateChange((e) => { if (e !== 'INITIAL_SESSION') order.push(e); });
    const onRecovery = vi.fn(() => { order.push(`hold(token-calls=${calls.filter((c) => c.path.startsWith('/auth/v1/token')).length})`); });
    const onRecoveryFailed = vi.fn();
    const out = await dispatchDeepLink('snatchit://?code=code-1', {
      stripeCallback: async () => false,
      verifyOtp: (i) => client.auth.verifyOtp(i),
      exchangeCodeForSession: (c) => client.auth.exchangeCodeForSession(c),
      isRecoveryCode: () => pendingCodeIsRecovery(client.auth),
      onRecovery,
      onRecoveryFailed,
      warn: () => {},
    });
    expect(out).toEqual({ kind: 'pkce', error: null });
    expect(onRecovery).toHaveBeenCalledTimes(1);
    expect(onRecoveryFailed).not.toHaveBeenCalled();
    expect(order).toEqual(['hold(token-calls=0)', 'SIGNED_IN']);
  });

  it('RC7: the same link shape after a magic-link request signs in WITHOUT the recovery hold', async () => {
    const { client } = makeClient();
    await client.auth.signInWithOtp({ email: 'owner@snatchit.test', options: { emailRedirectTo: 'snatchit://' } });
    const onRecovery = vi.fn();
    await dispatchDeepLink('snatchit://?code=code-2', {
      stripeCallback: async () => false,
      verifyOtp: (i) => client.auth.verifyOtp(i),
      exchangeCodeForSession: (c) => client.auth.exchangeCodeForSession(c),
      isRecoveryCode: () => pendingCodeIsRecovery(client.auth),
      onRecovery,
      warn: () => {},
    });
    expect(onRecovery).not.toHaveBeenCalled();
  });
});
