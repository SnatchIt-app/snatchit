import type { Metadata } from "next";
import Link from "next/link";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { toListPage, toOrderRows, num } from "@/lib/types";
import { cursorOf, first, limitOf, list, type SearchParams } from "@/lib/search-params";
import { FUNDS_STATE_LABELS, PAYMENT_STATUS_LABELS, TRANSFER_STATUS_LABELS } from "@/lib/format";
import { PageHeader } from "@/components/ui/PageHeader";
import { OpsFailureAlert } from "@/components/ui/Alert";
import { OrderTable } from "@/components/orders/OrderTable";
import { Icon } from "@/components/ui/Icon";

export const metadata: Metadata = { title: "Orders" };
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
const OPEN_CASE_LABELS: Record<string, string> = { true: "Has an open case", false: "No open case" };

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const FILTER_KEYS = ["payment_status", "transfer_status", "payout_state", "has_open_case", "from", "to"] as const;
type FilterKey = (typeof FILTER_KEYS)[number];

/**
 * Saved views: the questions an operator brings to this page, as one click.
 * Each is only a preset of the filters below — nothing the filter column
 * cannot also express.
 */
const VIEWS: { key: string; label: string; params: Partial<Record<FilterKey, string>> }[] = [
  { key: "all", label: "All orders", params: {} },
  { key: "cases", label: "Open cases", params: { has_open_case: "true" } },
  { key: "delivery", label: "Awaiting seller delivery", params: { transfer_status: "pending" } },
  { key: "disputed", label: "Disputed", params: { transfer_status: "disputed" } },
  { key: "review", label: "Manual review", params: { payout_state: "manual_review" } },
  { key: "refunds", label: "Refund recorded", params: { payment_status: "refunded" } },
];

function href(params: Record<string, string | undefined>): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v) q.set(k, v);
  const s = q.toString();
  return s ? `/orders?${s}` : "/orders";
}

export default async function OrdersPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  await requireOperator();

  const paymentStatus = list(sp.payment_status)?.filter((s) => PAYMENT_STATUSES.includes(s));
  const transferStatus = list(sp.transfer_status)?.filter((s) => TRANSFER_STATUSES.includes(s));
  const payoutState = first(sp.payout_state);
  const hasOpenCase = first(sp.has_open_case);
  const from = first(sp.from);
  const to = first(sp.to);
  const q = (first(sp.q) ?? "").trim().slice(0, 200);

  const filters: Record<string, unknown> = {};
  if (paymentStatus?.length) filters.payment_status = paymentStatus;
  if (transferStatus?.length) filters.transfer_status = transferStatus;
  if (payoutState && PAYOUT_STATES.includes(payoutState)) filters.payout_state = payoutState;
  if (hasOpenCase === "true" || hasOpenCase === "false") filters.has_open_case = hasOpenCase === "true";
  if (from && DATE.test(from)) filters.from = `${from}T00:00:00Z`;
  if (to && DATE.test(to)) filters.to = `${to}T23:59:59.999Z`;
  if (q) filters.q = q;

  const res = await callOps<unknown>("list_orders", { p_filters: filters, p_cursor: cursorOf(sp), p_limit: limitOf(sp) });
  const page = res.ok ? toListPage(res.data) : null;
  const rows = page ? toOrderRows(page.items) : [];
  const countHint = res.ok && typeof res.data === "object" && res.data !== null ? num((res.data as Record<string, unknown>).count_hint) : null;

  // The filters as applied, normalised, so views and chips compare like with like.
  const applied: Partial<Record<FilterKey, string>> = {
    payment_status: paymentStatus?.length ? paymentStatus.join(",") : undefined,
    transfer_status: transferStatus?.length ? transferStatus.join(",") : undefined,
    payout_state: payoutState && PAYOUT_STATES.includes(payoutState) ? payoutState : undefined,
    has_open_case: hasOpenCase === "true" || hasOpenCase === "false" ? hasOpenCase : undefined,
    from: from && DATE.test(from) ? from : undefined,
    to: to && DATE.test(to) ? to : undefined,
  };
  const activeView = VIEWS.find((v) => FILTER_KEYS.every((k) => (v.params[k] ?? undefined) === applied[k]))?.key ?? null;
  const chips = chipList(applied);
  const filterCount = chips.length;

  return (
    <>
      <PageHeader
        title="Orders"
        meta={countHint !== null ? `${countHint.toLocaleString("en-US")}${filterCount || q ? " matching" : ""} order${countHint === 1 ? "" : "s"}` : "Money movement"}
        description="Each captured payment creates a seller transfer obligation. Payment, refund, dispute, connected-account transfer and bank payout are separate facts — bank payouts are not tracked here."
      />

      <section aria-label="Orders" className="md:rounded-[20px] md:bg-white md:p-5">
        {/* Saved views — the reference's tab row, as filter pills. */}
        <nav aria-label="Saved views" className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 [scrollbar-width:none] md:mx-0 md:px-0">
          {VIEWS.map((v) => (
            <Link key={v.key} href={href({ ...v.params, q: q || undefined })} aria-current={activeView === v.key ? "page" : undefined} className="filter-chip shrink-0">
              {v.label}
            </Link>
          ))}
        </nav>

        <div className="mt-4 grid gap-4 xl:grid-cols-[15rem_minmax(0,1fr)]">
          {/* Filters: a column on wide screens, a disclosure below that. */}
          <aside className="hidden xl:block" aria-label="Filters">
            <FilterPanel idPrefix="d" applied={applied} q={q} count={filterCount} />
          </aside>

          <div className="min-w-0 md:rounded-[14px] md:border md:border-line md:bg-white">
            <div className="flex flex-wrap items-center gap-2 pb-3 md:border-b md:border-line md:p-3">
              <details className="xl:hidden">
                <summary className="filter-chip">
                  <Icon name="filter" size={15} />
                  Filters
                  {filterCount ? <span className="count">{filterCount}</span> : null}
                </summary>
                <div className="mt-3 w-[min(22rem,calc(100vw-4rem))]">
                  <FilterPanel idPrefix="m" applied={applied} q={q} count={filterCount} />
                </div>
              </details>
              <form method="get" action="/orders" role="search" className="search-pill min-w-[12rem] flex-1 md:max-w-sm">
                <Icon name="search" size={16} className="text-dim" />
                <label htmlFor="orders-q" className="sr-only">
                  Search orders
                </label>
                <input id="orders-q" name="q" type="search" defaultValue={q} placeholder="Payment, pi_, tr_, re_, listing or event" autoComplete="off" spellCheck={false} />
                {FILTER_KEYS.map((k) => (applied[k] ? <input key={k} type="hidden" name={k} value={applied[k]} /> : null))}
              </form>
            </div>

            {chips.length > 0 || q ? (
              <div className="flex flex-wrap items-center gap-2 pb-3 md:border-b md:border-line md:px-3 md:py-2.5">
                {q ? <RemovableChip label={`Search: ${q}`} href={href({ ...applied })} /> : null}
                {chips.map((c) => (
                  <RemovableChip key={c.key} label={c.label} href={href({ ...applied, [c.key]: undefined, q: q || undefined })} />
                ))}
                <Link href="/orders" className="ml-1 text-[0.8125rem] font-medium text-muted underline-offset-4 hover:text-ink hover:underline">
                  Clear all
                </Link>
              </div>
            ) : null}

            <div>
              {!res.ok ? (
                <div className="p-3">
                  <OpsFailureAlert failure={res} fn="list_orders" retryHref="/orders" />
                </div>
              ) : (
                <OrderTable
                  rows={rows}
                  basePath="/orders"
                  searchParams={sp}
                  nextCursor={page?.next_cursor}
                  emptyText={filterCount || q ? "No orders match these filters." : "No orders yet."}
                />
              )}
            </div>
          </div>
        </div>
      </section>
    </>
  );
}

