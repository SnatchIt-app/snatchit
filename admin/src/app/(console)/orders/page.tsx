import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { toListPage, toOrderRows, num, type OrderRow } from "@/lib/types";
import { cursorOf, first, limitOf, list, type SearchParams } from "@/lib/search-params";
import { FUNDS_STATE_LABELS, PAYMENT_STATUS_LABELS, TRANSFER_STATUS_LABELS, isPast, labelFor, transferStateLabel } from "@/lib/format";
import { PageHeader } from "@/components/ui/PageHeader";
import { OpsFailureAlert } from "@/components/ui/Alert";
import { OrderTable } from "@/components/orders/OrderTable";
import { OrderDrawer } from "@/components/orders/OrderDrawer";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { Money } from "@/components/ui/Money";
import { DateTime, TimeAgo } from "@/components/ui/DateTime";
import { PartyLink } from "@/components/ui/IdLink";
import { Icon, type IconName } from "@/components/ui/Icon";

export const metadata: Metadata = { title: "Orders & transfers" };
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
type Params = Partial<Record<FilterKey, string>>;

/**
 * The work queue. Four saved views carry the questions an operator brings to
 * this page and show how many orders each one holds right now. Every view is
 * only a preset of the filters — nothing the filter chips cannot also express.
 */
const QUEUES: { key: string; label: string; hint: string; icon: IconName; params: Params }[] = [
  { key: "cases", label: "Open cases", hint: "An order someone is working on", icon: "case", params: { has_open_case: "true" } },
  { key: "delivery", label: "Awaiting seller delivery", hint: "Paid; ticket not yet sent", icon: "clock", params: { transfer_status: "pending" } },
  { key: "disputed", label: "Disputed", hint: "Buyer raised a problem", icon: "alert", params: { transfer_status: "disputed" } },
  { key: "review", label: "Manual review", hint: "Seller funds held for a person", icon: "flag", params: { payout_state: "manual_review" } },
];

function href(params: Record<string, string | undefined>): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v) q.set(k, v);
  const s = q.toString();
  return s ? `/orders?${s}` : "/orders";
}

