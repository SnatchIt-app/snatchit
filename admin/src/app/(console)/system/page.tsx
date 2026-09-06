import type { Metadata } from "next";
import Link from "next/link";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { newIdempotencyKey } from "@/lib/idempotency";
import { canRequest } from "@/lib/permissions";
import { settingFieldName, settingKind } from "@/lib/form-params";
import { humanize, labelFor, shortId, ACTION_STATE_LABELS, ACTION_TYPE_LABELS } from "@/lib/format";
import { first, limitOf, list, type SearchParams } from "@/lib/search-params";
import {
  toActions,
  toApproval,
  toAuditRow,
  toDailySummary,
  toJobHealth,
  toListPage,
  toSettings,
  type Approval,
  type AuditRow,
  type CronJob,
  type OpsJob,
  type Setting,
} from "@/lib/types";
import { PageHeader } from "@/components/ui/PageHeader";
import { Panel } from "@/components/ui/Panel";
import { KeyValue } from "@/components/ui/KeyValue";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DateTime, TimeAgo } from "@/components/ui/DateTime";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";
import { ConfirmForm } from "@/components/ui/ConfirmForm";
import { DataTable, type Column } from "@/components/ui/DataTable";
import { IdLink } from "@/components/ui/IdLink";
import { MetricGrid, MetricTile } from "@/components/ui/MetricTile";
import { FilterField, FilterSelect } from "@/components/ui/FilterField";
import { ActionTable } from "@/components/actions/ActionTable";
import { AuditTable } from "@/components/system/AuditTable";
import { SummaryView } from "@/components/system/SummaryView";
import { ReportFreshness } from "@/components/shell/Freshness";

export const metadata: Metadata = { title: "System" };
export const dynamic = "force-dynamic";

const ACTION_STATES = Object.keys(ACTION_STATE_LABELS);
const ACTION_TYPES = Object.keys(ACTION_TYPE_LABELS);

const SETTING_HELP: Record<string, string> = {
  refund_execute_enabled: "Gate for the refund_execute action. Flip to true only after the ops-refund-execute edge function is deployed.",
  detectors_enabled: "Master switch for the 5-minute detector tick.",
  dispute_sla_hours: "Hours before an open in-app dispute is overdue.",
  transfer_deadline_soon_hours: "Window before the seller deadline that raises Transfer due soon.",
  paid_unsettled_grace_minutes: "Grace after a captured payment before Paid but not settled fires.",
  webhook_stuck_minutes: "Age of an unprocessed Stripe webhook that counts as stuck.",
  release_stuck_minutes: "Minutes after a recorded release without a Stripe Transfer before Release stuck fires.",
  approval_ttl_hours: "Hours before a pending second-founder approval expires.",
};

