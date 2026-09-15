import Link from "next/link";
import type { MetricTile } from "@/lib/types";
import { metricHref } from "@/lib/routes";
import { ENV_LABEL } from "@/lib/env";
import { readPeriod, readSeries } from "@/lib/analytics";
import {
  dayCount,
  delta,
  formatUsdExact,
  formatUsdWhole,
  isEmptySeries,
  isoDay,
  previousPeriod,
  refundAmount,
  shortDay,
  type MoneyFigures,
} from "@/lib/analytics-core";
import { ReportFreshness } from "@/components/shell/Freshness";
import { KpiTile } from "@/components/charts/KpiTile";
import { ChartCard } from "@/components/charts/ChartCard";
import { TrendChart, type TrendPoint } from "@/components/charts/TrendChart";
import { OpsFailureAlert } from "@/components/ui/Alert";

// ---------------------------------------------------------------------------
// Sample-data notice — every preview against the local harness says so.
// ---------------------------------------------------------------------------
export function SampleDataNotice() {
  if (!/local|harness|rehears|sample|preview/i.test(ENV_LABEL)) return null;
  return (
    <p role="note" className="mb-6 flex items-start gap-2 rounded-[var(--radius-control)] border border-warning/30 bg-warning-soft px-3 py-2 text-[13px] text-ink">
      <span aria-hidden="true" className="mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-warning text-[10px] font-bold text-white">
        !
      </span>
      <span>
        <strong className="font-semibold">Sample data.</strong> This console is connected to the local synthetic harness ({ENV_LABEL}). Every figure and
        chart below is fixture data, not Snatch It business data.
      </span>
    </p>
  );
}

// ---------------------------------------------------------------------------
// Needs attention — operational counts from ops.today(), most severe first.
// ---------------------------------------------------------------------------
const SEVERITY: Record<string, "critical" | "warning" | "info"> = {
  transfers_overdue: "critical",
  evidence_due_72h: "critical",
  jobs_failing: "critical",
  webhook_backlog: "critical",
  alerts_firing: "critical",
  paid_unsettled: "critical",
  transfers_due_6h: "warning",
  stripe_disputes_open: "warning",
  disputes_open: "warning",
  refunds_pending: "warning",
  payout_review: "warning",
  approvals_pending: "warning",
  reports_pending: "info",
  open_cases: "info",
};
const SEVERITY_ORDER = { critical: 0, warning: 1, info: 2 } as const;
const SEVERITY_STYLE = {
  critical: { dot: "bg-danger-soft text-danger", glyph: "✕", word: "Urgent" },
  warning: { dot: "bg-warning-soft text-warning", glyph: "!", word: "Soon" },
  info: { dot: "bg-info-soft text-info", glyph: "i", word: "Queue" },
} as const;
const SHORT_LABEL: Record<string, string> = {
  transfers_overdue: "Transfers past seller deadline",
  evidence_due_72h: "Dispute evidence due in 72 h",
  jobs_failing: "Background jobs failing",
  webhook_backlog: "Stripe webhooks stuck",
  alerts_firing: "Alerts firing",
  paid_unsettled: "Paid orders without a transfer",
  transfers_due_6h: "Transfers due in 6 h",
  stripe_disputes_open: "Open Stripe disputes",
  disputes_open: "Open buyer/seller disputes",
  refunds_pending: "Refunds owed, not executed",
  payout_review: "Payouts in manual review",
  approvals_pending: "Approvals waiting",
  reports_pending: "User reports to review",
  open_cases: "Open cases",
};

