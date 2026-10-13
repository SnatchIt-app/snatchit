import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { newIdempotencyKey } from "@/lib/idempotency";
import { CASE_PRIORITIES, CASE_STATUSES, toCaseDetail } from "@/lib/types";
import { humanize } from "@/lib/format";
import { PageHeader } from "@/components/ui/PageHeader";
import { Panel } from "@/components/ui/Panel";
import { KeyValue } from "@/components/ui/KeyValue";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DateTime } from "@/components/ui/DateTime";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";
import { ConfirmForm } from "@/components/ui/ConfirmForm";
import { GenericTable, hrefFor, renderValue } from "@/components/generic/GenericRpc";

export const metadata: Metadata = { title: "Case" };
export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function CaseDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const me = await requireOperator();

  const res = await callOps<unknown>("case_detail", { p_case_id: id });
  if (!res.ok) {
    return (
      <>
        <PageHeader eyebrow="Case" title={id.slice(0, 8)} />
        <OpsFailureAlert failure={res} fn="case_detail" retryHref={`/cases/${id}`} />
      </>
    );
  }
  const detail = toCaseDetail(res.data);
  if (!detail || !detail.case) {
    return (
      <>
        <PageHeader eyebrow="Case" title={id.slice(0, 8)} />
        <Alert state="empty" title="No case with this id." retryHref="/cases" retryLabel="Back to cases" />
      </>
    );
  }
  const c = detail.case;
  const path = `/cases/${id}`;
  // Every mutation carries the version we rendered, so a concurrent edit is
  // rejected server-side as stale_state instead of silently overwriting.
  const expected = c.version !== undefined ? { version: c.version } : {};
  const envelope = { subjectKind: "case", subjectId: id, expected, revalidate: path };
  const subjectHref = hrefFor(c.subject_kind, c.subject_id);
  const closed = c.status === "resolved" || c.status === "dismissed";

  return (
    <>
      <PageHeader
        eyebrow={
          <>
            <Link href="/cases" className="hover:text-ink">
              Cases
            </Link>{" "}
            / {c.case_type ?? "case"}
          </>
        }
        title={c.title ?? humanize(c.case_type ?? "Case")}
        description={c.summary}
        meta={
          <span className="flex flex-wrap items-center gap-2">
            <StatusBadge status={c.status} />
            <StatusBadge status={c.priority} />
            <span>
              Subject:{" "}
              {subjectHref ? (
                <Link href={subjectHref} className="link font-mono">
                  {c.subject_kind} {c.subject_label ?? c.subject_ref ?? c.subject_id}
                </Link>
              ) : (
                <span className="font-mono">{c.subject_ref ?? c.subject_id ?? "—"}</span>
              )}
            </span>
            <span>
              · Detected <DateTime value={c.detected_at ?? c.created_at} />
            </span>
            {c.version !== undefined ? <span className="font-mono text-dim">· v{c.version}</span> : null}
          </span>
        }
      />

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <Panel eyebrow="Case" title="Details">
            <KeyValue
              columns={3}
              items={[
                { key: "id", value: <code className="font-mono text-[12px]">{c.id}</code> },
                { key: "detector", value: c.detector },
                { key: "dedupe_key", value: c.dedupe_key ? <code className="font-mono text-[12px]">{c.dedupe_key}</code> : null },
                { key: "assignee", value: c.assignee ? (c.assignee === me.id ? "me" : c.assignee_label ?? c.assignee_email_masked ?? c.assignee) : "unassigned" },
                { key: "due_at", value: <DateTime value={c.due_at} /> },
                { key: "last_seen_at", value: <DateTime value={c.last_seen_at} /> },
                { key: "resolved_at", value: <DateTime value={c.resolved_at} /> },
                { key: "resolved_by", value: c.resolved_by },
                { key: "resolution_note", value: c.resolution_note },
              ]}
            />
          </Panel>

          {detail.subject ? (
            <Panel eyebrow="Subject" title={humanize(c.subject_kind ?? "subject")}>
              <KeyValue columns={3} items={Object.entries(detail.subject).map(([k, v]) => ({ key: k, value: renderValue(k, v, 1) }))} />
            </Panel>
          ) : null}

          <Panel eyebrow={`${detail.notes.length}`} title="Notes">
            {detail.notes.length === 0 ? (
              <p className="text-dim">No notes yet.</p>
            ) : (
              <ol className="space-y-3">
                {detail.notes.map((n, i) => (
                  <li key={n.id ?? i} className="border-l-2 border-line-strong pl-3">
                    <p className="whitespace-pre-wrap text-[13px] text-ink">{n.body ?? "—"}</p>
                    <p className="mt-1 text-[11px] text-dim">
                      {n.author_email_masked ?? (n.author === me.id ? "me" : n.author?.slice(0, 8)) ?? "—"} · <DateTime value={n.created_at} />
                    </p>
                  </li>
                ))}
              </ol>
            )}
            <div className="mt-4 border-t border-line-neutral pt-4">
              <ConfirmForm key={`note-${c.version}`} idempotencyKey={newIdempotencyKey()} actionType="case_note" {...envelope} label="Add note" reasonRequired={false}>
                <label htmlFor="note-body" className="eyebrow block text-dim">
                  New note
                </label>
                <textarea id="note-body" name="param.body" required rows={3} maxLength={4000} className="field mt-1" placeholder="Append-only; visible to all operators." />
              </ConfirmForm>
            </div>
          </Panel>

          <Panel eyebrow={`${detail.events.length}`} title="Timeline">
            {detail.events.length === 0 ? (
              <p className="text-dim">No events.</p>
            ) : (
              <ol className="space-y-2">
                {detail.events.map((e, i) => (
                  <li key={e.id ?? i} className="flex flex-wrap items-baseline gap-2 border-b border-line-neutral pb-2 text-[13px]">
                    <DateTime value={e.at} />
                    <StatusBadge status={e.kind} variant="neutral" />
                    <span className="text-ink">{e.label ?? humanize(e.kind ?? "event")}</span>
                    {e.actor ? <span className="text-dim">by {e.actor === me.id ? "me" : e.actor}</span> : null}
                  </li>
                ))}
              </ol>
            )}
          </Panel>

          {detail.actions.length ? (
            <Panel eyebrow={`${detail.actions.length}`} title="Actions on this case">
              <GenericTable rows={detail.actions} basePath={path} />
            </Panel>
          ) : null}
        </div>

        <div className="space-y-6">
          {closed ? <Alert state="info" title={`This case is ${c.status}.`} compact /> : null}

          <Panel eyebrow="Ownership" title="Assign">
            <ConfirmForm key={`assign-${c.version}`} idempotencyKey={newIdempotencyKey()} actionType="case_assign" {...envelope} label="Assign">
              <label htmlFor="assignee" className="eyebrow block text-dim">
                Assignee
              </label>
              <select id="assignee" name="param.assignee" defaultValue={c.assignee ?? ""} className="field mt-1">
                <option value="">Unassigned</option>
                <option value={me.id}>Me ({me.whoami.email_masked ?? me.email ?? me.id.slice(0, 8)})</option>
                {detail.operators
                  .filter((o) => o.user_id && o.user_id !== me.id)
                  .map((o) => (
                    <option key={o.user_id} value={o.user_id}>
                      {o.display ?? o.email_masked ?? o.user_id} {o.role ? `· ${o.role.replace("platform_", "")}` : ""}
                    </option>
                  ))}
              </select>
            </ConfirmForm>
          </Panel>

          <Panel eyebrow="State" title="Status">
            <ConfirmForm key={`status-${c.version}`} idempotencyKey={newIdempotencyKey()} actionType="case_status" {...envelope} label="Set status">
              <label htmlFor="status" className="eyebrow block text-dim">
                Status
              </label>
              <select id="status" name="param.status" defaultValue={c.status ?? "open"} className="field mt-1">
                {CASE_STATUSES.map((s) => (
                  <option key={s} value={s}>
                    {s.replace("_", " ")}
                  </option>
                ))}
              </select>
            </ConfirmForm>
          </Panel>

          <Panel eyebrow="Triage" title="Priority">
            <ConfirmForm key={`priority-${c.version}`} idempotencyKey={newIdempotencyKey()} actionType="case_priority" {...envelope} label="Set priority">
              <label htmlFor="priority" className="eyebrow block text-dim">
                Priority
              </label>
              <select id="priority" name="param.priority" defaultValue={c.priority ?? "p3"} className="field mt-1">
                {CASE_PRIORITIES.map((p) => (
                  <option key={p} value={p}>
                    {p.toUpperCase()}
                  </option>
                ))}
              </select>
            </ConfirmForm>
          </Panel>

          <Panel eyebrow="SLA" title="Due">
            <ConfirmForm key={`due-${c.version}`} idempotencyKey={newIdempotencyKey()} actionType="case_due" {...envelope} label="Set due">
              <label htmlFor="due" className="eyebrow block text-dim">
                Due (your local time; stored as UTC)
              </label>
              <input id="due" type="datetime-local" name="param.due_at" defaultValue={c.due_at ? c.due_at.slice(0, 16) : ""} className="field mt-1" />
              <p className="mt-1 text-[11px] text-dim">Leave empty to clear the due date.</p>
            </ConfirmForm>
          </Panel>
        </div>
      </div>
    </>
  );
}
