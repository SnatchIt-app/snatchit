import Link from "next/link";
import { DataTable, type Column, type SearchParamsLike } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { TimeAgo } from "@/components/ui/DateTime";
import { Money } from "@/components/ui/Money";
import { PartyLink } from "@/components/ui/IdLink";
import { labelFor } from "@/lib/format";
import type { ListingSummary } from "@/lib/types";

export function ListingTable({
  rows,
  basePath,
  searchParams,
  nextCursor,
  hideSeller = false,
}: {
  rows: ListingSummary[];
  basePath: string;
  searchParams?: SearchParamsLike;
  nextCursor?: string | null;
  hideSeller?: boolean;
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
          <span className="text-[11px] text-dim">
            {[l.venue, l.event_date, l.ticket_type, l.quantity ? `×${l.quantity}` : null].filter(Boolean).join(" · ")}
          </span>
        </span>
      ),
    },
    ...(hideSeller ? [] : ([{ key: "seller", header: "Seller", render: (l) => <PartyLink id={l.seller_id} displayName={l.seller_display_name} /> }] as Column<ListingSummary>[])),
    { key: "status", header: "Status", render: (l) => <StatusBadge status={l.status} /> },
    { key: "auction_status", header: "Auction", render: (l) => <StatusBadge status={l.auction_status} /> },
    { key: "proof_status", header: "Proof", render: (l) => <StatusBadge status={l.proof_status} /> },
    {
      key: "price",
      header: "Buy now / Bid",
      align: "right",
      render: (l) => (
        <span className="flex flex-col items-end text-[12px]">
          {l.buy_now_enabled ? <Money cents={l.buy_now_price} /> : <span className="text-dim">no buy now</span>}
          <span className="text-dim">
            bid <Money cents={l.current_bid ?? l.starting_bid} /> ({l.bid_count ?? 0})
          </span>
        </span>
      ),
    },
    {
      key: "payment_status",
      header: "Latest payment",
      render: (l) => (l.payment_status ? <StatusBadge status={l.payment_status} label={labelFor("payment", l.payment_status)} /> : <span className="text-dim">none</span>),
    },
    { key: "reports", header: "Reports", align: "right", render: (l) => <span className="tabular-nums">{l.report_count ?? 0}</span> },
    { key: "open_cases", header: "Open cases", align: "right", render: (l) => <span className="tabular-nums">{l.open_cases ?? 0}</span> },
    { key: "ends_at", header: "Ends", render: (l) => <TimeAgo value={l.ends_at} /> },
  ];
  return <DataTable columns={columns} rows={rows} rowKey={(l, i) => l.id ?? `${i}`} basePath={basePath} searchParams={searchParams} nextCursor={nextCursor} emptyText="No listings match." caption="Listings" dense />;
}