export function AttentionSummary({ metrics, definitions }: { metrics: MetricTile[]; definitions: Record<string, string> }) {
  const counted = metrics
    .map((m) => ({ ...m, n: typeof m.value === "number" ? m.value : Number(m.value), sev: SEVERITY[m.key] ?? "info" }))
    .filter((m) => Number.isFinite(m.n));
  const active = counted.filter((m) => m.n > 0).sort((a, b) => SEVERITY_ORDER[a.sev] - SEVERITY_ORDER[b.sev] || b.n - a.n);
  const clear = counted.filter((m) => m.n === 0);
  const urgent = active.filter((m) => m.sev === "critical").length;
  return (
    <div>
      <p className="mb-3 text-[14px] text-muted">
        {active.length === 0 ? (
          <span className="font-medium text-success">✓ Nothing needs attention right now.</span>
        ) : (
          <>
            <span className="font-semibold text-ink">
              {urgent} urgent · {active.length - urgent} other
            </span>{" "}
            signals need attention. Each links to the queue where you act on it.
          </>
        )}
      </p>
      {active.length ? (
        <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {active.map((m) => {
            const s = SEVERITY_STYLE[m.sev];
            const href = metricHref(m.key);
            const body = (
              <>
                <span className="flex items-center gap-2 text-[13px] font-medium text-muted">
                  <span aria-hidden="true" className={`flex h-5 w-5 items-center justify-center rounded-full text-[11px] font-bold ${s.dot}`}>
                    {s.glyph}
                  </span>
                  <span className="sr-only">{s.word}: </span>
                  {SHORT_LABEL[m.key] ?? m.label}
                </span>
                <span className="mt-1.5 block text-[26px] font-semibold leading-tight text-ink">{m.n.toLocaleString("en-US")}</span>
                <span className="mt-1 block text-[12px] leading-snug text-dim">{m.definition ?? definitions[m.key]}</span>
              </>
            );
            return (
              <li key={m.key}>
                {href ? (
                  <Link
                    href={href}
                    className={`block h-full rounded-[var(--radius-card)] border bg-card p-4 transition-colors hover:bg-raised ${m.sev === "critical" ? "border-danger/35" : "border-line"}`}
                  >
                    {body}
                  </Link>
                ) : (
                  <div className="h-full rounded-[var(--radius-card)] border border-line bg-card p-4">{body}</div>
                )}
              </li>
            );
          })}
        </ul>
      ) : null}
      {clear.length ? (
        <details className="mt-3 rounded-[var(--radius-control)]">
          <summary className="inline-block rounded-[var(--radius-control)] px-2 py-1 text-[13px] text-dim">
            {clear.length} check{clear.length === 1 ? "" : "s"} clear
          </summary>
          <p className="px-2 pt-1 text-[13px] text-dim">{clear.map((m) => SHORT_LABEL[m.key] ?? m.label).join(" · ")}</p>
        </details>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Business measures — shared definitions (docs/ANALYTICS_DATA_CONTRACT.md).
// ---------------------------------------------------------------------------
export const DEF = {
  captured: "Card payments captured (status succeeded or refunded), including buyer fees. Refunds are not subtracted.",
  fees: "Buyer + seller fees on succeeded payments. Gross, before refunds — not net revenue.",
  refunds:
    "Payments whose status is refunded — i.e. fully refunded. Partial refunds may not appear here and stay in captured sales. The refunded amount is not recorded yet.",
  released: "Seller share sent to sellers' Stripe connected accounts. Not a bank payout.",
  pending: "Seller share of confirmed transfers not yet sent. Point in time — ignores the date range.",
  bank: "Payouts from connected accounts to sellers' banks happen in Stripe and are not tracked here.",
};

function refundValue(periods: MoneyFigures[]) {
  const r = refundAmount(periods);
  if (r.state === "none") return { value: "0", note: "No fully refunded payments" };
  if (r.state === "known") return { value: r.count.toLocaleString("en-US"), note: `${formatUsdExact(r.knownCents)} refunded` };
  if (r.state === "mixed")
    return { value: r.count.toLocaleString("en-US"), note: `${formatUsdExact(r.knownCents)} known · the rest at most ${r.atMostCents === null ? "unknown" : formatUsdExact(r.atMostCents)}` };
  return { value: r.count.toLocaleString("en-US"), note: `Amount not recorded — at most ${r.atMostCents === null ? "unknown" : formatUsdExact(r.atMostCents)}` };
}

export async function MoneyKpis({ from, to, compact = false }: { from: string; to: string; compact?: boolean }) {
  const prev = previousPeriod(from, to);
  const [cur, before] = await Promise.all([readPeriod(from, to), prev ? readPeriod(prev.from, prev.to) : Promise.resolve(null)]);
  if (!cur.ok) return <OpsFailureAlert failure={cur} fn="money_overview" retryHref={compact ? "/" : "/money"} />;
  const f = cur.figures;
  const p = before && before.ok ? before.figures : null;
  const rv = refundValue([f]);
  const tiles = (
    <>
      <KpiTile label="Captured sales" value={formatUsdWhole(f.capturedCents)} valueNote={`${f.capturedCount ?? 0} payments`} delta={delta(f.capturedCents, p?.capturedCents ?? null)} definition={DEF.captured} />
      <KpiTile label="Platform fees (gross)" value={formatUsdWhole(f.feesCents)} valueNote={`${f.feesCount ?? 0} succeeded payments`} delta={delta(f.feesCents, p?.feesCents ?? null)} definition={DEF.fees} />
      <KpiTile label="Fully refunded payments" value={rv.value} valueNote={rv.note} delta={delta(f.refundCount, p?.refundCount ?? null)} goodWhen="down" definition={DEF.refunds} />
      <KpiTile label="Seller funds released" value={formatUsdWhole(f.releasedCents)} valueNote={`${f.releasedCount ?? 0} transfers`} delta={delta(f.releasedCents, p?.releasedCents ?? null)} goodWhen="neutral" definition={DEF.released} />
    </>
  );
  return (
    <>
      <ReportFreshness at={cur.overview.computed_at} />
      <div className={compact ? "grid grid-cols-1 gap-3 min-[480px]:grid-cols-2" : "grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4"}>{tiles}</div>
      {!compact ? (
        <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
          <KpiTile label="Seller funds pending release · now" value={formatUsdWhole(f.pendingCents)} valueNote={`${f.pendingCount ?? 0} transfers`} goodWhen="neutral" definition={DEF.pending} />
          <KpiTile label="Bank payouts" value="Not tracked" muted definition={DEF.bank} />
        </div>
      ) : null}
      <p className="mt-2 text-[12px] text-dim">
        {shortDay(from)} – {shortDay(to)} (UTC){prev ? ` compared with ${shortDay(prev.from)} – ${shortDay(prev.to)}` : ""}.
        {before && !before.ok ? " Previous period unavailable — no comparison shown." : ""}
      </p>
    </>
  );
}

function tableRows(points: { label: string; detail: string; value: number }[], fmt: (v: number) => string) {
  return points.map((p) => [p.detail, fmt(p.value)]);
}

export async function MoneyCharts({ from, to, only }: { from: string; to: string; only?: "captured" }) {
  const series = await readSeries(from, to);
  const range = `${shortDay(from)} – ${shortDay(to)} (UTC)`;
  const today = isoDay(new Date());
  const grainWord = !series.ok ? "" : series.grain === "day" ? "per day" : "per week";
  if (!series.ok) {
    const err = { kind: "error" as const, message: <OpsFailureAlert failure={series} fn={`money_overview (${series.failedBucket})`} retryHref={only ? "/" : "/money"} /> };
    return only ? (
      <ChartCard title="Captured sales" description={range} state={err} />
    ) : (
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <ChartCard title="Captured sales" description={range} state={err} />
      </div>
    );
  }
  const partialLast = series.points.length > 0 && series.points[series.points.length - 1].bucket.to >= today;
  const pts = (pick: (f: MoneyFigures) => number | null): TrendPoint[] =>
    series.points.map((p, i) => ({
      label: p.bucket.label,
      detail: `${p.bucket.from === p.bucket.to ? shortDay(p.bucket.from) : p.bucket.label}${partialLast && i === series.points.length - 1 ? " (today so far)" : ""}`,
      value: pick(p.figures) ?? 0,
    }));
  const empty = isEmptySeries(series.points);
  const emptyState = { kind: "empty" as const, message: <>No payments, fees, refunds or releases between {range}. Nothing is drawn rather than a flat line.</> };
  const ok = { kind: "ok" as const };
  const days = dayCount(from, to);
  const footnote = `${series.calls} database aggregates (${series.grain === "day" ? "one per UTC day" : "one per week"}).${partialLast ? " The last period is today so far." : ""}`;

  const captured = pts((f) => f.capturedCents);
  const capturedCard = (
    <ChartCard
      title="Captured sales"
      description={`USD ${grainWord} · ${range}`}
      state={empty ? emptyState : ok}
      definition={DEF.captured}
      footnote={footnote}
      table={{ caption: `Captured sales ${grainWord}, ${range}`, head: ["Period", "Captured sales (USD)"], rows: tableRows(captured, formatUsdExact) }}
    >
      <TrendChart kind="line" unit="usd_cents" points={captured} title={`Captured sales ${grainWord}, ${range}`} partialLast={partialLast} />
    </ChartCard>
  );
  if (only === "captured") return capturedCard;

  const fees = pts((f) => f.feesCents);
  const refunds = pts((f) => f.refundCount);
  const released = pts((f) => f.releasedCents);
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
      {capturedCard}
      <ChartCard
        title="Platform fees (gross)"
        description={`USD ${grainWord} · ${range}`}
        state={empty ? emptyState : ok}
        definition={DEF.fees}
        table={{ caption: `Platform fees ${grainWord}, ${range}`, head: ["Period", "Platform fees (USD)"], rows: tableRows(fees, formatUsdExact) }}
      >
        <TrendChart kind="line" unit="usd_cents" points={fees} title={`Platform fees (gross) ${grainWord}, ${range}`} partialLast={partialLast} />
      </ChartCard>
      <ChartCard
        title="Fully refunded payments"
        description={`Payments ${grainWord} · ${range}`}
        state={empty ? emptyState : ok}
        definition={`${DEF.refunds} Compare periods by bar height; amounts are not charted.`}
        table={{ caption: `Fully refunded payments ${grainWord}, ${range}`, head: ["Period", "Payments"], rows: tableRows(refunds, (v) => v.toLocaleString("en-US")) }}
      >
        <TrendChart kind="column" unit="count" points={refunds} title={`Fully refunded payments ${grainWord}, ${range}`} />
      </ChartCard>
      <ChartCard
        title="Seller funds released"
        description={`USD ${grainWord} · ${range}`}
        state={empty ? emptyState : ok}
        definition={DEF.released}
        table={{ caption: `Seller funds released ${grainWord}, ${range}`, head: ["Period", "Released (USD)"], rows: tableRows(released, formatUsdExact) }}
      >
        <TrendChart kind="column" unit="usd_cents" points={released} title={`Seller funds released ${grainWord}, ${range}`} />
      </ChartCard>
      <p className="text-[12px] text-dim lg:col-span-2">
        {days} day{days === 1 ? "" : "s"}, {footnote} Measures are separate and never netted against each other.
      </p>
    </div>
  );
}
