"use client";

import { useEffect, useRef, useState } from "react";
import { Elements, PaymentElement, useElements, useStripe } from "@stripe/react-stripe-js";
import { loadStripe } from "@stripe/stripe-js";
import { Alert } from "@/components/ui/Alert";
import { Button } from "@/components/ui/Button";
import { STRIPE_PUBLISHABLE_KEY, SITE_URL } from "@/lib/env";
import { startPrivatePilotCheckout } from "@/lib/private-pilot-actions";

const stripePromise = STRIPE_PUBLISHABLE_KEY ? loadStripe(STRIPE_PUBLISHABLE_KEY) : null;

function PaymentStatus() {
  return <p role="status">Check Tickets in the Snatch It app for your confirmed ticket.</p>;
}

function CardForm({ sessionId }: { sessionId: string }) {
  const stripe = useStripe();
  const elements = useElements();
  const pending = useRef(false);
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState<string>();

  async function pay(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!stripe || !elements || pending.current) return;
    pending.current = true;
    setSubmitting(true);
    setError(undefined);
    try {
      const result = await stripe.confirmPayment({
        elements,
        confirmParams: { return_url: `${SITE_URL}/primary-pilot/${sessionId}?payment=return` },
        redirect: "if_required",
      });
      if (result.error) setError(result.error.message ?? "Payment could not be submitted.");
      else if (result.paymentIntent?.status === "succeeded" || result.paymentIntent?.status === "processing") {
        setSubmitted(true);
      } else {
        setError("Payment could not be verified. Check Tickets before retrying.");
      }
    } catch {
      setError("Payment could not be verified. Check Tickets before retrying.");
    } finally {
      pending.current = false;
      setSubmitting(false);
    }
  }

  if (submitted) return <PaymentStatus />;
  return (
    <form className="space-y-4" onSubmit={pay}>
      {error && <Alert tone="error">{error}</Alert>}
      <PaymentElement />
      <Button type="submit" disabled={!stripe || !elements || submitting}>
        {submitting ? "Submitting…" : "Pay"}
      </Button>
    </form>
  );
}

export function PilotPayment({
  sessionId,
  totalMinor,
  returning,
}: {
  sessionId: string;
  totalMinor: number;
  returning: boolean;
}) {
  const pending = useRef(false);
  const [loading, setLoading] = useState(false);
  const [clientSecret, setClientSecret] = useState<string>();
  const [error, setError] = useState<string>();

  useEffect(() => {
    if (returning) {
      window.history.replaceState(null, "", `/primary-pilot/${sessionId}?payment=return`);
    }
  }, [returning, sessionId]);

  async function begin() {
    if (!stripePromise || pending.current) return;
    pending.current = true;
    setLoading(true);
    setError(undefined);
    try {
      const storageKey = `snatchit:private-pilot:${sessionId}`;
      const attempt = sessionStorage.getItem(storageKey) ?? crypto.randomUUID();
      sessionStorage.setItem(storageKey, attempt);
      const result = await startPrivatePilotCheckout(sessionId, attempt, totalMinor);
      if ("error" in result) {
        if (result.expired) sessionStorage.removeItem(storageKey);
        setError(result.error);
      } else {
        setClientSecret(result.clientSecret);
      }
    } catch {
      setError("Checkout is temporarily unavailable. Try again from this page.");
    } finally {
      pending.current = false;
      setLoading(false);
    }
  }

  if (returning) return <PaymentStatus />;
  if (!stripePromise) return <Alert tone="error">Payment is unavailable.</Alert>;
  if (clientSecret) {
    return (
      <Elements stripe={stripePromise} options={{ clientSecret }}>
        <CardForm sessionId={sessionId} />
      </Elements>
    );
  }

  return (
    <div className="space-y-4">
      {error && <Alert tone="error">{error}</Alert>}
      <Button type="button" onClick={begin} disabled={loading}>
        {loading ? "Preparing payment…" : "Continue to payment"}
      </Button>
    </div>
  );
}