function toFilters(p: Params): Record<string, unknown> {
  const f: Record<string, unknown> = {};
  if (p.payment_status) f.payment_status = p.payment_status.split(",");
  if (p.transfer_status) f.transfer_status = p.transfer_status.split(",");
  if (p.payout_state) f.payout_state = p.payout_state;
  if (p.has_open_case) f.has_open_case = p.has_open_case === "true";
  if (p.from) f.from = `${p.from}T00:00:00Z`;
  if (p.to) f.to = `${p.to}T23:59:59.999Z`;
  return f;
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
  const open = first(sp.open) ?? null;

  const applied: Params = {
    payment_status: paymentStatus?.length ? paymentStatus.join(",") : undefined,
    transfer_status: transferStatus?.length ? transferStatus.join(",") : undefined,
    payout_state: payoutState && PAYOUT_STATES.includes(payoutState) ? payoutState : undefined,
    has_open_case: hasOpenCase === "true" || hasOpenCase === "false" ? hasOpenCase : undefined,
    from: from && DATE.test(from) ? from : undefined,
    to: to && DATE.test(to) ? to : undefined,
  };
  const filters = toFilters(applied);
  if (q) filters.q = q;

  // The page, plus one count per queue. count_hint when the read gives one;
  // otherwise the first page itself, which is exact when there is no next page.
  const [res, ...queueRes] = await Promise.all([
    callOps<unknown>("list_orders", { p_filters: filters, p_cursor: cursorOf(sp), p_limit: limitOf(sp) }),
    ...QUEUES.map((v) => callOps<unknown>("list_orders", { p_filters: toFilters(v.params), p_cursor: null, p_limit: 100 })),
  ]);
  // count_hint is omitted when nothing matches; an empty first page is a real zero.
  const countOf = (r: { ok: boolean; data?: unknown }) => {
    if (!r.ok || typeof r.data !== "object" || r.data === null) return null;
    const hint = num((r.data as Record<string, unknown>).count_hint);
    if (hint !== null) return hint;
    const lp = toListPage(r.data);
    return lp.next_cursor ? null : lp.items.length;
  };
  const page = res.ok ? toListPage(res.data) : null;
  const rows = page ? toOrderRows(page.items) : [];
  const countHint = countOf(res);

  const same = (p: Params) => FILTER_KEYS.every((k) => (p[k] ?? undefined) === applied[k]);
  const activeQueue = QUEUES.find((v) => same(v.params))?.key ?? null;
  const chips = chipList(applied);
  const filterCount = chips.length;
  const keep = { ...applied, q: q || undefined };
  const openHref = (id: string) => href({ ...keep, cursor: first(sp.cursor), open: id });
  const closeHref = href({ ...keep, cursor: first(sp.cursor) });
  const opened = open ? (rows.find((r) => r.payment_id === open) ?? null) : null;

  return (
    <>
      <PageHeader
        eyebrow="Money"
        title="Orders & transfers"
        meta={countHint !== null ? `${countHint.toLocaleString("en-US")}${filterCount || q ? " matching" : ""} order${countHint === 1 ? "" : "s"}` : undefined}
        description="Each captured payment creates a seller transfer obligation. Payment, refund, dispute, connected-account transfer and bank payout are separate facts — bank payouts are not tracked here."
      />

      {/* What needs a person — counts first, and each card is the view. */}
      <nav aria-labelledby="queues-h" className="enter-2 mb-6">
        <h2 id="queues-h" className="sr-only">
          Work queues
        </h2>
        {/* Grouped figures (approved concept): one panel, cells divided by hairlines. Each cell is the view. */}
        <ul className="grid grid-cols-2 gap-px overflow-hidden rounded-[20px] border border-[rgba(70,50,30,0.09)] bg-[rgba(70,50,30,0.09)] xl:grid-cols-4">
          {QUEUES.map((v, i) => {
            const n = countOf(queueRes[i]);
            const on = activeQueue === v.key;
            return (
              <li key={v.key} className="min-w-0">
                <Link
                  href={on ? href({ q: q || undefined }) : href({ ...v.params, q: q || undefined })}
                  aria-current={on ? "page" : undefined}
                  aria-label={`${v.label}: ${n ?? "count unavailable"}${on ? " — showing; select to clear" : ""}`}
                  className={`group relative flex h-full flex-col px-5 pb-4 pt-4 transition-colors md:px-6 ${on ? "bg-white" : "bg-[#fffdfa] hover:bg-white"}`}
                >
                  {on ? <span aria-hidden="true" className="absolute inset-x-5 bottom-0 h-[3px] rounded-full bg-[#26211d] md:inset-x-6" /> : null}
                  <span className="flex items-center justify-between gap-2 text-[0.875rem] text-muted group-hover:text-ink">
                    <span className="flex items-center gap-2">
                      <Icon name={v.icon} size={16} strokeWidth={1.6} className={n ? "text-[#a82d17]" : ""} />
                      {v.label}
                    </span>
                    <span aria-hidden="true" className="text-[0.75rem]">{on ? "Clear" : ""}</span>
                  </span>
                  {n === null ? (
                    <span className="mt-3 text-[0.9375rem] font-medium leading-[2.625rem] text-muted">Count unavailable</span>
                  ) : (
                    <span className="stat-num mt-3">{n}</span>
                  )}
                  <span className="mt-2 text-[0.75rem] text-muted">{v.hint}</span>
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>

      <section aria-labelledby="orders-h" className="panel enter-3 min-w-0 overflow-visible">
        <h2 id="orders-h" className="sr-only">
          {filterCount || q ? "Matching orders" : "All orders"}
        </h2>
        <div className="flex flex-wrap items-center gap-2 border-b border-line p-3 md:p-4">
          <div className="flex flex-wrap items-center gap-2">
            <DimensionChip title="Payment" name="payment_status" kind="check" options={PAYMENT_STATUSES.map((v) => [v, PAYMENT_STATUS_LABELS[v] ?? v])} applied={applied} q={q} />
            <DimensionChip title="Ticket transfer" name="transfer_status" kind="check" options={TRANSFER_STATUSES.map((v) => [v, TRANSFER_STATUS_LABELS[v] ?? v])} applied={applied} q={q} />
            <DimensionChip title="Seller funds" name="payout_state" kind="radio" options={PAYOUT_STATES.map((v) => [v, PAYOUT_STATE_LABELS[v]])} applied={applied} q={q} />
            <DimensionChip title="Cases" name="has_open_case" kind="radio" options={[["true", OPEN_CASE_LABELS.true], ["false", OPEN_CASE_LABELS.false]]} applied={applied} q={q} />
            <DimensionChip title="Created" name="from" kind="dates" options={[]} applied={applied} q={q} />
          </div>
          <form method="get" action="/orders" role="search" className="search-pill min-w-[12rem] flex-1 lg:ml-auto lg:max-w-xs">
            <Icon name="search" size={16} className="text-dim" />
            <label htmlFor="orders-q" className="sr-only">
              Search orders by payment, pi_, tr_, re_, listing or event
            </label>
            <input id="orders-q" name="q" type="search" defaultValue={q} placeholder="Payment, pi_, tr_, re_, event" autoComplete="off" spellCheck={false} />
            {FILTER_KEYS.map((k) => (applied[k] ? <input key={k} type="hidden" name={k} value={applied[k]} /> : null))}
          </form>
        </div>

        {chips.length > 0 || q ? (
          <div className="flex flex-wrap items-center gap-2 border-b border-line px-3 py-2.5 md:px-4">
            <span className="text-[0.75rem] font-medium text-muted">Showing</span>
            {q ? <RemovableChip label={`Search: ${q}`} href={href({ ...applied })} /> : null}
            {chips.map((c) => (
              <RemovableChip key={c.key} label={c.label} href={href({ ...applied, [c.key]: undefined, q: q || undefined })} />
            ))}
            <Link href="/orders" className="ml-1 rounded-full px-2 text-[0.8125rem] font-medium text-muted underline-offset-4 hover:text-ink hover:underline">
              Clear all
            </Link>
          </div>
        ) : null}

        <div className="p-2 md:p-1">
          {!res.ok ? (
            <div className="p-3">
              <OpsFailureAlert failure={res} fn="list_orders" retryHref="/orders" subject="Orders" />
            </div>
          ) : rows.length === 0 ? (
            <div className="flex flex-col items-center px-6 py-14 text-center">
              <span className="grid h-12 w-12 place-items-center rounded-full bg-[#f5f3ef]">
                <Icon name={filterCount || q ? "filter" : "receipt"} size={20} />
              </span>
              <p className="title-section mt-4">{filterCount || q ? "No orders match these filters." : "No orders yet."}</p>
              <p className="mt-1 max-w-sm text-[0.875rem] text-muted">{filterCount || q ? "Remove a filter or search for a payment, pi_, tr_ or re_ id instead." : "Orders appear here as soon as a buyer pays."}</p>
              {filterCount || q ? (
                <Link href="/orders" className="btn btn-ghost mt-5">
                  Show all orders
                </Link>
              ) : null}
            </div>
          ) : (
            <OrderTable rows={rows} basePath="/orders" searchParams={sp} nextCursor={page?.next_cursor} openHref={openHref} selectedId={open} />
          )}
        </div>
      </section>

      {open ? (
        <OrderDrawer id={open} closeHref={closeHref} title={opened?.event_name ?? "Order"}>
          {opened ? <OrderPreview r={opened} /> : <NotOnPage id={open} />}
        </OrderDrawer>
      ) : null}
    </>
  );
}

/** The drawer body: what happened to the money and the ticket, then the references. */
function OrderPreview({ r }: { r: OrderRow }) {
  const id = r.payment_id ?? "";
  return (
    <div className="flex flex-col gap-6">
      <div>
        <p className="figure text-[2rem] leading-none">
          <Money cents={r.amount} />
        </p>
        <p className="mt-1.5 text-[0.8125rem] text-muted">
          Buyer paid <Money cents={r.total} /> in total{r.created_at ? <> · ordered <TimeAgo value={r.created_at} /></> : null}
        </p>
        {r.open_cases ? (
          <Link href={`/cases?subject_id=${id}`} className="badge badge-red mt-3">
            {r.open_cases} open {r.open_cases === 1 ? "case" : "cases"} — view
          </Link>
        ) : null}
      </div>

      <ol className="flex flex-col">
        <Step n={1} title="Payment">
          <StatusBadge status={r.payment_status} label={labelFor("payment", r.payment_status)} qualifier="below" />
        </Step>
        <Step n={2} title="Ticket transfer">
          {r.transfer_id ? (
            <span className="flex flex-col items-start gap-1">
              <StatusBadge status={r.transfer_status} label={transferStateLabel({ status: r.transfer_status, buyer_confirmed_at: r.buyer_confirmed_at })} qualifier="below" />
              {r.transfer_expires_at && r.transfer_status === "pending" ? (
                <span className={`pl-1 text-[0.75rem] ${isPast(r.transfer_expires_at) ? "font-medium text-danger" : "text-muted"}`}>
                  {isPast(r.transfer_expires_at) ? "Deadline passed " : "Deadline "}
                  <TimeAgo value={r.transfer_expires_at} />
                </span>
              ) : null}
            </span>
          ) : (
            <span className="text-[0.8125rem] text-muted">No transfer</span>
          )}
        </Step>
        <Step n={3} title="Seller funds" last>
          <StatusBadge status={r.seller_funds_state} label={labelFor("funds", r.seller_funds_state)} variant={r.seller_funds_state === "released_to_connected_account" ? "ok" : undefined} qualifier="below" />
          {r.payout_hold_until ? (
            <p className="mt-1 pl-1 text-[0.75rem] text-muted">
              Held until <DateTime value={r.payout_hold_until} relative={false} />
            </p>
          ) : null}
        </Step>
      </ol>

      <dl className="grid grid-cols-[7rem_minmax(0,1fr)] gap-x-4 gap-y-2 rounded-2xl bg-[#faf9f7] p-4 text-[0.8125rem]">
        <dt className="text-muted">Buyer</dt>
        <dd>
          <PartyLink id={r.buyer?.id} displayName={r.buyer?.display_name} />
        </dd>
        <dt className="text-muted">Seller</dt>
        <dd>
          <PartyLink id={r.seller?.id} displayName={r.seller?.display_name} />
        </dd>
        <dt className="text-muted">Event</dt>
        <dd>
          {r.listing_id ? (
            <Link href={`/marketplace/${r.listing_id}`} className="link">
              {r.event_name ?? "Listing"}
            </Link>
          ) : (
            (r.event_name ?? "—")
          )}
          {r.event_date ? <span className="text-muted"> · {r.event_date}</span> : null}
        </dd>
      </dl>

      <details className="group" open>
        <summary className="flex min-h-9 items-center justify-between rounded-xl text-[0.8125rem] font-semibold">
          References
          <Icon name="down" size={15} className="transition-transform group-open:rotate-180" />
        </summary>
        <dl className="mt-2 flex flex-col gap-2 text-[0.75rem]">
          {[
            ["Payment", r.payment_id],
            ["Payment intent", r.stripe_payment_intent_id],
            ["Transfer", r.transfer_id],
            ["Stripe transfer", r.stripe_transfer_id],
            ["Refund", r.stripe_refund_id],
            ["Listing", r.listing_id],
          ]
            .filter(([, v]) => v)
            .map(([k, v]) => (
              <div key={k} className="flex items-baseline justify-between gap-3">
                <dt className="shrink-0 text-muted">{k}</dt>
                <dd className="min-w-0 select-all break-all text-right font-mono">{v}</dd>
              </div>
            ))}
        </dl>
      </details>

      <Link href={`/orders/${id}`} className="btn btn-primary btn-lg w-full">
        Open full order
        <Icon name="arrow" size={16} />
      </Link>
    </div>
  );
}

function Step({ n, title, last = false, children }: { n: number; title: string; last?: boolean; children: ReactNode }) {
  return (
    <li className="grid grid-cols-[1.75rem_minmax(0,1fr)] gap-x-3">
      <span className="flex flex-col items-center">
        <span className="grid h-7 w-7 place-items-center rounded-full bg-[#f5f3ef] text-[0.75rem] font-semibold">{n}</span>
        {last ? null : <span aria-hidden="true" className="w-px flex-1 bg-[rgba(28,25,23,0.12)]" />}
      </span>
      <div className={last ? "" : "pb-5"}>
        <p className="mb-1.5 pt-1 text-[0.8125rem] font-semibold">{title}</p>
        {children}
      </div>
    </li>
  );
}

function NotOnPage({ id }: { id: string }) {
  return (
    <div className="flex flex-col gap-4">
      <p className="text-[0.875rem] text-muted">This order is not in the current list. Its full record is still available.</p>
      <p className="break-all font-mono text-[0.75rem]">{id}</p>
      <Link href={`/orders/${id}`} className="btn btn-primary w-full">
        Open full order
      </Link>
    </div>
  );
}

function chipList(applied: Params): { key: FilterKey; label: string }[] {
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
    <Link href={href} className="badge gap-1.5 py-1 pr-1.5 transition-colors hover:border-[rgba(28,25,23,0.4)]" aria-label={`Remove filter: ${label}`}>
      {label}
      <span aria-hidden="true" className="grid h-4 w-4 place-items-center rounded-full bg-[#efece7]">
        <Icon name="close" size={10} strokeWidth={2.5} />
      </span>
    </Link>
  );
}

/**
 * One chip per filter dimension (Payment ▾, Ticket transfer ▾ …): the chip
 * says what is selected, and opens a small form for just that dimension. Each
 * form carries every other applied filter as hidden fields, so applying one
 * dimension never drops the rest. A GET form — every filtered view is a URL.
 */
function DimensionChip({ title, name, kind, options, applied, q }: { title: string; name: FilterKey; kind: "check" | "radio" | "dates"; options: [string, string][]; applied: Params; q: string }) {
  const selected = kind === "dates" ? [applied.from, applied.to].filter(Boolean) : (applied[name] ?? "").split(",").filter(Boolean);
  const label =
    kind === "dates"
      ? applied.from || applied.to
        ? `${applied.from ?? "…"} → ${applied.to ?? "…"}`
        : null
      : selected.length === 1
        ? (options.find(([v]) => v === selected[0])?.[1] ?? selected[0])
        : selected.length > 1
          ? `${selected.length} selected`
          : null;
  const keepKeys = FILTER_KEYS.filter((k) => (kind === "dates" ? k !== "from" && k !== "to" : k !== name));
  return (
    <details data-popover className="relative">
      <summary className={`filter-chip ${selected.length ? "!bg-ink !text-white !shadow-none" : ""}`} aria-label={`${title} filter${label ? `: ${label}` : ""}`}>
        <span className={selected.length ? "text-white/70" : "text-muted"}>{title}</span>
        {label ? <span className="max-w-[10rem] truncate font-semibold">{label}</span> : null}
        <Icon name="down" size={14} />
      </summary>
      <form method="get" action="/orders" className="popover glass glass-solid left-0 w-[min(19rem,calc(100vw-2rem))] p-2">
        {q ? <input type="hidden" name="q" value={q} /> : null}
        {keepKeys.map((k) => (applied[k] ? <input key={k} type="hidden" name={k} value={applied[k]} /> : null))}
        <fieldset className="flex max-h-[18rem] flex-col gap-0.5 overflow-y-auto p-1">
          <legend className="px-1.5 pb-1 pt-1 text-[0.75rem] font-semibold text-muted">{title}</legend>
          {kind === "check"
            ? options.map(([v, l]) => <Check key={v} id={`f-${name}-${v}`} name={name} value={v} label={l} checked={selected.includes(v)} />)
            : kind === "radio"
              ? [<Radio key="any" id={`f-${name}-any`} name={name} value="" label="Any" checked={selected.length === 0} />, ...options.map(([v, l]) => <Radio key={v} id={`f-${name}-${v}`} name={name} value={v} label={l} checked={selected.includes(v)} />)]
              : (
                  <div className="grid gap-2 px-1.5 pb-1">
                    <label htmlFor="f-from" className="grid gap-1 text-[0.8125rem] text-muted">
                      From (UTC)
                      <input id="f-from" type="date" name="from" defaultValue={applied.from ?? ""} className="field" />
                    </label>
                    <label htmlFor="f-to" className="grid gap-1 text-[0.8125rem] text-muted">
                      To (UTC)
                      <input id="f-to" type="date" name="to" defaultValue={applied.to ?? ""} className="field" />
                    </label>
                  </div>
                )}
        </fieldset>
        <div className="mt-1 flex items-center justify-between gap-2 border-t border-line p-1.5 pt-2.5">
          <Link href={href({ ...applied, ...(kind === "dates" ? { from: undefined, to: undefined } : { [name]: undefined }), q: q || undefined })} className="btn btn-ghost btn-sm">
            Clear
          </Link>
          <button type="submit" className="btn btn-primary btn-sm">
            Apply
          </button>
        </div>
      </form>
    </details>
  );
}

function Check({ id, name, value, label, checked }: { id: string; name: string; value: string; label: string; checked: boolean }) {
  return (
    <label htmlFor={id} className="flex min-h-9 cursor-pointer items-start gap-2.5 rounded-lg px-1.5 py-1.5 text-[0.8125rem] leading-snug transition-colors hover:bg-[rgba(28,25,23,0.04)]">
      <input id={id} type="checkbox" name={name} value={value} defaultChecked={checked} className="mt-0.5 h-4 w-4 shrink-0 accent-[#1c1917]" />
      <span>{label}</span>
    </label>
  );
}

function Radio({ id, name, value, label, checked }: { id: string; name: string; value: string; label: string; checked: boolean }) {
  return (
    <label htmlFor={id} className="flex min-h-9 cursor-pointer items-start gap-2.5 rounded-lg px-1.5 py-1.5 text-[0.8125rem] leading-snug transition-colors hover:bg-[rgba(28,25,23,0.04)]">
      <input id={id} type="radio" name={name} value={value} defaultChecked={checked} className="mt-0.5 h-4 w-4 shrink-0 accent-[#1c1917]" />
      <span>{label}</span>
    </label>
  );
}
