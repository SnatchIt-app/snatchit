import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { newIdempotencyKey } from "@/lib/idempotency";
import { isUuid } from "@/lib/routes";
import { labelFor, refundStateLabel, shortId, REFUND_STATUS_LABELS } from "@/lib/format";
import { refundStatusOf, toActionDetail, type Approval, type ApprovalDecision } from "@/lib/types";
import { PageHeader } from "@/components/ui/PageHeader";
import { Panel } from "@/components/ui/Panel";
import { KeyValue } from "@/components/ui/KeyValue";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DateTime } from "@/components/ui/DateTime";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";
import { ConfirmForm } from "@/components/ui/ConfirmForm";
import { DataTable, type Column } from "@/components/ui/DataTable";
import { IdLink } from "@/components/ui/IdLink";
import { CaseTable } from "@/components/cases/CaseTable";
import { ResumeRefundForm } from "@/components/actions/ResumeRefundForm";
import { AuditTable } from "@/components/system/AuditTable";
import { renderValue } from "@/components/generic/GenericRpc";

export const metadata: Metadata = { title: "Action" };
export const dynamic = "force-dynamic";

/** ops.executor_claim() only claims processing / unknown; succeeded_at_provider completes via the webhook + detector. */
const RESUMABLE = new Set(["processing", "unknown"]);

