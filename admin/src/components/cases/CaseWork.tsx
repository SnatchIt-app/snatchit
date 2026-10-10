import Link from "next/link";
import type { ReactNode } from "react";
import { newIdempotencyKey } from "@/lib/idempotency";
import { CASE_PRIORITIES, CASE_STATUSES, type OpsCase, type CaseDetail } from "@/lib/types";
import { humanize } from "@/lib/format";
import { ConfirmForm } from "@/components/ui/ConfirmForm";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DateTime, TimeAgo } from "@/components/ui/DateTime";
import { Icon } from "@/components/ui/Icon";
import { hrefFor } from "@/components/generic/GenericRpc";

/**
 * The pieces of a case shared by the split view's detail pane and the full
 * case page, so both offer exactly the same work with exactly the same
 * safeguards: every change is an `execute_action` carrying the version that
 * was rendered (a concurrent edit is rejected as stale_state), a fresh
 * idempotency key, and the reason the audit log requires.
 */

type Me = { id: string; label: string };
export type CaseEnvelope = { subjectKind: string; subjectId: string; expected: Record<string, unknown>; revalidate: string };

export function caseEnvelope(c: OpsCase, id: string, revalidate: string): CaseEnvelope {
  return { subjectKind: "case", subjectId: id, expected: c.version !== undefined ? { version: c.version } : {}, revalidate };
}

export const assigneeName = (c: OpsCase, meId: string) =>
  c.assignee ? (c.assignee === meId ? "me" : (c.assignee_label ?? c.assignee_email_masked ?? c.assignee.slice(0, 8))) : null;

/** The subject the case is about, as a link when the console has a page for it. */
export function CaseSubject({ c }: { c: OpsCase }) {
  const href = hrefFor(c.subject_kind, c.subject_id);
  const label = c.subject_label ?? c.subject_ref ?? c.subject_id?.slice(0, 8);
  if (!c.subject_kind || c.subject_kind === "none") return <span className="text-muted">No subject</span>;
  return (
    <span className="min-w-0">
      <span className="text-muted">{humanize(c.subject_kind)} </span>
      {href ? (
        <Link href={href} className="link font-mono text-[0.8125rem]">
          {label}
        </Link>
      ) : (
        <span className="font-mono text-[0.8125rem]">{label ?? "—"}</span>
      )}
    </span>
  );
}

/** Who, when and what — the case's facts in one hairline-divided list. */
export function CaseFacts({ c, meId, notes }: { c: OpsCase; meId: string; notes?: number }) {
  const who = assigneeName(c, meId);
  const rows: [string, ReactNode][] = [
    ["Subject", <CaseSubject key="s" c={c} />],
    ["Assignee", who ? <span className={who === "me" ? "font-medium" : ""}>{who}</span> : <span className="text-muted">Unassigned</span>],
    ["Due", c.due_at ? <DateTime value={c.due_at} /> : <span className="text-muted">No due date</span>],
    ["Detected", <DateTime key="d" value={c.detected_at ?? c.created_at} />],
    ["Last seen", c.last_seen_at ? <DateTime value={c.last_seen_at} /> : <span className="text-muted">—</span>],
  ];
  if (notes !== undefined) rows.push(["Notes", String(notes)]);
  if (c.resolved_at) rows.push(["Resolved", <DateTime key="r" value={c.resolved_at} />]);
  if (c.resolution_note) rows.push(["Resolution", <span key="n" className="whitespace-pre-wrap">{c.resolution_note}</span>]);
  return (
    <dl className="divide-y divide-[rgba(70,50,30,0.1)] border-y border-line text-[0.875rem]">
      {rows.map(([k, v]) => (
        <div key={k} className="grid grid-cols-[6.5rem_minmax(0,1fr)] gap-x-4 py-2.5">
          <dt className="text-muted">{k}</dt>
          <dd className="min-w-0 break-words">{v}</dd>
        </div>
      ))}
    </dl>
  );
}

/**
 * Assign, status, priority and due — one disclosure each, so the pane stays
 * short and the current value is readable without opening anything.
 */
