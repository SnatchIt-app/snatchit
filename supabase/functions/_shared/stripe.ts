/**
 * supabase/functions/_shared/stripe.ts — shared Stripe REST client
 *
 * Single source of truth for:
 *   • the Stripe API version pinned server-side
 *   • the Authorization header (reads STRIPE_SECRET_KEY from env)
 *   • the urlencoded body shape Stripe expects
 *   • the standard error surface our edge functions consume
 *
 * Why pin a version:
 *   Stripe rotates the account-level "default" API version periodically.
 *   Code written against the account default silently inherits behavior
 *   changes (field renames, response-shape diffs) on every rotation.
 *   Pinning makes upgrades intentional: bump the constant + ship, never
 *   surprise-broken at 3am because Stripe shipped a new default.
 *
 * The two versions we use:
 *   STRIPE_API_VERSION         — server-default for PaymentIntent, Refund,
 *                                Transfer, Account, Customer endpoints.
 *                                Conservative recent stable.
 *   STRIPE_MOBILE_API_VERSION  — REQUIRED for ephemeral_keys (must match
 *                                the iOS/Android SDK's bundled version,
 *                                otherwise PaymentSheet can't decode the
 *                                returned secret).
 *
 * Bumping STRIPE_API_VERSION later is intentional:
 *   1. Read https://docs.stripe.com/upgrades for the target version.
 *   2. Update STRIPE_API_VERSION here, redeploy all functions.
 *   3. Run the test checklist in the latest "Pin Stripe API version" doc.
 */

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')!;

export const STRIPE_API_VERSION        = '2024-09-30.acacia';
export const STRIPE_MOBILE_API_VERSION = '2024-04-10';

type StripeFetchInit = {
  method?:        'GET' | 'POST' | 'DELETE';
  /** Form-encoded body: pass a Record, the helper URL-encodes it. */
  body?:          Record<string, string>;
  /** Optional version override. Used by ephemeral_keys only. */
  stripeVersion?: string;
  /** Optional idempotency key for POSTs. Stripe semantics. */
  idempotencyKey?: string;
};

export type StripeError = {
  type?:    string;
  code?:    string;
  message?: string;
};

/**
 * Fetch wrapper around api.stripe.com. Returns the parsed JSON body on
 * 2xx, or throws an Error whose `.message` is Stripe's `error.message`
 * (or a status-code fallback). All call sites should `await` it inside
 * a try/catch and let the outer captureException pick up real failures.
 */
export async function stripeFetch<T = unknown>(
  path: string,
  init: StripeFetchInit = {},
): Promise<T> {
  const url = `https://api.stripe.com/v1${path.startsWith('/') ? path : `/${path}`}`;
  const headers: Record<string, string> = {
    Authorization:    `Bearer ${STRIPE_SECRET_KEY}`,
    'Stripe-Version': init.stripeVersion ?? STRIPE_API_VERSION,
  };
  let body: string | undefined;
  if (init.body) {
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    body = new URLSearchParams(init.body).toString();
  }
  if (init.idempotencyKey) {
    headers['Idempotency-Key'] = init.idempotencyKey;
  }
  const res  = await fetch(url, { method: init.method ?? (init.body ? 'POST' : 'GET'), headers, body });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = (data as { error?: StripeError }).error;
    throw new Error(err?.message ?? `Stripe ${init.method ?? 'GET'} ${path} → ${res.status}`);
  }
  return data as T;
}

/**
 * Variant that returns a partial result on non-2xx instead of throwing.
 * Useful for "does this customer still exist?" probes where 404 is
 * meaningful, not an error.
 */
export async function stripeFetchRaw(
  path: string,
  init: StripeFetchInit = {},
): Promise<{ ok: boolean; status: number; data: unknown }> {
  const url = `https://api.stripe.com/v1${path.startsWith('/') ? path : `/${path}`}`;
  const headers: Record<string, string> = {
    Authorization:    `Bearer ${STRIPE_SECRET_KEY}`,
    'Stripe-Version': init.stripeVersion ?? STRIPE_API_VERSION,
  };
  let body: string | undefined;
  if (init.body) {
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    body = new URLSearchParams(init.body).toString();
  }
  if (init.idempotencyKey) headers['Idempotency-Key'] = init.idempotencyKey;
  const res  = await fetch(url, { method: init.method ?? (init.body ? 'POST' : 'GET'), headers, body });
  const data = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, data };
}
