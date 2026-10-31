import type { Metadata } from "next";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { num, toListPage, toReport, type Report } from "@/lib/types";
import { cursorOf, first, limitOf, list, type SearchParams } from "@/lib/search-params";
import { labelFor, REPORT_STATUS_LABELS } from "@/lib/format";
import { PageHeader } from "@/components/ui/PageHeader";
import { OpsFailureAlert } from "@/components/ui/Alert";
import { FilterField, FilterForm, FilterSelect } from "@/components/ui/FilterField";
import { DataTable, type Column } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DateTime } from "@/components/ui/DateTime";
import { IdLink } from "@/components/ui/IdLink";
import { ReportResolveForms } from "@/components/reports/ReportResolveForms";

export const metadata: Metadata = { title: "Reports" };
export const dynamic = "force-dynamic";

const STATUSES = ["pending", "reviewing", "actioned", "dismissed"];
const TARGETS = ["listing", "user"];

export default async function ReportsPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  await requireOperator();

  const status = list(sp.status);
  const targetType = first(sp.target_type);
  const filters: Record<string, unknown> = {};
  if (status) filters.status = status;
  if (targetType && TARGETS.includes(targetType)) filters.target_type = targetType;

  const res = await callOps<unknown>("list_reports", { p_filters: filters, p_cursor: cursorOf(sp), p_limit: limitOf(sp, 25) });
  const page = res.ok ? toListPage(res.data) : null;
  const rows: Report[] = page ? page.items.map(toReport).filter((r): r is Report => r !== null) : [];
  const countHint = res.ok && typeof res.data === "object" && res.data !== null ? num((res.data as Record<string, unknown>).count_hint) : null;
  const basePath = "/reports";
  const revalidate = (() => {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries(sp)) if (typeof v === "string" && v) q.set(k, v);
    const s = q.toString();
    return s ? `${basePath}?${s}` : basePath;
  })();

  const columns: Column<Report>[] = [
    { key: "created_at", header: "Filed", render: (r) => <DateTime value={r.created_at} /> },
    {
      key: "target",
      header: "Target",
      render: (r) => (
        <span className="flex flex-col">
          <span className="text-[11px] uppercase tracking-wider text-dim">{r.target_type ?? "—"}</span>
          <IdLink kind={r.target_type} id={r.target_id} label={r.target_label ?? undefined} />
        </span>
      ),
    },
    { key: "reason", header: "Reason", render: (r) => <span className="font-mono text-[12px]">{r.reason ?? "—"}</span> },
    { key: "notes", header: "Notes", render: (r) => <span className="line-clamp-3 max-w-[320px] whitespace-pre-wrap text-[12px] text-muted">{r.notes ?? "—"}</span> },
    { key: "reporter", header: "Reporter", render: (r) => <IdLink kind="user" id={r.reporter_id} label={r.reporter_label ?? undefined} /> },
    {
      key: "status",
      header: "Status",
      render: (r) => (
        <span className="flex flex-col gap-1">
          <StatusBadge status={r.status} label={labelFor("report", r.status)} />
          {r.resolved_at ? (
            <span className="text-[11px] text-dim">
              resolved <DateTime value={r.resolved_at} relative={false} />
            </span>
          ) : null}
          {r.open_cases ? <span className="text-[11px] text-dim">{r.open_cases} open case</span> : null}
        </span>
      ),
    },
    { key: "id", header: "Report", render: (r) => <span id={`report-${r.id}`}><IdLink kind="report" id={r.id} /></span> },
    { key: "actions", header: "Triage", render: (r) => <ReportResolveForms report={r} revalidate={revalidate} compact /> },
  ];

  return (
    <>
      <PageHeader
        eyebrow="Moderation"
        title="Reports"
        description="User reports on listings and users. Triage: Reviewing → Actioned / Dismissed, each with a reason. Resolving a report closes its Report review case; it does not touch the listing or the user."
        meta={countHint !== null ? `${countHint.toLocaleString("en-US")} report${countHint === 1 ? "" : "s"}` : undefined}
      />
      <FilterForm action={basePath}>
        <FilterField label="Status">
          <FilterSelect name="status" options={STATUSES} value={first(sp.status)} labels={REPORT_STATUS_LABELS} />
        </FilterField>
        <FilterField label="Target">
          <FilterSelect name="target_type" options={TARGETS} value={targetType} />
        </FilterField>
      </FilterForm>
      {!res.ok ? (
        <OpsFailureAlert failure={res} fn="list_reports" retryHref={basePath} />
      ) : (
        <DataTable columns={columns} rows={rows} rowKey={(r, i) => r.id ?? `${i}`} basePath={basePath} searchParams={sp} nextCursor={page?.next_cursor} emptyText="No reports match." caption="Reports" />
      )}
    </>
  );
}
