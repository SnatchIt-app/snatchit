/**
 * useFrozenCheckoutParams.ts — the checkout screen's route params are read ONCE, at mount (F4).
 *
 * The 3-D Secure web view returns through the returnURL, and expo-router's own Linking
 * subscription dispatches NAVIGATE to checkout/[id] with whatever the URL carries. StackClient's
 * singular-id match reuses the same route key and REPLACES its params in place — no push, no
 * remount. With the old bare returnURL that replacement dropped mode, totalCents, bidAmount,
 * eventName and venue mid-settlement: isBuyNow flipped to false, the countdown and the Pay
 * withdrawal vanished, the breakdown said "Winning bid", the confirmation showed the auction face,
 * and later Pay/recheck actions routed to the auction handlers. (A's independent reviewer,
 * 2026-10-12: warm return confirmed and the common case.)
 *
 * The returnURL now carries the context (checkoutMode.ts), AND the screen no longer trusts a
 * later param replacement at all: whatever the route said when the screen mounted is what the
 * screen is about until it unmounts. A later replacement cannot change the mode or the figures.
 *
 * Nothing here is logged, reported or read beyond the five named fields — Stripe may append
 * payment_intent / payment_intent_client_secret to the return URL, and those must never be read
 * or recorded by this screen.
 */
import { useState } from 'react';

export interface CheckoutRouteParamsRaw {
  id?: string | string[];
  mode?: string | string[];
  bidAmount?: string | string[];
  totalCents?: string | string[];
  eventName?: string | string[];
  venue?: string | string[];
}

export interface FrozenCheckoutParams {
  id: string | undefined;
  mode: string | undefined;
  bidAmount: string | undefined;
  totalCents: string | undefined;
  eventName: string | undefined;
  venue: string | undefined;
}

const first = (v: string | string[] | undefined): string | undefined => (Array.isArray(v) ? v[0] : v);

/** Pure: the five fields the screen reads, and nothing else from the URL. */
export function freezeCheckoutParams(raw: CheckoutRouteParamsRaw): FrozenCheckoutParams {
  return {
    id: first(raw.id),
    mode: first(raw.mode),
    bidAmount: first(raw.bidAmount),
    totalCents: first(raw.totalCents),
    eventName: first(raw.eventName),
    venue: first(raw.venue),
  };
}

/** The params as they were at mount. A later replacement of the route's params is ignored. */
export function useFrozenCheckoutParams(raw: CheckoutRouteParamsRaw): FrozenCheckoutParams {
  const [frozen] = useState(() => freezeCheckoutParams(raw));
  return frozen;
}
