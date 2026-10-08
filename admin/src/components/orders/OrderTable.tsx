import Link from "next/link";
import type { ReactNode } from "react";
import { DataTable, type Column, type SearchParamsLike } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { TimeAgo } from "@/components/ui/DateTime";
import { Money } from "@/components/ui/Money";
import { PartyLink } from "@/components/ui/IdLink";
import { Icon } from "@/components/ui/Icon";
import { labelFor, shortId, transferStateLabel } from "@/lib/format";
import type { OrderRow } from "@/lib/types";

/**
 * Payment + transfer row (ops.order_row). Shared by /orders, users and listings.
 *
 * The order's name (its event) opens the order; the payment reference stays on
 * the row, copyable, because support and Stripe both speak in ids. Every
 * status uses the reviewed vocabulary verbatim — a qualifier such as "not
 * confirmed settled" is moved under its pill, never dropped.
 */
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
    { key: "order", header: "Order", render: (r) => <OrderName r={r} /> },
    ...(hideParties
      ? []
      : ([
          {
            key: "parties",
            header: "Buyer → Seller",
            render: (r) => (
              <span className="flex flex-col gap-0.5 whitespace-nowrap">
                <PartyLink id={r.buyer?.id} displayName={r.buyer?.display_name} />
                <span className="text-muted">
                  <span aria-hidden="true">→ </span>
                  <span className="sr-only">sold by </span>
                  <PartyLink id={r.seller?.id} displayName={r.seller?.display_name} />
                </span>
              </span>
            ),
          },
        ] as Column<OrderRow>[])),
    {
      key: "amount",
      header: "Amount",
      align: "right",
      render: (r) => (
        <span className="flex flex-col items-end whitespace-nowrap">
          <Money cents={r.amount} className="font-semibold" />
          <span className="text-[0.75rem] text-muted">
            total <Money cents={r.total} />
          </span>
        </span>
      ),
    },
    { key: "payment_status", header: "Payment", render: (r) => <StatusBadge status={r.payment_status} label={labelFor("payment", r.payment_status)} qualifier="below" /> },
    { key: "transfer_status", header: "Ticket transfer", render: (r) => <TransferCell r={r} /> },
    { key: "funds", header: "Seller funds", render: (r) => <FundsCell r={r} /> },
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
      card={(r) => (
        <article className="rounded-2xl bg-white p-4">
          <div className="flex items-start justify-between gap-3">
            <OrderName r={r} />
            <span className="shrink-0 whitespace-nowrap text-right">
              <Money cents={r.amount} className="font-semibold" />
              <span className="block text-[0.75rem] text-muted">
                total <Money cents={r.total} />
              </span>
            </span>
          </div>
          <div className="mt-3 grid gap-3 [grid-template-columns:repeat(auto-fit,minmax(min(9rem,100%),1fr))]">
            <Labelled label="Payment">
              <StatusBadge status={r.payment_status} label={labelFor("payment", r.payment_status)} qualifier="below" />
            </Labelled>
            <Labelled label="Ticket transfer">
              <TransferCell r={r} />
            </Labelled>
            <Labelled label="Seller funds">
              <FundsCell r={r} />
            </Labelled>
          </div>
          {hideParties ? null : (
            <p className="mt-3 border-t border-line pt-3 text-[0.8125rem] text-muted">
              <PartyLink id={r.buyer?.id} displayName={r.buyer?.display_name} /> → <PartyLink id={r.seller?.id} displayName={r.seller?.display_name} />
            </p>
          )}
        </article>
      )}
    />
  );
}

function OrderName({ r }: { r: OrderRow }) {
  const title = r.event_name ?? (r.payment_id ? `Order ${shortId(r.payment_id)}` : "Order");
  return (
    <span className="flex min-w-0 flex-col items-start gap-0.5 md:min-w-[12rem]">
      {r.payment_id ? (
        <Link href={`/orders/${r.payment_id}`} className="group inline-flex items-center gap-1 font-semibold text-ink hover:underline hover:underline-offset-4">
          {title}
          <Icon name="chevron" size={14} className="text-dim group-hover:text-ink" />
        </Link>
      ) : (
        <span className="font-semibold text-ink">{title}</span>
      )}
      <span className="text-[0.75rem] text-muted">
        {[r.event_date, r.mode ? r.mode.replace(/_/g, " ") : null].filter(Boolean).join(" · ") || "—"}
        {r.created_at ? (
          <>
            {" · ordered "}
            <TimeAgo value={r.created_at} />
          </>
        ) : null}
      </span>
      {r.open_cases ? (
        <span className="mt-0.5">
          <CasesCell r={r} />
        </span>
      ) : null}
      {r.payment_id ? (
        <code className="bg-transparent p-0 font-mono text-[0.6875rem] text-dim" title={`Payment ${r.payment_id}${r.stripe_payment_intent_id ? ` · ${r.stripe_payment_intent_id}` : ""}`}>
          {shortId(r.payment_id)}
          {r.stripe_payment_intent_id ? ` · ${r.stripe_payment_intent_id}` : ""}
        </code>
      ) : null}
    </span>
  );
}

function TransferCell({ r }: { r: OrderRow }) {
  if (!r.transfer_id) return <span className="text-muted">No transfer</span>;
  return (
    <span className="flex flex-col items-start gap-1">
      <StatusBadge status={r.transfer_status} label={transferStateLabel({ status: r.transfer_status, buyer_confirmed_at: r.buyer_confirmed_at })} qualifier="below" />
      {r.transfer_expires_at && r.transfer_status === "pending" ? (
        <span className="pl-1 text-[0.75rem] text-muted">
          due <TimeAgo value={r.transfer_expires_at} />
        </span>
      ) : null}
    </span>
  );
}

function FundsCell({ r }: { r: OrderRow }) {
  return (
    <StatusBadge
      status={r.seller_funds_state}
      label={labelFor("funds", r.seller_funds_state)}
      variant={r.seller_funds_state === "released_to_connected_account" ? "ok" : undefined}
      qualifier="below"
    />
  );
}

function CasesCell({ r }: { r: OrderRow }) {
  if (!r.open_cases) return null;
  return (
    <Link href={`/cases?subject_id=${r.payment_id ?? ""}`} className="badge badge-red tabular-nums hover:bg-[rgba(196,0,0,0.06)]">
      {r.open_cases} open {r.open_cases === 1 ? "case" : "cases"}
    </Link>
  );
}

function Labelled({ label, children }: { label: string; children: ReactNode }) {
  return (
    <span className="flex min-w-0 flex-col items-start gap-1">
      <span className="text-[0.6875rem] font-medium text-muted">{label}</span>
      {children}
    </span>
  );
}
