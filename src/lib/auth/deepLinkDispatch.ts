/**
 * src/lib/auth/deepLinkDispatch.ts — every incoming URL goes through here.
 *
 * Pure orchestration with injected effects, so the rule is tested as
 * behaviour. NativeAppShell supplies the real Stripe and Supabase calls.
 *
 * ORDER (D5 acceptance failure, build 15). After a 3-D Secure challenge iOS
 * reopens the app at the checkout return URL, but the Stripe SDK only dismisses
 * its browser and resolves the PaymentSheet when the app hands that URL back via
 * `handleURLCallback`. Nothing did, so the browser sat on the completed page
 * until the buyer exited it by hand. The Stripe callback is therefore asked
 * FIRST; `true` means Stripe consumed the URL and nothing else runs — the auth
 * branch must never parse a Stripe redirect looking for token_hash/code. On
 * Android the SDK returns `false`, so the auth path is unchanged there.
 *
 * ONE FUNNEL. `attachDeepLinkFunnel` routes BOTH `getInitialURL()` (cold start:
 * iOS killed the app behind the browser and the return arrives as the launch
 * URL) and the 'url' event (warm return) through the same dispatch.
 *
 * The auth branch is the pre-existing H-5 contract, unchanged: only
 * `verifyOtp({ token_hash, type })` and `exchangeCodeForSession(code)` may mint
 * a session; there is no setSession-from-URL path and none may be added.
 */

import { exchangeWasRecovery } from './recoveryClaim';

export type EmailOtpType = 'recovery' | 'signup' | 'email' | 'magiclink' | 'invite' | 'email_change';

export interface DeepLinkDeps {
  /** Stripe SDK: true when it consumed the URL (iOS 3DS/redirect return). */
  stripeCallback(url: string): Promise<boolean>;
  verifyOtp(input: { type: EmailOtpType; token_hash: string }): Promise<{ error: { message: string } | null }>;
  exchangeCodeForSession(code: string): Promise<{ data?: unknown; error: { message: string } | null }>;
  /**
   * N7: whether the code waiting on THIS installation came from a password-recovery request
   * (recoveryClaim.pendingCodeIsRecovery). GoTrue's PKCE recovery redirect is `snatchit://?code=…` with
   * no `type`, so without this a recovery link exchanges into a plain sign-in and the root route goes Home.
   */
  isRecoveryCode?(): Promise<boolean>;
  /**
   * Review T6: a code or token_hash is single-use, so only its first claim may act. Returns false when the
   * key was already claimed in this process; the dispatch then ignores the link (and leaves the hold alone).
   */
  claimOnce?(key: string): boolean;
  /** Raise the recovery hold; the root layout moves to the reset screen once its navigator is ready. */
  onRecovery(): void;
  /**
   * Release the hold `onRecovery` raised, because the link's claim did not hold up: the token was
   * rejected (expired, or consumed by a link pre-scanner — AGENTS.md records those), the exchange
   * threw, or the link carried no token at all. Without this the root route holds on `isRecovery`
   * with no session, reset-password's updateUser fails "Auth session missing!", and only SIGNED_OUT
   * or a relaunch clears it (F7).
   */
  onRecoveryFailed?(): void;
  warn?: (message: string, ...rest: unknown[]) => void;
}

export type DeepLinkOutcome =
  | { kind: 'ignored' }
  | { kind: 'stripe' }
  | { kind: 'otp'; type: EmailOtpType; error: string | null }
  | { kind: 'pkce'; error: string | null }
  | { kind: 'no_auth_params' };

export function parseDeepLink(url: string): Record<string, string | null> & { get(k: string): string | null } {
  // Parse BOTH the query string and the fragment; treat all as untrusted.
  const queryStr = url.includes('?') ? url.split('?')[1].split('#')[0] : '';
  const hashStr = url.includes('#') ? url.split('#')[1] : '';
  const qp = new URLSearchParams(queryStr);
  const hp = new URLSearchParams(hashStr);
  const get = (k: string) => qp.get(k) ?? hp.get(k);
  return { get } as Record<string, string | null> & { get(k: string): string | null };
}

