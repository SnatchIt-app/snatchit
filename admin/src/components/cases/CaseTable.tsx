import { humanize } from "@/lib/format";
import Link from "next/link";
import { DataTable, type Column, type SearchParamsLike } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { TimeAgo } from "@/components/ui/DateTime";
import { hrefFor } from "@/components/generic/GenericRpc";
import type { OpsCase } from "@/lib/types";

/** The assignee as the row shows it: "me", the label, or null when unassigned. */
export const caseAssigneeText = (c: OpsCase, meId?: string): string | null =>
  c.assignee ? (c.assignee === meId ? "me" : (c.assignee_label ?? c.assignee_email_masked ?? c.assignee.slice(0, 8))) : null;

/** What the page filter matches on a case row. */
export function caseFilterText(c: OpsCase, meId?: string): string {
  return [c.title, c.summary, c.case_type, c.case_type ? humanize(c.case_type) : null, c.status, c.priority, c.subject_kind, c.subject_label, c.subject_ref, c.subject_id, caseAssigneeText(c, meId) ?? "unassigned"]
    .filter(Boolean)
    .join(" ");
}

export function CaseTable({
  rows,
  basePath,
  searchParams,
  nextCursor,
  meId,
  emptyText = "No cases match.",
  filterable = false,
}: {
  rows: OpsCase[];
  basePath: string;
  searchParams?: SearchParamsLike;
  nextCursor?: string | null;
  meId?: string;
  emptyText?: string;
  /** Client-side text filter over the rows on this page. */
  filterable?: boolean;
}) {
  const columns: Column<OpsCase>[] = [
    {
      key: "priority",
      header: "Pri",
      headerText: "Priority",
      render: (c) => <StatusBadge status={c.priority} />,
      sortValue: (c) => c.priority ?? null,
    },
    {
      key: "title",
      header: "Case",
      render: (c) => (
        <div className="min-w-[220px]">
          {c.id ? (
            <Link href={`/cases/${c.id}`} className="link font-medium">
              {c.title ?? c.case_type ?? c.id}
            </Link>
          ) : (
            <span>{c.title ?? "—"}</span>
          )}
          {c.summary ? <p className="mt-0.5 line-clamp-2 text-[0.75rem] text-muted">{c.summary}</p> : null}
        </div>
      ),
      sortValue: (c) => c.title ?? c.case_type ?? null,
    },
    { key: "case_type", header: "Type", render: (c) => (c.case_type ? <span title={c.case_type}>{humanize(c.case_type)}</span> : <span className="text-muted">—</span>), sortValue: (c) => c.case_type ?? null },
    { key: "status", header: "Status", render: (c) => <StatusBadge status={c.status} />, sortValue: (c) => c.status ?? null },
    {
      key: "subject",
      header: "Subject",
      render: (c) => {
        const href = hrefFor(c.subject_kind, c.subject_id);
        const label = c.subject_label ?? c.subject_ref ?? c.subject_id?.slice(0, 8) ?? "—";
        return (
          <span className="font-mono text-[0.75rem]">
            <span className="text-dim">{c.subject_kind ?? ""} </span>
            {href ? (
              <Link href={href} className="link">
                {label}
              </Link>
            ) : (
              label
            )}
          </span>
        );
      },
      sortValue: (c) => c.subject_label ?? c.subject_ref ?? c.subject_id ?? null,
    },
    {
      key: "assignee",
      header: "Assignee",
      render: (c) =>
        c.assignee ? (
          <span className={c.assignee === meId ? "font-semibold text-ink" : ""}>
            {c.assignee === meId ? "me" : c.assignee_label ?? c.assignee_email_masked ?? c.assignee.slice(0, 8)}
          </span>
        ) : (
          <span className="text-dim">unassigned</span>
        ),
      sortValue: (c) => caseAssigneeText(c, meId),
    },
    { key: "due_at", header: "Due", render: (c) => <TimeAgo value={c.due_at} />, sortValue: (c) => c.due_at ?? null },
    { key: "detected_at", header: "Detected", render: (c) => <TimeAgo value={c.detected_at ?? c.created_at} />, sortValue: (c) => c.detected_at ?? c.created_at ?? null, firstSortDir: "desc" },
  ];
  return (
    <DataTable
      columns={columns}
      rows={rows}
      rowKey={(c, i) => c.id ?? `${i}`}
      basePath={basePath}
      searchParams={searchParams}
      nextCursor={nextCursor}
      emptyText={emptyText}
      caption="Cases"
      filterable={filterable}
      filterText={(c) => caseFilterText(c, meId)}
    />
  );
}
