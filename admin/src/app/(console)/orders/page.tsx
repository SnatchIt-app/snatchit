import type { Metadata } from "next";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { toListPage, toOrderRows, num } from "@/lib/types";
import { cursorOf, first, limitOf, list, type SearchParams } from "@/lib/search-params";
import { FUNDS_STATE_LABELS, PAYMENT_STATUS_LABELS, TRANSFER_STATUS_LABELS } from "@/lib/format";
import { PageHeader } from "@/components/ui/PageHeader";
import { OpsFailureAlert } from "@/components/ui/Alert";
import { FilterField, FilterForm, FilterSelect } from "@/components/ui/FilterField";
import { OrderTable } from "@/components/orders/OrderTable";

export const metadata: Metadata = { title: "Orders & Transfers" };
export const dynamic = "force-dynamic";

const PAYMENT_STATUSES = ["pending", "processing", "succeeded", "failed", "refunded"];
const TRANSFER_STATUSES = ["pending", "seller_sent", "buyer_confirmed", "auto_released", "disputed", "expired", "reversed"];
const PAYOUT_STATES = ["released", "pending_release", "held", "manual_review", "none"];
const PAYOUT_STATE_LABELS: Record<string, string> = {
  released: FUNDS_STATE_LABELS.released_to_connected_account,
  pending_release: "Pending release (no Stripe Transfer yet)",
  held: "Held",
  manual_review: "Manual review",
  none: "No release pending",
};

const DATE = /^\d{4}-\d{2}-\d{2}$/;

export default async function OrdersPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  await requireOperator();

  const paymentStatus = list(sp.payment_status);
  const transferStatus = list(sp.transfer_status);
  const payoutState = first(sp.payout_state);
  const hasOpenCase = first(sp.has_open_case);
  const from = first(sp.from);
  const to = first(sp.to);
  const q = (first(sp.q) ?? "").trim().slice(0, 200);

  const filters: Record<string, unknown> = {};
  if (paymentStatus) filters.payment_status = paymentStatus;
  if (transferStatus) filters.transfer_status = transferStatus;
  if (payoutState && PAYOUT_STATES.includes(payoutState)) filters.payout_state = payoutState;
  if (hasOpenCase === "true" || hasOpenCase === "false") filters.has_open_case = hasOpenCase === "true";
  if (from && DATE.test(from)) filters.from = `${from}T00:00:00Z`;
  if (to && DATE.test(to)) filters.to = `${to}T23:59:59.999Z`;
  if (q) filters.q = q;

  const res = await callOps<unknown>("list_orders", { p_filters: filters, p_cursor: cursorOf(sp), p_limit: limitOf(sp) });
  const page = res.ok ? toListPage(res.data) : null;
  const rows = page ? toOrderRows(page.items) : [];
  const countHint = res.ok && typeof res.data === "object" && res.data !== null ? num((res.data as Record<string, unknown>).count_hint) : null;

  return (
    <>
      <PageHeader
        eyebrow="Money movement"
        title="Orders & Transfers"
        description="Each captured payment creates a seller transfer obligation. Captured payment ≠ refund ≠ dispute ≠ connected-account transfer ≠ bank payout (not tracked)."
        meta={countHint !== null ? `${countHint.toLocaleString("en-US")} matching order${countHint === 1 ? "" : "s"}` : undefined}
      />

      <FilterForm action="/orders">
        <FilterField label="Payment status">
          <FilterSelect name="payment_status" options={PAYMENT_STATUSES} value={first(sp.payment_status)} labels={PAYMENT_STATUS_LABELS} />
        </FilterField>
        <FilterField label="Transfer status">
          <FilterSelect name="transfer_status" options={TRANSFER_STATUSES} value={first(sp.transfer_status)} labels={TRANSFER_STATUS_LABELS} />
        </FilterField>
        <FilterField label="Seller funds">
          <FilterSelect name="payout_state" options={PAYOUT_STATES} value={payoutState} labels={PAYOUT_STATE_LABELS} />
        </FilterField>
        <FilterField label="Open case">
          <select name="has_open_case" defaultValue={hasOpenCase ?? ""} className="field min-w-[120px] py-1.5 text-[13px]">
            <option value="">Any</option>
            <option value="true">Has open case</option>
            <option value="false">No open case</option>
          </select>
        </FilterField>
        <FilterField label="Created from (UTC)">
          <input type="date" name="from" defaultValue={from ?? ""} className="field py-1.5 text-[13px]" />
        </FilterField>
        <FilterField label="To (UTC)">
          <input type="date" name="to" defaultValue={to ?? ""} className="field py-1.5 text-[13px]" />
        </FilterField>
        <FilterField label="Search" className="min-w-[220px]">
          <input name="q" defaultValue={q} placeholder="payment/transfer/listing id, pi_, tr_, re_, event" className="field py-1.5 text-[13px]" />
        </FilterField>
      </FilterForm>

      {!res.ok ? <OpsFailureAlert failure={res} fn="list_orders" retryHref="/orders" /> : <OrderTable rows={rows} basePath="/orders" searchParams={sp} nextCursor={page?.next_cursor} />}
    </>
  );
}
