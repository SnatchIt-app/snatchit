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

export type EmailOtpType = 'recovery' | 'signup' | 'email' | 'magiclink' | 'invite' | 'email_change';

export interface DeepLinkDeps {
  /** Stripe SDK: true when it consumed the URL (iOS 3DS/redirect return). */
  stripeCallback(url: string): Promise<boolean>;
  verifyOtp(input: { type: EmailOtpType; token_hash: string }): Promise<{ error: { message: string } | null }>;
  exchangeCodeForSession(code: string): Promise<{ error: { message: string } | null }>;
  /** Route to the reset screen and raise the recovery hold. */
  onRecovery(): void;
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

  // Route to the reset screen for recovery links. The session is established
  // below, never by trusting tokens in the URL. Routing first shows the UI.
  if (type === 'recovery') deps.onRecovery();

  try {
    if (token_hash && type) {
      const { error } = await deps.verifyOtp({ type: type as EmailOtpType, token_hash });
      if (error) warn('[auth] verifyOtp error:', error.message);
      return { kind: 'otp', type: type as EmailOtpType, error: error?.message ?? null };
    }
    if (code) {
      const { error } = await deps.exchangeCodeForSession(code);
      if (error) warn('[auth] exchangeCodeForSession error:', error.message);
      return { kind: 'pkce', error: error?.message ?? null };
    }
  } catch (e) {
    warn('[auth] deep-link session exchange failed:', e);
  }
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