export default async function ActionPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();
  const me = await requireOperator();
  const path = `/actions/${id}`;

  const res = await callOps<unknown>("action_detail", { p_action_id: id });
  if (!res.ok) {
    return (
      <>
        <PageHeader eyebrow="Action" title={<code className="font-mono">{shortId(id)}</code>} />
        {res.kind === "error" && res.message.toLowerCase().includes("not_found") ? (
          <Alert state="empty" title="No action with this id." retryHref="/system#actions" retryLabel="Back to actions" />
        ) : (
          <OpsFailureAlert failure={res} fn="action_detail" retryHref={path} />
        )}
      </>
    );
  }
  const d = toActionDetail(res.data);
  if (!d || !d.action) {
    return (
      <>
        <PageHeader eyebrow="Action" title={<code className="font-mono">{shortId(id)}</code>} />
        <Alert state="failed" title="Unrecognised payload from ops.action_detail()" retryHref={path} />
      </>
    );
  }
  const a = d.action;
  const pending = d.approvals.find((ap) => ap.state === "pending");
  const isRequester = a.requested_by === me.id;
  const resumable = a.action_type === "refund_execute" && RESUMABLE.has(a.state ?? "") && me.role === "platform_admin";
  const refundStatus = a.action_type === "refund_execute" ? refundStatusOf(a.result) : null;
  const stateLabel = a.action_type === "refund_execute" ? refundStateLabel(a.state, refundStatus) : labelFor("action", a.state);

  return (
    <>
      <PageHeader
        eyebrow={
          <>
            <Link href="/system#actions" className="hover:text-ink">
              Actions
            </Link>{" "}
            / {shortId(id)}
          </>
        }
        title={labelFor("action_type", a.action_type)}
        description={a.reason}
        meta={
          <span className="flex flex-wrap items-center gap-2">
            <StatusBadge status={a.state} label={stateLabel} />
            {a.reject_reason ? <StatusBadge status={a.reject_reason} label={`reject: ${a.reject_reason.replace(/_/g, " ")}`} /> : null}
            <span>
              Subject: <span className="text-dim">{a.subject_kind}</span> <IdLink kind={a.subject_kind} id={a.subject_id} subjectRef={a.subject_ref} label={a.subject_label ?? undefined} />
            </span>
            <span>
              · Requested <DateTime value={a.requested_at} /> by {isRequester ? "me" : a.requested_by_label ?? shortId(a.requested_by)}
            </span>
          </span>
        }
      />

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <Panel eyebrow="ops.action" title="Record">
            <KeyValue
              columns={3}
              items={[
                { key: "id", value: <code className="font-mono text-[12px]">{a.id}</code> },
                { key: "action_type", value: <code className="font-mono text-[12px]">{a.action_type}</code> },
                { key: "state", value: <StatusBadge status={a.state} label={stateLabel} /> },
                ...(a.action_type === "refund_execute"
                  ? [{ key: "refund_status", label: "Provider refund status", value: refundStatus ? <StatusBadge status={refundStatus} label={REFUND_STATUS_LABELS[refundStatus] ?? refundStatus} /> : <span className="text-dim">not reported yet</span> }]
                  : []),
                { key: "requested_by", value: isRequester ? "me" : a.requested_by_label ?? a.requested_by },
                { key: "requested_at", value: <DateTime value={a.requested_at} withSeconds /> },
                { key: "completed_at", value: <DateTime value={a.completed_at} withSeconds /> },
                { key: "correlation_id", value: <code className="font-mono text-[12px]">{a.correlation_id ?? "—"}</code> },
                { key: "idempotency_key", value: <code className="font-mono text-[12px]">{a.idempotency_key ?? "—"}</code> },
                { key: "provider_ref", label: "Provider reference (Stripe)", value: a.provider_ref ? <code className="font-mono text-[12px]">{a.provider_ref}</code> : null },
                { key: "approval_id", value: a.approval_id ? <code className="font-mono text-[12px]">{a.approval_id}</code> : null },
                { key: "version", value: a.version !== undefined ? `v${a.version}` : null },
                { key: "error", value: a.error ? <span className="text-danger">{a.error}</span> : null },
              ]}
            />
            <h3 className="eyebrow mt-4 text-dim">Params (as requested)</h3>
            <div className="mt-2 text-[13px]">{renderValue("params", a.params ?? {})}</div>
            <h3 className="eyebrow mt-4 text-dim">Expected state at request time</h3>
            <div className="mt-2 text-[13px]">{renderValue("expected", a.expected ?? {})}</div>
            <h3 className="eyebrow mt-4 text-dim">Result (authoritative)</h3>
            <div className="mt-2 text-[13px]">{a.result === null || a.result === undefined ? <span className="text-dim">no result yet</span> : renderValue("result", a.result)}</div>
          </Panel>

          <Panel eyebrow={`${d.approvals.length}`} title="Approvals">
            <ApprovalTable rows={d.approvals} basePath={path} meId={me.id} />
            {pending ? (
              <div className="mt-4 border-t border-line-neutral pt-4">
                {isRequester ? (
                  <Alert state="info" title="You requested this — a different founder must decide." compact>
                    Expires <DateTime value={pending.expires_at} />.
                  </Alert>
                ) : pending.can_decide ? (
                  <ApprovalDecisionForms approval={pending} actionId={id} revalidate={path} />
                ) : (
                  <Alert state="info" title="Only another platform_admin can decide this approval." compact />
                )}
              </div>
            ) : null}
          </Panel>

          <Panel eyebrow={`${d.audit.length}`} title="Related audit rows">
            <AuditTable rows={d.audit} basePath={path} meId={me.id} />
          </Panel>

          {d.related_cases.length ? (
            <Panel eyebrow={`${d.related_cases.length}`} title="Related cases">
              <CaseTable rows={d.related_cases} basePath={path} meId={me.id} />
            </Panel>
          ) : null}
        </div>

        <div className="space-y-6">
          {a.action_type === "refund_execute" ? (
            <Panel eyebrow="Executor" title="Refund execution">
              {a.state === "processing" ? (
                <Alert state="warning" title={refundStatus === "requires_action" ? "Requires action at Stripe — not succeeded." : refundStatus === "pending" ? "Accepted by Stripe, not yet succeeded." : "Processing — the outcome is not yet known."} compact>
                  {refundStatus ? (
                    <>
                      Stripe reports refund status <code className="font-mono">{refundStatus}</code>. This is not a completed refund; the payment shows “refunded” only after the charge.refunded webhook lands.
                    </>
                  ) : (
                    "The executor has not recorded a provider status yet. Resume is safe (same idempotency key)."
                  )}
                </Alert>
              ) : null}
              {a.state === "unknown" ? (
                <Alert state="failed" title="Outcome unknown — needs reconciliation." compact>
                  Stripe may or may not have refunded. Resume looks the refund up under its idempotency key before doing anything; if it stays unknown, verify in the Stripe Dashboard and escalate.
                </Alert>
              ) : null}
              {a.state === "succeeded_at_provider" ? (
                <Alert state="info" title="Succeeded at provider — awaiting local webhook." compact>
                  Stripe refunded{a.provider_ref ? <> (<code className="font-mono">{a.provider_ref}</code>)</> : null}; the local payment flips to refunded when charge.refunded lands and the detector completes this action. Nothing to resume.
                </Alert>
              ) : null}
              <div className={a.state === "processing" || a.state === "unknown" || a.state === "succeeded_at_provider" ? "mt-3" : ""}>
                {resumable ? (
                  <ResumeRefundForm actionId={id} state={a.state} refundStatus={refundStatus} />
                ) : (
                  <Alert state="info" title={RESUMABLE.has(a.state ?? "") ? "Only a founder can resume execution." : `Nothing to resume in state “${stateLabel}”.`} compact>
                    {a.state === "awaiting_approval" ? "The other founder must approve first." : null}
                  </Alert>
                )}
              </div>
            </Panel>
          ) : null}

          {d.subject ? (
            <Panel eyebrow={a.subject_kind ?? "subject"} title="Subject snapshot">
              <KeyValue
                columns={1}
                items={Object.entries(d.subject)
                  .filter(([k]) => !["open_cases"].includes(k))
                  .slice(0, 24)
                  .map(([k, v]) => ({ key: k, value: renderValue(k, v, 1) }))}
              />
            </Panel>
          ) : null}
        </div>
      </div>
    </>
  );
}

