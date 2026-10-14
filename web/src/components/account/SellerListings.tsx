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
import { Badge, type Tone } from "@/components/ui/Badge";
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

const BADGE_TONE: Record<SellerBadge, Tone> = {
  ACTIVE: "success",
  "ENDING SOON": "warning",
  RESERVED: "warning",
  SOLD: "neutral",
  ENDED: "neutral",
  CANCELLED: "neutral",
};

/** The status words stay lib/seller-listing-status.ts's; only their case changes for display ("Ending soon"). */
function badgeLabel(badge: SellerBadge): string {
  return badge.charAt(0) + badge.slice(1).toLowerCase();
}

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
        icon="tag"
        title="No listings yet"
        message="List a spare ticket and it shows up here with its bids and status."
        action={<LinkButton href="/sell">List a ticket</LinkButton>}
      />
    );
  }

  return (
    <div className="space-y-6">
      <nav aria-label="Filter listings" className="flex flex-wrap gap-2">
        {FILTERS.map((f) => {
          const on = filter === f.key;
          return (
            <button
              key={f.key}
              type="button"
              onClick={() => setFilter(f.key)}
              aria-pressed={on}
              className={`pressable min-h-10 rounded-full border px-4 text-[14px] font-medium ${
                on ? "border-ink bg-ink text-canvas" : "border-control text-ink hover:border-ink"
              }`}
            >
              {f.label} <span className="tabular-nums">({counts[f.key] ?? 0})</span>
            </button>
          );
        })}
      </nav>

      {error ? <Alert tone="error">{error}</Alert> : null}
      {notice ? <Alert tone="success">{notice}</Alert> : null}

      {shown.length === 0 ? (
        <EmptyState
          icon="filter"
          title="Nothing in this filter"
          message="Switch tabs to see your other listings."
        />
      ) : (
        <ul className="border-t border-line">
          {shown.map((l) => {
            const busy = isPending && busyId === l.id;
            const showEdit = canEdit(l.badge, l.realBidCount);
            const showCancel = canCancel(l.badge, l.realBidCount);
            const showDelete = canDelete(l.badge, l.realBidCount);
            const showSend = l.needsTicketSend && l.pendingTransferId;
            return (
              <li key={l.id} className="border-b border-line py-4">
                <div className={`flex flex-wrap items-start gap-4 sm:gap-5 ${l.badge === "CANCELLED" ? "opacity-60" : ""}`}>
                  {/* Same destination as the event name below, so the poster is a pointer target only. */}
                  <Link
                    href={`/listing/${l.id}`}
                    tabIndex={-1}
                    aria-hidden="true"
                    className="poster relative block h-[78px] w-[62px] shrink-0 overflow-hidden rounded-media sm:h-[100px] sm:w-[80px]"
                  >
                    <Image
                      // Via coverImageUrl, not raw process.env — this was the
                      // one place bypassing STORAGE_BASE_URL, so any env gap
                      // rendered "undefined/storage/..." broken thumbnails.
                      src={coverImageUrl(l.cover_image_path)}
                      alt=""
                      fill
                      sizes="80px"
                      className="object-contain"
                    />
                  </Link>

                  {/* Beside the poster; under it when the row is too narrow (200% zoom) to fit the badge. */}
                  <div className="min-w-0 grow basis-48">
                    <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
                      <Badge tone={BADGE_TONE[l.badge]}>{badgeLabel(l.badge)}</Badge>
                      <span className="t-body-sm text-muted">
                        {l.realBidCount > 0 ? (
                          <>
                            <span className="t-price whitespace-nowrap text-ink">{allInFromDollars(l.current_bid)}</span> current
                          </>
                        ) : (
                          "No bids"
                        )}
                      </span>
                    </div>
                    <Link
                      href={`/listing/${l.id}`}
                      className="t-name-row mt-2 block break-words text-ink underline-offset-4 hover:underline hover:decoration-2"
                    >
                      {l.event_name}
                    </Link>
                    <p className="t-body-sm mt-0.5 break-words text-muted">{l.venue}</p>
                    <p
                      className={`t-body-sm mt-1.5 ${
                        l.needsTicketSend ? "font-semibold text-brand-text" : "text-ink-2"
                      }`}
                    >
                      {subline(l)}
                    </p>
                  </div>
                </div>

                {showSend || showEdit || showCancel || showDelete ? (
                  <div className="mt-3.5 flex flex-wrap items-center gap-2 sm:pl-[100px]">
                    {showSend ? (
                      <LinkButton href={`/transfer/send/${l.pendingTransferId}`} size="md">
                        Send tickets
                      </LinkButton>
                    ) : null}
                    {showEdit ? (
                      <LinkButton href={`/account/listings/${l.id}/edit`} variant="secondary" size="md">
                        Edit
                      </LinkButton>
                    ) : null}
                    {showCancel ? (
                      <Button
                        variant="destructive"
                        size="md"
                        disabled={busy}
                        pending={busy}
                        pendingLabel="Cancelling…"
                        onClick={() => {
                          if (!confirm("Cancel this listing? All bids on it will be voided.")) return;
                          run(l.id, () => cancelListingAction(l.id), "Listing cancelled.");
                        }}
                      >
                        Cancel
                      </Button>
                    ) : null}
                    {showDelete ? (
                      <Button
                        variant="destructive"
                        size="md"
                        disabled={busy}
                        pending={busy}
                        pendingLabel="Deleting…"
                        onClick={() => {
                          if (!confirm("Delete this listing? This can't be undone.")) return;
                          run(l.id, () => deleteListingAction(l.id), "Listing deleted.");
                        }}
                      >
                        Delete
                      </Button>
                    ) : null}
                  </div>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
