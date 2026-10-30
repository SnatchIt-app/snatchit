/**
 * src/config/envValue.ts — read an inlined EXPO_PUBLIC_ value safely.
 *
 * WHY THIS EXISTS (a real production incident, 2026-09-04):
 * `.env` had the Stripe publishable key wrapped in SMART quotes:
 *   EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY=‘pk_live_…’
 * dotenv strips a matching pair of STRAIGHT quotes (" or ') but not curly ones,
 * so the app booted with a literal `‘pk_live_…’`. It was non-empty, so the
 * existing empty-key guard never fired; the Stripe SDK then authenticated to
 * api.stripe.com with a malformed key and the failure surfaced only when the
 * payment sheet tried to load — as `kCFErrorDomainCFNetwork -1001` (timeout),
 * with no hint that the cause was configuration. Smart quotes arrive whenever a
 * key is pasted from a document, chat or notes app, so this is worth defending.
 *
 * `envValue` trims whitespace and one matching pair of wrapping quotes, straight
 * or curly. `looksLikeStripePublishableKey` lets the shell fail loudly and early
 * instead of hanging later.
 */

/** Straight and curly quote pairs that can end up wrapping a pasted value. */
const QUOTE_PAIRS: [string, string][] = [
  ['"', '"'],
  ["'", "'"],
  ['‘', '’'], // ‘ ’
  ['“', '”'], // “ ”
];

export function envValue(raw: string | undefined | null): string {
  let v = (raw ?? '').trim();
  // Strip repeatedly: a value can end up both quoted and re-quoted.
  let changed = true;
  while (changed && v.length >= 2) {
    changed = false;
    for (const [open, close] of QUOTE_PAIRS) {
      if (v.startsWith(open) && v.endsWith(close)) {
        v = v.slice(open.length, v.length - close.length).trim();
        changed = true;
        break;
      }
    }
  }
  return v;
}

/** Shape check only — never validates the key against Stripe. */
export function looksLikeStripePublishableKey(key: string): boolean {
  return /^pk_(test|live)_[A-Za-z0-9]+$/.test(key);
}

/** 'test' | 'live' | null — for developer diagnostics, never for logic. */
export function stripeKeyMode(key: string): 'test' | 'live' | null {
  if (key.startsWith('pk_live_')) return 'live';
  if (key.startsWith('pk_test_')) return 'test';
  return null;
}
