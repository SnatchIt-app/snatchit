import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { callEdgeFunction } from "@/lib/edge-functions";
import type { WebListing } from "@/lib/listings";

export const RESERVATION_MINUTES = 10; // matches src/config/app.ts (mobile)

/** The two ways a listing gets paid for — same vocabulary as create-payment-intent. */
export type CheckoutMode = "buy_now" | "auction";

/**
 * The window in which an auction winner still owes money: finalize_auction
 * parks the listing at auction_status='ended' with a winner, and payment is
 * what flips it to 'sold' (complete_auction_payment sets both status and
 * auction_status). So 'ended' + winner + not sold is exactly the state
 * create-payment-intent's auction branch accepts — checking it here just
 * stops us from sending a buyer to a checkout the server would reject.
 */
export function isUnpaidAuctionWinner(
  listing: Pick<WebListing, "status" | "auction_status" | "winner_user_id">,
  userId: string | null | undefined,
): boolean {
  return (
    !!userId &&
    listing.auction_status === "ended" &&
    listing.status !== "sold" &&
    listing.winner_user_id === userId
  );
}

export type ReserveResult = { error?: string };

export type ReservationState = {
  status: string;
  reservedBy: string | null;
  reservedUntil: string | null;
};

/** Reservation-specific fields, kept out of the public listing query (listings.ts). */
export async function getReservationState(listingId: string): Promise<ReservationState | null> {
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase
    .from("listings")
    .select("status, reserved_by, reserved_until")
    .eq("id", listingId)
    .maybeSingle();
  if (!data) return null;
  return { status: data.status, reservedBy: data.reserved_by, reservedUntil: data.reserved_until };
}

/** Mirrors ListingDetailScreen.handleBuyNow's reserve_buy_now call. */
export async function reserveBuyNow(listingId: string, userId: string): Promise<ReserveResult> {
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("reserve_buy_now", {
    p_listing_id: listingId,
    p_user_id: userId,
    p_minutes: RESERVATION_MINUTES,
  });
  if (!error) return {};

  const msg = error.message ?? "Could not reserve this listing.";
  if (msg.includes("already reserved")) return { error: "Reserved by another buyer. Try again in a few minutes." };
  if (msg.includes("sold")) return { error: "This listing has already been sold." };
  if (msg.includes("cancelled")) return { error: "This listing was cancelled by the seller." };
  if (msg.includes("own listing")) return { error: "You cannot purchase your own listing." };
  if (msg.includes("ended")) return { error: "This listing is no longer available." };
  return { error: msg };
}

export type PaymentIntentResult = {
  clientSecret?: string;
  amount?: number;
  buyer_fee?: number;
  total?: number;
  error?: string;
};

/** Server-to-server call to create-payment-intent — see edge-functions.ts for why. */
export async function createPaymentIntent(
  listingId: string,
  mode: CheckoutMode,
  expectedTotalCents?: number,
): Promise<PaymentIntentResult> {
  return callEdgeFunction<PaymentIntentResult>("create-payment-intent", {
    listing_id: listingId,
    mode,
    expected_total_cents: expectedTotalCents,
  });
}

/**
 * Post-payment bookkeeping, run after Stripe confirms the PaymentIntent
 * client-side.
 *
 * This used to fire confirm-payment and discard the result, then mark the
 * listing sold and mint a transfer unconditionally — so a PaymentIntent that
 * Stripe never actually settled still marked the listing sold and handed the
 * seller a send-tickets obligation. Migration 061 closed the database half of
 * that (ensure_transfer_exists now demands a succeeded payment); this is the
 * application half, and it also stops mark_listing_sold, which 061 does not
 * cover.
 *
 * Verification is server-authoritative and never trusts the caller's
 * paymentIntentId on its own:
 *
 *   fast path — confirm-payment reports stripe_verified, meaning it fetched
 *   /payment_intents/{id} and saw status === 'succeeded'
 *
 *   fallback  — the payments row itself is already 'succeeded', which covers
 *   the race where the Stripe webhook promoted it before this call ran. The
 *   lookup pins listing_id, buyer_id AND stripe_payment_intent_id together,
 *   so a PaymentIntent belonging to another buyer or another listing matches
 *   nothing, and a fabricated id matches nothing.
 *
 * Only if both fail do we refuse. The refusal is recoverable by design: the
 * card may genuinely have been charged, and the webhook settles it moments
 * later, so the buyer is pointed at their purchases rather than told the
 * payment failed.
 */
export async function finalizePurchase(
  listingId: string,
  userId: string,
  paymentIntentId: string,
  mode: CheckoutMode = "buy_now",
): Promise<{ transferId: string | null; warning?: string; error?: string }> {
  const confirm = await callEdgeFunction<{ success?: boolean; stripe_verified?: boolean }>(
    "confirm-payment",
    { payment_intent_id: paymentIntentId },
  );

  const supabase = await createSupabaseServerClient();

  let verified = !confirm.error && confirm.stripe_verified === true;
  if (!verified) {
    const { data: settled } = await supabase
      .from("payments")
      .select("id")
      .eq("listing_id", listingId)
      .eq("buyer_id", userId)
      .eq("stripe_payment_intent_id", paymentIntentId)
      .eq("status", "succeeded")
      .maybeSingle();
    verified = Boolean(settled);
  }

  if (!verified) {
    return {
      transferId: null,
      error:
        "We couldn't confirm this payment with Stripe. If your card was charged, " +
        "the purchase will appear under your purchases within a few minutes — " +
        "please don't pay again. Contact support if it doesn't show up.",
    };
  }

  // Same split the Stripe webhook makes on metadata.mode: a Buy Now settles a
  // reservation, an auction settles a win, and the two RPCs guard different
  // preconditions. A caller who names the wrong mode cannot promote anything —
  // each RPC re-derives the caller from auth.uid() and re-checks reservation
  // holder / winner itself, so a mismatch just fails and surfaces the warning.
  const settleRpc = mode === "auction" ? "complete_auction_payment" : "mark_listing_sold";
  const { error: soldErr } = await supabase.rpc(settleRpc, {
    p_listing_id: listingId,
    p_user_id: userId,
  });
  if (soldErr) {
    return { transferId: null, warning: "Your payment was processed but we had trouble updating the listing. Please contact support." };
  }

  const { data: transferId, error: transferErr } = await supabase.rpc("ensure_transfer_exists", {
    p_listing_id: listingId,
    p_user_id: userId,
  });
  if (transferErr) {
    return { transferId: null };
  }

  return { transferId: (transferId as string) ?? null };
}
