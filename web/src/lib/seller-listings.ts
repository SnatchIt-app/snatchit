import "server-only";

import { cache } from "react";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { findBannedTerm } from "@/lib/content-moderation";
import { sellerBadge, type SellerBadge } from "@/lib/seller-listing-status";

/**
 * Seller-side listing queries and mutations.
 *
 * SECURITY NOTE — read before changing anything here.
 * Three of mobile's seller rules have NO server-side enforcement, verified
 * against the live database:
 *
 *   1. `listings.bid_count` and `highest_bidder_id` are NOT covered by
 *      guard_listing_state_columns(), and the listings UPDATE policy is
 *      ownership-only. A seller can therefore set bid_count = 0 on their own
 *      listing and satisfy any check that trusts it. Every gate below counts
 *      real rows in `bids` instead.
 *   2. DELETE on listings is ownership-only — no bid-count condition, no
 *      BEFORE DELETE trigger — and `bids` + `saved_listings` CASCADE. The
 *      "cannot delete once bid on" rule exists only in mobile's UI, so it is
 *      re-implemented here.
 *   3. cancel_listing() blocks only on status = 'sold'; it does not check
 *      auction_status or the clock. The active-only rule is imposed here.
 */

/** Superset of LISTING_COLUMNS — adds the fields sellerBadge() needs. */
export const SELLER_LISTING_COLUMNS =
  "id, seller_id, event_name, venue, neighborhood, category, status, auction_status, event_date, event_time, ticket_type, quantity, starting_bid, current_bid, buy_now_enabled, buy_now_price, cover_image_path, ends_at, bid_count, ticket_platform, transfer_method, restrictions, reserved_until, winner_user_id, winning_bid_amount, sold_at, ended_at, proof_status, created_at";

export type SellerListing = {
  id: string;
  seller_id: string;
  event_name: string;
  venue: string;
  neighborhood: string;
  category: string;
  status: string;
  auction_status: string;
  event_date: string;
  event_time: string;
  ticket_type: string;
  quantity: number;
  starting_bid: number;
  current_bid: number;
  buy_now_enabled: boolean;
  buy_now_price: number | null;
  cover_image_path: string;
  ends_at: string;
  bid_count: number;
  ticket_platform: string;
  transfer_method: string;
  restrictions: string | null;
  reserved_until: string | null;
  winner_user_id: string | null;
  winning_bid_amount: number | null;
  sold_at: string | null;
  ended_at: string | null;
  proof_status: string;
  created_at: string | null;
};

