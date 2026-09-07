import type { Metadata } from "next";
import type { ReactNode } from "react";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { first, limitOf, type SearchParams } from "@/lib/search-params";
import { humanize, labelFor, FUNDS_STATE_LABELS } from "@/lib/format";
import { metricDisplay } from "@/lib/metrics";
import { str, toListPage, toMoneyOverview, toPayoutRow, toReconItem, type PayoutRow, type ReconItem } from "@/lib/types";
import { PageHeader } from "@/components/ui/PageHeader";
import { Panel } from "@/components/ui/Panel";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";
import { DateTime } from "@/components/ui/DateTime";
import { Money } from "@/components/ui/Money";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DataTable, type Column } from "@/components/ui/DataTable";
import { IdLink, PartyLink } from "@/components/ui/IdLink";
import { MetricGrid, MetricTile } from "@/components/ui/MetricTile";
import { FilterField, FilterSelect } from "@/components/ui/FilterField";
import { ReportFreshness } from "@/components/shell/Freshness";

export const metadata: Metadata = { title: "Money" };
export const dynamic = "force-dynamic";

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const PAYOUT_STATES = ["released", "pending_release", "held", "manual_review", "none"];
const PAYOUT_STATE_LABELS: Record<string, string> = {
  released: FUNDS_STATE_LABELS.released_to_connected_account,
  pending_release: "Pending release (no Stripe Transfer yet)",
  held: "Held",
  manual_review: "Manual review",
  none: "No release pending",
};
const METRIC_LABELS: Record<string, string> = {
  gross_captured_volume: "Gross captured volume",
  refunded_volume: "Refunded volume",
  platform_fees_gross: "Platform fees (gross, pre-refund)",
  seller_funds_released: "Seller funds released to connected account",
  seller_funds_pending: "Seller funds pending release",
  bank_payouts: "Bank payouts",
};

function isoDate(v: string | undefined, fallback: Date): string {
  return v && DATE.test(v) ? v : fallback.toISOString().slice(0, 10);
}

