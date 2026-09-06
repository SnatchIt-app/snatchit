import Link from "next/link";
import { DataTable, type Column, type SearchParamsLike } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { TimeAgo } from "@/components/ui/DateTime";
import { hrefFor } from "@/components/generic/GenericRpc";
import type { OpsCase } from "@/lib/types";

export function CaseTable({
  rows,
  basePath,
  searchParams,
  nextCursor,
  meId,
  emptyText = "No cases match.",
}: {
  rows: OpsCase[];
  basePath: string;
  searchParams?: SearchParamsLike;
  nextCursor?: string | null;
  meId?: string;
  emptyText?: string;
}) {
  const columns: Column<OpsCase>[] = [
    {
      key: "priority",
      header: "Pri",
      sortKey: "priority",
      render: (c) => <StatusBadge status={c.priority} />,
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
          {c.summary ? <p className="mt-0.5 line-clamp-2 text-[12px] text-muted">{c.summary}</p> : null}
        </div>
      ),
    },
    { key: "case_type", header: "Type", sortKey: "case_type", render: (c) => <span className="font-mono text-[12px]">{c.case_type ?? "—"}</span> },
    { key: "status", header: "Status", sortKey: "status", render: (c) => <StatusBadge status={c.status} /> },
    {
      key: "subject",
      header: "Subject",
      render: (c) => {
        const href = hrefFor(c.subject_kind, c.subject_id);
        const label = c.subject_label ?? c.subject_ref ?? c.subject_id?.slice(0, 8) ?? "—";
        return (
          <span className="font-mono text-[12px]">
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
    },
    {
      key: "assignee",
      header: "Assignee",
      sortKey: "assignee",
      render: (c) =>
        c.assignee ? (
          <span className={c.assignee === meId ? "font-semibold text-ink" : ""}>
            {c.assignee === meId ? "me" : c.assignee_label ?? c.assignee_email_masked ?? c.assignee.slice(0, 8)}
          </span>
        ) : (
          <span className="text-dim">unassigned</span>
        ),
    },
    { key: "due_at", header: "Due", sortKey: "due_at", render: (c) => <TimeAgo value={c.due_at} /> },
    { key: "detected_at", header: "Detected", sortKey: "detected_at", render: (c) => <TimeAgo value={c.detected_at ?? c.created_at} /> },
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
    />
  );
}
