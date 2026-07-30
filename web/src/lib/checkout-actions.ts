"use server";

import { getAuthedUser } from "@/lib/auth/session";
import {
  createPaymentIntent,
  finalizeBuyNowPurchase,
  reserveBuyNow,
  type PaymentIntentResult,
} from "@/lib/checkout";

export async function reserveBuyNowAction(listingId: string): Promise<{ ok: boolean; error?: string }> {
  const user = await getAuthedUser();
  if (!user) return { ok: false, error: "AUTH_REQUIRED" };
  const result = await reserveBuyNow(listingId, user.id);
  if (result.error) return { ok: false, error: result.error };
  return { ok: true };
}

export async function createPaymentIntentAction(listingId: string): Promise<PaymentIntentResult> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  return createPaymentIntent(listingId, "buy_now");
}

export async function finalizeBuyNowPurchaseAction(
  listingId: string,
  paymentIntentId: string,
): Promise<{ transferId: string | null; warning?: string; error?: string }> {
  const user = await getAuthedUser();
  if (!user) return { transferId: null, error: "AUTH_REQUIRED" };
  return finalizeBuyNowPurchase(listingId, user.id, paymentIntentId);
}
