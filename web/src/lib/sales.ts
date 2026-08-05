import "server-only";

import { cache } from "react";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { TransferStatus } from "@/lib/transfers";

/**
 * Seller-side sales history — the mirror of /account/purchases.
 *
 * Amounts come from `payments` (the seller has a `payments: seller select`
 * RLS policy), not from the listing, so what's shown is what was actually
 * charged. Seller net is amount − seller_fee, the same 10/10 arithmetic the
 * payout path uses.
 *
 * Read-only. Payout state is surfaced but never written here — payout
 * columns belong to the edge functions.
 */

const SALE_COLUMNS =
  "id, listing_id, status, created_at, seller_sent_at, buyer_confirmed_at, disputed_at, payout_released_at, payout_review_status, expires_at, auto_release_at";

export type SaleView = {
  id: string;
  listing_id: string;
  status: TransferStatus;
  createdAt: string | null;
  soldAtLabel: string | null;
  eventName: string;
  venue: string;
  coverImagePath: string;
  buyerName: string | null;
  grossCents: number | null;
  netCents: number | null;
  paymentStatus: string | null;
  payoutReleasedAt: string | null;
  payoutReviewStatus: string | null;
};

type Joined<T> = T | T[] | null | undefined;
function one<T>(v: Joined<T>): T | null {
  if (!v) return null;
  return Array.isArray(v) ? (v[0] ?? null) : v;
}

/** Seller-facing payout line. Ordering matters: dispute outranks everything. */
export function payoutLabel(s: SaleView): { text: string; urgent: boolean } {
  if (s.status === "disputed") return { text: "On hold — buyer reported an issue", urgent: true };
  if (s.status === "expired") return { text: "Expired — buyer refunded", urgent: false };
  if (s.status === "pending") return { text: "Send the tickets", urgent: true };
  if (s.payoutReleasedAt) return { text: "Paid out", urgent: false };
  if (s.payoutReviewStatus === "manual_review") return { text: "Payout under review", urgent: false };
  if (s.payoutReviewStatus === "held") return { text: "Payout held until after the event", urgent: false };
  if (s.status === "seller_sent") return { text: "Awaiting buyer confirmation", urgent: false };
  if (s.status === "buyer_confirmed" || s.status === "auto_released") {
    return { text: "Payout processing", urgent: false };
  }
  return { text: "", urgent: false };
}

export const getMySales = cache(async (userId: string): Promise<SaleView[]> => {
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase
    .from("transfers")
    .select(
      `${SALE_COLUMNS}, buyer:profiles!buyer_id(display_name), listing:listings!listing_id(event_name, venue, cover_image_path), payment:payments!payment_id(amount, seller_fee, status, paid_at)`,
    )
    .eq("seller_id", userId)
    .order("created_at", { ascending: false });

  type Row = Record<string, unknown> & {
    buyer?: Joined<{ display_name: string | null }>;
    listing?: Joined<{ event_name: string; venue: string; cover_image_path: string }>;
    payment?: Joined<{ amount: number | null; seller_fee: number | null; status: string | null; paid_at: string | null }>;
  };

  return ((data ?? []) as unknown as Row[]).map((r) => {
    const listing = one(r.listing);
    const payment = one(r.payment);
    const gross = payment?.amount ?? null;
    return {
      id: r.id as string,
      listing_id: r.listing_id as string,
      status: r.status as TransferStatus,
      createdAt: (r.created_at as string) ?? null,
      soldAtLabel: payment?.paid_at ?? (r.created_at as string) ?? null,
      eventName: listing?.event_name ?? "Ticket",
      venue: listing?.venue ?? "",
      coverImagePath: listing?.cover_image_path ?? "",
      buyerName: one(r.buyer)?.display_name ?? null,
      grossCents: gross,
      netCents: gross == null ? null : gross - (payment?.seller_fee ?? 0),
      paymentStatus: payment?.status ?? null,
      payoutReleasedAt: (r.payout_released_at as string) ?? null,
      payoutReviewStatus: (r.payout_review_status as string) ?? null,
    };
  });
});
