import type { Metadata } from "next";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { newIdempotencyKey } from "@/lib/idempotency";
import { canRequest } from "@/lib/permissions";
import { settingFieldName, settingKind } from "@/lib/form-params";
import { humanize, labelFor, shortId, ACTION_STATE_LABELS, ACTION_TYPE_LABELS } from "@/lib/format";
import { first, limitOf, list, selfHref, type SearchParams } from "@/lib/search-params";
import {
  toActions,
  toApproval,
  toAuditRow,
  toDailySummary,
  toJobHealth,
  toListPage,
  toSettings,
  type Approval,
  type ApprovalDecision,
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
import { FigureMeta } from "@/components/charts/FigureMeta";
import { FilterField, FilterSelect } from "@/components/ui/FilterField";
import { ActionTable } from "@/components/actions/ActionTable";
import { AuditTable } from "@/components/system/AuditTable";
import { SummaryView } from "@/components/system/SummaryView";
import { AlertList } from "@/components/system/AlertList";
import { AlertDeliveryChannel, type SettingsRead } from "@/components/system/AlertChannel";
import { MoneySettingsPanel } from "@/components/system/MoneySettingsPanel";
import { OperationalSettingsForm } from "@/components/system/OperationalSettingsForm";
import { VenueApprovalForm } from "@/components/system/VenueApprovalForm";
import { toMoneyConfigList } from "@/lib/money-config";
import { toOperationalSettings } from "@/lib/operational-config";
import { ReportFreshness } from "@/components/shell/Freshness";

export const metadata: Metadata = { title: "Platform health" };
export const dynamic = "force-dynamic";

const ACTION_STATES = Object.keys(ACTION_STATE_LABELS);
const ACTION_TYPES = Object.keys(ACTION_TYPE_LABELS);

const SETTING_LABEL: Record<string, string> = {
  actions_enabled: "Allow console actions",
  refund_execute_enabled: "Allow refund execution",
  detectors_enabled: "Run scheduled checks and reports",
  dispute_sla_hours: "Dispute response time (hours)",
  transfer_deadline_soon_hours: "Seller deadline warning (hours)",
  paid_unsettled_grace_minutes: "Paid order transfer grace period (minutes)",
  webhook_stuck_minutes: "Payment update delay warning (minutes)",
  release_stuck_minutes: "Seller release delay warning (minutes)",
  approval_ttl_hours: "Approval expiry (hours)",
  alert_delivery_enabled: "Send alerts",
  refund_resolution_detector_enabled: "Check unresolved refunds",
};

const SETTING_HELP: Record<string, string> = {
  actions_enabled: "Pause or resume console actions. False pauses actions, approval decisions and refund resumes. You can still read records and change this switch. Not paused: Money settings, Operational settings, alert acknowledgements and opening evidence. Set true to resume.",
  refund_execute_enabled: "Allow or block Execute refund. Keep false until the refund service (ops-refund-execute) is deployed and ready. Set true only after that check.",
  detectors_enabled: "Turn scheduled console checks and reports on or off: issue checks and metric snapshots every 5 minutes, plus the daily summary. This does not pause other console actions.",
  dispute_sla_hours: "Hours before an open in-app dispute is overdue.",
  transfer_deadline_soon_hours: "Window before the seller deadline that raises Transfer due soon.",
  paid_unsettled_grace_minutes: "Minutes after a payment is captured before it is flagged for having no recorded transfer.",
  webhook_stuck_minutes: "Minutes before an unprocessed Stripe payment update is flagged as delayed.",
  release_stuck_minutes: "Minutes after a recorded release before it is flagged for having no Stripe Transfer.",
  approval_ttl_hours: "Hours before a pending second-founder approval expires.",
  // Owner decisions (A, PR #89 port): the help says so, and never tells an operator to flip them.
  alert_delivery_enabled:
    "Owner decision; not changed without the owner. While false, no alert is sent. True only allows sending: a sender must also be scheduled, and that is a separate owner decision.",
  refund_resolution_detector_enabled:
    "Owner decision; not changed without the owner. While false, the check for unresolved refunds never runs, even with Run now, so it opens no refund-resolution cases.",
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

  const [healthRes, approvalsRes, settingsRes, moneyRes, operationalRes, auditRes, actionsRes, summaryRes] = await Promise.all([
    callOps<unknown>("job_health"),
    callOps<unknown>("list_approvals", { p_state: "pending" }),
    isAdmin ? callOps<unknown>("settings") : Promise.resolve(null),
    isAdmin ? callOps<unknown>("list_config_approvals", { p_state: "all" }) : Promise.resolve(null),
    isAdmin ? callOps<unknown>("list_operational_config") : Promise.resolve(null),
    callOps<unknown>("audit_log", { p_cursor: first(sp.audit_cursor) ?? null, p_limit: 25 }),
    callOps<unknown>("list_actions", { p_filters: actionFilters, p_cursor: first(sp.actions_cursor) ?? null, p_limit: limitOf(sp, 25) }),
    callOps<unknown>("latest_summary"),
  ]);

  const health = healthRes.ok ? toJobHealth(healthRes.data) : null;
  const approvals: Approval[] = approvalsRes.ok ? toListPage(approvalsRes.data).items.map(toApproval).filter((a): a is Approval => a !== null) : [];
  const settings: Setting[] = settingsRes && settingsRes.ok ? toSettings(settingsRes.data) : [];
  // The Delivery channel block reads the same settings result; it makes no call of its own.
  const settingsRead: SettingsRead = !isAdmin ? { status: "not_admin" } : settingsRes && settingsRes.ok ? { status: "ok", settings } : { status: "failed" };
  const money = moneyRes && moneyRes.ok ? toMoneyConfigList(moneyRes.data) : null;
  const moneyPending = money ? money.items.filter((r) => r.state === "pending").length : 0;
  const operational = operationalRes && operationalRes.ok ? toOperationalSettings(operationalRes.data) : null;
  const auditPage = auditRes.ok ? toListPage(auditRes.data) : null;
  const audit: AuditRow[] = auditPage ? auditPage.items.map(toAuditRow).filter((a): a is AuditRow => a !== null) : [];
  const actionsPage = actionsRes.ok ? toListPage(actionsRes.data) : null;
  const actions = actionsPage ? toActions(actionsPage.items) : [];
  const summary = summaryRes.ok ? toDailySummary(summaryRes.data) : null;

  // Time of this read (server render, per request): the metric row is point in time, so its label says when.
  const readAt = new Date();
  const failingJobs = health?.ops_jobs.filter((j) => (j.consecutive_failures ?? 0) >= 2).length ?? 0;
  const lastSuccess = health?.ops_jobs.reduce<string | null>((acc, j) => (j.last_success_at && (!acc || j.last_success_at > acc) ? j.last_success_at : acc), null) ?? null;

  return (
    <>
      {health?.generated_at ? <ReportFreshness at={health.generated_at} /> : null}
      <PageHeader
        eyebrow="Health"
        title="Platform health"
        description="Check what needs attention, review approvals and manage platform controls."
        meta={
          health ? (
            <>
              Generated <DateTime value={health.generated_at} withSeconds /> · last successful check{" "}
              {lastSuccess ? <DateTime value={lastSuccess} /> : <span className="text-warning">never</span>}
            </>
          ) : undefined
        }
      />

      <nav aria-label="Platform health sections" className="mb-6 flex flex-wrap gap-2 text-[0.75rem]">
        {[
          ["#jobs", "Automated checks"],
          ["#cron", "Scheduled tasks"],
          ["#webhooks", "Payment updates"],
          ["#notify", "Notifications"],
          ["#alerts", "Alerts"],
          // v2 keeps its own form of this label: a FAILED approvals read shows "—" rather than 0,
          // which production's `approvals.length` could not distinguish. The money link is production's.
          ["#approvals", `Approvals (${approvalsRes.ok ? approvals.length : "—"})`],
          ["#money", money ? `Money settings (${moneyPending})` : "Money settings"],
          ["#operational", "Sales rules"],
          ["#settings", "Platform controls"],
          ["#actions", "Action history"],
          ["#audit", "Change history"],
          ["#summary", "Daily summary"],
          ["/system/test-data", "Test records (restricted)"],
          ["/system/prelaunch-archive", "Pre-launch test archive"],
        ].map(([href, label]) => (
          <a key={href} href={href} className="btn btn-ghost btn-sm">
            {label}
          </a>
        ))}
      </nav>

      <div className="space-y-6">
        {!healthRes.ok ? (
          <OpsFailureAlert failure={healthRes} fn="job_health" retryHref={selfHref("/system", sp)} />
        ) : !health ? (
          <Alert state="failed" title="Unexpected answer from ops.job_health()" />
        ) : (
          <>
            <MetricGrid cols={6}>
              <MetricTile label="Automated checks" value={health.ops_jobs.length} definition="Issue checks, daily summaries and metric snapshots run by the console." href="#jobs" />
              <MetricTile label="Checks failing" value={failingJobs} definition="Console jobs with 2 or more consecutive failures, disabled jobs included." href="#jobs" />
              <MetricTile label="Payment updates waiting" value={health.webhook_backlog.unprocessed ?? "—"} definition="Stripe payment updates not yet processed and not marked failed." href="#webhooks" />
              <MetricTile label="Payment updates failed" value={health.webhook_backlog.failed ?? "—"} definition="Stripe payment updates marked failed and not processed." href="#webhooks" />
              <MetricTile label="Active alerts" value={health.alerts.length} definition="Alerts that are firing now." href="#alerts" />
              <MetricTile label="Approvals pending" value={approvalsRes.ok ? approvals.length : "—"} note={approvalsRes.ok ? null : "Couldn't be loaded"} definition="Second-founder approvals awaiting a decision." href="#approvals" />
            </MetricGrid>
            <FigureMeta pointInTime computedAt={health.generated_at} readAt={readAt} className="px-1" />

            <Panel eyebrow="Run by the console" title="Automated checks" description="Review failed checks and their last successful run. Founders can run a check again after reviewing the problem.">
              <OpsJobTable jobs={health.ops_jobs} canRetry={canRequest(me.role, "job_retry")} />
            </Panel>

            <Panel eyebrow="Scheduled in the database" title="Scheduled tasks" description="See which tasks are active, when they last ran and whether they failed.">
              {!health.cron.available ? (
                <Alert state="info" title="Run history unavailable." compact>
                  {health.cron.note ?? "This database does not keep cron run history."}
                </Alert>
              ) : null}
              <div className={health.cron.available ? "" : "mt-3"}>
                <CronTable rows={health.cron.items} available={health.cron.available} />
              </div>
            </Panel>

            <div className="grid gap-6 lg:grid-cols-2">
              <Panel eyebrow="From Stripe" title="Payment updates" description="Updates from Stripe that are waiting or failed. Review delayed updates before changing a payment record.">
                <div id="webhooks" />
                <KeyValue
                  columns={2}
                  items={[
                    { key: "unprocessed", label: "Waiting to be processed", value: health.webhook_backlog.unprocessed ?? null },
                    { key: "failed", label: "Failed updates", value: health.webhook_backlog.failed ?? null },
                    { key: "oldest_unprocessed_at", label: "Oldest waiting update", value: <DateTime value={health.webhook_backlog.oldest_unprocessed_at} /> },
                  ]}
                />
                <p className="mt-3 text-[0.75rem] text-muted">Re-send stuck or failed payment updates from Stripe Dashboard → Developers → Webhooks → event → Resend. This console cannot re-send them.</p>
                <details className="mt-3 text-xs text-muted">
                  <summary className="cursor-pointer py-1">Technical details · payment update reference</summary>
                  <p className="mt-2 break-all">Oldest waiting event: <code>{health.webhook_backlog.oldest_unprocessed_event_id ?? "Not available"}</code></p>
                </details>
              </Panel>

              <Panel eyebrow="From the database" title="Notification delivery">
                <div id="notify" />
                <h3 className="eyebrow text-dim">Delivery by state</h3>
                <CountList map={health.notify.delivery} />
                <h3 className="eyebrow mt-3 text-dim">Outbox by state</h3>
                <CountList map={health.notify.outbox} />
                {health.notify.note ? <p className="mt-3 text-[0.6875rem] text-dim">{health.notify.note}</p> : null}
              </Panel>
            </div>

            <Panel eyebrow={`${health.alerts.length} firing`} title="Alerts">
              <div id="alerts" />
              <AlertDeliveryChannel settings={settingsRead} />
              <AlertList alerts={health.alerts} meId={me.id} />
            </Panel>
          </>
        )}

        <Panel eyebrow={approvalsRes.ok ? `${approvals.length} pending` : "—"} title="Approvals (second founder)">
          <div id="approvals" />
          {!approvalsRes.ok ? (
            <OpsFailureAlert failure={approvalsRes} fn="list_approvals" retryHref={selfHref("/system", sp)} />
          ) : approvals.length === 0 ? (
            <p className="text-dim">Nothing awaiting approval.</p>
          ) : (
            <div className="space-y-5">
              {approvals.map((ap) => (
                <ApprovalCard key={ap.id} approval={ap} meId={me.id} isAdmin={isAdmin} />
              ))}
            </div>
          )}
          <p className="mt-3 text-[0.6875rem] text-dim">An approval covers the exact terms of the action. If the request changes, the approval is void. You cannot approve your own request. Approvals expire after approval_ttl_hours (see Settings).</p>
        </Panel>

        {/* 196's Money settings panel, carried from production (dddc8e92) with 196's ops reads,
            guards and copy unchanged. 197 adds one read-only live-values overview below the decided
            list; its position remains in the v2 /system layout above the console switches. */}
        <Panel eyebrow={money ? `${moneyPending} pending` : "Two-founder rule"} title="Money settings (second founder)">
          <div id="money" />
          {!isAdmin ? (
            <Alert state="info" title="Only founders can see Money settings." compact />
          ) : moneyRes && !moneyRes.ok ? (
            <OpsFailureAlert failure={moneyRes} fn="list_config_approvals" retryHref="/system#money" />
          ) : money ? (
            <MoneySettingsPanel list={money} meId={me.id} />
          ) : null}
          <p className="mt-3 text-[11px] text-dim">Money keys (refund, payout, fee, authn, …) follow the two-founder rule: a loosening needs a second founder, and a tightening applies at once. You cannot approve your own request. Approving needs a recent check with your authenticator. Requests expire after 72 hours.</p>
        </Panel>

        <Panel eyebrow="Single-founder rule" title="Sales rules" description="Operational settings for buyer holds, ticket issuance and scanning.">
          <div id="operational" />
          {!isAdmin ? (
            <Alert state="info" title="Only founders can see Operational settings." compact />
          ) : operationalRes && !operationalRes.ok ? (
            operationalRes.kind === "error" && operationalRes.unavailable ? (
              <Alert state="info" title="Needs registry 197 — operational settings are not available on this server." compact>
                The server could not provide <code>ops.list_operational_config</code>. No value was read or changed, and no write control is shown.
              </Alert>
            ) : (
              <OpsFailureAlert failure={operationalRes} fn="list_operational_config" retryHref="/system#operational" />
            )
          ) : operationalRes && operationalRes.ok && operational === null ? (
            <Alert state="failed" title="Unexpected answer from ops.list_operational_config" compact>
              The read did not return the four operational settings. No write control is shown. Reload the page before you change anything.
            </Alert>
          ) : operational ? (
            <OperationalSettingsForm settings={operational} commandKey={newIdempotencyKey()} />
          ) : null}
          <p className="mt-3 text-[11px] text-dim">Hold max, hold lifetime and the native issuance and scanning flags are single-founder settings: one founder changes them, and the change applies at once. Money keys stay in Money settings, under the two-founder rule.</p>
        </Panel>

        {isAdmin ? (
          <Panel eyebrow="Venue access" title="Approve a venue">
            <div id="venue-approval" />
            <VenueApprovalForm commandKey={newIdempotencyKey()} />
          </Panel>
        ) : null}

        <Panel eyebrow="Console switches" title="Platform controls" description="Review each switch’s scope before saving. Every change still needs a reason and confirmation.">
          <div id="settings" />
          {!isAdmin ? (
            <Alert state="info" title="Only founders can see Settings." compact />
          ) : settingsRes && !settingsRes.ok ? (
            <OpsFailureAlert failure={settingsRes} fn="settings" retryHref={selfHref("/system", sp)} />
          ) : (
            <SettingsList settings={settings} />
          )}
        </Panel>

        <Panel eyebrow={`${actions.length} shown`} title="Action history">
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
            <OpsFailureAlert failure={actionsRes} fn="list_actions" retryHref={selfHref("/system", sp)} />
          ) : (
            <ActionTable rows={actions} basePath="/system" searchParams={sp} nextCursor={actionsPage?.next_cursor} cursorParam="actions_cursor" meId={me.id} />
          )}
        </Panel>

        <Panel eyebrow="Permanent record" title="Change history" description="A record of who changed what. Existing entries cannot be edited.">
          <div id="audit" />
          {!auditRes.ok ? <OpsFailureAlert failure={auditRes} fn="audit_log" retryHref={selfHref("/system", sp)} /> : <AuditTable rows={audit} basePath="/system" searchParams={sp} nextCursor={auditPage?.next_cursor} cursorParam="audit_cursor" meId={me.id} />}
        </Panel>

        <Panel eyebrow="Daily at 13:00 UTC (8:00 AM EST, 9:00 AM EDT)" title="Latest daily summary">
          <div id="summary" />
          {!summaryRes.ok ? (
            <OpsFailureAlert failure={summaryRes} fn="latest_summary" retryHref={selfHref("/system", sp)} />
          ) : !summary ? (
            <Alert state="empty" title="No daily summary has been generated yet." compact>
              The daily_summary job makes one summary a day at 13:00 UTC (8:00 AM EST, 9:00 AM EDT). A founder can make one now with Run now on that job in the jobs table. The summary shows only here; no delivery channel is configured.
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
  if (entries.length === 0) return <p className="text-[0.75rem] text-dim">no rows</p>;
  return (
    <ul className="mt-1 flex flex-wrap gap-2 text-[0.75rem]">
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
      header: "Check",
      render: (j) => (
        <div id={`job-${j.job_name}`} className="flex flex-col">
          <span className="font-medium text-ink">{humanize(j.job_name)}</span>
          <details className="mt-1 text-xs text-muted"><summary className="cursor-pointer py-1">Technical details</summary><code className="break-all">{j.job_name}</code></details>
          <StatusBadge status={j.enabled ? "active" : "inactive"} label={j.enabled ? "enabled" : "disabled"} />
        </div>
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
    { key: "backoff_until", header: "Retry after", render: (j) => <DateTime value={j.backoff_until} /> },
    { key: "last_error", header: "Last error", render: (j) => <span className="line-clamp-2 max-w-[260px] text-[0.75rem] text-danger">{j.last_error ?? <span className="text-dim">—</span>}</span> },
    {
      key: "recent_runs",
      header: "Last 5 runs",
      render: (j) =>
        j.recent_runs.length === 0 ? (
          <span className="text-dim">no runs</span>
        ) : (
          <ol className="space-y-0.5 text-[0.6875rem]">
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
          <ConfirmForm idempotencyKey={newIdempotencyKey()} actionType="job_retry" subjectKind="job" subjectRef={j.job_name} params={{ job_name: j.job_name }} revalidate="/system" label="Run now" className="min-w-[200px]" />
        ) : (
          <span className="text-[0.6875rem] text-dim">founder only</span>
        ),
    },
  ];
  return <DataTable id="jobs" columns={columns} rows={jobs} rowKey={(j) => j.job_name} basePath="/system" emptyText="No automated checks are registered. Ask platform support to check the setup." caption="Automated checks" dense />;
}

function CronTable({ rows, available }: { rows: CronJob[]; available: boolean }) {
  const columns: Column<CronJob>[] = [
    { key: "jobname", header: "Task", render: (c) => <span>{c.jobname ? humanize(c.jobname) : "Scheduled task"}</span> },
    { key: "schedule", header: "Schedule details", render: (c) => <details className="text-xs text-muted"><summary className="cursor-pointer py-1">Technical details</summary><dl className="mt-2 space-y-1"><div><dt>Task reference</dt><dd className="break-all"><code>{c.jobname ?? c.jobid ?? "—"}</code></dd></div><div><dt>Schedule (cron, UTC)</dt><dd><code>{c.schedule ?? "—"}</code></dd></div>{c.jobid != null ? <div><dt>Task ID</dt><dd>{c.jobid}</dd></div> : null}</dl></details> },
    { key: "active", header: "Active", render: (c) => <StatusBadge status={String(c.active ?? false)} label={c.active ? "active" : "inactive"} /> },
    { key: "last_status", header: "Last status", render: (c) => (available ? <StatusBadge status={c.last_status} /> : <span className="text-dim">unavailable</span>) },
    { key: "last_end", header: "Last end", render: (c) => (available ? <DateTime value={c.last_end} /> : <span className="text-dim">—</span>) },
    { key: "runs_24h", header: "Runs / failures (24 h)", align: "right", render: (c) => (available ? <span className="tabular-nums">{c.runs_24h ?? 0} / {c.failures_24h ?? 0}</span> : <span className="text-dim">—</span>) },
    { key: "last_message", header: "Last message", render: (c) => <span className="line-clamp-2 max-w-[280px] text-[0.75rem] text-muted">{c.last_message ?? "—"}</span> },
  ];
  return <DataTable id="cron" columns={columns} rows={rows} rowKey={(c, i) => c.jobname ?? `${c.jobid ?? i}`} basePath="/system" emptyText="No scheduled tasks." caption="Scheduled tasks" dense />;
}

function ApprovalCard({ approval: ap, meId, isAdmin }: { approval: Approval; meId: string; isAdmin: boolean }) {
  const a = ap.action;
  const mine = ap.requested_by === meId;
  const actionId = ap.action_id ?? a?.id;
  return (
    <div className="border border-line-neutral p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className="text-[0.875rem] font-semibold text-ink">
          {labelFor("action_type", a?.action_type)}{" "}
          <span className="text-dim">
            on {a?.subject_kind} <IdLink kind={a?.subject_kind} id={a?.subject_id} subjectRef={a?.subject_ref} label={a?.subject_label ?? undefined} />
          </span>
        </p>
        <span className="text-[0.75rem] text-dim">
          requested by {mine ? "me" : ap.requested_by_label ?? shortId(ap.requested_by)} <TimeAgo value={ap.created_at} /> · expires <TimeAgo value={ap.expires_at} />
        </span>
      </div>
      <KeyValue
        columns={3}
        items={[
          { key: "reason", label: "Requester's reason", value: a?.reason },
          { key: "params", label: "Terms (params)", value: <code className="whitespace-pre-wrap break-words font-mono text-[0.6875rem]">{JSON.stringify(a?.params ?? {})}</code> },
          { key: "expected", label: "Expected state", value: <code className="whitespace-pre-wrap break-words font-mono text-[0.6875rem]">{JSON.stringify(a?.expected ?? {})}</code> },
          { key: "action", value: actionId ? <IdLink kind="action" id={actionId} full /> : null },
          { key: "terms", label: "Terms unchanged", value: ap.hash_current === false ? <StatusBadge status="stale" label="changed — will be voided" /> : <StatusBadge status="ok" label="yes" /> },
        ]}
      />
      <div className="mt-3">
        {mine ? (
          <Alert state="info" title="You requested this — a different founder must decide." compact />
        ) : !isAdmin ? (
          <Alert state="info" title="Only a founder can decide approvals." compact />
        ) : !ap.can_decide ? (
          <Alert state="info" title="This approval cannot be decided by you (expired or already decided)." compact />
        ) : actionId ? (
          <div className="grid gap-4 md:grid-cols-2">
            <ConfirmForm idempotencyKey={newIdempotencyKey()} actionType="approval_decide" subjectKind="action" subjectId={actionId} params={{ action_id: actionId, decision: "approve" satisfies ApprovalDecision }} revalidate="/system" label="Approve and execute" danger reasonLabel="Approval reason" />
            <ConfirmForm idempotencyKey={newIdempotencyKey()} actionType="approval_decide" subjectKind="action" subjectId={actionId} params={{ action_id: actionId, decision: "deny" satisfies ApprovalDecision }} revalidate="/system" label="Deny" reasonLabel="Denial reason" />
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
        // The <li> carries the #setting-<key> anchor; the control needs its own id, or its <label> resolves to the <li>.
        const inputId = `setting-${s.key}-value`;
        return (
          <li key={s.key} id={`setting-${s.key}`} className="grid gap-3 py-4 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
            <div>
              <p className="text-[0.8125rem] font-semibold text-ink">
                {SETTING_LABEL[s.key] ?? humanize(s.key)}
              </p>
              <p className="mt-1 text-[0.75rem] text-muted">{SETTING_HELP[s.key] ?? humanize(s.key)}</p>
              <p className="mt-2 text-[0.75rem]">
                Current value: <code className="font-mono text-ink">{JSON.stringify(s.value)}</code>
              </p>
              <details className="mt-2 text-xs text-muted">
                <summary className="cursor-pointer py-1">Technical details · setting reference</summary>
                <p className="mt-2 break-all"><code>{s.key}</code> · Value type: {kind}</p>
              </details>
              <p className="mt-1 text-[0.6875rem] text-dim">
                Last changed <DateTime value={s.updated_at} /> {s.updated_by_label ? `by ${s.updated_by_label}` : s.updated_by ? `by ${shortId(s.updated_by)}` : "(no person recorded)"}
              </p>
            </div>
            <ConfirmForm idempotencyKey={newIdempotencyKey()} actionType="setting_set" subjectKind="setting" subjectRef={s.key} revalidate="/system" label="Save setting" danger={s.key === "refund_execute_enabled" || s.key === "actions_enabled"}>
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
                <textarea id={inputId} name={field} rows={2} defaultValue={JSON.stringify(s.value)} required className="field mt-1 font-mono text-[0.75rem]" />
              )}
            </ConfirmForm>
          </li>
        );
      })}
    </ul>
  );
}