export default async function MoneyPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  await requireOperator();
  const now = new Date();
  const to = isoDate(first(sp.to), now);
  const from = isoDate(first(sp.from), new Date(now.getTime() - 30 * 86400_000));
  const state = first(sp.state);
  const payoutFilters: Record<string, unknown> = {};
  if (state && PAYOUT_STATES.includes(state)) payoutFilters.state = state;

  const [overviewRes, payoutsRes, reconRes] = await Promise.all([
    callOps<unknown>("money_overview", { p_from: from, p_to: to }),
    callOps<unknown>("list_payouts", { p_filters: payoutFilters, p_cursor: first(sp.payouts_cursor) ?? null, p_limit: limitOf(sp, 25) }),
    callOps<unknown>("reconciliation_queue", { p_cursor: first(sp.recon_cursor) ?? null, p_limit: 25 }),
  ]);
  const overview = overviewRes.ok ? toMoneyOverview(overviewRes.data) : null;
  const payoutsPage = payoutsRes.ok ? toListPage(payoutsRes.data) : null;
  const payouts: PayoutRow[] = payoutsPage ? payoutsPage.items.map(toPayoutRow).filter((r): r is PayoutRow => r !== null) : [];
  const reconPage = reconRes.ok ? toListPage(reconRes.data) : null;
  const recon: ReconItem[] = reconPage ? reconPage.items.map(toReconItem).filter((r): r is ReconItem => r !== null) : [];

  return (
    <>
      {overview?.computed_at ? <ReportFreshness at={overview.computed_at} /> : null}
      <PageHeader
        eyebrow="Money"
        title="Money"
        description="USD only, UTC calendar-day basis. Gross captured volume, refunds, platform fees and seller funds are separate figures and are not netted against each other. Bank payouts are not tracked."
        meta={
          overview ? (
            <>
              Live figures computed <DateTime value={overview.computed_at} withSeconds /> · Snapshot freshness:{" "}
              {overview.snapshot_computed_at ? <DateTime value={overview.snapshot_computed_at} /> : <span className="text-warning">no snapshot yet (metric_snapshot job has not run)</span>}
            </>
          ) : undefined
        }
        actions={
          <form method="get" action="/money" className="flex flex-wrap items-end gap-2">
            <FilterField label="From (UTC)">
              <input type="date" name="from" defaultValue={from} className="field py-1 text-[13px]" />
            </FilterField>
            <FilterField label="To (UTC)">
              <input type="date" name="to" defaultValue={to} className="field py-1 text-[13px]" />
            </FilterField>
            {state ? <input type="hidden" name="state" value={state} /> : null}
            <button type="submit" className="btn btn-ghost btn-sm">
              Apply
            </button>
          </form>
        }
      />

      <div className="space-y-6">
        {!overviewRes.ok ? (
          <OpsFailureAlert failure={overviewRes} fn="money_overview" retryHref="/money" />
        ) : !overview ? (
          <Alert state="failed" title="Unrecognised payload from ops.money_overview()" />
        ) : (
          <section aria-label="Money metrics">
            <MetricGrid cols={3}>
              {overview.metrics.map((m) => {
                const disp = metricDisplay(m);
                return (
                  <MetricTile
                    key={m.key}
                    label={METRIC_LABELS[m.key] ?? humanize(m.key)}
                    definition={[m.definition, m.source ? `Source: ${m.source}.` : null, m.basis ? `Basis: ${m.basis}.` : null, m.currency ? `Currency: ${m.currency}.` : null].filter(Boolean).join(" ")}
                    value={m.tracked && m.value_cents !== null ? disp.headline : null}
                    notTracked={!m.tracked}
                    note={disp.note}
                    sub={
                      <>
                        {disp.secondary}
                        {m.tracked && m.source ? <span className="block font-mono text-[10px]">{m.source}</span> : null}
                      </>
                    }
                  />
                );
              })}
            </MetricGrid>
            <p className="mt-2 text-[11px] text-dim">
              Hover a tile for its definition, source and basis. Range {overview.from} → {overview.to} ({overview.currency ?? "USD"}). “Seller funds pending” is point-in-time and ignores the range.
            </p>
          </section>
        )}

        <Panel eyebrow="Connected-account transfers" title="Payouts (seller funds by transfer)">
          <form method="get" action="/money#payouts" className="mb-3 flex flex-wrap items-end gap-2">
            <input type="hidden" name="from" value={from} />
            <input type="hidden" name="to" value={to} />
            <FilterField label="Seller funds state">
              <FilterSelect name="state" options={PAYOUT_STATES} value={state} labels={PAYOUT_STATE_LABELS} />
            </FilterField>
            <button type="submit" className="btn btn-ghost btn-sm">
              Filter
            </button>
          </form>
          {!payoutsRes.ok ? <OpsFailureAlert failure={payoutsRes} fn="list_payouts" retryHref="/money" /> : <PayoutTable rows={payouts} searchParams={sp} nextCursor={payoutsPage?.next_cursor} />}
          <p className="mt-3 text-[11px] text-dim">“Released to connected account” means a Stripe Transfer exists (stripe_transfer_id). Bank payouts from the connected account are not tracked.</p>
        </Panel>

        <Panel eyebrow="Read-only detector" title="Reconciliation queue">
          {!reconRes.ok ? (
            <OpsFailureAlert failure={reconRes} fn="reconciliation_queue" retryHref="/money" />
          ) : (
            <ReconTable rows={recon} searchParams={sp} nextCursor={reconPage?.next_cursor} />
          )}
          <p className="mt-3 text-[11px] text-dim">Money facts that disagree. Investigate before any money action; the console never repairs money state — escalate with the ids.</p>
        </Panel>
      </div>
    </>
  );
}

