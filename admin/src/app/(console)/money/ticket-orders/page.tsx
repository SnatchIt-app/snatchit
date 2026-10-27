import { PageHeader } from "@/components/ui/PageHeader";
import { Panel } from "@/components/ui/Panel";
import { OpsFailureAlert } from "@/components/ui/Alert";
import { DataTable, type Column } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DateTime } from "@/components/ui/DateTime";
import { PrimaryRefundForm } from "@/components/money/PrimaryRefundForm";
import { requireOperator } from "@/lib/auth/session";
import { formatMoney } from "@/lib/format";
import { newRefundKey, readPrimaryReconciliation } from "@/lib/primary-refund-actions";
import { doorWouldStillAdmit, refundSidesAgree, type PrimaryRow } from "@/lib/primary-money";

export const dynamic = "force-dynamic";
export const metadata = { title: "Ticket orders" };

/**
 * Ticket (primary) orders and their money — readiness row 8, on migration 189.
 *
 * The console's only view of primary money: per order, what was paid, what the
 * tickets are doing, and BOTH refund sides — what this system recorded and what
 * Stripe reports. Where they disagree the server names it, and the worst case
 * is first: Stripe refunded but the tickets are still live, so the door would
 * still admit them.
 *
 * Refunds are manual by owner decision. "Record this refund" voids the order's
 * voidable tickets and writes the refund row under the operator's name; a
 * person then refunds the PaymentIntent in Stripe, and the webhook brings the
 * other side back here. Nothing on this page moves money.
 */
export default async function TicketOrdersPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  await requireOperator();
  const sp = await searchParams;
  const one = (k: string) => (typeof sp[k] === "string" ? (sp[k] as string) : null);
  const res = await readPrimaryReconciliation(one("from"), one("to"));
  const open = one("refund");

  if (!res.ok) {
    return (
      <>
        <PageHeader eyebrow="Money" title="Ticket orders" description="Primary ticket orders, their tickets, and both refund sides." />
        <OpsFailureAlert failure={res} fn="primary_reconciliation" retryHref="/money/ticket-orders" subject="Ticket orders" />
      </>
    );
  }

  const r = res.data;
  const refundKey = open ? await newRefundKey() : null;
  const openRow = open ? r.rows.find((x) => x.orderId === open) ?? null : null;

  const columns: Column<PrimaryRow>[] = [
    { key: "order", header: "Order", render: (x) => <code className="font-mono">{(x.orderId ?? "").slice(0, 8)}</code>, sortValue: (x) => x.orderId ?? null },
    { key: "linked_at", header: "Paid", render: (x) => <DateTime value={x.linkedAt} />, sortValue: (x) => x.linkedAt ?? null },
    {
      key: "status",
      header: "Order",
      render: (x) => (
        <span className="flex flex-wrap items-center gap-1">
          <StatusBadge status={x.orderStatus} />
          {x.stripeLivemode === false ? <span className="text-[0.6875rem] uppercase tracking-wide text-dim">stripe test mode</span> : null}
        </span>
      ),
    },
    { key: "paid", header: "Paid", align: "right", render: (x) => <span className="tabular-nums">{x.paymentTotalMinor === null ? "—" : formatMoney(x.paymentTotalMinor)}</span>, sortValue: (x) => x.paymentTotalMinor },
    {
      key: "tickets",
      header: "Tickets",
      render: (x) => (
        <span className="text-[0.8125rem]">
          {x.ticketsIssued ?? "—"} issued · {x.ticketsVoided ?? "—"} voided · {x.ticketsAdmitted ?? "—"} admitted ·{" "}
          <strong className={doorWouldStillAdmit(x) ? "text-ink" : "text-dim"}>{x.ticketsLive ?? "—"} live</strong>
        </span>
      ),
    },
    {
      key: "refunds",
      header: "Refunded here / at Stripe",
      align: "right",
      render: (x) => {
        const agree = refundSidesAgree(x);
        return (
          <span className="tabular-nums">
            {x.kernelRefundMinor === null ? "—" : formatMoney(x.kernelRefundMinor)} / {x.stripeRefundSucceededMinor === null ? "unknown" : formatMoney(x.stripeRefundSucceededMinor)}
            {agree === false ? <span className="ml-1 text-danger">disagree</span> : null}
            {(x.stripeRefundOpenMinor ?? 0) > 0 ? <span className="ml-1 text-warning">({formatMoney(x.stripeRefundOpenMinor)} pending at Stripe)</span> : null}
          </span>
        );
      },
    },
    {
      key: "act",
      header: "",
      render: (x) =>
        x.orderId ? (
          <a href={`/money/ticket-orders?refund=${encodeURIComponent(x.orderId)}`} className="link text-[0.8125rem]">
            Record a refund
          </a>
        ) : null,
    },
  ];

  return (
    <>
      <PageHeader
        eyebrow="Money"
        title="Ticket orders"
        description="Primary ticket orders: what was paid, what the tickets are doing, and both refund sides. Refunds are recorded here and paid by hand in Stripe."
        meta={
          <>
            {r.count ?? 0} order{r.count === 1 ? "" : "s"}
            {r.attentionCount ? ` · ${r.attentionCount} needing attention` : ""}
            {r.criticalCount ? ` · ${r.criticalCount} critical` : ""}
            {r.computedAt ? (
              <>
                {" · as of "}
                <DateTime value={r.computedAt} withSeconds />
              </>
            ) : null}
          </>
        }
      />

      {r.basis ? <p className="mb-4 text-xs text-dim">Counted by {r.basis}.</p> : null}

      {r.attention.length > 0 ? (
        <Panel eyebrow="Read-only detector" title="Money facts that disagree" description="Named by the server, worst first.">
          <ul className="divide-y divide-line-neutral text-sm">
            {r.attention.map((a, i) => (
              <li key={`${a.code}-${a.orderId ?? i}`} className="flex flex-wrap items-start gap-2 py-2">
                <StatusBadge status={a.severity ?? "warning"} />
                <span className="font-medium">{a.code.replace(/_/g, " ")}</span>
                <span className="min-w-0 flex-1 text-muted">{a.message ?? "—"}</span>
                {a.orderId ? (
                  <a href={`/money/ticket-orders?refund=${encodeURIComponent(a.orderId)}`} className="link shrink-0 text-[0.8125rem]">
                    Record a refund
                  </a>
                ) : null}
              </li>
            ))}
          </ul>
        </Panel>
      ) : null}

      {open && refundKey ? (
        <Panel eyebrow={`Order ${open.slice(0, 8)}`} title="Record a manual refund" description="Voids the order's voidable tickets and writes the refund. It does not move money.">
          {openRow ? (
            <PrimaryRefundForm orderId={open} maxMinor={openRow.paymentTotalMinor ?? openRow.orderTotalMinor ?? null} commandKey={refundKey} />
          ) : (
            <p className="text-sm text-muted">That order is not in the period shown. Widen the dates, or open it from its own row.</p>
          )}
        </Panel>
      ) : null}

      <section aria-labelledby="primary-orders" className="mt-6">
        <h2 id="primary-orders" className="mb-2 title-section">
          Orders
        </h2>
        <DataTable
          id="primary-orders-table"
          columns={columns}
          rows={r.rows}
          rowKey={(x, i) => x.orderId ?? `${i}`}
          basePath="/money/ticket-orders"
          searchParams={sp}
          emptyText="No ticket orders in this period."
          filterable
          dense
        />
      </section>
    </>
  );
}
