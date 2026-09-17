import type { Metadata } from "next";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { CASE_PRIORITIES, CASE_STATUSES, toCase, toListPage, type OpsCase } from "@/lib/types";
import { cursorOf, first, limitOf, list, type SearchParams } from "@/lib/search-params";
import { PageHeader } from "@/components/ui/PageHeader";
import { OpsFailureAlert } from "@/components/ui/Alert";
import { CaseTable } from "@/components/cases/CaseTable";
import { NewCaseForm } from "@/components/cases/NewCaseForm";

export const metadata: Metadata = { title: "Cases" };
export const dynamic = "force-dynamic";

export default async function CasesPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  const me = await requireOperator();

  const status = list(sp.status);
  const caseType = list(sp.case_type);
  const priority = list(sp.priority);
  const assigneeRaw = first(sp.assignee);
  const assignee = assigneeRaw === "me" ? me.id : assigneeRaw === "unassigned" ? undefined : assigneeRaw;
  const sort = first(sp.sort);
  const dir = first(sp.dir) === "asc" ? "asc" : "desc";

  const subjectKind = first(sp.subject_kind);
  const subjectId = first(sp.subject_id);
  const filters: Record<string, unknown> = {};
  if (subjectKind) filters.subject_kind = subjectKind;
  if (subjectId && /^[0-9a-f-]{36}$/i.test(subjectId)) filters.subject_id = subjectId;
  if (status) filters.status = status;
  if (caseType) filters.case_type = caseType;
  if (priority) filters.priority = priority;
  if (assignee) filters.assignee = assignee;
  if (assigneeRaw === "unassigned") filters.unassigned = true;
  if (sort) filters.sort = { key: sort, dir };

  const res = await callOps<unknown>("list_cases", {
    p_filters: filters,
    p_cursor: cursorOf(sp),
    p_limit: limitOf(sp),
  });

  const page = res.ok ? toListPage(res.data) : null;
  const rows: OpsCase[] = page ? page.items.map(toCase).filter((c): c is OpsCase => c !== null) : [];

  const select = (name: string, options: string[], current: string | undefined, all: string) => (
    <label className="flex flex-col gap-1 text-[11px] uppercase tracking-wider text-dim">
      {name.replace("_", " ")}
      <select name={name} defaultValue={current ?? ""} className="field min-w-[140px] py-1.5 text-[13px]">
        <option value="">{all}</option>
        {options.map((o) => (
          <option key={o} value={o}>
            {o.replace(/_/g, " ")}
          </option>
        ))}
      </select>
    </label>
  );

  return (
    <>
      <PageHeader eyebrow="Work" title="Cases" description="Detector-raised and manual cases across payments, transfers, disputes, users, and jobs." />

      <details className="mb-4 border border-line-neutral bg-card">
        <summary className="cursor-pointer px-3 py-2 text-[13px] font-semibold text-ink">New manual case</summary>
        <div className="border-t border-line-neutral p-3">
          <p className="mb-3 text-[12px] text-muted">A free-standing case with no subject. To attach a case to an order, listing or user, open it from that record&apos;s page.</p>
          <NewCaseForm subjectKind="none" revalidate="/cases" />
        </div>
      </details>

      <form method="get" action="/cases" className="mb-4 flex flex-wrap items-end gap-3 border border-line-neutral bg-card p-3">
        {select("status", CASE_STATUSES, first(sp.status), "Any status")}
        {select("priority", CASE_PRIORITIES, first(sp.priority), "Any priority")}
        <label className="flex flex-col gap-1 text-[11px] uppercase tracking-wider text-dim">
          Type
          <input name="case_type" defaultValue={first(sp.case_type) ?? ""} placeholder="e.g. refund_pending" className="field min-w-[180px] py-1.5 text-[13px]" />
        </label>
        <label className="flex flex-col gap-1 text-[11px] uppercase tracking-wider text-dim">
          Assignee
          <select name="assignee" defaultValue={assigneeRaw ?? ""} className="field min-w-[140px] py-1.5 text-[13px]">
            <option value="">Anyone</option>
            <option value="me">Me</option>
            <option value="unassigned">Unassigned</option>
          </select>
        </label>
        {subjectKind ? <input type="hidden" name="subject_kind" value={subjectKind} /> : null}
        {subjectId ? <input type="hidden" name="subject_id" value={subjectId} /> : null}
        {sort ? <input type="hidden" name="sort" value={sort} /> : null}
        {sort ? <input type="hidden" name="dir" value={dir} /> : null}
        <button type="submit" className="btn btn-ghost btn-sm">
          Filter
        </button>
      </form>

      {!res.ok ? (
        <OpsFailureAlert failure={res} fn="list_cases" retryHref="/cases" />
      ) : (
        <CaseTable rows={rows} basePath="/cases" searchParams={sp} nextCursor={page?.next_cursor} meId={me.id} />
      )}
    </>
  );
}
