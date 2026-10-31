import Link from "next/link";
import { DataTable, type Column, type SearchParamsLike } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { TimeAgo } from "@/components/ui/DateTime";
import { Money } from "@/components/ui/Money";
import { IdLink, PartyLink } from "@/components/ui/IdLink";
import { labelFor } from "@/lib/format";
import type { OrderRow } from "@/lib/types";

/** Payment + transfer row (ops.order_row). Shared by /orders, users and listings. */
export function OrderTable({
  rows,
  basePath,
  searchParams,
  nextCursor,
  cursorParam,
  emptyText = "No orders match.",
  caption = "Orders",
  hideParties = false,
}: {
  rows: OrderRow[];
  basePath: string;
  searchParams?: SearchParamsLike;
  nextCursor?: string | null;
  cursorParam?: string;
  emptyText?: string;
  caption?: string;
  hideParties?: boolean;
}) {
  const columns: Column<OrderRow>[] = [
    { key: "created_at", header: "Created", render: (r) => <TimeAgo value={r.created_at} /> },
    {
      key: "payment_id",
      header: "Payment",
      render: (r) => (
        <span className="flex flex-col">
          <IdLink kind="payment" id={r.payment_id} />
          {r.stripe_payment_intent_id ? <span className="font-mono text-[10px] text-dim">{r.stripe_payment_intent_id}</span> : null}
        </span>
      ),
    },
    {
      key: "event",
      header: "Event",
      render: (r) => (
        <span className="block min-w-[160px]">
          {r.listing_id ? (
            <Link href={`/marketplace/${r.listing_id}`} className="link">
              {r.event_name ?? "listing"}
            </Link>
          ) : (
            r.event_name ?? "—"
          )}
          {r.event_date ? <span className="block text-[11px] text-dim">{r.event_date}</span> : null}
          {r.mode ? <span className="block text-[11px] text-dim">{r.mode.replace(/_/g, " ")}</span> : null}
        </span>
      ),
    },
    ...(hideParties
      ? []
      : ([
          {
            key: "parties",
            header: "Buyer / Seller",
            render: (r) => (
              <span className="flex flex-col gap-0.5 text-[12px]">
                <span>
                  <span className="text-dim">B </span>
                  <PartyLink id={r.buyer?.id} displayName={r.buyer?.display_name} />
                </span>
                <span>
                  <span className="text-dim">S </span>
                  <PartyLink id={r.seller?.id} displayName={r.seller?.display_name} />
                </span>
              </span>
            ),
          },
        ] as Column<OrderRow>[])),
    {
      key: "amount",
      header: "Amount / Total",
      align: "right",
      render: (r) => (
        <span className="flex flex-col items-end">
          <Money cents={r.amount} />
          <span className="text-[11px] text-dim">
            total <Money cents={r.total} />
          </span>
        </span>
      ),
    },
    { key: "payment_status", header: "Payment", render: (r) => <StatusBadge status={r.payment_status} label={labelFor("payment", r.payment_status)} /> },
    {
      key: "transfer_status",
      header: "Transfer",
      render: (r) =>
        r.transfer_id ? (
          <span className="flex flex-col gap-0.5">
            <StatusBadge status={r.transfer_status} label={labelFor("transfer", r.transfer_status)} />
            {r.transfer_expires_at && r.transfer_status === "pending" ? (
              <span className="text-[11px] text-dim">
                due <TimeAgo value={r.transfer_expires_at} />
              </span>
            ) : null}
          </span>
        ) : (
          <span className="text-dim">no transfer</span>
        ),
    },
    {
      key: "funds",
      header: "Seller funds",
      render: (r) => <StatusBadge status={r.seller_funds_state} label={labelFor("funds", r.seller_funds_state)} variant={r.seller_funds_state === "released_to_connected_account" ? "ok" : undefined} />,
    },
    {
      key: "open_cases",
      header: "Open cases",
      align: "right",
      render: (r) =>
        r.open_cases ? (
          <Link href={`/cases?subject_id=${r.payment_id ?? ""}`} className="link tabular-nums">
            {r.open_cases}
          </Link>
        ) : (
          <span className="text-dim">0</span>
        ),
    },
  ];
  return (
    <DataTable
      columns={columns}
      rows={rows}
      rowKey={(r, i) => r.payment_id ?? `${i}`}
      basePath={basePath}
      searchParams={searchParams}
      nextCursor={nextCursor}
      cursorParam={cursorParam}
      emptyText={emptyText}
      caption={caption}
      dense
    />
  );
}
