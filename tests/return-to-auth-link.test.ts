/**
 * CFT-603 review RAS-2 — a session minted from a link can never consume the remembered screen.
 *
 * auth-js's PKCE exchange notifies SIGNED_IN, not PASSWORD_RECOVERY (recoveryClaim.ts). When this installation's
 * stored claim cannot be read, deepLinkDispatch only raises the recovery hold AFTER the exchange returns (its late
 * fallback, exchangeWasRecovery) — and by then SIGNED_IN has already reached the root, with no hold up, so the root
 * could open the remembered screen for a recovery session before the guard moved it to "New password".
 *
 * The native shell's deep-link funnel now drops the remembered screen before it dispatches any link that carries a
 * code or a token_hash. deepLinkDispatch (the H-5 contract) is unchanged. Real auth-js with a mocked network, the
 * real dispatch and the real store: NOT device evidence.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { beforeEach, describe, expect, it } from 'vitest';

import { claimAuthParamOnce, dispatchDeepLink, parseDeepLink, type DeepLinkDeps } from '../src/lib/auth/deepLinkDispatch';
import { captureReturnTo, clearReturnTo, forgetReturnToForAuthLink, peekReturnTo } from '../src/lib/auth/returnTo';

const LISTING = '/listing/4a1d2c3b-0000-4000-8000-00000000abcd';
const USER = 'user-1';

beforeEach(() => { clearReturnTo(); });

describe('forgetReturnToForAuthLink', () => {
  it('RA1: a link with a code or a token_hash drops the remembered screen', () => {
    for (const url of [
      'snatchit://?code=abc',
      'snatchit://#code=abc',
      'snatchit://?token_hash=h1&type=recovery',
      'snatchit://?token_hash=h1',
      'snatchit://listing/x?code=planted',     // an untrusted code on any path still means "a session may follow"
    ]) {
      captureReturnTo(LISTING, null);
      expect({ url, dropped: forgetReturnToForAuthLink(url) }).toEqual({ url, dropped: true });
      expect(peekReturnTo(USER)).toBeNull();
    }
  });

  it('RA2: any other link keeps it — a listing link, a Stripe return, an expired-link error, nothing at all', () => {
    captureReturnTo(LISTING, null);
    for (const url of [
      'snatchit://listing/4a1d2c3b-0000-4000-8000-00000000abcd',
      'snatchit://stripe-redirect?payment_intent=pi_1&redirect_status=succeeded',
      'snatchit://?error=access_denied&error_code=otp_expired',
      '', null, undefined,
    ]) expect({ url, dropped: forgetReturnToForAuthLink(url) }).toEqual({ url, dropped: false });
    expect(peekReturnTo(USER)).toBe(LISTING);
  });

  it('RA3: nothing stored is reported as nothing dropped', () => {
    expect(forgetReturnToForAuthLink('snatchit://?code=abc')).toBe(false);
  });
  it("RA8: it reads a link's code and token_hash exactly as deepLinkDispatch's own parser does", () => {
    for (const url of [
      'snatchit://?code=a', 'snatchit://#code=a', 'snatchit://?x=1#token_hash=h&type=recovery', 'snatchit://?code=',
      'snatchit://?token_hash=', 'snatchit://?codes=a', 'snatchit://listing/1', 'snatchit://?a=1&code=b#c=d',
      'https://snatchitapp.com/auth?code=a', 'snatchit://?error=access_denied',
    ]) {
      const p = parseDeepLink(url);
      captureReturnTo(LISTING, null);
      const dropped = forgetReturnToForAuthLink(url);
      expect({ url, dropped }).toEqual({ url, dropped: !!(p.get('code') || p.get('token_hash')) });
      clearReturnTo();
    }
  });
});

function makeClient() {
  const mem = new Map<string, string>();
  const storage = {
    getItem: async (k: string) => mem.get(k) ?? null,
    setItem: async (k: string, v: string) => { mem.set(k, v); },
    removeItem: async (k: string) => { mem.delete(k); },
  };
  const fetchImpl: typeof fetch = async (input) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    const u = new URL(url);
    const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { 'content-type': 'application/json' } });
    if (u.pathname.endsWith('/recover')) return json({});
    if (u.pathname.endsWith('/token') && u.searchParams.get('grant_type') === 'pkce') {
      return json({
        access_token: 'at', token_type: 'bearer', expires_in: 3600,
        expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'rt',
        user: { id: USER, aud: 'authenticated', role: 'authenticated', email: 'owner@snatchit.test', app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() },
      });
    }
    return json({ message: `unexpected ${url}` }, 500);
  };
  return createClient('http://sandbox.test', 'anon-key', {
    auth: { storage, autoRefreshToken: false, persistSession: true, detectSessionInUrl: false, flowType: 'pkce', storageKey: 'test-auth' },
    global: { fetch: fetchImpl },
  });
}

/**
 * The warm recovery the late fallback handles: a remembered listing, a recovery link, and a claim that cannot be
 * read. Records what the root would see when SIGNED_IN reaches it: the screen it could open, and whether the hold
 * was up yet. `funnel` is the shell's funnel callback order — with or without the RAS-2 step.
 */