export async function dispatchDeepLink(url: string | null | undefined, deps: DeepLinkDeps): Promise<DeepLinkOutcome> {
  const warn = deps.warn ?? ((m: string, ...r: unknown[]) => console.warn(m, ...r));
  if (!url) return { kind: 'ignored' };

  // 1. Stripe first. A rejection here must not take the auth path down with it.
  try {
    if (await deps.stripeCallback(url)) return { kind: 'stripe' };
  } catch (e) {
    warn('[deep-link] stripe callback threw; continuing to auth handling', e);
  }

  // 2. Auth links — unchanged contract.
  const p = parseDeepLink(url);
  const type = p.get('type');
  const code = p.get('code');
  const token_hash = p.get('token_hash');
  const errParam = p.get('error') ?? p.get('error_code');
  if (errParam) warn('[auth] deep-link error:', errParam, p.get('error_description') ?? '');

  // Review T6: an overlapping second delivery of the same single-use link must not act — its exchange would
  // fail on the consumed verifier and release a hold the first one's session needs.
  const authKey = token_hash && type ? `otp:${token_hash}` : code ? `code:${code}` : null;
  if (authKey && deps.claimOnce && !deps.claimOnce(authKey)) return { kind: 'ignored' };

  // Raise the recovery hold for recovery links. The session is established
  // below, never by trusting tokens in the URL. The hold goes up first so the
  // session that follows is held for the reset screen instead of routed Home.
  // The hold is raised on the link's CLAIM; if the claim fails below, it is released again (F7).
  // A throw from the hold (a cold-start navigation before the navigator mounts) must never skip the
  // exchange, so it is caught here.
  let recoveryRaised = false;
  const raiseRecovery = () => {
    if (recoveryRaised) return;
    recoveryRaised = true;
    try { deps.onRecovery(); } catch (e) { warn('[auth] recovery hold threw; continuing with the link', e); }
  };
  if (type === 'recovery') raiseRecovery();
  const releaseRecovery = () => { if (recoveryRaised) deps.onRecoveryFailed?.(); };

  try {
    if (token_hash && type) {
      const { error } = await deps.verifyOtp({ type: type as EmailOtpType, token_hash });
      if (error) {
        warn('[auth] verifyOtp error:', error.message);
        releaseRecovery();
      }
      return { kind: 'otp', type: type as EmailOtpType, error: error?.message ?? null };
    }
    if (code) {
      // N7: the PKCE recovery redirect carries no type; this installation's stored verifier does.
      if (!recoveryRaised && deps.isRecoveryCode) {
        let claimed = false;
        try { claimed = await deps.isRecoveryCode(); } catch { claimed = false; }
        if (claimed) raiseRecovery();
      }
      const { data, error } = await deps.exchangeCodeForSession(code);
      if (error) {
        warn('[auth] exchangeCodeForSession error:', error.message);
        releaseRecovery();
      } else if (exchangeWasRecovery(data)) {
        // Late fallback: the stored claim was unreadable but auth-js reports a recovery exchange.
        raiseRecovery();
      }
      return { kind: 'pkce', error: error?.message ?? null };
    }
  } catch (e) {
    warn('[auth] deep-link session exchange failed:', e);
    releaseRecovery();
    return { kind: 'no_auth_params' };
  }
  // A recovery link with nothing to verify is a claim with no credential: do not hold on it.
  releaseRecovery();
  return { kind: 'no_auth_params' };
}

export interface LinkingLike {
  getInitialURL(): Promise<string | null>;
  addEventListener(type: 'url', listener: (ev: { url: string }) => void): { remove(): void };
}

/** Both entry points, one dispatch. Returns the teardown. */
export function attachDeepLinkFunnel(linking: LinkingLike, dispatch: (url: string) => void): () => void {
  linking.getInitialURL().then((url) => { if (url) dispatch(url); });
  const sub = linking.addEventListener('url', ({ url }) => dispatch(url));
  return () => sub.remove();
}

/** Process-wide single-claim memory for auth link parameters (review T6). */
const claimedAuthParams = new Set<string>();
export function claimAuthParamOnce(key: string): boolean {
  if (claimedAuthParams.has(key)) return false;
  claimedAuthParams.add(key);
  return true;
}
