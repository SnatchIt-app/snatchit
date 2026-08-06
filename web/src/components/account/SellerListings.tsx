"use client";

import { useState, useTransition } from "react";
import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { allInFromDollars } from "@snatchit/core";
// From lib/format, NOT lib/listings — the latter imports lib/supabase/server
// (next/headers) and would drag a server-only module into this client bundle.
import { coverImageUrl } from "@/lib/format";
import type { SellerListingView } from "@/lib/seller-listings";
import {
  canCancel,
  canDelete,
  canEdit,
  inBucket,
  type SellerBadge,
  type SellerFilter,
} from "@/lib/seller-listing-status";
import { cancelListingAction, deleteListingAction } from "@/lib/seller-listings-actions";
import { Badge } from "@/components/ui/Badge";
import { Button, LinkButton } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";
import { EmptyState } from "@/components/ui/EmptyState";

const FILTERS: { key: SellerFilter; label: string }[] = [
  { key: "all", label: "All" },
  { key: "active", label: "Active" },
  { key: "needs_action", label: "Send tickets" },
  { key: "sold", label: "Sold" },
  { key: "ended", label: "Ended" },
];

const BADGE_VARIANT: Record<SellerBadge, "live" | "soon" | "sold" | "buyNow"> = {
  ACTIVE: "live",
  "ENDING SOON": "soon",
  RESERVED: "buyNow",
  SOLD: "sold",
  ENDED: "sold",
  CANCELLED: "sold",
};

/** Mirrors mobile's secondary line on SellerListingCard. */
function subline(l: SellerListingView): string {
  if (l.badge === "CANCELLED") return "Cancelled — bids voided";
  if (l.badge === "SOLD" && l.needsTicketSend) return "Action needed — send the tickets";
  if (l.badge === "SOLD" && l.sold_at) return `Sold ${new Date(l.sold_at).toLocaleDateString("en-US", { month: "short", day: "numeric" })}`;
  if (l.badge === "SOLD") return "Sold";
  if (l.badge === "ENDED") return l.winner_user_id ? "Winner selected" : "No winner";
  if (l.badge === "RESERVED") return "Reserved by a buyer";
  return `${l.realBidCount} bid${l.realBidCount === 1 ? "" : "s"}`;
}

export function SellerListings({ listings }: { listings: SellerListingView[] }) {
  const [filter, setFilter] = useState<SellerFilter>("all");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const router = useRouter();

  const counts = FILTERS.reduce<Record<string, number>>((acc, f) => {
    acc[f.key] = listings.filter((l) => inBucket(l.badge, l.needsTicketSend, f.key)).length;
    return acc;
  }, {});

  const shown = listings.filter((l) => inBucket(l.badge, l.needsTicketSend, filter));

  function run(id: string, fn: () => Promise<{ ok?: true; error?: string }>, successMsg: string) {
    setError(null);
    setNotice(null);
    setBusyId(id);
    startTransition(async () => {
      const result = await fn();
      setBusyId(null);
      if (result.error === "AUTH_REQUIRED") {
        router.push("/login?next=%2Faccount%2Flistings");
        return;
      }
      if (result.error) {
        setError(result.error);
        return;
      }
      setNotice(successMsg);
      router.refresh();
    });
  }

  if (listings.length === 0) {
    return (
      <EmptyState
        title="No listings yet"
        message="List a spare ticket and it shows up here with its bids and status."
        action={<LinkButton href="/sell">List a ticket</LinkButton>}
      />
    );
  }

  return (
    <div className="space-y-6">
      <nav aria-label="Filter listings" className="flex flex-wrap gap-2">
        {FILTERS.map((f) => (
          <button
            key={f.key}
            type="button"
            onClick={() => setFilter(f.key)}
            aria-pressed={filter === f.key}
            className={`border px-3.5 py-2 text-[11px] font-medium uppercase tracking-[0.2em] transition-colors ${
              filter === f.key
                ? "border-primary bg-primary/[0.10] text-primary"
                : "border-white/15 text-white/55 hover:border-white/35 hover:text-white/80"
            }`}
          >
            {f.label} ({counts[f.key] ?? 0})
          </button>
        ))}
      </nav>

      {error ? <Alert tone="error">{error}</Alert> : null}
      {notice ? <Alert tone="success">{notice}</Alert> : null}

      {shown.length === 0 ? (
        <EmptyState
          title="Nothing in this filter"
          message="Switch tabs to see your other listings."
        />
      ) : (
        <ul className="space-y-3">
          {shown.map((l) => {
            const busy = isPending && busyId === l.id;
            return (
              <li
                key={l.id}
                className={`border border-primary/20 bg-card p-4 ${l.badge === "CANCELLED" ? "opacity-60" : ""}`}
              >
                <div className="flex gap-4">
                  <Link href={`/listing/${l.id}`} className="relative size-20 shrink-0 overflow-hidden border border-white/10">
                    <Image
                      // Via coverImageUrl, not raw process.env — this was the
                      // one place bypassing STORAGE_BASE_URL, so any env gap
                      // rendered "undefined/storage/..." broken thumbnails.
                      src={coverImageUrl(l.cover_image_path)}
                      alt=""
                      fill
                      sizes="80px"
                      className="object-cover"
                    />
                  </Link>

                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <Badge variant={BADGE_VARIANT[l.badge]}>{l.badge}</Badge>
                      <span className="text-[12px] tabular-nums text-white/55">
                        {l.realBidCount > 0 ? `${allInFromDollars(l.current_bid)} current` : "No bids"}
                      </span>
                    </div>
                    <Link href={`/listing/${l.id}`} className="mt-1.5 block truncate text-[15px] font-bold text-ink hover:text-primary">
                      {l.event_name}
                    </Link>
                    <p className="mt-0.5 truncate text-[12.5px] text-white/50">{l.venue}</p>
                    <p
                      className={`mt-1 text-[12.5px] ${
                        l.needsTicketSend ? "font-bold text-primary" : "text-white/45"
                      }`}
                    >
                      {subline(l)}
                    </p>
                  </div>
                </div>

                <div className="mt-3 flex flex-wrap items-center gap-2 border-t border-primary/10 pt-3">
                  {l.needsTicketSend && l.pendingTransferId ? (
                    <LinkButton href={`/transfer/send/${l.pendingTransferId}`} size="md">
                      Send tickets
                    </LinkButton>
                  ) : null}
                  {canEdit(l.badge, l.realBidCount) ? (
                    <LinkButton href={`/account/listings/${l.id}/edit`} variant="secondary" size="md">
                      Edit
                    </LinkButton>
                  ) : null}
                  {canCancel(l.badge, l.realBidCount) ? (
                    <Button
                      variant="secondary"
                      size="md"
                      disabled={busy}
                      onClick={() => {
                        if (!confirm("Cancel this listing? All bids on it will be voided.")) return;
                        run(l.id, () => cancelListingAction(l.id), "Listing cancelled.");
                      }}
                    >
                      {busy ? "Cancelling…" : "Cancel"}
                    </Button>
                  ) : null}
                  {canDelete(l.badge, l.realBidCount) ? (
                    <Button
                      variant="ghost"
                      size="md"
                      disabled={busy}
                      onClick={() => {
                        if (!confirm("Delete this listing? This can't be undone.")) return;
                        run(l.id, () => deleteListingAction(l.id), "Listing deleted.");
                      }}
                    >
                      {busy ? "Deleting…" : "Delete"}
                    </Button>
                  ) : null}
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