export type SellerListingView = SellerListing & {
  badge: SellerBadge;
  needsTicketSend: boolean;
  /** Transfer awaiting the seller's send, when needsTicketSend is true. */
  pendingTransferId: string | null;
  realBidCount: number;
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Mirrors mobile my-listings.tsx: all of the seller's listings newest-first,
 * plus their transfers so a sold listing can surface "send the tickets".
 * Badges are computed here (server-side, one clock) so the client never has
 * to derive a time-sensitive label and risk a hydration mismatch.
 */
export const getMyListings = cache(async (userId: string): Promise<SellerListingView[]> => {
  const supabase = await createSupabaseServerClient();

  const [{ data: listings, error }, { data: transfers }] = await Promise.all([
    supabase
      .from("listings")
      .select(SELLER_LISTING_COLUMNS)
      .eq("seller_id", userId)
      .order("created_at", { ascending: false }),
    supabase.from("transfers").select("id, listing_id, status").eq("seller_id", userId),
  ]);

  if (error) throw new Error(`seller listings query failed: ${error.message}`);

  const ids = ((listings ?? []) as unknown as SellerListing[]).map((l) => l.id);
  // Scoped to this seller's listings — bids_select_all is public, so an
  // unfiltered select here would pull the whole table.
  const { data: bidRows } = ids.length
    ? await supabase.from("bids").select("listing_id").in("listing_id", ids)
    : { data: [] as { listing_id: string }[] };

  // listing_id -> transfer id, for sold listings still awaiting a send.
  const pendingTransfer = new Map<string, string>();
  for (const t of (transfers ?? []) as { id: string; listing_id: string; status: string }[]) {
    if (t.status === "pending") pendingTransfer.set(t.listing_id, t.id);
  }
  // Real bid counts — listings.bid_count is seller-writable, see the note above.
  const realBids = new Map<string, number>();
  for (const b of (bidRows ?? []) as { listing_id: string }[]) {
    realBids.set(b.listing_id, (realBids.get(b.listing_id) ?? 0) + 1);
  }

  const now = Date.now();
  return ((listings ?? []) as unknown as SellerListing[]).map((l) => {
    const badge = sellerBadge(l, now);
    return {
      ...l,
      badge,
      needsTicketSend: badge === "SOLD" && pendingTransfer.has(l.id),
      pendingTransferId: pendingTransfer.get(l.id) ?? null,
      realBidCount: realBids.get(l.id) ?? 0,
    };
  });
});

export async function getMyListing(userId: string, listingId: string): Promise<SellerListingView | null> {
  if (!UUID_RE.test(listingId)) return null;
  const all = await getMyListings(userId);
  return all.find((l) => l.id === listingId) ?? null;
}

/** Real bid rows for one listing — never trust listings.bid_count. */
async function countRealBids(listingId: string): Promise<number> {
  const supabase = await createSupabaseServerClient();
  const { count } = await supabase
    .from("bids")
    .select("id", { count: "exact", head: true })
    .eq("listing_id", listingId);
  return count ?? 0;
}

function mapSellerError(msg: string): string {
  if (msg.includes("auction state columns")) {
    return "That field can't be changed directly. Refresh and try again.";
  }
  if (msg.includes("only cancel your own") || msg.includes("Cannot change listing owner")) {
    return "You can only manage your own listings.";
  }
  if (msg.includes("already been sold")) return "This listing has already sold and can't be changed.";
  if (msg.includes("Listing not found")) return "This listing no longer exists.";
  if (msg.includes("row-level security") || msg.includes("permission denied")) {
    return "You don't have permission to change this listing.";
  }
  return msg;
}

export type MutationResult = { ok?: true; error?: string };

/** The four fields mobile's edit screen allows. Nothing else is writable here. */
export type EditableListingFields = {
  eventName: string;
  venue: string;
  restrictions: string | null;
  ticketPlatform: string;
};

export async function updateSellerListing(
  userId: string,
  listingId: string,
  fields: EditableListingFields,
): Promise<MutationResult> {
  const listing = await getMyListing(userId, listingId);
  if (!listing) return { error: "This listing no longer exists." };

  if (listing.badge !== "ACTIVE" && listing.badge !== "ENDING SOON") {
    return { error: "This listing is no longer active and can't be edited." };
  }
  if ((await countRealBids(listingId)) > 0) {
    return { error: "This listing already has bids. Cancel it instead if you need to remove it." };
  }

  const flagged = findBannedTerm(`${fields.eventName} ${fields.venue} ${fields.restrictions ?? ""}`);
  if (flagged) return { error: "Listing details can't mention prohibited content — please rephrase." };

  if (!fields.eventName.trim()) return { error: "Event name is required." };
  if (!fields.venue.trim()) return { error: "Venue is required." };

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase
    .from("listings")
    .update({
      event_name: fields.eventName.trim(),
      venue: fields.venue.trim(),
      restrictions: fields.restrictions?.trim() || null,
      ticket_platform: fields.ticketPlatform,
    })
    .eq("id", listingId)
    .eq("seller_id", userId); // defence in depth; RLS enforces this too

  if (error) return { error: mapSellerError(error.message) };
  return { ok: true };
}

/** Voids a listing that already has bids. Wraps the cancel_listing RPC. */
export async function cancelSellerListing(userId: string, listingId: string): Promise<MutationResult> {
  const listing = await getMyListing(userId, listingId);
  if (!listing) return { error: "This listing no longer exists." };
  if (listing.badge === "SOLD") return { error: "This listing has already sold and can't be cancelled." };
  if (listing.badge === "CANCELLED") return { ok: true }; // RPC is idempotent
  if (listing.badge === "ENDED") return { error: "This auction has already ended." };

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("cancel_listing", {
    p_listing_id: listingId,
    p_user_id: userId,
  });
  if (error) return { error: mapSellerError(error.message) };
  return { ok: true };
}

/**
 * Hard-deletes a listing with no bids. `bids` and `saved_listings` CASCADE,
 * so the zero-bid check above is what keeps this from destroying bid history.
 */
export async function deleteSellerListing(userId: string, listingId: string): Promise<MutationResult> {
  const listing = await getMyListing(userId, listingId);
  if (!listing) return { error: "This listing no longer exists." };
  if (listing.badge !== "ACTIVE" && listing.badge !== "ENDING SOON") {
    return { error: "Only an active listing with no bids can be deleted." };
  }
  if ((await countRealBids(listingId)) > 0) {
    return { error: "This listing has bids and can't be deleted. Cancel it instead." };
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.from("listings").delete().eq("id", listingId).eq("seller_id", userId);
  if (error) return { error: mapSellerError(error.message) };

  // Best-effort cover cleanup, matching mobile. Proof docs are deliberately
  // retained (mobile keeps them too) as the ownership record.
  await supabase.storage.from("auction-media").remove([listing.cover_image_path]);
  return { ok: true };
}
