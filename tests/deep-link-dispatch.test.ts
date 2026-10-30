/**
 * tests/deep-link-dispatch.test.ts — the Stripe return URL reaches the SDK
 * first, and the auth contract is untouched. Behavioural, with every effect
 * mocked; nothing here asserts on source text.
 *
 * DEVICE-ONLY: these prove the WIRING — that the URL is handed to
 * handleURLCallback first and that both entry points reach it. Whether iOS
 * actually returns from the 3-D Secure browser is proven only on hardware.
 */

import { describe, expect, it, vi } from 'vitest';

import { attachDeepLinkFunnel, dispatchDeepLink, type DeepLinkDeps } from '../src/lib/auth/deepLinkDispatch';

const STRIPE_URL = 'snatchit://checkout/7ff98ba1-e7ba-4961-ac2b-763b863f1ac4?payment_intent=pi_x&payment_intent_client_secret=cs_x&redirect_status=succeeded';
const OTP_URL = 'snatchit://auth?token_hash=abc123&type=recovery';
const PKCE_URL = 'snatchit://auth?code=pkce-code-1';

function deps(over: Partial<DeepLinkDeps> = {}) {
  const d = {
    stripeCallback: vi.fn(async () => false),
    verifyOtp: vi.fn(async () => ({ error: null })),
    exchangeCodeForSession: vi.fn(async () => ({ error: null })),
    onRecovery: vi.fn(),
    onRecoveryFailed: vi.fn(),
    warn: vi.fn(),
    ...over,
  };
  return d as DeepLinkDeps & { [K in keyof DeepLinkDeps]: ReturnType<typeof vi.fn> };
}

describe('(a2) F7: a recovery link whose token the provider rejects must release the hold it raised', () => {
  /*
   * The hold is raised on the link's CLAIM (type=recovery) before verifyOtp runs, so the reset
   * screen shows at once — that ordering is pinned below in (b) and stays. But a consumed or
   * expired token (AGENTS.md records link pre-scanners consuming one-time links within seconds)
   * left the hold raised with no session: rootRouteDecision holds on isRecovery, reset-password's
   * updateUser fails "Auth session missing!", and only SIGNED_OUT or a relaunch clears it. The
   * claim failed, so the hold it bought must be released.
   */
  it('calls onRecoveryFailed exactly once when verifyOtp returns an error for a recovery link', async () => {
    const d = deps({ verifyOtp: vi.fn(async () => ({ error: { message: 'Token has expired' } })) });
    await dispatchDeepLink(OTP_URL, d);
    expect(d.onRecovery).toHaveBeenCalledTimes(1);
    expect(d.onRecoveryFailed).toHaveBeenCalledTimes(1);
  });

  it('calls onRecoveryFailed when verifyOtp THROWS for a recovery link', async () => {
    const d = deps({ verifyOtp: vi.fn(async () => { throw new Error('network'); }) });
    await dispatchDeepLink(OTP_URL, d);
    expect(d.onRecoveryFailed).toHaveBeenCalledTimes(1);
  });

  it('releases the hold for a recovery link that carries no token at all', async () => {
    const d = deps();
    const out = await dispatchDeepLink('snatchit://auth?type=recovery', d);
    expect(out).toEqual({ kind: 'no_auth_params' });
    expect(d.onRecovery).toHaveBeenCalledTimes(1);
    expect(d.onRecoveryFailed).toHaveBeenCalledTimes(1);
    expect(d.verifyOtp).not.toHaveBeenCalled();
  });

  it('does not call onRecoveryFailed on success, nor for a non-recovery link that fails', async () => {
    const ok = deps();
    await dispatchDeepLink(OTP_URL, ok);
    expect(ok.onRecoveryFailed).not.toHaveBeenCalled();
    const signupFail = deps({ verifyOtp: vi.fn(async () => ({ error: { message: 'Token has expired' } })) });
    await dispatchDeepLink('snatchit://auth?token_hash=abc&type=signup', signupFail);
    expect(signupFail.onRecovery).not.toHaveBeenCalled();
    expect(signupFail.onRecoveryFailed).not.toHaveBeenCalled();
  });
});

describe('(a) a Stripe return URL', () => {
  it('reaches handleURLCallback first; when consumed, no auth exchange and no navigation side effect', async () => {
    const d = deps({ stripeCallback: vi.fn(async () => true) });
    const out = await dispatchDeepLink(STRIPE_URL, d);
    expect(out).toEqual({ kind: 'stripe' });
    expect(d.stripeCallback).toHaveBeenCalledWith(STRIPE_URL);
    expect(d.verifyOtp).not.toHaveBeenCalled();
    expect(d.exchangeCodeForSession).not.toHaveBeenCalled();
    expect(d.onRecovery).not.toHaveBeenCalled();
  });

  it('is asked BEFORE any auth parsing (call order)', async () => {
    const order: string[] = [];
    const d = deps({
      stripeCallback: vi.fn(async () => { order.push('stripe'); return false; }),
      exchangeCodeForSession: vi.fn(async () => { order.push('pkce'); return { error: null }; }),
    });
    await dispatchDeepLink(PKCE_URL, d);
    expect(order).toEqual(['stripe', 'pkce']);
  });
});