export function CaseControls({ c, detail, me, envelope, idPrefix }: { c: OpsCase; detail: CaseDetail; me: Me; envelope: CaseEnvelope; idPrefix: string }) {
  const id = (s: string) => `${idPrefix}-${s}`;
  return (
    <div className="divide-y divide-[rgba(70,50,30,0.1)] border-y border-line">
      <Control title="Assign" current={assigneeName(c, me.id) ?? "Unassigned"}>
        <ConfirmForm key={`assign-${c.version}`} idempotencyKey={newIdempotencyKey()} actionType="case_assign" {...envelope} label="Assign">
          <label htmlFor={id("assignee")} className="eyebrow block text-dim">
            Assignee
          </label>
          <select id={id("assignee")} name="param.assignee" defaultValue={c.assignee ?? ""} className="field mt-1">
            <option value="">Unassigned</option>
            <option value={me.id}>Me ({me.label})</option>
            {detail.operators
              .filter((o) => o.user_id && o.user_id !== me.id)
              .map((o) => (
                <option key={o.user_id} value={o.user_id}>
                  {o.display ?? o.email_masked ?? o.user_id} {o.role ? `· ${o.role.replace("platform_", "")}` : ""}
                </option>
              ))}
          </select>
        </ConfirmForm>
      </Control>

      <Control title="Status" current={<StatusBadge status={c.status} />}>
        <ConfirmForm key={`status-${c.version}`} idempotencyKey={newIdempotencyKey()} actionType="case_status" {...envelope} label="Set status">
          <label htmlFor={id("status")} className="eyebrow block text-dim">
            Status
          </label>
          <select id={id("status")} name="param.status" defaultValue={c.status ?? "open"} className="field mt-1">
            {CASE_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s.replace("_", " ")}
              </option>
            ))}
          </select>
        </ConfirmForm>
      </Control>

      <Control title="Priority" current={<StatusBadge status={c.priority} />}>
        <ConfirmForm key={`priority-${c.version}`} idempotencyKey={newIdempotencyKey()} actionType="case_priority" {...envelope} label="Set priority">
          <label htmlFor={id("priority")} className="eyebrow block text-dim">
            Priority
          </label>
          <select id={id("priority")} name="param.priority" defaultValue={c.priority ?? "p3"} className="field mt-1">
            {CASE_PRIORITIES.map((p) => (
              <option key={p} value={p}>
                {p.toUpperCase()}
              </option>
            ))}
          </select>
        </ConfirmForm>
      </Control>

      <Control title="Due" current={c.due_at ? <TimeAgo value={c.due_at} /> : "No due date"}>
        <ConfirmForm key={`due-${c.version}`} idempotencyKey={newIdempotencyKey()} actionType="case_due" {...envelope} label="Set due">
          <label htmlFor={id("due")} className="eyebrow block text-dim">
            Due (your local time; stored as UTC)
          </label>
          <input id={id("due")} type="datetime-local" name="param.due_at" defaultValue={c.due_at ? c.due_at.slice(0, 16) : ""} className="field mt-1" />
          <p className="mt-1 text-[0.6875rem] text-dim">Leave empty to clear the due date.</p>
        </ConfirmForm>
      </Control>
    </div>
  );
}

function Control({ title, current, children }: { title: string; current: ReactNode; children: ReactNode }) {
  return (
    <details className="group">
      <summary className="flex min-h-12 cursor-pointer items-center gap-3 rounded-[10px] py-2 text-[0.875rem] [&::marker]:hidden [&::-webkit-details-marker]:hidden">
        <span className="w-[6.5rem] shrink-0 text-muted">{title}</span>
        <span className="min-w-0 flex-1 truncate">{current}</span>
        <span className="flex items-center gap-1 text-[0.8125rem] font-medium text-muted group-hover:text-ink">
          <span className="group-open:hidden">Change</span>
          <span className="hidden group-open:inline">Close</span>
          <Icon name="down" size={14} className="transition-transform group-open:rotate-180" />
        </span>
      </summary>
      <div className="pb-4 pt-1">{children}</div>
    </details>
  );
}

/** Append-only notes, newest last, with the form to add one. */
export function CaseNotes({ c, detail, meId, envelope, idPrefix, limit }: { c: OpsCase; detail: CaseDetail; meId: string; envelope: CaseEnvelope; idPrefix: string; limit?: number }) {
  const notes = limit ? detail.notes.slice(-limit) : detail.notes;
  const hidden = detail.notes.length - notes.length;
  return (
    <div>
      {detail.notes.length === 0 ? (
        <p className="text-[0.875rem] text-muted">No notes yet.</p>
      ) : (
        <ol className="flex flex-col gap-3">
          {hidden > 0 ? <li className="text-[0.8125rem] text-muted">{hidden} earlier {hidden === 1 ? "note" : "notes"} on the full case.</li> : null}
          {notes.map((n, i) => (
            <li key={n.id ?? i} className="rounded-[14px] bg-[rgba(255,255,255,0.7)] px-3.5 py-3 ring-1 ring-[rgba(70,50,30,0.08)]">
              <p className="whitespace-pre-wrap text-[0.875rem] leading-relaxed">{n.body ?? "—"}</p>
              <p className="mt-1.5 text-[0.75rem] text-muted">
                {n.author_email_masked ?? (n.author === meId ? "me" : n.author?.slice(0, 8)) ?? "—"} · <DateTime value={n.created_at} />
              </p>
            </li>
          ))}
        </ol>
      )}
      <div className="mt-4">
        <ConfirmForm key={`note-${c.version}`} idempotencyKey={newIdempotencyKey()} actionType="case_note" {...envelope} label="Add note" reasonRequired={false}>
          <label htmlFor={`${idPrefix}-note`} className="eyebrow block text-dim">
            New note
          </label>
          <textarea id={`${idPrefix}-note`} name="param.body" required rows={3} maxLength={4000} className="field mt-1" placeholder="Append-only; visible to all operators." />
        </ConfirmForm>
      </div>
    </div>
  );
}