export default async function SystemPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  const me = await requireOperator();
  const isAdmin = me.role === "platform_admin";

  const actionFilters: Record<string, unknown> = {};
  const stateF = list(sp.state);
  const typeF = list(sp.action_type);
  if (stateF) actionFilters.state = stateF;
  if (typeF) actionFilters.action_type = typeF;

  const [healthRes, approvalsRes, settingsRes, auditRes, actionsRes, summaryRes] = await Promise.all([
    callOps<unknown>("job_health"),
    callOps<unknown>("list_approvals", { p_state: "pending" }),
    isAdmin ? callOps<unknown>("settings") : Promise.resolve(null),
    callOps<unknown>("audit_log", { p_cursor: first(sp.audit_cursor) ?? null, p_limit: 25 }),
    callOps<unknown>("list_actions", { p_filters: actionFilters, p_cursor: first(sp.actions_cursor) ?? null, p_limit: limitOf(sp, 25) }),
    callOps<unknown>("latest_summary"),
  ]);

  const health = healthRes.ok ? toJobHealth(healthRes.data) : null;
  const approvals: Approval[] = approvalsRes.ok ? toListPage(approvalsRes.data).items.map(toApproval).filter((a): a is Approval => a !== null) : [];
  const settings: Setting[] = settingsRes && settingsRes.ok ? toSettings(settingsRes.data) : [];
  const auditPage = auditRes.ok ? toListPage(auditRes.data) : null;
  const audit: AuditRow[] = auditPage ? auditPage.items.map(toAuditRow).filter((a): a is AuditRow => a !== null) : [];
  const actionsPage = actionsRes.ok ? toListPage(actionsRes.data) : null;
  const actions = actionsPage ? toActions(actionsPage.items) : [];
  const summary = summaryRes.ok ? toDailySummary(summaryRes.data) : null;

  const failingJobs = health?.ops_jobs.filter((j) => (j.consecutive_failures ?? 0) >= 2).length ?? 0;
  const lastSuccess = health?.ops_jobs.reduce<string | null>((acc, j) => (j.last_success_at && (!acc || j.last_success_at > acc) ? j.last_success_at : acc), null) ?? null;

  return (
    <>
      {health?.generated_at ? <ReportFreshness at={health.generated_at} /> : null}
      <PageHeader
        eyebrow="Health"
        title="System"
        description="Detectors, cron, webhook backlog, notification delivery, approvals, settings, the action log and the append-only audit trail. Stripe webhooks are re-sent from the Stripe Dashboard, never replayed from here."
        meta={
          health ? (
            <>
              Generated <DateTime value={health.generated_at} withSeconds /> · last detector success{" "}
              {lastSuccess ? <DateTime value={lastSuccess} /> : <span className="text-warning">never</span>}
            </>
          ) : undefined
        }
      />

      <nav aria-label="System sections" className="mb-6 flex flex-wrap gap-2 text-[12px]">
        {[
          ["#jobs", "Jobs"],
          ["#cron", "Cron"],
          ["#webhooks", "Webhooks"],
          ["#notify", "Notifications"],
          ["#alerts", "Alerts"],
          ["#approvals", `Approvals (${approvals.length})`],
          ["#settings", "Settings"],
          ["#actions", "Actions"],
          ["#audit", "Audit log"],
          ["#summary", "Daily summary"],
        ].map(([href, label]) => (
          <a key={href} href={href} className="btn btn-ghost btn-sm">
            {label}
          </a>
        ))}
      </nav>

      <div className="space-y-6">
        {!healthRes.ok ? (
          <OpsFailureAlert failure={healthRes} fn="job_health" retryHref="/system" />
        ) : !health ? (
          <Alert state="failed" title="Unrecognised payload from ops.job_health()" />
        ) : (
          <>
            <MetricGrid cols={6}>
              <MetricTile label="Ops jobs" value={health.ops_jobs.length} definition="Rows in ops.job_state (detectors + daily summary + metric snapshot)." href="#jobs" />
              <MetricTile label="Jobs failing" value={failingJobs} definition="Enabled ops jobs with 2 or more consecutive failures." href="#jobs" />
              <MetricTile label="Webhooks unprocessed" value={health.webhook_backlog.unprocessed ?? 0} definition="stripe_webhook_events with processed_at null and no failed_at." href="#webhooks" />
              <MetricTile label="Webhooks failed" value={health.webhook_backlog.failed ?? 0} definition="stripe_webhook_events with failed_at set and processed_at null." href="#webhooks" />
              <MetricTile label="Alerts firing" value={health.alerts.length} definition="ops.alert rows in state firing." href="#alerts" />
              <MetricTile label="Approvals pending" value={approvals.length} definition="Second-founder approvals awaiting a decision." href="#approvals" />
            </MetricGrid>

            <Panel eyebrow="ops.job_state" title="Console jobs (detectors)">
              <OpsJobTable jobs={health.ops_jobs} canRetry={canRequest(me.role, "job_retry")} />
            </Panel>

            <Panel eyebrow="pg_cron" title="Cron jobs">
              {!health.cron.available ? (
                <Alert state="info" title="Run history unavailable." compact>
                  {health.cron.note ?? "cron.job_run_details is not present on this database."}
                </Alert>
              ) : null}
              <div className={health.cron.available ? "" : "mt-3"}>
                <CronTable rows={health.cron.items} available={health.cron.available} />
              </div>
            </Panel>

            <div className="grid gap-6 lg:grid-cols-2">
              <Panel eyebrow="stripe_webhook_events" title="Webhook backlog">
                <div id="webhooks" />
                <KeyValue
                  columns={2}
                  items={[
                    { key: "unprocessed", value: String(health.webhook_backlog.unprocessed ?? 0) },
                    { key: "failed", value: String(health.webhook_backlog.failed ?? 0) },
                    { key: "oldest_unprocessed_at", value: <DateTime value={health.webhook_backlog.oldest_unprocessed_at} /> },
                    { key: "oldest_unprocessed_event_id", value: health.webhook_backlog.oldest_unprocessed_event_id ? <code className="font-mono text-[12px]">{health.webhook_backlog.oldest_unprocessed_event_id}</code> : null },
                  ]}
                />
                <p className="mt-3 text-[11px] text-dim">Stuck or failed events are re-sent from the Stripe Dashboard (Developers → Webhooks → event → Resend). The console does not replay webhooks.</p>
              </Panel>

              <Panel eyebrow="notify.*" title="Notification delivery">
                <div id="notify" />
                <h3 className="eyebrow text-dim">Delivery by state</h3>
                <CountList map={health.notify.delivery} />
                <h3 className="eyebrow mt-3 text-dim">Outbox by state</h3>
                <CountList map={health.notify.outbox} />
                {health.notify.note ? <p className="mt-3 text-[11px] text-dim">{health.notify.note}</p> : null}
              </Panel>
            </div>

            <Panel eyebrow={`${health.alerts.length} firing`} title="Alerts">
              <div id="alerts" />
              {health.alerts.length === 0 ? (
                <p className="text-dim">No alerts firing.</p>
              ) : (
                <ul className="space-y-2">
                  {health.alerts.map((a, i) => {
                    const caseId = typeof a.payload?.case_id === "string" ? a.payload.case_id : null;
                    const title = typeof a.payload?.title === "string" ? a.payload.title : null;
                    return (
                      <li key={a.alert_key ?? i} className="flex flex-wrap items-baseline gap-2 border-l-2 border-warning pl-3 text-[13px]">
                        <StatusBadge status={a.state} label={a.state ?? "firing"} />
                        <span className="font-mono text-[12px] text-dim">{a.kind}</span>
                        {caseId ? (
                          <Link href={`/cases/${caseId}`} className="link">
                            {title ?? a.alert_key}
                          </Link>
                        ) : (
                          <span>{title ?? a.alert_key}</span>
                        )}
                        <span className="text-[11px] text-dim">
                          first <TimeAgo value={a.first_fired_at} /> · last <TimeAgo value={a.last_fired_at} /> · ×{a.fire_count ?? 1}
                        </span>
                      </li>
                    );
                  })}
                </ul>
              )}
            </Panel>
          </>
        )}

        <Panel eyebrow={`${approvals.length} pending`} title="Approvals (second founder)">
          <div id="approvals" />
          {!approvalsRes.ok ? (
            <OpsFailureAlert failure={approvalsRes} fn="list_approvals" retryHref="/system" />
          ) : approvals.length === 0 ? (
            <p className="text-dim">Nothing awaiting approval.</p>
          ) : (
            <div className="space-y-5">
              {approvals.map((ap) => (
                <ApprovalCard key={ap.id} approval={ap} meId={me.id} isAdmin={isAdmin} />
              ))}
            </div>
          )}
          <p className="mt-3 text-[11px] text-dim">Approval is bound to the exact action terms; if anything about the request changes it is voided. You cannot approve your own request. Approvals expire after the configured TTL.</p>
        </Panel>

        <Panel eyebrow="ops.setting" title="Settings">
          <div id="settings" />
          {!isAdmin ? (
            <Alert state="info" title="Settings are visible to platform_admin only." compact />
          ) : settingsRes && !settingsRes.ok ? (
            <OpsFailureAlert failure={settingsRes} fn="settings" retryHref="/system" />
          ) : (
            <SettingsList settings={settings} />
          )}
        </Panel>

        <Panel eyebrow={`${actions.length} shown`} title="Actions">
          <div id="actions" />
          <form method="get" action="/system#actions" className="mb-3 flex flex-wrap items-end gap-2">
            <FilterField label="State">
              <FilterSelect name="state" options={ACTION_STATES} value={first(sp.state)} labels={ACTION_STATE_LABELS} />
            </FilterField>
            <FilterField label="Type">
              <FilterSelect name="action_type" options={ACTION_TYPES} value={first(sp.action_type)} labels={ACTION_TYPE_LABELS} />
            </FilterField>
            <button type="submit" className="btn btn-ghost btn-sm">
              Filter
            </button>
          </form>
          {!actionsRes.ok ? (
            <OpsFailureAlert failure={actionsRes} fn="list_actions" retryHref="/system" />
          ) : (
            <ActionTable rows={actions} basePath="/system" searchParams={sp} nextCursor={actionsPage?.next_cursor} cursorParam="actions_cursor" meId={me.id} />
          )}
        </Panel>

        <Panel eyebrow="Append-only" title="Audit log">
          <div id="audit" />
          {!auditRes.ok ? <OpsFailureAlert failure={auditRes} fn="audit_log" retryHref="/system" /> : <AuditTable rows={audit} basePath="/system" searchParams={sp} nextCursor={auditPage?.next_cursor} cursorParam="audit_cursor" meId={me.id} />}
        </Panel>

        <Panel eyebrow="13:00 UTC daily" title="Latest daily summary">
          <div id="summary" />
          {!summaryRes.ok ? (
            <OpsFailureAlert failure={summaryRes} fn="latest_summary" retryHref="/system" />
          ) : !summary ? (
            <Alert state="empty" title="No daily summary has been generated yet." compact>
              The daily_summary job writes one row per day at 13:00 UTC; run it now from the jobs table to generate one. Portal only — no delivery channel is configured.
            </Alert>
          ) : (
            <SummaryView summary={summary} />
          )}
        </Panel>
      </div>
    </>
  );
}

