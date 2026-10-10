import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { toCaseDetail } from "@/lib/types";
import { humanize } from "@/lib/format";
import { PageHeader } from "@/components/ui/PageHeader";
import { Panel } from "@/components/ui/Panel";
import { KeyValue } from "@/components/ui/KeyValue";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DateTime } from "@/components/ui/DateTime";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";
import { Icon } from "@/components/ui/Icon";
import { CaseControls, CaseFacts, CaseNotes, caseEnvelope } from "@/components/cases/CaseWork";
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
  const envelope = caseEnvelope(c, id, path);
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
            / {humanize(c.case_type ?? "case")}
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

      <div className="grid grid-cols-1 items-start gap-6 lg:grid-cols-[minmax(0,1fr)_24rem]">
        <div className="min-w-0 space-y-6">
          <Panel title="The case">
            <CaseFacts c={c} meId={me.id} />
            <details className="group mt-3">
              <summary className="inline-flex min-h-9 items-center gap-1.5 rounded-lg text-[0.8125rem] text-muted hover:text-ink">
                For support
                <Icon name="down" size={14} className="transition-transform group-open:rotate-180" />
              </summary>
              <dl className="mt-2 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-4 gap-y-2 rounded-2xl bg-[rgba(255,255,255,0.6)] p-4 text-[0.75rem]">
                <dt className="text-muted">Case id</dt>
                <dd className="select-all break-all font-mono">{c.id}</dd>
                <dt className="text-muted">Raised by</dt>
                <dd className="break-all font-mono">{c.detector ?? "—"}</dd>
                <dt className="text-muted">Duplicate key</dt>
                <dd className="break-all font-mono">{c.dedupe_key ?? "—"}</dd>
                <dt className="text-muted">Resolved by</dt>
                <dd className="break-all font-mono">{c.resolved_by ?? "—"}</dd>
              </dl>
            </details>
          </Panel>

          {detail.subject ? (
            <Panel eyebrow="What this case is about" title={humanize(c.subject_kind ?? "subject")}>
              <KeyValue columns={3} items={Object.entries(detail.subject).map(([k, v]) => ({ key: k, value: renderValue(k, v, 1) }))} />
            </Panel>
          ) : null}

          <Panel title="Notes" description={`${detail.notes.length} ${detail.notes.length === 1 ? "note" : "notes"} · append-only`}>
            <CaseNotes c={c} detail={detail} meId={me.id} envelope={envelope} idPrefix="page" />
          </Panel>

          <Panel title="Timeline">
            {detail.events.length === 0 ? (
              <p className="text-[0.875rem] text-muted">No events.</p>
            ) : (
              <ol className="flex flex-col">
                {detail.events.map((e, i) => (
                  <li key={e.id ?? i} className="grid grid-cols-[1.25rem_minmax(0,1fr)] gap-x-3">
                    <span className="flex flex-col items-center">
                      <span aria-hidden="true" className="mt-1.5 h-2 w-2 rounded-full bg-[#b9aa9b]" />
                      {i < detail.events.length - 1 ? <span aria-hidden="true" className="w-px flex-1 bg-[rgba(70,50,30,0.14)]" /> : null}
                    </span>
                    <div className="pb-4 text-[0.875rem]">
                      <p className="font-medium">{e.label ?? humanize(e.kind ?? "event")}</p>
                      <p className="mt-0.5 flex flex-wrap items-center gap-x-2 text-[0.8125rem] text-muted">
                        <DateTime value={e.at} />
                        {e.actor ? <span>by {e.actor === me.id ? "me" : e.actor}</span> : null}
                        {e.kind ? (
                          <span className="font-mono text-[0.75rem]" title="Event kind">
                            {e.kind}
                          </span>
                        ) : null}
                      </p>
                    </div>
                  </li>
                ))}
              </ol>
            )}
          </Panel>

          {detail.actions.length ? (
            <Panel title="Actions on this case" description={`${detail.actions.length} recorded`} flush>
              <GenericTable rows={detail.actions} basePath={path} />
            </Panel>
          ) : null}
        </div>

        <div className="space-y-6 lg:sticky lg:top-24">
          {closed ? <Alert state="info" title={`This case is ${c.status}.`} compact /> : null}
          <Panel title="Work this case" description="Each change needs a reason and is written to the audit log.">
            <CaseControls c={c} detail={detail} me={{ id: me.id, label: me.whoami.email_masked ?? me.email ?? me.id.slice(0, 8) }} envelope={envelope} idPrefix="page" />
          </Panel>
        </div>
      </div>
    </>
  );
}