function ApprovalDecisionForms({ approval, actionId, revalidate }: { approval: Approval; actionId: string; revalidate: string }) {
  const approve: ApprovalDecision = "approve";
  const deny: ApprovalDecision = "deny";
  return (
    <div className="grid gap-4 sm:grid-cols-2">
      {approval.hash_current === false ? <Alert state="stale" title="Action terms changed since approval was requested — the decision will be rejected as stale." compact /> : null}
      <ConfirmForm idempotencyKey={newIdempotencyKey()} actionType="approval_decide" subjectKind="action" subjectId={actionId} params={{ action_id: actionId, decision: approve }} revalidate={revalidate} label="Approve and execute" danger reasonLabel="Approval reason">
        <p className="text-[12px] text-muted">Approving executes the action immediately with the requester as the domain actor. Bound to the exact terms shown above.</p>
      </ConfirmForm>
      <ConfirmForm idempotencyKey={newIdempotencyKey()} actionType="approval_decide" subjectKind="action" subjectId={actionId} params={{ action_id: actionId, decision: deny }} revalidate={revalidate} label="Deny" reasonLabel="Denial reason">
        <p className="text-[12px] text-muted">Denying rejects the action; nothing changes.</p>
      </ConfirmForm>
    </div>
  );
}

function ApprovalTable({ rows, basePath, meId }: { rows: Approval[]; basePath: string; meId: string }) {
  const columns: Column<Approval>[] = [
    { key: "created_at", header: "Requested", render: (r) => <DateTime value={r.created_at} /> },
    { key: "requested_by", header: "Requester", render: (r) => (r.requested_by === meId ? "me" : r.requested_by_label ?? shortId(r.requested_by)) },
    { key: "state", header: "State", render: (r) => <StatusBadge status={r.state} label={labelFor("approval", r.state)} /> },
    { key: "decided_by", header: "Decided by", render: (r) => (r.decided_by ? (r.decided_by === meId ? "me" : r.decided_by_label ?? shortId(r.decided_by)) : <span className="text-dim">—</span>) },
    { key: "decided_at", header: "Decided", render: (r) => <DateTime value={r.decided_at} /> },
    { key: "expires_at", header: "Expires", render: (r) => <DateTime value={r.expires_at} /> },
    { key: "reason", header: "Decision reason", render: (r) => <span className="text-[12px] text-muted">{r.reason ?? "—"}</span> },
    { key: "hash", header: "Terms", render: (r) => (r.hash_current === false ? <StatusBadge status="stale" label="changed" /> : <code className="font-mono text-[10px] text-dim">{r.action_hash?.slice(0, 12)}</code>) },
  ];
  return <DataTable columns={columns} rows={rows} rowKey={(r, i) => r.id ?? `${i}`} basePath={basePath} emptyText="No approval required for this action." caption="Approvals" dense />;
}