function CountList({ map }: { map: Record<string, number> }) {
  const entries = Object.entries(map);
  if (entries.length === 0) return <p className="text-[12px] text-dim">no rows</p>;
  return (
    <ul className="mt-1 flex flex-wrap gap-2 text-[12px]">
      {entries.map(([k, v]) => (
        <li key={k} className="border border-line-neutral px-2 py-0.5">
          <StatusBadge status={k} /> <span className="ml-1 tabular-nums">{v}</span>
        </li>
      ))}
    </ul>
  );
}

function OpsJobTable({ jobs, canRetry }: { jobs: OpsJob[]; canRetry: boolean }) {
  const columns: Column<OpsJob>[] = [
    {
      key: "job_name",
      header: "Job",
      render: (j) => (
        <span id={`job-${j.job_name}`} className="flex flex-col">
          <code className="font-mono text-[12px] text-ink">{j.job_name}</code>
          <StatusBadge status={j.enabled ? "active" : "inactive"} label={j.enabled ? "enabled" : "disabled"} />
        </span>
      ),
    },
    { key: "last_success_at", header: "Last success", render: (j) => <DateTime value={j.last_success_at} /> },
    { key: "last_run_at", header: "Last run", render: (j) => <DateTime value={j.last_run_at} /> },
    {
      key: "consecutive_failures",
      header: "Consecutive failures",
      align: "right",
      render: (j) => <span className={`tabular-nums ${(j.consecutive_failures ?? 0) >= 2 ? "font-semibold text-danger" : ""}`}>{j.consecutive_failures ?? 0}</span>,
    },
    { key: "backoff_until", header: "Backoff until", render: (j) => <DateTime value={j.backoff_until} /> },
    { key: "last_error", header: "Last error", render: (j) => <span className="line-clamp-2 max-w-[260px] text-[12px] text-danger">{j.last_error ?? <span className="text-dim">—</span>}</span> },
    {
      key: "recent_runs",
      header: "Last 5 runs",
      render: (j) =>
        j.recent_runs.length === 0 ? (
          <span className="text-dim">no runs</span>
        ) : (
          <ol className="space-y-0.5 text-[11px]">
            {j.recent_runs.map((r, i) => (
              <li key={r.id ?? i} className="flex flex-wrap items-baseline gap-1">
                <StatusBadge status={r.status} />
                <TimeAgo value={r.started_at} />
                <span className="text-dim">{r.trigger}</span>
                {r.status === "succeeded" ? <span className="text-dim">scanned {r.items_scanned ?? 0} · +{r.cases_opened ?? 0} / −{r.cases_resolved ?? 0}</span> : null}
                {r.error ? <span className="text-danger">{r.error}</span> : null}
              </li>
            ))}
          </ol>
        ),
    },
    {
      key: "run",
      header: "Run now",
      render: (j) =>
        canRetry ? (
          <ConfirmForm idempotencyKey={newIdempotencyKey()} actionType="job_retry" subjectKind="job" subjectRef={j.job_name} params={{ job_name: j.job_name }} label="Run now" className="min-w-[200px]" />
        ) : (
          <span className="text-[11px] text-dim">founder only</span>
        ),
    },
  ];
  return <DataTable id="jobs" columns={columns} rows={jobs} rowKey={(j) => j.job_name} basePath="/system" emptyText="No ops jobs registered (migration 117 not applied?)." caption="Console jobs" dense />;
}

