"use server";

import { getAuthedUser } from "@/lib/auth/session";
import {
  createPaymentIntent,
  finalizePurchase,
  reserveBuyNow,
  type CheckoutMode,
  type PaymentIntentResult,
} from "@/lib/checkout";

export async function reserveBuyNowAction(listingId: string): Promise<{ ok: boolean; error?: string }> {
  const user = await getAuthedUser();
  if (!user) return { ok: false, error: "AUTH_REQUIRED" };
  const result = await reserveBuyNow(listingId, user.id);
  if (result.error) return { ok: false, error: result.error };
  return { ok: true };
}

// mode defaults to buy_now so it stays optional at every call site; the edge
// function re-validates it (reservation for buy_now, ended + winner for
// auction) and derives the amount itself, so it is never a trusted input.
export async function createPaymentIntentAction(
  listingId: string,
  mode: CheckoutMode = "buy_now",
): Promise<PaymentIntentResult> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  return createPaymentIntent(listingId, mode);
}

export async function finalizePurchaseAction(
  listingId: string,
  paymentIntentId: string,
  mode: CheckoutMode = "buy_now",
): Promise<{ transferId: string | null; warning?: string; error?: string }> {
  const user = await getAuthedUser();
  if (!user) return { transferId: null, error: "AUTH_REQUIRED" };
  return finalizePurchase(listingId, user.id, paymentIntentId, mode);
}
