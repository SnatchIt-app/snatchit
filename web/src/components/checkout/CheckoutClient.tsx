"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import { loadStripe, type Appearance } from "@stripe/stripe-js";
import { Elements } from "@stripe/react-stripe-js";
import { createPaymentIntentAction } from "@/lib/checkout-actions";
import type { CheckoutMode } from "@/lib/checkout";
import { STRIPE_PUBLISHABLE_KEY } from "@/lib/env";
import { PriceBreakdown } from "@/components/ui/PriceDisplay";
import { Alert } from "@/components/ui/Alert";
import { Icon } from "@/components/ui/Icon";
import { Spinner } from "@/components/ui/Button";
import { coverImageUrl } from "@/lib/format";
import { PaymentForm } from "@/components/checkout/PaymentForm";
import { ProofWaiverNotice } from "@/components/listing/ProofWaiverNotice";

const stripePromise = STRIPE_PUBLISHABLE_KEY ? loadStripe(STRIPE_PUBLISHABLE_KEY) : null;

export function CheckoutClient({
  listingId,
  mode,
  eventName,
  venue,
  baseDollars,
  posterPath,
  when,
  tickets,
  proofWaived = false,
}: {
  listingId: string;
  /** Which entitlement the page authorized — decides the intent + settle RPC. */
  mode: CheckoutMode;
  eventName: string;
  venue: string;
  /** Base price in whole dollars: Buy Now price, or the winning bid. */
  baseDollars: number;
  /** Presentation only: the order identity row (native OrderIdentity). */
  posterPath?: string;
  when?: string;
  tickets?: string;
  /** Owner proof waiver (156): disclosed in the summary, before the payment form. */
  proofWaived?: boolean;
}) {
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    createPaymentIntentAction(listingId, mode).then((res) => {
      if (cancelled) return;
      if (res.error || !res.clientSecret) {
        setError(res.error ?? "Unable to set up payment. Please try again.");
        return;
      }
      setClientSecret(res.clientSecret);
    });
    return () => {
      cancelled = true;
    };
  }, [listingId, mode]);

  return (
    <div className="mt-7 grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] lg:gap-10">
      <section aria-labelledby="summary-title" className="h-fit rounded-card bg-surface p-5 sm:p-6">
        <h2 id="summary-title" className="t-label text-muted">
          Order summary
        </h2>
        <div className="mt-4 flex gap-4">
          {posterPath ? (
            <span className="poster relative block h-[90px] w-[72px] shrink-0 overflow-hidden rounded-media">
              <Image src={coverImageUrl(posterPath)} alt="" fill sizes="72px" className="object-contain" />
            </span>
          ) : null}
          <dl className="min-w-0">
            <dt className="sr-only">Event</dt>
            <dd className="t-name-order text-ink">{eventName}</dd>
            <dt className="sr-only">Venue</dt>
            <dd className="t-body-sm mt-1 text-muted">
              {when ? `${when} · ` : ""}
              {venue}
            </dd>
            {tickets ? <dd className="t-body-sm text-muted">{tickets}</dd> : null}
          </dl>
        </div>
        {proofWaived ? <ProofWaiverNotice className="mt-4" /> : null}
        <div className="mt-5 border-t border-line pt-1">
          <PriceBreakdown baseDollars={baseDollars} />
        </div>
      </section>

      <section aria-labelledby="payment-title" className="rounded-card border border-line p-5 sm:p-6">
        <h2 id="payment-title" className="t-label text-muted">
          Payment
        </h2>
        <div className="mt-4">
          {error ? (
            <Alert tone="error">{error}</Alert>
          ) : !clientSecret || !stripePromise ? (
            <p className="t-body flex items-center gap-2.5 text-muted" role="status">
              {stripePromise ? <Spinner /> : null}
              {stripePromise ? "Preparing secure payment…" : "Payment is not configured."}
            </p>
          ) : (
            <Elements stripe={stripePromise} options={{ clientSecret, appearance: stripeAppearance() }}>
              <PaymentForm listingId={listingId} mode={mode} />
            </Elements>
          )}
        </div>
        <p className="t-body-sm mt-5 flex items-start justify-center gap-2 text-center text-muted">
          <Icon name="lock" size={16} className="mt-px" />
          Payments are secure and encrypted via Stripe. Your card details never touch Snatch It.
        </p>
      </section>
    </div>
  );
}

/**
 * Stripe Payment Element in the page's resolved theme (Stripe's own "night"
 * or "stripe" base, brand red, the native control radius). Presentation only;
 * read once when the element mounts.
 */
function stripeAppearance(): Appearance {
  const root = document.documentElement;
  const dark =
    root.dataset.theme === "dark" ||
    (root.dataset.theme !== "light" && window.matchMedia("(prefers-color-scheme: dark)").matches);
  return {
    theme: dark ? "night" : "stripe",
    variables: { colorPrimary: "#ff1a1a", borderRadius: "10px", colorBackground: dark ? "#111111" : "#ffffff" },
  };
}
