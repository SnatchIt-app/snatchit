import "server-only";

import { cache } from "react";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { TransferStatus } from "@/lib/transfers";
import { sellerPayoutLine } from "@/lib/transfer-wording";

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
  "id, listing_id, status, created_at, seller_sent_at, buyer_confirmed_at, disputed_at, dispute_resolution, dispute_resolved_at, payout_released_at, payout_review_status, payout_hold_until, expires_at, auto_release_at";

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
  // Needed by the payout line's order of precedence (WT §2h): a decided
  // dispute, a hold with a stored end, and the scheduled release decision.
  // All three columns predate 075 and are in the production ledger.
  payoutHoldUntil: string | null;
  autoReleaseAt: string | null;
  disputeResolution: string | null;
  disputeResolvedAt: string | null;
};

type Joined<T> = T | T[] | null | undefined;
function one<T>(v: Joined<T>): T | null {
  if (!v) return null;
  return Array.isArray(v) ? (v[0] ?? null) : v;
}

/**
 * Seller-facing payout line. The precedence lives in `sellerPayoutLine`
 * (src/lib/transfer-wording.ts), where it is unit-tested; this is the
 * SaleView adapter. 'reversed' and an open dispute outrank
 * payout_released_at — a reversed row still carries it (WT §2d).
 */
export function payoutLabel(s: SaleView): { text: string; urgent: boolean } {
  return sellerPayoutLine({
    status: s.status,
    dispute_resolved_at: s.disputeResolvedAt,
    dispute_resolution: s.disputeResolution,
    payout_released_at: s.payoutReleasedAt,
    payout_review_status: s.payoutReviewStatus,
    payout_hold_until: s.payoutHoldUntil,
    auto_release_at: s.autoReleaseAt,
  });
}

export const getMySales = cache(async (userId: string): Promise<SaleView[]> => {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("transfers")
    .select(
      `${SALE_COLUMNS}, buyer:profiles!buyer_id(display_name), listing:listings!listing_id(event_name, venue, cover_image_path), payment:payments!payment_id(amount, seller_fee, status, paid_at)`,
    )
    .eq("seller_id", userId)
    .order("created_at", { ascending: false });
  // Surface query failures instead of swallowing them. Returning [] here made
  // an RLS or outage failure render as "No purchases yet" / "No sales yet" —
  // a seller with real money in flight would be told they had sold nothing.
  if (error) throw new Error(`transfers query failed: ${error.message}`);

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
      payoutHoldUntil: (r.payout_hold_until as string) ?? null,
      autoReleaseAt: (r.auto_release_at as string) ?? null,
      disputeResolution: (r.dispute_resolution as string) ?? null,
      disputeResolvedAt: (r.dispute_resolved_at as string) ?? null,
    };
  });
});