function chipList(applied: Partial<Record<FilterKey, string>>): { key: FilterKey; label: string }[] {
  const out: { key: FilterKey; label: string }[] = [];
  const names = (v: string, labels: Record<string, string>) =>
    v
      .split(",")
      .map((x) => labels[x] ?? x.replace(/_/g, " "))
      .join(", ");
  if (applied.payment_status) out.push({ key: "payment_status", label: `Payment: ${names(applied.payment_status, PAYMENT_STATUS_LABELS)}` });
  if (applied.transfer_status) out.push({ key: "transfer_status", label: `Ticket transfer: ${names(applied.transfer_status, TRANSFER_STATUS_LABELS)}` });
  if (applied.payout_state) out.push({ key: "payout_state", label: `Seller funds: ${PAYOUT_STATE_LABELS[applied.payout_state]}` });
  if (applied.has_open_case) out.push({ key: "has_open_case", label: OPEN_CASE_LABELS[applied.has_open_case] });
  if (applied.from) out.push({ key: "from", label: `From ${applied.from} (UTC)` });
  if (applied.to) out.push({ key: "to", label: `To ${applied.to} (UTC)` });
  return out;
}

function RemovableChip({ label, href }: { label: string; href: string }) {
  return (
    <Link href={href} className="badge gap-1.5 py-1 pr-1.5 hover:border-[rgba(11,11,11,0.4)]" aria-label={`Remove filter: ${label}`}>
      {label}
      <span aria-hidden="true" className="grid h-4 w-4 place-items-center rounded-full bg-[#ececeb]">
        <Icon name="close" size={10} strokeWidth={2.5} />
      </span>
    </Link>
  );
}

