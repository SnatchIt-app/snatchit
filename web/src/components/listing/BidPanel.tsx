"use client";

import { useState, useTransition } from "react";
import { useRouter, usePathname } from "next/navigation";
import { allInFromDollars, APP_CONFIG } from "@snatchit/core";
import { placeBidAction } from "@/lib/bids-actions";
import { useListingBids, type BidRow } from "@/hooks/useListingBids";
import { Button } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";
import { PriceBreakdown, PriceDisplay } from "@/components/ui/PriceDisplay";

const MIN_INCREMENT = APP_CONFIG.MIN_BID_INCREMENT;
const QUICK_CHIPS = [5, 10, 25] as const;

// Plain function, not a component — exempt from the render-purity rule that
// disallows Date.now() directly in a component body (see checkout/[id]/page.tsx's
// isStillReservedFor for the same exemption pattern).
function isAuctionEnded(auctionStatus: string, endsAt: string): boolean {
  return auctionStatus !== "active" || new Date(endsAt).getTime() <= Date.now();
}

function timeAgo(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  const minutes = Math.floor(ms / 60_000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

/**
 * Live bidding panel: current bid + recent bids from useListingBids's
 * realtime channels, plus a stepper/quick-chip bid form matching mobile's
 * PlaceBidScreen. `compact` drops the headline figure and bid history for
 * the hybrid (Buy Now + bidding) layout, where Buy Now is primary and the
 * top-of-panel price block already shows the current bid as a stat.
 */
export function BidPanel({
  listingId,
  sellerId,
  currentUserId,
  initialCurrentBid,
  initialBidCount,
  initialAuctionStatus,
  initialEndsAt,
  compact = false,
}: {
  listingId: string;
  sellerId: string;
  currentUserId: string | null;
  initialCurrentBid: number;
  initialBidCount: number;
  initialAuctionStatus: string;
  initialEndsAt: string;
  compact?: boolean;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const isOwner = currentUserId !== null && currentUserId === sellerId;

  const { bids, bidCount, currentBid, auctionStatus, endsAt } = useListingBids(listingId, {
    currentBid: initialCurrentBid,
    bidCount: initialBidCount,
    auctionStatus: initialAuctionStatus,
    endsAt: initialEndsAt,
  });

  const ended = isAuctionEnded(auctionStatus, endsAt);
  const minimumBid = currentBid + MIN_INCREMENT;

  const [selectedBid, setSelectedBid] = useState(minimumBid);
  const [error, setError] = useState<string | null>(null);
  const [placed, setPlaced] = useState<number | null>(null);
  const [isPending, startTransition] = useTransition();

  // Re-syncs the default selection whenever the live current bid moves —
  // mirrors PlaceBidScreen's effect on listing.current_bid. Adjusting state
  // during render (React's documented pattern for "reset state when a prop
  // changes") avoids the extra render+effect round trip a useEffect would add.
  const [syncedBid, setSyncedBid] = useState(currentBid);
  if (currentBid !== syncedBid) {
    setSyncedBid(currentBid);
    setSelectedBid(currentBid + MIN_INCREMENT);
  }

  function handleSubmit() {
    setError(null);
    startTransition(async () => {
      const result = await placeBidAction(listingId, selectedBid);
      if (result.error === "AUTH_REQUIRED") {
        router.push(`/login?next=${encodeURIComponent(pathname)}`);
        return;
      }
      if (result.error) {
        setError(result.error);
        return;
      }
      setPlaced(selectedBid);
    });
  }

  if (isOwner) {
    return (
      <p className="mt-6 border border-primary/20 bg-card p-4 text-center text-[13px] text-white/50">
        You can&apos;t bid on your own listing.
      </p>
    );
  }

  if (ended) {
    return (
      <div className="mt-6 space-y-2.5">
        <Button variant="secondary" className="w-full" disabled>
          Bidding has ended
        </Button>
      </div>
    );
  }

  return (
    <div className={compact ? "mt-4 space-y-3" : "mt-6 space-y-4"}>
      {!compact ? (
        <div>
          <p className="text-[10.5px] font-medium uppercase tracking-[0.25em] text-white/45">
            Current bid · all-in
          </p>
          <PriceDisplay baseDollars={currentBid} size="lg" suffix={null} className="mt-2.5" />
          <p className="mt-3 text-[13.5px] text-muted">
            {bidCount} bid{bidCount === 1 ? "" : "s"}
          </p>
        </div>
      ) : (
        <p className="text-[11px] font-medium uppercase tracking-[0.25em] text-white/45">Or place a bid</p>
      )}

      {!compact && bids.length > 0 ? (
        <ul className="max-h-32 space-y-1.5 overflow-y-auto border-y border-primary/15 py-3 text-[12.5px]">
          {bids.slice(0, 5).map((b: BidRow) => (
            <li key={b.id} className="flex items-center justify-between text-white/60">
              <span>
                {b.profiles?.display_name ?? "Bidder"}
                {b.bidder_id === currentUserId ? " (you)" : ""}
              </span>
              <span className="tabular-nums font-semibold text-white/85">
                ${b.amount} · {timeAgo(b.created_at)}
              </span>
            </li>
          ))}
        </ul>
      ) : null}

      {error ? <Alert tone="error">{error}</Alert> : null}
      {placed !== null ? (
        <Alert tone="success">
          Bid of {allInFromDollars(placed)} placed. You&apos;ll be notified if you&apos;re outbid.
        </Alert>
      ) : null}

      <div className="border border-primary/20 bg-card p-5">
        <div className="flex items-center justify-between">
          <p className="text-[10.5px] font-medium uppercase tracking-[0.25em] text-white/45">Your bid</p>
          <p className="text-[11px] text-white/40">min ${minimumBid}</p>
        </div>
        <div className="mt-3 flex items-center gap-3">
          <button
            type="button"
            onClick={() => setSelectedBid((p) => Math.max(minimumBid, p - MIN_INCREMENT))}
            disabled={selectedBid <= minimumBid}
            aria-label="Decrease bid"
            className="flex size-10 shrink-0 items-center justify-center border border-white/15 text-lg text-white/80 transition-colors hover:border-primary/40 disabled:opacity-30"
          >
            −
          </button>
          <p className="flex-1 text-center font-display text-[28px] font-bold text-ink">${selectedBid}</p>
          <button
            type="button"
            onClick={() => setSelectedBid((p) => p + MIN_INCREMENT)}
            aria-label="Increase bid"
            className="flex size-10 shrink-0 items-center justify-center border border-white/15 text-lg text-white/80 transition-colors hover:border-primary/40"
          >
            +
          </button>
        </div>
        <div className="mt-3 flex gap-2">
          {QUICK_CHIPS.map((n) => (
            <button
              key={n}
              type="button"
              onClick={() => setSelectedBid((p) => p + n)}
              className="flex-1 border border-primary/40 bg-primary/[0.06] py-1.5 text-[12px] font-semibold text-primary transition-colors hover:bg-primary/[0.12]"
            >
              +${n}
            </button>
          ))}
        </div>
      </div>

      {!compact ? <PriceBreakdown baseDollars={selectedBid} /> : null}

      <Button variant="primary" className="w-full" onClick={handleSubmit} disabled={isPending}>
        {isPending ? "Placing bid…" : `Place bid · ${allInFromDollars(selectedBid)}`}
      </Button>
      <p className="text-center text-[11px] text-white/35">Only charged if you win the auction.</p>
    </div>
  );
}
