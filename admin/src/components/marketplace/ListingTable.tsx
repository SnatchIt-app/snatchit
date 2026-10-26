import Link from "next/link";
import { DataTable, type Column, type SearchParamsLike } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { TestDataFooter, TestRecordBadge } from "@/components/ui/HiddenTestRowsNotice";
import { TimeAgo } from "@/components/ui/DateTime";
import { Money } from "@/components/ui/Money";
import { PartyLink } from "@/components/ui/IdLink";
import { labelFor } from "@/lib/format";
import type { ListingSummary } from "@/lib/types";

/** The price the row leads with: the buy-now price when enabled, else the current (or starting) bid. Integer cents. */
const leadPrice = (l: ListingSummary): number | null => (l.buy_now_enabled ? (l.buy_now_price ?? null) : (l.current_bid ?? l.starting_bid ?? null));

/** What the page filter matches on a listing row. */
export function listingFilterText(l: ListingSummary): string {
  return [l.event_name, l.venue, l.event_date, l.ticket_type, l.id, l.seller_display_name, l.status, l.auction_status, l.proof_status, l.payment_status ? labelFor("payment", l.payment_status) : null]
    .filter(Boolean)
    .join(" ");
}

export function ListingTable({
  rows,
  basePath,
  searchParams,
  nextCursor,
  hideSeller = false,
  filterable = false,
}: {
  rows: ListingSummary[];
  basePath: string;
  searchParams?: SearchParamsLike;
  nextCursor?: string | null;
  hideSeller?: boolean;
  /** Client-side text filter over the rows on this page. */
  filterable?: boolean;
}) {
  const columns: Column<ListingSummary>[] = [
    {
      key: "event_name",
      header: "Listing",
      render: (l) => (
        <span className="flex min-w-[180px] flex-col">
          {l.id ? (
            <Link href={`/marketplace/${l.id}`} className="link font-medium">
              {l.event_name ?? l.id.slice(0, 8)}
            </Link>
          ) : (
            l.event_name ?? "—"
          )}
          <span className="text-[0.6875rem] text-dim">
            {[l.venue, l.event_date, l.ticket_type, l.quantity ? `×${l.quantity}` : null].filter(Boolean).join(" · ")}
          </span>
        </span>
      ),
      sortValue: (l) => l.event_name ?? null,
    },
    ...(hideSeller
      ? []
      : ([{ key: "seller", header: "Seller", render: (l) => <PartyLink id={l.seller_id} displayName={l.seller_display_name} />, sortValue: (l) => l.seller_display_name ?? null }] as Column<ListingSummary>[])),
    {
      key: "status",
      header: "Status",
      render: (l) => (
        <span className="flex flex-wrap items-center gap-1">
          <StatusBadge status={l.status} />
          <TestRecordBadge isTest={l.is_test} />
        </span>
      ),
      sortValue: (l) => l.status ?? null,
    },
    { key: "auction_status", header: "Auction", render: (l) => <StatusBadge status={l.auction_status} />, sortValue: (l) => l.auction_status ?? null },
    { key: "proof_status", header: "Proof", render: (l) => <StatusBadge status={l.proof_status} />, sortValue: (l) => l.proof_status ?? null },
    {
      key: "price",
      header: "Buy now / Bid",
      align: "right",
      render: (l) => (
        <span className="flex flex-col items-end text-[0.75rem]">
          {l.buy_now_enabled ? <Money cents={l.buy_now_price} /> : <span className="text-dim">no buy now</span>}
          <span className="text-dim">
            bid <Money cents={l.current_bid ?? l.starting_bid} /> ({l.bid_count ?? 0})
          </span>
        </span>
      ),
      sortValue: leadPrice,
      firstSortDir: "desc",
    },
    {
      key: "payment_status",
      header: "Latest payment",
      render: (l) => (l.payment_status ? <StatusBadge status={l.payment_status} label={labelFor("payment", l.payment_status)} /> : <span className="text-dim">none</span>),
      sortValue: (l) => l.payment_status ?? null,
    },
    { key: "reports", header: "Reports", align: "right", render: (l) => <span className="tabular-nums">{l.report_count ?? 0}</span>, sortValue: (l) => l.report_count ?? 0, firstSortDir: "desc" },
    { key: "open_cases", header: "Open cases", align: "right", render: (l) => <span className="tabular-nums">{l.open_cases ?? 0}</span>, sortValue: (l) => l.open_cases ?? 0, firstSortDir: "desc" },
    { key: "ends_at", header: "Ends", render: (l) => <TimeAgo value={l.ends_at} />, sortValue: (l) => l.ends_at ?? null },
  ];
  return (
    <DataTable
      notice={<TestDataFooter rows={rows} />}
      columns={columns}
      rows={rows}
      rowKey={(l, i) => l.id ?? `${i}`}
      basePath={basePath}
      searchParams={searchParams}
      nextCursor={nextCursor}
      emptyText="No listings match."
      caption="Listings"
      dense
      filterable={filterable}
      filterText={listingFilterText}
    />
  );
}
