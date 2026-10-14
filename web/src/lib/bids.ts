import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { readServerRefusal } from "@/lib/server-refusal";

export type PlaceBidResult = { error?: string };

/**
 * Mirrors PlaceBidScreen.handleConfirm's bids insert exactly — a plain
 * insert, no RPC. All business rules (self-bid, auction-ended, minimum
 * amount, rate limit) are enforced by the validate_and_apply_bid() BEFORE
 * INSERT trigger, atomic with the listings.current_bid update.
 */
export async function placeBid(
  listingId: string,
  userId: string,
  amountDollars: number,
): Promise<PlaceBidResult> {
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.from("bids").insert({
    listing_id: listingId,
    bidder_id: userId,
    amount: amountDollars,
  });
  if (!error) return {};

  // Migration 152: blocked parties, suspended accounts and suspended sellers' listings.
  const refusal = readServerRefusal(error);
  if (refusal) return { error: refusal.message };

  const msg = error.message ?? "Could not place bid.";
  if (msg.includes("own listing")) return { error: "You cannot bid on your own listing." };
  if (msg.includes("cancelled")) return { error: "This listing was cancelled by the seller." };
  if (msg.includes("ended")) return { error: "This auction has ended." };
  if (msg.includes("greater than")) return { error: msg };
  if (msg.includes("wait before bidding")) return { error: "Please wait a few seconds before bidding again." };
  if (msg.includes("not found")) return { error: "This listing is no longer available." };
  return { error: msg };
}
