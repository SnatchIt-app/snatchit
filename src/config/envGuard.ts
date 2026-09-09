/**
 * src/config/envGuard.ts — environment pairing guard (fail fast, fail closed).
 *
 * WHY: `EXPO_PUBLIC_*` values are inlined into the bundle at build time, so the
 * environment a binary talks to is fixed at compile time and cannot be flipped
 * later. A build that pairs the WRONG Supabase project with the WRONG Stripe
 * account is therefore a permanent, silent hazard — e.g. a Stripe TEST key
 * against the PRODUCTION database, or live keys against a sandbox database.
 * This module turns every such pairing into a refusal.
 *
 * WHERE: imported as the FIRST import of `src/lib/supabase.ts`, which is the
 * deepest common ancestor of every network path (auth, payments, edge
 * functions, storage, realtime). Placing it only in `app/_layout.tsx` is too
 * late: import evaluation constructs the Supabase client before the layout body
 * runs.
 *
 * HOW IT SURFACES: never a module-load throw in a release build (that produces
 * an instant iOS launch crash with no diagnostics — see the note in
 * `src/lib/supabase.ts`). Instead:
 *   - `__DEV__`: throws, so the mistake is loud in the dev loop and in tests.
 *   - otherwise: exports ENV_GUARD_FAILURE, which makes `src/lib/supabase.ts`
 *     construct the client against an unroutable host and makes
 *     `app/_layout.tsx` render a non-dismissible blocking screen.
 */

/** Supabase project refs this app is allowed to talk to. */
const SANDBOX_REF = 'ofaidukbieeekqaboscm';
const PROD_REF = 'hqycwntpfoztoinemqns';

/**
 * Stripe account fragments. A publishable key embeds its account id, so this
 * catches "right mode, wrong account" — e.g. the test key of the LIVE account
 * pointed at the sandbox project.
 */
const SANDBOX_ACCT_FRAGMENT = '51T6Fb1'; // acct_1T6Fb1GlD5aqtxIw (Stripe Sandbox)
const LIVE_ACCT_FRAGMENT = '51T6Far'; // acct_1T6FarGdOzCmGbHw (live account)

/**
 * The PaymentSheet return URL and the deep-link scheme are literals elsewhere in
 * the app; restating them here makes an edit to either one fail the guard
 * instead of silently breaking the 3DS round trip.
 */
export const EXPECTED_RETURN_URL = 'snatchit://checkout';
export const EXPECTED_URL_SCHEME = 'snatchit';

export type EnvVerdict = {
  appEnv: string;
  host: string;
  isSandboxHost: boolean;
  isProdHost: boolean;
  isTestKey: boolean;
  isLiveKey: boolean;
  keyAccount: string;
  failure: string | null;
};

export function evaluateEnv(input: {
  appEnv?: string;
  supabaseUrl?: string;
  publishableKey?: string;
  returnUrl?: string;
  urlScheme?: string;
}): EnvVerdict {
  const appEnv = input.appEnv ?? 'production';
  const url = input.supabaseUrl ?? '';
  const pk = input.publishableKey ?? '';
  const returnUrl = input.returnUrl ?? EXPECTED_RETURN_URL;
  const urlScheme = input.urlScheme ?? EXPECTED_URL_SCHEME;

  const host = url.replace(/^https?:\/\//, '').split('/')[0];
  const isSandboxHost = host === `${SANDBOX_REF}.supabase.co`;
  const isProdHost = host === `${PROD_REF}.supabase.co`;
  const isTestKey = pk.startsWith('pk_test_');
  const isLiveKey = pk.startsWith('pk_live_');
  const keyAccount = pk.replace(/^pk_(test|live)_/, '').slice(0, 7);

  const fail = (code: string, detail: string) =>
    `[SnatchIt env guard] ${code}: ${detail}\n` +
    `  APP_ENV=${appEnv} host=${host || '<unset>'} stripe=${
      isLiveKey ? 'pk_live' : isTestKey ? 'pk_test' : '<unset>'
    }:${keyAccount || '<none>'}`;

  // F6 — nothing resolved. Without this the app boots against placeholders.
  if (!host || !pk) {
    return verdict(fail('F6', 'Supabase URL or Stripe publishable key is unset'));
  }
  // F3 — live money against a sandbox database.
  if (isSandboxHost && isLiveKey) {
    return verdict(fail('F3', 'LIVE Stripe key paired with the SANDBOX database'));
  }
  // F4 — a test key against production data (silent breakage + prod data access).
  if (isProdHost && isTestKey) {
    return verdict(fail('F4', 'TEST Stripe key paired with the PRODUCTION database'));
  }
  // F5 — right mode, wrong Stripe account.
  if (isSandboxHost && keyAccount !== SANDBOX_ACCT_FRAGMENT) {
    return verdict(fail('F5', 'Stripe key does not belong to the sandbox account'));
  }
  if (isProdHost && keyAccount !== LIVE_ACCT_FRAGMENT) {
    return verdict(fail('F5', 'Stripe key does not belong to the production account'));
  }
  // F7 — an unknown host is never acceptable for a money app.
  if (!isSandboxHost && !isProdHost) {
    return verdict(fail('F7', 'Supabase host is neither the sandbox nor the production project'));
  }
  // F1 — a build labelled sandbox that points anywhere else.
  if (appEnv === 'sandbox' && !(isSandboxHost && isTestKey)) {
    return verdict(fail('F1', 'APP_ENV=sandbox but the target is not the sandbox pair'));
  }
  // F2 — inverse guard: a production build must be production+live.
  if (appEnv === 'production' && !(isProdHost && isLiveKey)) {
    return verdict(fail('F2', 'APP_ENV=production but the target is not the production pair'));
  }
  // F8 — the deep-link contract the 3DS round trip depends on.
  if (returnUrl !== EXPECTED_RETURN_URL || urlScheme !== EXPECTED_URL_SCHEME) {
    return verdict(fail('F8', 'PaymentSheet return URL / scheme no longer match the guard'));
  }
  return verdict(null);

  function verdict(failure: string | null): EnvVerdict {
    return { appEnv, host, isSandboxHost, isProdHost, isTestKey, isLiveKey, keyAccount, failure };
  }
}

export const ENV_VERDICT: EnvVerdict = evaluateEnv({
  appEnv: process.env.EXPO_PUBLIC_APP_ENV,
  supabaseUrl: process.env.EXPO_PUBLIC_SUPABASE_URL,
  publishableKey: process.env.EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY,
});

export const ENV_GUARD_FAILURE: string | null = ENV_VERDICT.failure;

/** True only for a correctly paired sandbox build (used for the on-screen badge). */
export const IS_SANDBOX_BUILD =
  ENV_VERDICT.failure === null && ENV_VERDICT.appEnv === 'sandbox' && ENV_VERDICT.isSandboxHost;

declare const __DEV__: boolean | undefined;

if (ENV_GUARD_FAILURE) {
  // Loud in development and in unit tests; a release build shows the blocking
  // screen instead (see app/_layout.tsx) because a module-load throw crashes
  // iOS before React mounts.
  console.error(ENV_GUARD_FAILURE);
  if (typeof __DEV__ !== 'undefined' && __DEV__) {
    throw new Error(ENV_GUARD_FAILURE);
  }
}