function PayoutTable({ rows, searchParams, nextCursor }: { rows: PayoutRow[]; searchParams: SearchParams; nextCursor?: string | null }) {
  const columns: Column<PayoutRow>[] = [
    { key: "created_at", header: "Transfer created", render: (r) => <DateTime value={r.created_at} relative={false} /> },
    {
      key: "payment",
      header: "Order",
      render: (r) => (
        <span className="flex flex-col">
          <IdLink kind="payment" id={r.payment_id} />
          <span className="text-[11px] text-dim">{r.event_name ?? ""}</span>
        </span>
      ),
    },
    { key: "seller", header: "Seller", render: (r) => <PartyLink id={r.seller_id} displayName={r.seller?.display_name} emailMasked={r.seller?.email_masked} /> },
    { key: "share", header: "Seller share", align: "right", render: (r) => <Money cents={r.seller_share_cents} /> },
    { key: "payment_status", header: "Payment", render: (r) => <StatusBadge status={r.payment_status} label={labelFor("payment", r.payment_status)} /> },
    { key: "status", header: "Transfer", render: (r) => <StatusBadge status={r.status} label={labelFor("transfer", r.status)} /> },
    { key: "funds", header: "Seller funds", render: (r) => <StatusBadge status={r.seller_funds_state} label={labelFor("funds", r.seller_funds_state)} variant={r.seller_funds_state === "released_to_connected_account" ? "ok" : undefined} /> },
    {
      key: "review",
      header: "Review / hold",
      render: (r) => (
        <span className="flex flex-col text-[12px]">
          {r.payout_review_status ? <StatusBadge status={r.payout_review_status} label={labelFor("payout_review", r.payout_review_status)} /> : <span className="text-dim">—</span>}
          {r.payout_hold_until ? (
            <span className="text-dim">
              hold until <DateTime value={r.payout_hold_until} relative={false} />
            </span>
          ) : null}
          {r.payout_risk_tier ? <span className="text-dim">tier {r.payout_risk_tier}</span> : null}
        </span>
      ),
    },
    { key: "released", header: "Release recorded", render: (r) => <DateTime value={r.payout_released_at} relative={false} /> },
    { key: "stripe_transfer_id", header: "Stripe Transfer", render: (r) => (r.stripe_transfer_id ? <code className="font-mono text-[11px]">{r.stripe_transfer_id}</code> : <span className="text-dim">none</span>) },
  ];
  return <DataTable id="payouts" columns={columns} rows={rows} rowKey={(r, i) => r.id ?? `${i}`} basePath="/money" searchParams={searchParams} nextCursor={nextCursor} cursorParam="payouts_cursor" emptyText="No transfers match." caption="Payouts" dense />;
}

function ReconTable({ rows, searchParams, nextCursor }: { rows: ReconItem[]; searchParams: SearchParams; nextCursor?: string | null }) {
  const columns: Column<ReconItem>[] = [
    { key: "since", header: "Since", render: (r) => <DateTime value={r.since} /> },
    { key: "kind", header: "Mismatch", render: (r) => <StatusBadge status={r.kind} variant="danger" label={humanize(r.kind ?? "mismatch")} /> },
    {
      key: "subject",
      header: "Subject",
      render: (r) => (
        <span className="text-[12px]">
          <span className="text-dim">{r.subject_kind} </span>
          <IdLink kind={r.subject_kind} id={r.subject_id} label={r.subject_label ?? undefined} />
        </span>
      ),
    },
    {
      key: "detail",
      header: "Detail",
      render: (r) => (
        <dl className="grid grid-cols-[auto_1fr] gap-x-2 text-[11px]">
          {Object.entries(r.detail ?? {}).map(([k, v]) => (
            <ReconDetail key={k} k={k} v={v} />
          ))}
        </dl>
      ),
    },
  ];
  return <DataTable id="reconciliation" columns={columns} rows={rows} rowKey={(r, i) => `${r.kind}-${r.subject_id ?? i}`} basePath="/money" searchParams={searchParams} nextCursor={nextCursor} cursorParam="recon_cursor" emptyText="No money mismatches detected." caption="Reconciliation queue" dense />;
}

function ReconDetail({ k, v }: { k: string; v: unknown }) {
  const kind = k === "payment_id" ? "payment" : k === "transfer_id" ? "transfer" : k === "subject_id" ? null : null;
  const s = str(v);
  let value: ReactNode;
  if (v === null || v === undefined) value = <span className="text-dim">—</span>;
  else if (kind && s) value = <IdLink kind={kind} id={s} />;
  else if (/_at$/.test(k) && s) value = <DateTime value={s} relative={false} />;
  else if (typeof v === "number" && /(amount|total|fee|cents)/.test(k)) value = <Money cents={v} />;
  else if (typeof v === "boolean") value = v ? "yes" : "no";
  else value = <code className="font-mono">{typeof v === "string" ? v : JSON.stringify(v)}</code>;
  return (
    <>
      <dt className="text-dim">{k}</dt>
      <dd>{value}</dd>
    </>
  );
}
