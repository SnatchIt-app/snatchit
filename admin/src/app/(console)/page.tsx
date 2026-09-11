import type { Metadata } from "next";
import Link from "next/link";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { toToday, type OpsCase } from "@/lib/types";
import { first, type SearchParams } from "@/lib/search-params";
import { formatMoney, humanize } from "@/lib/format";
import { metricHref } from "@/lib/routes";
import { MetricGrid, MetricTile } from "@/components/ui/MetricTile";
import { PageHeader } from "@/components/ui/PageHeader";
import { Panel } from "@/components/ui/Panel";
import { OpsFailureAlert, Alert } from "@/components/ui/Alert";
import { DateTime } from "@/components/ui/DateTime";
import { CaseTable } from "@/components/cases/CaseTable";
import { ReportFreshness } from "@/components/shell/Freshness";

export const metadata: Metadata = { title: "Today" };
export const dynamic = "force-dynamic";

type Assignee = "me" | "unassigned" | "all";

/** Tooltip definitions for the counts ops.today() returns (§3.5 / §5). */
const METRIC_DEFINITIONS: Record<string, string> = {
  open_cases: "ops.case rows whose status is not resolved or dismissed.",
  paid_unsettled: "Succeeded payments older than the grace window with no transfer row yet.",
  transfers_due_6h: "Pending transfers whose seller deadline falls within the next 6 hours.",
  transfers_overdue: "Pending transfers whose seller deadline has passed.",
  refunds_pending: "Expired or buyer-win/partial-refund transfers whose payment is still 'succeeded' (refund not yet executed).",
  disputes_open: "Transfers currently in 'disputed' status (buyer/seller dispute, not Stripe).",
  stripe_disputes_open: "Stripe disputes not yet won, lost, warning_closed or charge_refunded.",
  evidence_due_72h: "Open Stripe disputes whose evidence_due_by is within 72 hours.",
  payout_review: "Transfers flagged for manual payout review without a Stripe transfer id yet.",
  reports_pending: "User reports in 'pending' status.",
  jobs_failing: "Enabled ops jobs with 2+ consecutive failures.",
  webhook_backlog: "Stripe webhook events unprocessed for longer than the stuck window.",
  approvals_pending: "Second-operator approvals still pending and not expired.",
  alerts_firing: "ops.alert rows in 'firing' state.",
};

function tileValue(value: unknown, format?: string, key?: string): string {
  if (value === null || value === undefined) return "—";
  if (format === "money" || (typeof value === "number" && /(_cents|volume|amount|total|fee)/i.test(key ?? ""))) {
    return formatMoney(value);
  }
  if (typeof value === "number") return value.toLocaleString("en-US");
  if (typeof value === "string" || typeof value === "boolean") return String(value);
  return "—";
}

export default async function TodayPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  const me = await requireOperator();
  const assignee: Assignee = first(sp.assignee) === "me" ? "me" : first(sp.assignee) === "unassigned" ? "unassigned" : "all";

  const res = await callOps<unknown>("today");
  if (!res.ok) {
    return (
      <>
        <PageHeader eyebrow="Attention" title="Today" />
        <OpsFailureAlert failure={res} fn="today" retryHref="/" />
      </>
    );
  }
  const today = toToday(res.data);
  if (!today) {
    return (
      <>
        <PageHeader eyebrow="Attention" title="Today" />
        <Alert state="failed" title="Unrecognised payload from ops.today()" retryHref="/" />
      </>
    );
  }

  const filtered = today.attention.filter((c) =>
    assignee === "all" ? true : assignee === "me" ? c.assignee === me.id : !c.assignee,
  );
  const groups = new Map<string, OpsCase[]>();
  for (const c of filtered) {
    const k = c.case_type ?? "other";
    groups.set(k, [...(groups.get(k) ?? []), c]);
  }
  const filterLink = (v: Assignee, label: string) => (
    <Link
      href={v === "all" ? "/" : `/?assignee=${v}`}
      aria-current={assignee === v ? "page" : undefined}
      className={`btn btn-sm ${assignee === v ? "btn-primary" : "btn-ghost"}`}
    >
      {label}
    </Link>
  );

  return (
    <>
      <ReportFreshness at={today.computed_at} />
      <PageHeader
        eyebrow="Attention"
        title="Today"
        description="What needs attention, who owns it, and what can we safely do."
        meta={
          <>
            Data as of <DateTime value={today.computed_at} withSeconds />
            {" · "}
            {today.attention.length} open item{today.attention.length === 1 ? "" : "s"}
          </>
        }
        actions={
          <div className="flex gap-1" role="group" aria-label="Assignee filter">
            {filterLink("all", "All")}
            {filterLink("me", "Mine")}
            {filterLink("unassigned", "Unassigned")}
          </div>
        }
      />

      {today.metrics.length ? (
        <div className="mb-6">
          <MetricGrid cols={4}>
            {today.metrics.map((m) => (
              <MetricTile
                key={m.key}
                label={humanize(m.label)}
                value={tileValue(m.value, m.format, m.key)}
                definition={m.definition ?? METRIC_DEFINITIONS[m.key] ?? null}
                href={metricHref(m.key)}
              />
            ))}
          </MetricGrid>
        </div>
      ) : null}

      {groups.size === 0 ? (
        <Alert state="empty" title="Nothing needs attention in this view.">
          {assignee !== "all" ? (
            <Link href="/" className="link">
              Show all
            </Link>
          ) : null}
        </Alert>
      ) : (
        <div className="space-y-6">
          {[...groups.entries()].map(([type, rows]) => (
            <Panel
              key={type}
              eyebrow={`${rows.length} item${rows.length === 1 ? "" : "s"}`}
              title={
                <Link href={`/cases?case_type=${encodeURIComponent(type)}`} className="hover:text-primary-ink">
                  {humanize(type)}
                </Link>
              }
              actions={
                <Link href={`/cases?case_type=${encodeURIComponent(type)}`} className="link text-[12px]">
                  All {humanize(type).toLowerCase()} cases
                </Link>
              }
            >
              <CaseTable rows={rows} basePath="/" searchParams={sp} meId={me.id} />
            </Panel>
          ))}
        </div>
      )}
    </>
  );
}
