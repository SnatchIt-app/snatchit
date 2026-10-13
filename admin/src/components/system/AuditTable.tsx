import { DataTable, type Column } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DateTime } from "@/components/ui/DateTime";
import { IdLink } from "@/components/ui/IdLink";
import { shortId } from "@/lib/format";
import type { AuditRow } from "@/lib/types";

/** ops.audit rows (append-only). Shared by /system and /actions/[id]. */
export function AuditTable({ rows, basePath, meId, searchParams, nextCursor, cursorParam, id }: { rows: AuditRow[]; basePath: string; meId: string; searchParams?: Record<string, string | string[] | undefined>; nextCursor?: string | null; cursorParam?: string; id?: string }) {
  const columns: Column<AuditRow>[] = [
    { key: "occurred_at", header: "At", render: (r) => <DateTime value={r.occurred_at} withSeconds /> },
    { key: "action", header: "Event", render: (r) => <code className="font-mono text-[12px]">{r.action ?? "—"}</code> },
    { key: "outcome", header: "Outcome", render: (r) => <StatusBadge status={r.outcome} /> },
    { key: "actor", header: "Actor", render: (r) => (r.actor ? (r.actor === meId ? "me" : r.actor_label ?? shortId(r.actor)) : <span className="text-dim">automation</span>) },
    {
      key: "subject",
      header: "Subject",
      render: (r) => (
        <span className="text-[12px]">
          <span className="text-dim">{r.subject_kind} </span>
          <IdLink kind={r.subject_kind} id={r.subject_id} subjectRef={r.subject_ref} label={r.subject_label ?? undefined} />
        </span>
      ),
    },
    { key: "reason", header: "Reason", render: (r) => <span className="line-clamp-2 max-w-[240px] text-[12px] text-muted">{r.reason ?? "—"}</span> },
    { key: "action_id", header: "Action", render: (r) => <IdLink kind="action" id={r.action_id} /> },
    {
      key: "diff",
      header: "Before → after",
      render: (r) => (
        <details className="text-[11px]">
          <summary className="cursor-pointer text-dim">show</summary>
          <pre className="mt-1 max-w-[360px] whitespace-pre-wrap break-words font-mono text-[10px] text-muted">{JSON.stringify({ before: r.before ?? null, after: r.after ?? null }, null, 1)}</pre>
        </details>
      ),
    },
  ];
  return <DataTable id={id} columns={columns} rows={rows} rowKey={(r, i) => r.id ?? `${i}`} basePath={basePath} searchParams={searchParams} nextCursor={nextCursor} cursorParam={cursorParam} emptyText="No audit rows." caption="Audit log" dense />;
}
