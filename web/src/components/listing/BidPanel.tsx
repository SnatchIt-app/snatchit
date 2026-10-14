"use client";

import { useState, useTransition } from "react";
import { useRouter, usePathname } from "next/navigation";
import { allInFromDollars, APP_CONFIG } from "@snatchit/core";
import { placeBidAction } from "@/lib/bids-actions";
import { useListingBids, type BidRow } from "@/hooks/useListingBids";
import { Button } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";
import { Badge } from "@/components/ui/Badge";
import { Icon } from "@/components/ui/Icon";
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
  buyNowPrice = null,
  compact = false,
}: {
  listingId: string;
  sellerId: string;
  currentUserId: string | null;
  initialCurrentBid: number;
  initialBidCount: number;
  initialAuctionStatus: string;
  initialEndsAt: string;
  /** Whole dollars. When set, bidding is capped below it — see cappedOut. */
  buyNowPrice?: number | null;
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

  // Nothing stopped the minimum bid overshooting Buy Now. On a $1-bid /
  // $2-Buy-Now listing the stepper's floor is $6, so the panel rendered
  // "Place bid · $6.60" directly under a "$2.20 Buy Now" headline and anyone
  // using the bid control paid 3x for the same ticket. Once the next legal bid
  // reaches Buy Now, bidding is no longer a rational action, so we stop
  // offering it and point at the cheaper path instead.
  const cappedOut = buyNowPrice != null && minimumBid >= buyNowPrice;

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

  // The listing page renders no price block for an active pure auction — the
  // figure lives here. So the owner branch must still show it, or the seller
  // sees their own listing with no price and no bid count at all.
  if (isOwner) {
    return (
      <div className={compact ? "mt-4" : "mt-6"}>
        {!compact ? (
          <div className="mb-4">
            <p className="t-label text-muted">Current bid · all-in</p>
            <PriceDisplay baseDollars={currentBid} size="md" suffix={null} className="mt-1" />
            <p className="t-body-sm mt-1 text-muted">
              {bidCount} bid{bidCount === 1 ? "" : "s"}
            </p>
          </div>
        ) : null}
        <Button size="lg" variant="secondary" className="w-full" disabled>
          You can&apos;t bid on your own listing.
        </Button>
      </div>
    );
  }

  if (ended) {
    return (
      <div className="mt-2 space-y-2.5">
        <Button variant="secondary" size="lg" className="w-full" disabled>
          Bidding has ended
        </Button>
      </div>
    );
  }

  if (cappedOut) {
    return (
      <div className={compact ? "mt-4 space-y-2.5" : "mt-6 space-y-2.5"}>
        <Alert tone="info">The next bid would cost more than Buy Now. Buy it outright instead.</Alert>
      </div>
    );
  }

  // The highest amount leads (the list is newest-first; never trust position).
  const leadingId = bids.reduce<BidRow | null>((top, b) => (!top || b.amount > top.amount ? b : top), null)?.id;

  return (
    <div className={compact ? "mt-1 space-y-4" : "space-y-4"}>
      {compact ? (
        <div className="flex items-center gap-3 pt-1" aria-hidden="true">
          <span className="h-px flex-1 bg-line" />
          <span className="t-body-sm text-muted">Or place a bid</span>
          <span className="h-px flex-1 bg-line" />
        </div>
      ) : null}

      {error ? <Alert tone="error">{error}</Alert> : null}
      {placed !== null ? (
        <Alert tone="success">
          Bid of {allInFromDollars(placed)} placed. You&apos;ll be notified if you&apos;re outbid.
        </Alert>
      ) : null}

      <div>
        <div className="flex items-baseline justify-between">
          <p className="t-label text-ink">Your bid</p>
          <p className="t-body-sm text-muted">min ${minimumBid} · ${MIN_INCREMENT} steps</p>
        </div>
        <div className="mt-3 flex items-stretch gap-3">
          <button
            type="button"
            onClick={() => setSelectedBid((p) => Math.max(minimumBid, p - MIN_INCREMENT))}
            disabled={selectedBid <= minimumBid}
            aria-label="Decrease bid"
            className="pressable flex w-14 shrink-0 items-center justify-center rounded-panel border border-control text-ink hover:border-ink disabled:opacity-30"
          >
            <svg aria-hidden="true" viewBox="0 0 24 24" className="size-6" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round"><path d="M6 12h12" /></svg>
          </button>
          <p className="flex min-h-16 flex-1 items-center justify-center rounded-panel bg-canvas text-[34px] font-bold tabular-nums tracking-tight text-ink" aria-live="polite">
            ${selectedBid}
          </p>
          <button
            type="button"
            onClick={() => setSelectedBid((p) => p + MIN_INCREMENT)}
            aria-label="Increase bid"
            className="pressable flex w-14 shrink-0 items-center justify-center rounded-panel border border-control text-ink hover:border-ink"
          >
            <svg aria-hidden="true" viewBox="0 0 24 24" className="size-6" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round"><path d="M6 12h12M12 6v12" /></svg>
          </button>
        </div>
        <div className="mt-3 grid grid-cols-3 gap-2">
          {QUICK_CHIPS.map((n) => (
            <button
              key={n}
              type="button"
              onClick={() => setSelectedBid((p) => p + n)}
              className="pressable min-h-10 rounded-full border border-control text-[14px] font-semibold text-ink hover:border-ink"
            >
              +${n}
            </button>
          ))}
        </div>
      </div>

      {!compact ? <PriceBreakdown baseDollars={selectedBid} /> : null}

      <Button variant={compact ? "secondary" : "primary"} size="lg" className="w-full" onClick={handleSubmit} pending={isPending} pendingLabel="Placing bid…" disabled={isPending}>
        Place bid · {allInFromDollars(selectedBid)}
      </Button>
      <p className="t-body-sm text-center text-muted">Only charged if you win the auction.</p>

      {!compact ? (
        <section aria-label="Bid activity" className="pt-2">
          <h3 className="t-title text-ink">Bid activity</h3>
          {bids.length > 0 ? (
            <ul className="mt-2 border-t border-line">
              {bids.slice(0, 5).map((b: BidRow) => (
                <li key={b.id} className="flex items-center justify-between gap-3 border-b border-line py-2.5 text-[14px]">
                  <span className="flex min-w-0 items-center gap-2 text-ink-2">
                    <span className="truncate">
                      {b.profiles?.display_name ?? "Bidder"}
                      {b.bidder_id === currentUserId ? " (you)" : ""}
                    </span>
                    {b.id === leadingId ? <Badge tone="success">Leading</Badge> : null}
                  </span>
                  <span className="shrink-0 tabular-nums text-ink">
                    <span className="font-semibold">${b.amount}</span>
                    <span className="text-muted"> · {timeAgo(b.created_at)}</span>
                  </span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="t-body-sm mt-1 flex items-center gap-2 text-muted">
              <Icon name="clock" size={16} /> {bidCount > 0 ? `${bidCount} bid${bidCount === 1 ? "" : "s"} placed` : "No bids yet"}
            </p>
          )}
        </section>
      ) : null}
    </div>
  );
}
