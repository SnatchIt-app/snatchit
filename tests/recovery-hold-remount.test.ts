/**
 * N7c — the recovery hold survives the root layout being remounted on a cold start.
 *
 * Production T1 (C, 2026-10-15/16, frozen 7fc72a08, real emailed link, cold start): the app landed on
 * Home signed in, never on "New password". The diagnostic trace (rc9-native/n7dbg-prod) showed why:
 * the first RootLayout instance dispatched the link, then was unmounted and replaced 5 ms later; the
 * replacement's own dispatch was refused by the process-wide claimOnce, while the first instance's
 * dispatch raised the hold — into the dead instance's useState. SIGNED_IN then reached the live
 * instance with no hold and the phase router went to Home. The claim was process-wide; the hold was
 * per-instance. The hold now lives for the process too, so any root instance — first, remounted or
 * later — reads the same hold. Mocked network, real auth-js and real dispatch: NOT device evidence.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { beforeEach, describe, expect, it } from 'vitest';

import { attachDeepLinkFunnel, claimAuthParamOnce, dispatchDeepLink, type DeepLinkOutcome } from '../src/lib/auth/deepLinkDispatch';
import { pendingCodeIsRecovery } from '../src/lib/auth/recoveryClaim';
import { getRecoveryHold, setRecoveryHold, subscribeRecoveryHold, useRecoveryHold } from '../src/lib/auth/recoveryHold';

/** A root-layout stand-in: a fresh instance each render, reading the hold exactly as RootLayout does. */
let capturedSetter: ((next: boolean) => void) | null = null;
function RootProbe() {
  const [isRecovery, setIsRecovery] = useRecoveryHold();
  capturedSetter = setIsRecovery;
  return createElement('span', null, isRecovery ? 'held' : 'free');
}
const mountFreshRoot = () => renderToString(createElement(RootProbe));

beforeEach(() => { setRecoveryHold(false); capturedSetter = null; });

describe('N7c — one hold per process', () => {
  it('RH1: a root instance mounted after the hold was raised (the cold-start remount) still sees it', () => {
    expect(mountFreshRoot()).toContain('free');
    setRecoveryHold(true);
    expect(mountFreshRoot()).toContain('held');
  });

  it('RH2: the setter an earlier, since-replaced instance captured still reaches the instance that replaced it', () => {
    mountFreshRoot();
    const setterFromFirstInstance = capturedSetter!;
    expect(mountFreshRoot()).toContain('free');          // the replacement mounts before the claim resolves
    setterFromFirstInstance(true);                        // the first instance's dispatch raises the hold
    expect(mountFreshRoot()).toContain('held');
  });

  it('RH3: listeners hear every change once, and an unsubscribed (unmounted) root hears nothing', () => {
    const heard: boolean[] = [];
    const off = subscribeRecoveryHold(() => heard.push(getRecoveryHold()));
    setRecoveryHold(true);
    setRecoveryHold(true);                                // no change, no notice
    off();
    setRecoveryHold(false);
    expect(heard).toEqual([true]);
    expect(getRecoveryHold()).toBe(false);
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
        user: { id: 'user-1', aud: 'authenticated', role: 'authenticated', email: 'owner@snatchit.test', app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() },
      });
    }
    return json({ message: `unexpected ${url}` }, 500);
  };
  return createClient('http://sandbox.test', 'anon-key', {
    auth: { storage, autoRefreshToken: false, persistSession: true, detectSessionInUrl: false, flowType: 'pkce', storageKey: 'test-auth' },
    global: { fetch: fetchImpl },
  });
}

describe('N7c — the production T1 sequence, replayed with the real funnel and the real claim', () => {
  it('RH4: first root dispatches, is replaced, the replacement is refused as a duplicate — and the live root still holds', async () => {
    const client = makeClient();
    await client.auth.resetPasswordForEmail('owner@snatchit.test', { redirectTo: 'snatchit://' });
    const link = 'snatchit://?code=rh4-cold-start-remount';
    const linking = { getInitialURL: async () => link, addEventListener: () => ({ remove() {} }) };
    const outcomes: Promise<DeepLinkOutcome>[] = [];
    const attachFor = (setIsRecovery: (v: boolean) => void) => attachDeepLinkFunnel(linking, (url) => {
      outcomes.push(dispatchDeepLink(url, {
        stripeCallback: async () => false,
        verifyOtp: (i) => client.auth.verifyOtp(i),
        exchangeCodeForSession: (c) => client.auth.exchangeCodeForSession(c),
        isRecoveryCode: () => pendingCodeIsRecovery(client.auth),
        claimOnce: claimAuthParamOnce,
        onRecovery: () => { setIsRecovery(true); },
        onRecoveryFailed: () => setIsRecovery(false),
        warn: () => {},
      }));
    });

    mountFreshRoot();
    const detachFirst = attachFor(capturedSetter!);       // instance 1's effect
    detachFirst();                                        // instance 1 unmounts (remount)
    mountFreshRoot();
    attachFor(capturedSetter!);                           // instance 2's effect
    await new Promise((r) => setTimeout(r, 0));
    const [first, second] = await Promise.all(outcomes);

    expect(second).toEqual({ kind: 'ignored' });          // the claim is process-wide
    expect(first).toEqual({ kind: 'pkce', error: null }); // the session was minted by instance 1's dispatch
    expect(mountFreshRoot()).toContain('held');           // and the live root still puts them on "New password"
  });
});

describe('wiring', () => {
  const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
  const layout = strip(readFileSync(resolve(__dirname, '..', 'app/_layout.tsx'), 'utf8'));
  const body = layout.slice(layout.indexOf('function RootLayout('), layout.indexOf('function RecoveryRouteGuard('));

  it('RH5: RootLayout reads the process-wide hold, not a useState that dies with the instance', () => {
    expect(body).toMatch(/const \[isRecovery, setIsRecovery\] = useRecoveryHold\(\);/);
    expect(body).not.toMatch(/\[isRecovery, setIsRecovery\] = useState/);
    expect(layout).toMatch(/import \{ useRecoveryHold \} from '@\/src\/lib\/auth\/recoveryHold';/);
  });
});