/** The reference's filter column: grey group headers, checkbox lists, Clear all + Apply. */
function FilterPanel({ idPrefix, applied, q, count }: { idPrefix: string; applied: Partial<Record<FilterKey, string>>; q: string; count: number }) {
  const has = (k: FilterKey, v: string) => (applied[k] ?? "").split(",").includes(v);
  return (
    <form method="get" action="/orders" className="inset flex flex-col">
      <div className="flex items-center justify-between px-4 pb-2 pt-4">
        <p className="flex items-center gap-2 text-[0.9375rem] font-semibold">
          Filters {count ? <span className="count bg-[#ececeb]">{count}</span> : null}
        </p>
      </div>
      {q ? <input type="hidden" name="q" value={q} /> : null}
      <div className="flex flex-col gap-3 px-3 pb-3">
        <Group title="Payment" count={(applied.payment_status ?? "").split(",").filter(Boolean).length}>
          {PAYMENT_STATUSES.map((s) => (
            <Check key={s} id={`${idPrefix}-pay-${s}`} name="payment_status" value={s} label={PAYMENT_STATUS_LABELS[s] ?? s} checked={has("payment_status", s)} />
          ))}
        </Group>
        <Group title="Ticket transfer" count={(applied.transfer_status ?? "").split(",").filter(Boolean).length}>
          {TRANSFER_STATUSES.map((s) => (
            <Check key={s} id={`${idPrefix}-tr-${s}`} name="transfer_status" value={s} label={TRANSFER_STATUS_LABELS[s] ?? s} checked={has("transfer_status", s)} />
          ))}
        </Group>
        <Group title="Seller funds" count={applied.payout_state ? 1 : 0}>
          <Radio id={`${idPrefix}-po-any`} name="payout_state" value="" label="Any" checked={!applied.payout_state} />
          {PAYOUT_STATES.map((s) => (
            <Radio key={s} id={`${idPrefix}-po-${s}`} name="payout_state" value={s} label={PAYOUT_STATE_LABELS[s]} checked={applied.payout_state === s} />
          ))}
        </Group>
        <Group title="Cases" count={applied.has_open_case ? 1 : 0}>
          <Radio id={`${idPrefix}-oc-any`} name="has_open_case" value="" label="Any" checked={!applied.has_open_case} />
          <Radio id={`${idPrefix}-oc-t`} name="has_open_case" value="true" label={OPEN_CASE_LABELS.true} checked={applied.has_open_case === "true"} />
          <Radio id={`${idPrefix}-oc-f`} name="has_open_case" value="false" label={OPEN_CASE_LABELS.false} checked={applied.has_open_case === "false"} />
        </Group>
        <Group title="Created (UTC)" count={(applied.from ? 1 : 0) + (applied.to ? 1 : 0)}>
          <label htmlFor={`${idPrefix}-from`} className="grid gap-1 text-[0.8125rem] text-muted">
            From
            <input id={`${idPrefix}-from`} type="date" name="from" defaultValue={applied.from ?? ""} className="field" />
          </label>
          <label htmlFor={`${idPrefix}-to`} className="mt-2 grid gap-1 text-[0.8125rem] text-muted">
            To
            <input id={`${idPrefix}-to`} type="date" name="to" defaultValue={applied.to ?? ""} className="field" />
          </label>
        </Group>
      </div>
      <div className="mt-auto flex items-center justify-between gap-2 border-t border-line p-3">
        <Link href={q ? href({ q }) : "/orders"} className="btn btn-ghost btn-sm">
          Clear all
        </Link>
        <button type="submit" className="btn btn-primary btn-sm">
          <Icon name="check" size={15} />
          Apply filters
        </button>
      </div>
    </form>
  );
}

function Group({ title, count, children }: { title: string; count: number; children: React.ReactNode }) {
  return (
    <details className="group" open={count > 0 || title === "Payment" || title === "Ticket transfer"}>
      <summary className="well flex min-h-10 items-center justify-between px-3 text-[0.8125rem] font-medium">
        <span>{title}</span>
        <span className="flex items-center gap-1.5">
          {count ? <span className="count">{count}</span> : null}
          <Icon name="down" size={14} className="transition-transform group-open:rotate-180" />
        </span>
      </summary>
      <fieldset className="mt-2 flex flex-col gap-0.5 px-1">
        <legend className="sr-only">{title}</legend>
        {children}
      </fieldset>
    </details>
  );
}

function Check({ id, name, value, label, checked }: { id: string; name: string; value: string; label: string; checked: boolean }) {
  return (
    <label htmlFor={id} className="flex min-h-9 cursor-pointer items-start gap-2.5 rounded-lg px-1.5 py-1.5 text-[0.8125rem] leading-snug hover:bg-[#f6f6f5]">
      <input id={id} type="checkbox" name={name} value={value} defaultChecked={checked} className="mt-0.5 h-4 w-4 shrink-0 accent-[#0f0f10]" />
      <span>{label}</span>
    </label>
  );
}

function Radio({ id, name, value, label, checked }: { id: string; name: string; value: string; label: string; checked: boolean }) {
  return (
    <label htmlFor={id} className="flex min-h-9 cursor-pointer items-start gap-2.5 rounded-lg px-1.5 py-1.5 text-[0.8125rem] leading-snug hover:bg-[#f6f6f5]">
      <input id={id} type="radio" name={name} value={value} defaultChecked={checked} className="mt-0.5 h-4 w-4 shrink-0 accent-[#0f0f10]" />
      <span>{label}</span>
    </label>
  );
}