function CronTable({ rows, available }: { rows: CronJob[]; available: boolean }) {
  const columns: Column<CronJob>[] = [
    { key: "jobname", header: "Cron job", render: (c) => <code className="font-mono text-[12px]">{c.jobname ?? c.jobid}</code> },
    { key: "schedule", header: "Schedule", render: (c) => <code className="font-mono text-[12px]">{c.schedule ?? "—"}</code> },
    { key: "active", header: "Active", render: (c) => <StatusBadge status={String(c.active ?? false)} label={c.active ? "active" : "inactive"} /> },
    { key: "last_status", header: "Last status", render: (c) => (available ? <StatusBadge status={c.last_status} /> : <span className="text-dim">unavailable</span>) },
    { key: "last_end", header: "Last end", render: (c) => (available ? <DateTime value={c.last_end} /> : <span className="text-dim">—</span>) },
    { key: "runs_24h", header: "Runs / failures (24 h)", align: "right", render: (c) => (available ? <span className="tabular-nums">{c.runs_24h ?? 0} / {c.failures_24h ?? 0}</span> : <span className="text-dim">—</span>) },
    { key: "last_message", header: "Last message", render: (c) => <span className="line-clamp-2 max-w-[280px] text-[12px] text-muted">{c.last_message ?? "—"}</span> },
  ];
  return <DataTable id="cron" columns={columns} rows={rows} rowKey={(c, i) => c.jobname ?? `${c.jobid ?? i}`} basePath="/system" emptyText="No cron jobs." caption="Cron jobs" dense />;
}

