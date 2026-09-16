import Link from "next/link";
import { DataTable, type Column, type SearchParamsLike } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { TimeAgo } from "@/components/ui/DateTime";
import { IdLink } from "@/components/ui/IdLink";
import { labelFor } from "@/lib/format";
import type { OpsAction } from "@/lib/types";

export function ActionTable({
  rows,
  basePath,
  searchParams,
  nextCursor,
  cursorParam,
  meId,
  hideSubject = false,
  id,
}: {
  rows: OpsAction[];
  basePath: string;
  searchParams?: SearchParamsLike;
  nextCursor?: string | null;
  cursorParam?: string;
  meId?: string;
  hideSubject?: boolean;
  id?: string;
}) {
  const columns: Column<OpsAction>[] = [
    { key: "requested_at", header: "Requested", render: (a) => <TimeAgo value={a.requested_at ?? a.created_at} /> },
    {
      key: "action_type",
      header: "Action",
      render: (a) => (
        <span className="flex flex-col">
          {a.id ? (
            <Link href={`/actions/${a.id}`} className="link font-medium">
              {labelFor("action_type", a.action_type)}
            </Link>
          ) : (
            labelFor("action_type", a.action_type)
          )}
          <code className="font-mono text-[10px] text-dim">{a.id}</code>
        </span>
      ),
    },
    { key: "state", header: "State", render: (a) => <StatusBadge status={a.state} label={labelFor("action", a.state)} /> },
    ...(hideSubject
      ? []
      : ([
          {
            key: "subject",
            header: "Subject",
            render: (a) => (
              <span className="text-[12px]">
                <span className="text-dim">{a.subject_kind} </span>
                <IdLink kind={a.subject_kind} id={a.subject_id} subjectRef={a.subject_ref} label={a.subject_label ?? undefined} />
              </span>
            ),
          },
        ] as Column<OpsAction>[])),
    {
      key: "requested_by",
      header: "Requester",
      render: (a) => <span>{a.requested_by === meId ? "me" : a.requested_by_label ?? a.requested_by?.slice(0, 8) ?? "—"}</span>,
    },
    { key: "reason", header: "Reason", render: (a) => <span className="line-clamp-2 max-w-[260px] text-[12px] text-muted">{a.reason ?? "—"}</span> },
    {
      key: "outcome",
      header: "Outcome",
      render: (a) => (
        <span className="text-[12px] text-muted">
          {a.reject_reason ? `rejected: ${a.reject_reason.replace(/_/g, " ")}` : a.error ? a.error : a.provider_ref ? <code className="font-mono">{a.provider_ref}</code> : "—"}
        </span>
      ),
    },
  ];
  return <DataTable id={id} columns={columns} rows={rows} rowKey={(a, i) => a.id ?? `${i}`} basePath={basePath} searchParams={searchParams} nextCursor={nextCursor} cursorParam={cursorParam} emptyText="No actions." caption="Actions" dense />;
}
