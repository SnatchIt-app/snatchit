import Link from "next/link";
import type { ReactNode } from "react";
import type { OpsAlert } from "@/lib/types";
import { shortId } from "@/lib/format";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { TimeAgo } from "@/components/ui/DateTime";
import { AlertAckForm } from "@/components/system/AlertAckForm";

/** ops.dispatch_alerts' c_max_attempts (migration 146): it posts an alert at most this many times. */
export const ALERT_MAX_ATTEMPTS = 5;

/**
 * Firing alerts on /system, with what the record says happened to each one
 * (migration 146) and the Acknowledge control. Port of PR #89's Alerts panel
 * onto v2's System page.
 */
export function AlertList({ alerts, meId, revalidate = "/system" }: { alerts: OpsAlert[]; meId?: string; revalidate?: string }) {
  return (
    <>
      {alerts.length === 0 ? (
        <p className="text-dim">No alerts firing.</p>
      ) : (
        <ul className="flex flex-col gap-4">
          {alerts.map((a, i) => {
            const caseId = typeof a.payload?.case_id === "string" ? a.payload.case_id : null;
            const title = typeof a.payload?.title === "string" ? a.payload.title : null;
            const seq = a.incident_seq ?? 1;
            return (
              <li key={a.alert_key ?? i} className="border-l-2 border-warning pl-3 text-[0.8125rem]">
                <div className="flex flex-wrap items-baseline gap-2">
                  <StatusBadge status={a.state} label={a.state ?? "firing"} />
                  <span className="font-mono text-[0.75rem] text-dim">{a.kind}</span>
                  {caseId ? (
                    <Link href={`/cases/${caseId}`} className="link">
                      {title ?? a.alert_key}
                    </Link>
                  ) : (
                    <span>{title ?? a.alert_key}</span>
                  )}
                  {seq > 1 ? <StatusBadge status="recurrence" label={`Incident #${seq}`} variant="neutral" /> : null}
                  <span className="text-[0.6875rem] text-dim">
                    first <TimeAgo value={a.first_fired_at} /> · last <TimeAgo value={a.last_fired_at} /> · ×{a.fire_count ?? 1}
                  </span>
                </div>
                <AlertDelivery alert={a} meId={meId} />
                {/* Rendered for acknowledged rows too, so the action's result survives the refresh that marks the row acknowledged. */}
                {a.alert_key ? <AlertAckForm alertKey={a.alert_key} incidentSeq={seq} acknowledged={Boolean(a.acknowledged_at)} revalidate={revalidate} /> : null}
              </li>
            );
          })}
        </ul>
      )}
      <p className="mt-4 border-t border-line-neutral pt-3 text-[0.6875rem] text-dim">
        Migration 146 records delivery but sends nothing by itself: it seeds <span className="font-mono">alert_delivery_enabled</span> false and schedules no caller for{" "}
        <span className="font-mono">ops.dispatch_alerts</span>. Turning delivery on and scheduling a caller are both owner decisions; until both are made, an alert reaches a
        person only when someone opens this page. Acknowledging records that a person saw this incident. It does not fix the condition, and it is not a delivery.
      </p>
    </>
  );
}

/**
 * What the alert row records, in 146's terms — two separate facts, each
 * stated only as far as the row establishes it:
 *
 *   acknowledgement — acknowledged_at/by: an operator pressed Acknowledge;
 *   delivery — QUEUED IS NOT DELIVERED. pg_net returns a request id the moment
 *     a post is accepted, so queued_at means only that. delivered_at is set
 *     only when notify-report answered 2xx AND reported that it delivered
 *     something (a bare 200 is what it answers for an event it does not know).
 *     A confirmed delivery still is not proof a person read it.
 */
export function AlertDelivery({ alert, meId }: { alert: OpsAlert; meId?: string }) {
  const attempts = alert.notify_attempts ?? 0;
  let delivery: ReactNode;
  if (alert.delivered_at) {
    delivery = (
      <>
        <span className="text-success">Delivery confirmed</span> <TimeAgo value={alert.delivered_at} />
        {alert.delivery_status ? ` (HTTP ${alert.delivery_status})` : ""}: notify-report reported a delivery — not proof anyone read it
      </>
    );
  } else if (alert.queued_at) {
    delivery = (
      <>
        <span className="text-warning">Queued</span> <TimeAgo value={alert.queued_at} />: pg_net accepted the post — not confirmed delivered
      </>
    );
  } else if (attempts > 0) {
    delivery = (
      <>
        <span className="text-warning">Not delivered</span> after {attempts} attempt{attempts === 1 ? "" : "s"}
        {alert.last_notify_error ? `: ${alert.last_notify_error}` : ""}
        {attempts >= ALERT_MAX_ATTEMPTS ? ` — attempt limit (${ALERT_MAX_ATTEMPTS}) reached; ops.dispatch_alerts no longer posts it` : ""}
      </>
    );
  } else {
    delivery = (
      <>
        Not sent: no delivery attempt is recorded for this incident
        {alert.last_notify_error ? ` (${alert.last_notify_error})` : ""}
      </>
    );
  }
  return (
    <>
      {alert.acknowledged_at ? (
        <p className="mt-1 text-[0.6875rem] text-dim">
          <span className="text-success">Acknowledged</span> <TimeAgo value={alert.acknowledged_at} />
          {alert.acknowledged_by ? ` by ${meId && alert.acknowledged_by === meId ? "me" : shortId(alert.acknowledged_by)}` : ""} · still firing until the condition clears
        </p>
      ) : null}
      <p className="mt-1 text-[0.6875rem] text-dim">{delivery}</p>
    </>
  );
}
