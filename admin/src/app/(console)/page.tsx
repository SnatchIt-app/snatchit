import type { Metadata } from "next";
import Link from "next/link";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { toToday, type OpsCase } from "@/lib/types";
import { first, type SearchParams } from "@/lib/search-params";
import { humanize } from "@/lib/format";
import { Suspense } from "react";
import { AttentionSummary, MoneyCharts, MoneyKpis, SampleDataNotice } from "@/components/analytics/sections";
import { ChartSkeleton } from "@/components/charts/ChartCard";
import { isoDay, DAY_MS } from "@/lib/analytics-core";
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

export default async function TodayPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  const me = await requireOperator();
  const assignee: Assignee = first(sp.assignee) === "me" ? "me" : first(sp.assignee) === "unassigned" ? "unassigned" : "all";

  const res = await callOps<unknown>("today");
  if (!res.ok) {
    return (
      <>
        <PageHeader eyebrow="Overview" title="Today" />
        <OpsFailureAlert failure={res} fn="today" retryHref="/" />
      </>
    );
  }
  const today = toToday(res.data);
  if (!today) {
    return (
      <>
        <PageHeader eyebrow="Overview" title="Today" />
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

  const now = new Date();
  const to = isoDay(now);
  const from30 = isoDay(new Date(now.getTime() - 29 * DAY_MS));
  const from14 = isoDay(new Date(now.getTime() - 13 * DAY_MS));

  return (
    <>
      <ReportFreshness at={today.computed_at} />
      <PageHeader
        eyebrow="Overview"
        title="Today"
        description="Operational problems first, then how the business is doing."
        meta={
          <>
            Data as of <DateTime value={today.computed_at} withSeconds />
            {" · "}
            {today.attention.length} open item{today.attention.length === 1 ? "" : "s"}
            {" · "}
            <a href="#business" className="link">
              Business snapshot
            </a>
          </>
        }
      />
      <SampleDataNotice />

      <section aria-labelledby="attention-heading" className="mb-10">
        <h2 id="attention-heading" className="mb-2 text-[18px] font-semibold text-ink">
          Needs attention
        </h2>
        <AttentionSummary metrics={today.metrics} definitions={METRIC_DEFINITIONS} />
      </section>

      <div className="grid grid-cols-1 gap-8 xl:grid-cols-[minmax(0,1fr)_400px]">
        <section aria-labelledby="cases-heading" className="min-w-0">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
            <h2 id="cases-heading" className="text-[18px] font-semibold text-ink">
              Cases to act on
            </h2>
            <div className="flex gap-1" role="group" aria-label="Assignee filter">
              {filterLink("all", "All")}
              {filterLink("me", "Mine")}
              {filterLink("unassigned", "Unassigned")}
            </div>
          </div>
          {groups.size === 0 ? (
            <Alert state="empty" title={assignee === "all" ? "No open cases." : "No open cases in this view."}>
              {today.metrics.some((m) => typeof m.value === "number" && m.value > 0 && m.key !== "open_cases") ? (
                <span className="block">Cases appear when the detectors run. The live signals under “Needs attention” link to their queues now.</span>
              ) : null}
              {assignee !== "all" ? (
                <Link href="/" className="link">
                  Show all
                </Link>
              ) : null}
            </Alert>
          ) : (
            <div className="space-y-4">
              {[...groups.entries()].map(([type, rows]) => (
                <Panel
                  key={type}
                  title={
                    <Link href={`/cases?case_type=${encodeURIComponent(type)}`} className="hover:text-primary-ink">
                      {humanize(type)}
                    </Link>
                  }
                  description={`${rows.length} open item${rows.length === 1 ? "" : "s"}`}
                  actions={
                    <Link href={`/cases?case_type=${encodeURIComponent(type)}`} className="link text-[13px]">
                      All {humanize(type).toLowerCase()} cases
                    </Link>
                  }
                >
                  <CaseTable rows={rows} basePath="/" searchParams={sp} meId={me.id} />
                </Panel>
              ))}
            </div>
          )}
        </section>

        <section id="business" aria-labelledby="business-heading" className="min-w-0 xl:sticky xl:top-20 xl:self-start">
          <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
            <h2 id="business-heading" className="text-[18px] font-semibold text-ink">
              Business · last 30 days
            </h2>
            <Link href="/money" className="link text-[13px]">
              Money analytics
            </Link>
          </div>
          <div className="space-y-4">
            <Suspense fallback={<div className="h-[340px] animate-pulse rounded-[var(--radius-card)] bg-raised" role="status" aria-label="Loading business figures" />}>
              <MoneyKpis from={from30} to={to} compact />
            </Suspense>
            <Suspense fallback={<ChartSkeleton title="Captured sales" />}>
              <MoneyCharts from={from14} to={to} only="captured" />
            </Suspense>
          </div>
        </section>
      </div>
    </>
  );
}
