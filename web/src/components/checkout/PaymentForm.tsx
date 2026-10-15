"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { PaymentElement, useElements, useStripe } from "@stripe/react-stripe-js";
import { finalizePurchaseAction } from "@/lib/checkout-actions";
import type { CheckoutMode } from "@/lib/checkout";
import { SITE_URL } from "@/lib/env";
import { Button, LinkButton } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";
import { Icon } from "@/components/ui/Icon";
import { PAYMENT_STILL_PROCESSING } from "@/lib/checkout-wording";
import { CHECKOUT_SESSION_ENDED, checkoutLoginHref, isSessionEnded } from "@/lib/checkout-return";

export function PaymentForm({ listingId, mode }: { listingId: string; mode: CheckoutMode }) {
  const stripe = useStripe();
  const elements = useElements();
  const router = useRouter();

  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sold, setSold] = useState(false);
  const [transferId, setTransferId] = useState<string | null>(null);
  // Paid, but the session ended before finalize: log in and finish on the complete page.
  const [paidNeedsLogin, setPaidNeedsLogin] = useState(false);
  const [loginHref, setLoginHref] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!stripe || !elements || submitting) return;

    setSubmitting(true);
    setError(null);

    // redirect: 'if_required' keeps this a single-page flow for the common
    // case (US cards rarely need a redirect); Stripe still redirects to
    // return_url for payment methods that require it (e.g. certain 3DS
    // challenges), where /checkout/[id]/complete finishes the same
    // finalize step below. Stripe preserves return_url's existing query
    // string, so ?mode carries the entitlement across the redirect — without
    // it that page would settle an auction win with the Buy Now RPC.
    const { error: confirmError, paymentIntent } = await stripe.confirmPayment({
      elements,
      confirmParams: { return_url: `${SITE_URL}/checkout/${listingId}/complete?mode=${mode}` },
      redirect: "if_required",
    });

    if (confirmError) {
      setError(confirmError.message ?? "Payment failed. Please try again.");
      setSubmitting(false);
      return;
    }

    if (paymentIntent?.status !== "succeeded") {
      // processing / requires_action without a redirect — rare, but don't
      // claim success we haven't confirmed.
      setError(PAYMENT_STILL_PROCESSING);
      setSubmitting(false);
      return;
    }

    const result = await finalizePurchaseAction(listingId, paymentIntent.id, mode);
    if (isSessionEnded(result)) {
      // The card is charged; nothing is recorded yet. Never show the raw code.
      setError(CHECKOUT_SESSION_ENDED);
      setLoginHref(checkoutLoginHref(listingId, paymentIntent.id, mode));
      setPaidNeedsLogin(true);
      setSubmitting(false);
      return;
    }
    if (result.error) {
      // The server could not verify the payment with Stripe, so it deliberately
      // did not mark the listing sold or create a transfer. Never show
      // "Purchase complete!" here — that would be a claim we can't back.
      setError(result.error);
      setSubmitting(false);
      return;
    }
    if (result.warning) {
      setError(result.warning);
    }
    setTransferId(result.transferId);
    setSold(true);
    setSubmitting(false);
  }

  if (sold) {
    return (
      <div className="space-y-4 py-2 text-center" role="status">
        <span
          className={`mx-auto inline-flex size-14 items-center justify-center rounded-full ${error ? "bg-surface text-warning" : "bg-success-soft text-on-success-soft"}`}
        >
          <Icon name={error ? "clock" : "check"} size={26} strokeWidth={2.2} />
        </span>
        <p className="t-name-state text-ink">{error ? "Payment received" : "Purchase complete!"}</p>
        {/* The warning used to be set into `error` and then never rendered:
            this early return shows only the success block, and the <Alert>
            lives in the form JSX below, which is now unreachable. So a buyer
            whose 10-minute reservation lapsed mid-card-entry was charged,
            told "Purchase complete!", and sent to an empty purchases page. */}
        {error ? <Alert tone="error">{error}</Alert> : null}
        <p className="t-body text-muted">
          {error
            ? "Your card was charged. We're finishing the last step — your purchase will appear shortly."
            : transferId
              ? "Your ticket is confirmed. Add your delivery details so the seller can send it."
              : "Your ticket is confirmed. Check your purchases for transfer details."}
        </p>
        <Button
          variant="primary"
          size="lg"
          onClick={() => router.push(transferId ? `/transfer/receive/${transferId}` : "/account/purchases")}
          className="w-full"
        >
          {transferId ? "Continue to transfer" : "Go to your purchases"}
        </Button>
      </div>
    );
  }

  if (paidNeedsLogin) {
    // No Pay button here: the card was already charged.
    return (
      <div className="space-y-4">
        <Alert tone="info">{error}</Alert>
        <LinkButton href={loginHref ?? "/login?next=%2Faccount%2Fpurchases"} size="lg" className="w-full">
          Log in to finish
        </LinkButton>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      {error ? <Alert tone="error">{error}</Alert> : null}
      <PaymentElement />
      <Button type="submit" variant="primary" size="lg" className="w-full" disabled={!stripe || submitting} pending={submitting} pendingLabel="Processing…">
        Pay
      </Button>
    </form>
  );
}
