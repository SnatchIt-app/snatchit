import type { ReactNode } from "react";
import type { Setting } from "@/lib/types";
import { KeyValue } from "@/components/ui/KeyValue";
import { DateTime } from "@/components/ui/DateTime";

/** Repository path of the owner's alert channel runbook (ordered owner steps; none authorised by the console). */
export const ALERT_CHANNEL_RUNBOOK_PATH = "docs/dashboards/ALERT_CHANNEL_RUNBOOK.md";

/** What the page read from ops.settings, which is platform_admin only (116:1593-1601). */
export type SettingsRead = { status: "not_admin" } | { status: "failed" } | { status: "ok"; settings: Setting[] };

export type DeliverySwitch = { state: "true" | "false"; updatedAt: string | null } | { state: "unknown"; reason: string };

/**
 * alert_delivery_enabled as the settings read returned it. Only a literal
 * boolean is a reading. Everything else is unknown, and never the seeded
 * default (146 seeds false, and ops.setting_bool falls back to false), because
 * a default is not a record of what the database holds.
 */
export function deliverySwitch(read: SettingsRead): DeliverySwitch {
  if (read.status === "not_admin") return { state: "unknown", reason: "ops.settings is readable by platform_admin only." };
  if (read.status === "failed") return { state: "unknown", reason: "ops.settings could not be read." };
  const row = read.settings.find((s) => s.key === "alert_delivery_enabled");
  if (!row) return { state: "unknown", reason: "ops.settings returned no alert_delivery_enabled row." };
  if (row.value === true) return { state: "true", updatedAt: row.updated_at };
  if (row.value === false) return { state: "false", updatedAt: row.updated_at };
  // Not echoed here: the Settings panel shows the stored value to the same reader.
  return { state: "unknown", reason: "ops.settings returned a value that is neither true nor false; the Settings panel below shows it as stored." };
}

/**
 * The read-only "Delivery channel" block on /system's Alerts panel. Each line
 * states only what its source establishes:
 *  - the delivery switch, from ops.settings (else unknown);
 *  - the schedule, which no console read returns: ops.job_health lists cron
 *    jobs by jobid, name, schedule and active flag only (143:186-197), and 146
 *    adds no read. So it is never asserted either way;
 *  - the channel, as the runbook prepared it, labelled as not a server read
 *    (its settings are edge-function secrets);
 *  - the runbook's path.
 * No email address is displayed or held here. Nothing in it is a control.
 */
export function AlertDeliveryChannel({ settings }: { settings: SettingsRead }) {
  const sw = deliverySwitch(settings);
  let switchLine: ReactNode;
  if (sw.state === "unknown") {
    switchLine = (
      <>
        <code className="font-mono">alert_delivery_enabled</code> = <strong className="font-semibold text-warning">unknown</strong> — {sw.reason}
      </>
    );
  } else {
    switchLine = (
      <>
        <code className="font-mono">alert_delivery_enabled</code> = <strong className="font-semibold">{sw.state}</strong> —{" "}
        {sw.state === "true" ? "a call to ops.dispatch_alerts can post alerts; the switch schedules nothing by itself." : "ops.dispatch_alerts posts nothing while it is false."}{" "}
        <span className="text-dim">
          Read from ops.settings; last changed <DateTime value={sw.updatedAt} />.
        </span>
      </>
    );
  }

  return (
    <section aria-labelledby="alert-delivery-channel" className="mb-5 border border-line-neutral p-4">
      <h3 id="alert-delivery-channel" className="eyebrow text-dim">
        Delivery channel
      </h3>
      <p className="mb-3 mt-1 text-[0.6875rem] text-dim">Read-only. Each line names its source; nothing here sends, schedules or switches anything.</p>
      <KeyValue
        columns={2}
        items={[
          { key: "switch", label: "Delivery switch", value: switchLine },
          {
            key: "schedule",
            label: "Schedule",
            value: (
              <>
                <strong className="font-semibold text-warning">not shown by the server (owner/A to verify)</strong> — ops.job_health lists each pg_cron job&apos;s name, schedule and
                active flag, not the command it runs (Cron jobs, above), and no other console read covers ops.dispatch_alerts. So this page cannot say whether anything calls it
                on a timer.
              </>
            ),
          },
          {
            key: "channel",
            label: "Channel",
            value: (
              <>
                <strong className="font-semibold">email to the owner&apos;s verified account email — prepared, not active (owner action)</strong>.{" "}
                <span className="text-dim">
                  From the runbook, not read from the server: the email channel&apos;s settings are edge-function secrets, which no console read returns.
                </span>
              </>
            ),
          },
          {
            key: "runbook",
            label: "Runbook",
            value: (
              <>
                <code className="font-mono">{ALERT_CHANNEL_RUNBOOK_PATH}</code> <span className="text-dim">— repository path of the owner&apos;s steps. This page performs none of them.</span>
              </>
            ),
          },
        ]}
      />
    </section>
  );
}
