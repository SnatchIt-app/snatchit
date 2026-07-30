"use client";

import { useEffect, useRef, useState } from "react";
import type { RealtimePostgresInsertPayload, RealtimePostgresUpdatePayload } from "@supabase/supabase-js";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

export type BidRow = {
  id: string;
  created_at: string;
  amount: number;
  bidder_id: string;
  profiles: { display_name: string | null } | null;
};

type InitialState = {
  currentBid: number;
  bidCount: number;
  auctionStatus: string;
  endsAt: string;
};

const BIDS_SELECT = "id, created_at, amount, bidder_id, profiles(display_name)";

/**
 * Ports mobile's useListingRealtime (src/hooks/useListingRealtime.ts) to the
 * web browser client: an initial fetch plus two channels — bids INSERT
 * (append-only, matching the bids_select_all/insert_authenticated RLS) and
 * listings UPDATE (picks up auction_status/ends_at transitions written by
 * the finalize_auction()/auto_finalize_expired_auctions() trigger path, so
 * bidding stops live when an auction ends without a page reload).
 */
export function useListingBids(listingId: string, initial: InitialState) {
  const [bids, setBids] = useState<BidRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [auctionState, setAuctionState] = useState({
    auctionStatus: initial.auctionStatus,
    endsAt: initial.endsAt,
    currentBid: initial.currentBid,
  });
  const bidsRef = useRef<BidRow[]>([]);
  useEffect(() => {
    bidsRef.current = bids;
  }, [bids]);

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();
    let cancelled = false;

    async function loadInitialBids() {
      const { data } = await supabase
        .from("bids")
        .select(BIDS_SELECT)
        .eq("listing_id", listingId)
        .order("created_at", { ascending: false });
      if (cancelled) return;
      setBids((data ?? []) as unknown as BidRow[]);
      setLoading(false);
    }
    loadInitialBids();

    const bidsChannel = supabase
      .channel(`bids:${listingId}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "bids", filter: `listing_id=eq.${listingId}` },
        async (payload: RealtimePostgresInsertPayload<{ id: string }>) => {
          const bidId = payload.new.id;
          if (bidsRef.current.some((b) => b.id === bidId)) return;
          const { data } = await supabase.from("bids").select(BIDS_SELECT).eq("id", bidId).single();
          if (data) setBids((prev) => [data as unknown as BidRow, ...prev]);
        },
      )
      .subscribe();

    const listingChannel = supabase
      .channel(`listing-bids-${listingId}`)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "listings", filter: `id=eq.${listingId}` },
        (
          payload: RealtimePostgresUpdatePayload<{
            auction_status?: string;
            ends_at?: string;
            current_bid?: number;
          }>,
        ) => {
          const next = payload.new;
          setAuctionState((prev) => ({
            auctionStatus: next.auction_status ?? prev.auctionStatus,
            endsAt: next.ends_at ?? prev.endsAt,
            currentBid: next.current_bid ?? prev.currentBid,
          }));
        },
      )
      .subscribe();

    return () => {
      cancelled = true;
      supabase.removeChannel(bidsChannel);
      supabase.removeChannel(listingChannel);
    };
  }, [listingId]);

  const currentBid =
    bids.length > 0 ? Math.max(auctionState.currentBid, ...bids.map((b) => b.amount)) : auctionState.currentBid;

  return {
    bids,
    bidCount: loading ? initial.bidCount : bids.length,
    currentBid,
    auctionStatus: auctionState.auctionStatus,
    endsAt: auctionState.endsAt,
    loading,
  };
}
