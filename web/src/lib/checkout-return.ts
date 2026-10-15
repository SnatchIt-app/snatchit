import { safeInternalPath } from "@/lib/auth/redirect";
import type { CheckoutMode } from "@/lib/checkout";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PAYMENT_INTENT_RE = /^pi_[A-Za-z0-9]{8,64}$/;

/**
 * Where a buyer whose session ended mid-checkout logs in and comes back to: the complete page
 * with only what it needs (the PaymentIntent id, the status Stripe already reported, the mode).
 * Built from known fields, never by forwarding the query — Stripe's return URL also carries
 * payment_intent_client_secret, which must not travel into a login link, logs or a referrer.
 * Null when the inputs aren't what Stripe sends.
 */
export function checkoutLoginHref(listingId: string, paymentIntentId: string | null, mode: CheckoutMode): string | null {
  if (!UUID_RE.test(listingId) || !paymentIntentId || !PAYMENT_INTENT_RE.test(paymentIntentId)) return null;
  const complete = `/checkout/${listingId}/complete?payment_intent=${paymentIntentId}&redirect_status=succeeded&mode=${mode}`;
  const next = safeInternalPath(complete, "");
  return next ? `/login?next=${encodeURIComponent(next)}` : null;
}

export const CHECKOUT_SESSION_ENDED =
  "Your session ended before we could record this purchase. Log in to finish — you won't be charged again.";

/** finalizePurchaseAction's answer for a browser without a session (paid; nothing recorded yet). */
export function isSessionEnded(result: { error?: string | null } | null | undefined): boolean {
  return result?.error === "AUTH_REQUIRED";
}

/**
 * The complete page's query after Stripe's redirect, minus payment_intent_client_secret: only
 * payment_intent, redirect_status and mode survive, so the secret leaves the address bar and
 * history (and can't ride along in a Referer) once the page has read what it needs.
 */
export function keptReturnQuery(search: string): string {
  const src = new URLSearchParams(search);
  const kept = new URLSearchParams();
  for (const k of ["payment_intent", "redirect_status", "mode"]) {
    const v = src.get(k);
    if (v !== null) kept.set(k, v);
  }
  const s = kept.toString();
  return s ? `?${s}` : "";
}
