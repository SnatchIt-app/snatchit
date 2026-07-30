import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { callEdgeFunction } from "@/lib/edge-functions";

export const RESERVATION_MINUTES = 10; // matches src/config/app.ts (mobile)

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
  mode: "buy_now" | "auction",
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
 * client-side. Mirrors CheckoutNative.handleConfirmPurchase exactly:
 * best-effort confirm-payment, then mark_listing_sold, then
 * ensure_transfer_exists (which also self-heals payment status if
 * confirm-payment's own update didn't land).
 */
export async function finalizeBuyNowPurchase(
  listingId: string,
  userId: string,
  paymentIntentId: string,
): Promise<{ transferId: string | null; warning?: string }> {
  await callEdgeFunction("confirm-payment", { payment_intent_id: paymentIntentId });

  const supabase = await createSupabaseServerClient();

  const { error: soldErr } = await supabase.rpc("mark_listing_sold", {
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