describe('(b) auth deep links still run exactly as today', () => {
  it('token_hash + type → verifyOtp, recovery routing raised, Stripe asked but not consumed', async () => {
    const d = deps();
    const out = await dispatchDeepLink(OTP_URL, d);
    expect(d.stripeCallback).toHaveBeenCalledTimes(1);
    expect(d.onRecovery).toHaveBeenCalledTimes(1);
    expect(d.verifyOtp).toHaveBeenCalledWith({ type: 'recovery', token_hash: 'abc123' });
    expect(d.exchangeCodeForSession).not.toHaveBeenCalled();
    expect(out).toEqual({ kind: 'otp', type: 'recovery', error: null });
  });

  it('code → exchangeCodeForSession; no recovery routing for a non-recovery link', async () => {
    const d = deps();
    const out = await dispatchDeepLink(PKCE_URL, d);
    expect(d.exchangeCodeForSession).toHaveBeenCalledWith('pkce-code-1');
    expect(d.verifyOtp).not.toHaveBeenCalled();
    expect(d.onRecovery).not.toHaveBeenCalled();
    expect(out).toEqual({ kind: 'pkce', error: null });
  });

  it('parameters in the fragment are honoured, as before', async () => {
    const d = deps();
    await dispatchDeepLink('snatchit://auth#token_hash=frag&type=signup', d);
    expect(d.verifyOtp).toHaveBeenCalledWith({ type: 'signup', token_hash: 'frag' });
  });

  it('a link with no auth params and not consumed by Stripe does nothing', async () => {
    const d = deps();
    expect(await dispatchDeepLink('snatchit://checkout/abc', d)).toEqual({ kind: 'no_auth_params' });
    expect(d.verifyOtp).not.toHaveBeenCalled();
    expect(d.exchangeCodeForSession).not.toHaveBeenCalled();
  });

  it('provider errors are surfaced as warnings, never thrown, never as a fake session', async () => {
    const d = deps({ verifyOtp: vi.fn(async () => ({ error: { message: 'Token has expired' } })) });
    const out = await dispatchDeepLink(OTP_URL, d);
    expect(out).toEqual({ kind: 'otp', type: 'recovery', error: 'Token has expired' });
    expect(d.warn).toHaveBeenCalledWith('[auth] verifyOtp error:', 'Token has expired');
  });
});

describe('(c) both entry points reach the same dispatch', () => {
  it('the initial URL (cold start) and the url event (warm) both call dispatch once', async () => {
    const dispatch = vi.fn();
    let listener: ((ev: { url: string }) => void) | null = null;
    const remove = vi.fn();
    const linking = {
      getInitialURL: vi.fn(async () => STRIPE_URL),
      addEventListener: vi.fn((_t: 'url', l: (ev: { url: string }) => void) => { listener = l; return { remove }; }),
    };
    const teardown = attachDeepLinkFunnel(linking, dispatch);
    await Promise.resolve(); await Promise.resolve();
    expect(dispatch).toHaveBeenCalledWith(STRIPE_URL);          // cold start
    listener!({ url: OTP_URL });
    expect(dispatch).toHaveBeenCalledWith(OTP_URL);             // warm
    expect(dispatch).toHaveBeenCalledTimes(2);
    teardown();
    expect(remove).toHaveBeenCalledTimes(1);
  });

  it('a null initial URL dispatches nothing', async () => {
    const dispatch = vi.fn();
    attachDeepLinkFunnel({ getInitialURL: async () => null, addEventListener: () => ({ remove() {} }) }, dispatch);
    await Promise.resolve(); await Promise.resolve();
    expect(dispatch).not.toHaveBeenCalled();
  });
});

describe('(d) a handleURLCallback rejection does not break the auth path', () => {
  it('auth exchange still runs after Stripe throws', async () => {
    const d = deps({ stripeCallback: vi.fn(async () => { throw new Error('native module missing'); }) });
    const out = await dispatchDeepLink(PKCE_URL, d);
    expect(d.exchangeCodeForSession).toHaveBeenCalledWith('pkce-code-1');
    expect(out).toEqual({ kind: 'pkce', error: null });
    expect(d.warn).toHaveBeenCalledWith(expect.stringContaining('stripe callback threw'), expect.any(Error));
  });
});

describe('(a3) F7: the shell wires the release to the same state the hold raised', () => {
  it('NativeAppShell passes onRecoveryFailed, and it lowers isRecovery', async () => {
    const { readFileSync } = await import('node:fs');
    const { resolve } = await import('node:path');
    const shell = readFileSync(resolve(__dirname, '..', 'src/providers/NativeAppShell.native.tsx'), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(shell).toContain('onRecovery: () => { setIsRecovery(true);');
    expect(shell).toContain('onRecoveryFailed: () => setIsRecovery(false)');
  });
});
