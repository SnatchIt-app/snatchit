"use client";

import { Suspense, useEffect, useState } from "react";
import { useParams, useRouter, useSearchParams } from "next/navigation";
import { finalizePurchaseAction } from "@/lib/checkout-actions";
import { Container } from "@/components/ui/Container";
import { Button, LinkButton, Spinner } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";
import { Icon } from "@/components/ui/Icon";
import { PAYMENT_STILL_PROCESSING } from "@/lib/checkout-wording";
import { CHECKOUT_SESSION_ENDED, checkoutLoginHref } from "@/lib/checkout-return";

type Status = "processing" | "success" | "unverified" | "pending" | "error" | "login";

/**
 * Fallback landing page for payment methods that require an actual browser
 * redirect (PaymentForm uses redirect: 'if_required', so most US card
 * payments never reach this page — Stripe only sends the browser here when
 * a redirect is unavoidable, e.g. certain 3DS challenges).
 */
function CompleteClient() {
  const params = useParams<{ id: string }>();
  const searchParams = useSearchParams();
  const router = useRouter();

  const redirectStatus = searchParams.get("redirect_status");
  const paymentIntentId = searchParams.get("payment_intent");
  // Stripe's redirect_status "processing" is NOT a failure: the payment may still succeed, so
  // "try again" could charge the buyer twice. It gets the same sentence PaymentForm shows inline
  // for a processing PaymentIntent, and points at purchases, never back to Buy Now.
  const stillProcessing = redirectStatus === "processing" && !!paymentIntentId;
  const failedUpfront = redirectStatus !== "succeeded" || !paymentIntentId;
  // PaymentForm puts ?mode on the return_url so the win settles with
  // complete_auction_payment, not mark_listing_sold. Anything unrecognised
  // (or a pre-auction link) falls back to buy_now.
  const mode = searchParams.get("mode") === "auction" ? "auction" : "buy_now";

  // Computed synchronously during render (not in the effect below) — this
  // branch needs no async work, just a state derived from the URL.
  const [status, setStatus] = useState<Status>(
    stillProcessing ? "pending" : failedUpfront ? "error" : "processing",
  );
  const [transferId, setTransferId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(
    stillProcessing
      ? PAYMENT_STILL_PROCESSING
      : failedUpfront
        ? redirectStatus === "failed"
          ? "Payment failed. Please go back and try again."
          : "Payment did not complete. Please go back and try again."
        : null,
  );

  useEffect(() => {
    if (failedUpfront) return;
    finalizePurchaseAction(params.id, paymentIntentId, mode)
      .then((result) => {
        if (result.error === "AUTH_REQUIRED") {
          // Stripe confirmed the payment, but this browser has no session (it ended during
          // 3DS, or the return opened elsewhere). Log in and come straight back here.
          setMessage(CHECKOUT_SESSION_ENDED);
          setStatus("login");
          return;
        }
        if (result.error) {
          // Server could not verify the PaymentIntent with Stripe, so it did
          // not mark the listing sold or mint a transfer. Show the recoverable
          // wording rather than claiming the purchase completed.
          setMessage(result.error);
          setStatus("unverified");
          return;
        }
        if (result.warning) setMessage(result.warning);
        setTransferId(result.transferId ?? null);
        setStatus("success");
      })
      .catch(() => {
        // The card has ALREADY been charged by this point — Stripe confirmed
        // before redirecting here. An unhandled rejection previously left the
        // buyer on "Confirming your payment…" forever with money taken and no
        // way forward. Fail into a state that tells them the payment landed
        // and points at the record of it.
        setMessage(
          "Your payment went through, but we couldn't load the confirmation. " +
            "Your purchase is safe — open your purchases to see it.",
        );
        setStatus("success");
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (status === "processing") {
    return (
      <p className="t-body flex items-center gap-2.5 text-muted" role="status">
        <Spinner /> Confirming your payment…
      </p>
    );
  }

  if (status === "pending") {
    return (
      <>
        <Alert tone="info">{message}</Alert>
        <Button variant="primary" size="lg" className="mt-5 w-full" onClick={() => router.push("/account/purchases")}>
          View your purchases
        </Button>
      </>
    );
  }

  if (status === "error") {
    return (
      <>
        <Alert tone="error">{message}</Alert>
        <Button variant="primary" size="lg" className="mt-5 w-full" onClick={() => router.push(`/listing/${params.id}`)}>
          Back to listing
        </Button>
      </>
    );
  }

  if (status === "login") {
    return (
      <>
        <Alert tone="info">{message}</Alert>
        <LinkButton
          href={checkoutLoginHref(params.id, paymentIntentId, mode) ?? "/login?next=%2Faccount%2Fpurchases"}
          size="lg"
          className="mt-5 w-full"
        >
          Log in to finish
        </LinkButton>
      </>
    );
  }

  // Stripe never confirmed the PaymentIntent, so nothing was marked sold and no
  // transfer exists. The charge may still settle via the webhook, so send the
  // buyer to their purchases rather than back to a Buy Now button.
  if (status === "unverified") {
    return (
      <>
        <Alert tone="error">{message}</Alert>
        <Button variant="primary" size="lg" className="mt-5 w-full" onClick={() => router.push("/account/purchases")}>
          View your purchases
        </Button>
      </>
    );
  }

  return (
    <div className="space-y-4 text-center" role="status">
      <span className="mx-auto inline-flex size-14 items-center justify-center rounded-full bg-success-soft text-on-success-soft">
        <Icon name="check" size={26} strokeWidth={2.2} />
      </span>
      <p className="t-name-state text-ink">Purchase complete!</p>
      {message ? <Alert tone="error">{message}</Alert> : null}
      <p className="t-body text-muted">Your ticket is confirmed. Next, tell the seller where to send it.</p>
      <Button
        variant="primary"
        size="lg"
        className="w-full"
        onClick={() => router.push(transferId ? `/transfer/receive/${transferId}` : "/account/purchases")}
      >
        {transferId ? "Add delivery details" : "View your purchases"}
      </Button>
    </div>
  );
}

export default function CheckoutCompletePage() {
  return (
    <Container size="tight" className="py-12 sm:py-16">
      <h1 className="t-display-lg text-ink">Checkout</h1>
      <div className="mt-8">
        <Suspense fallback={<p className="t-body text-muted">Loading…</p>}>
          <CompleteClient />
        </Suspense>
      </div>
    </Container>
  );
}