function ApprovalCard({ approval: ap, meId, isAdmin }: { approval: Approval; meId: string; isAdmin: boolean }) {
  const a = ap.action;
  const mine = ap.requested_by === meId;
  const actionId = ap.action_id ?? a?.id;
  return (
    <div className="border border-line-neutral p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className="text-[14px] font-semibold text-ink">
          {labelFor("action_type", a?.action_type)}{" "}
          <span className="text-dim">
            on {a?.subject_kind} <IdLink kind={a?.subject_kind} id={a?.subject_id} subjectRef={a?.subject_ref} label={a?.subject_label ?? undefined} />
          </span>
        </p>
        <span className="text-[12px] text-dim">
          requested by {mine ? "me" : ap.requested_by_label ?? shortId(ap.requested_by)} <TimeAgo value={ap.created_at} /> · expires <TimeAgo value={ap.expires_at} />
        </span>
      </div>
      <KeyValue
        columns={3}
        items={[
          { key: "reason", label: "Requester's reason", value: a?.reason },
          { key: "params", label: "Terms (params)", value: <code className="whitespace-pre-wrap break-words font-mono text-[11px]">{JSON.stringify(a?.params ?? {})}</code> },
          { key: "expected", label: "Expected state", value: <code className="whitespace-pre-wrap break-words font-mono text-[11px]">{JSON.stringify(a?.expected ?? {})}</code> },
          { key: "action", value: actionId ? <IdLink kind="action" id={actionId} full /> : null },
          { key: "terms", label: "Terms unchanged", value: ap.hash_current === false ? <StatusBadge status="stale" label="changed — will be voided" /> : <StatusBadge status="ok" label="yes" /> },
        ]}
      />
      <div className="mt-3">
        {mine ? (
          <Alert state="info" title="You requested this — a different founder must decide." compact />
        ) : !isAdmin ? (
          <Alert state="info" title="Only a platform_admin can decide approvals." compact />
        ) : !ap.can_decide ? (
          <Alert state="info" title="This approval cannot be decided by you (expired or already decided)." compact />
        ) : actionId ? (
          <div className="grid gap-4 md:grid-cols-2">
            <ConfirmForm idempotencyKey={newIdempotencyKey()} actionType="approval_decide" subjectKind="action" subjectId={actionId} params={{ action_id: actionId, decision: "approve" }} revalidate="/system" label="Approve and execute" danger reasonLabel="Approval reason" />
            <ConfirmForm idempotencyKey={newIdempotencyKey()} actionType="approval_decide" subjectKind="action" subjectId={actionId} params={{ action_id: actionId, decision: "reject" }} revalidate="/system" label="Deny" reasonLabel="Denial reason" />
          </div>
        ) : null}
      </div>
    </div>
  );
}