async function warmRecoveryWithUnreadableClaim(funnel: (url: string, dispatch: (url: string) => Promise<unknown>) => Promise<unknown>) {
  const client = makeClient();
  await client.auth.resetPasswordForEmail('owner@snatchit.test', { redirectTo: 'snatchit://' });
  captureReturnTo(LISTING, null);                       // a listing link opened while signed out
  let holdUp = false;
  const atSignedIn: { screen: string | null; holdUp: boolean }[] = [];
  const { data: { subscription } } = client.auth.onAuthStateChange((event) => {
    if (event === 'SIGNED_IN') atSignedIn.push({ screen: peekReturnTo(USER), holdUp });
  });
  const deps: DeepLinkDeps = {
    stripeCallback: async () => false,
    verifyOtp: (i) => client.auth.verifyOtp(i),
    exchangeCodeForSession: (c) => client.auth.exchangeCodeForSession(c),
    isRecoveryCode: async () => false,                 // the stored claim could not be read
    claimOnce: claimAuthParamOnce,
    onRecovery: () => { holdUp = true; },
    onRecoveryFailed: () => { holdUp = false; },
    warn: () => {},
  };
  const outcome = await funnel(`snatchit://?code=ras2-${Math.random().toString(36).slice(2)}`, (url) => dispatchDeepLink(url, deps));
  subscription.unsubscribe();
  return { outcome, atSignedIn, holdUp };
}

describe('the warm recovery race (real auth-js, real dispatch)', () => {
  it('RA4 (negative control): without the funnel step, SIGNED_IN reaches the root with no hold and the listing still stored', async () => {
    const r = await warmRecoveryWithUnreadableClaim((url, dispatch) => dispatch(url));
    expect(r.outcome).toEqual({ kind: 'pkce', error: null });
    expect(r.atSignedIn).toEqual([{ screen: LISTING, holdUp: false }]);
    expect(r.holdUp).toBe(true);                         // the late fallback raised it — after SIGNED_IN
  });

  it('RA5: with the shell funnel order (forget, then dispatch), SIGNED_IN finds nothing to open', async () => {
    const r = await warmRecoveryWithUnreadableClaim((url, dispatch) => { forgetReturnToForAuthLink(url); return dispatch(url); });
    expect(r.outcome).toEqual({ kind: 'pkce', error: null });
    expect(r.atSignedIn).toEqual([{ screen: null, holdUp: false }]);
    expect(r.holdUp).toBe(true);
    expect(peekReturnTo(USER)).toBeNull();
  });
});

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const read = (p: string) => strip(readFileSync(resolve(__dirname, '..', p), 'utf8'));

describe('wiring', () => {
  it('RA6: the shell funnel drops the remembered screen before it dispatches, and hands the dispatch the same claimer as before', () => {
    const shell = read('src/providers/NativeAppShell.native.tsx');
    expect(shell).toMatch(/return attachDeepLinkFunnel\(Linking, \(url\) => \{\s*forgetReturnToForAuthLink\(url\);\s*void dispatchDeepLink\(url, \{/);
    expect(shell).toContain("import { forgetReturnToForAuthLink } from '@/src/lib/auth/returnTo';");
    expect(shell).toContain('claimOnce: claimAuthParamOnce,');
  });

  it('RA7: deepLinkDispatch (H-5) knows nothing of the store', () => {
    const dispatch = read('src/lib/auth/deepLinkDispatch.ts');
    expect(dispatch).not.toMatch(/returnTo|ReturnTo/);
  });
});
