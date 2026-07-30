"use client";

import { useEffect, useState } from "react";
import { loadStripe } from "@stripe/stripe-js";
import { Elements } from "@stripe/react-stripe-js";
import { createPaymentIntentAction } from "@/lib/checkout-actions";
import { STRIPE_PUBLISHABLE_KEY } from "@/lib/env";
import { PriceBreakdown } from "@/components/ui/PriceDisplay";
import { Alert } from "@/components/ui/Alert";
import { PaymentForm } from "@/components/checkout/PaymentForm";

const stripePromise = STRIPE_PUBLISHABLE_KEY ? loadStripe(STRIPE_PUBLISHABLE_KEY) : null;

export function CheckoutClient({
  listingId,
  eventName,
  venue,
  buyNowPriceDollars,
}: {
  listingId: string;
  eventName: string;
  venue: string;
  buyNowPriceDollars: number;
}) {
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    createPaymentIntentAction(listingId).then((res) => {
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
  }, [listingId]);

  return (
    <div className="mt-7 space-y-6">
      <section className="border border-primary/20 bg-card p-6">
        <p className="eyebrow text-primary/80">Order summary</p>
        <dl className="mt-4 space-y-2 text-[13.5px]">
          <div className="flex justify-between gap-4">
            <dt className="text-muted">Event</dt>
            <dd className="text-right font-semibold text-ink">{eventName}</dd>
          </div>
          <div className="flex justify-between gap-4">
            <dt className="text-muted">Venue</dt>
            <dd className="text-right font-semibold text-ink">{venue}</dd>
          </div>
        </dl>
        <div className="mt-4 border-t border-primary/15 pt-4">
          <PriceBreakdown baseDollars={buyNowPriceDollars} />
        </div>
      </section>

      <section className="border border-primary/20 bg-card p-6">
        <p className="eyebrow text-primary/80">Payment</p>
        <div className="mt-4">
          {error ? (
            <Alert tone="error">{error}</Alert>
          ) : !clientSecret || !stripePromise ? (
            <p className="text-[13.5px] text-white/50">
              {stripePromise ? "Preparing secure payment…" : "Payment is not configured."}
            </p>
          ) : (
            <Elements stripe={stripePromise} options={{ clientSecret }}>
              <PaymentForm listingId={listingId} />
            </Elements>
          )}
        </div>
        <p className="mt-4 text-center text-[11.5px] leading-relaxed text-white/35">
          Payments are secure and encrypted via Stripe. Your card details never touch Snatch It.
        </p>
      </section>
    </div>
  );
}