function SettingsList({ settings }: { settings: Setting[] }) {
  if (settings.length === 0) return <p className="text-dim">No settings rows.</p>;
  return (
    <ul className="divide-y divide-line-neutral">
      {settings.map((s) => {
        const kind = settingKind(s.value);
        const field = settingFieldName(s.value);
        const inputId = `setting-${s.key}`;
        return (
          <li key={s.key} id={`setting-${s.key}`} className="grid gap-3 py-4 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
            <div>
              <p className="text-[13px] font-semibold text-ink">
                <code className="font-mono">{s.key}</code>
              </p>
              <p className="mt-1 text-[12px] text-muted">{SETTING_HELP[s.key] ?? humanize(s.key)}</p>
              <p className="mt-2 text-[12px]">
                Current: <code className="font-mono text-ink">{JSON.stringify(s.value)}</code> <span className="text-dim">({kind})</span>
              </p>
              <p className="mt-1 text-[11px] text-dim">
                Last changed <DateTime value={s.updated_at} /> {s.updated_by_label ? `by ${s.updated_by_label}` : s.updated_by ? `by ${shortId(s.updated_by)}` : "(seed)"}
              </p>
            </div>
            <ConfirmForm idempotencyKey={newIdempotencyKey()} actionType="setting_set" subjectKind="setting" subjectRef={s.key} label="Save setting" danger={s.key === "refund_execute_enabled"}>
              <label htmlFor={inputId} className="eyebrow block text-dim">
                New value ({kind})
              </label>
              {kind === "boolean" ? (
                <select id={inputId} name={field} defaultValue={String(s.value)} className="field mt-1">
                  <option value="true">true</option>
                  <option value="false">false</option>
                </select>
              ) : kind === "number" ? (
                <input id={inputId} name={field} type="number" step="any" defaultValue={String(s.value)} required className="field mt-1" />
              ) : kind === "string" ? (
                <input id={inputId} name={field} type="text" defaultValue={String(s.value)} required className="field mt-1" />
              ) : (
                <textarea id={inputId} name={field} rows={2} defaultValue={JSON.stringify(s.value)} required className="field mt-1 font-mono text-[12px]" />
              )}
            </ConfirmForm>
          </li>
        );
      })}
    </ul>
  );
}
