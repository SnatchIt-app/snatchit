import { KeyValue } from "@/components/ui/KeyValue";
import { DateTime } from "@/components/ui/DateTime";
import { Money } from "@/components/ui/Money";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { humanize } from "@/lib/format";
import { asRecords, isRecord, num, str, type DailySummary, type JsonRecord } from "@/lib/types";
import type { ReactNode } from "react";

function scalar(k: string, v: unknown): ReactNode {
  if (v === null || v === undefined) return null;
  if (typeof v === "boolean") return <StatusBadge status={String(v)} label={v ? "yes" : "no"} />;
  if (typeof v === "number") return /(cents|amount|total)$/.test(k) ? <Money cents={v} /> : v.toLocaleString("en-US");
  if (typeof v === "string") return /_at$|^from$|^to$/.test(k) && /\d{4}-\d{2}-\d{2}/.test(v) ? <DateTime value={v} /> : v;
  return <code className="font-mono text-[11px]">{JSON.stringify(v)}</code>;
}

function CountMap({ map }: { map: JsonRecord }) {
  const entries = Object.entries(map);
  if (entries.length === 0) return <span className="text-dim">none</span>;
  return (
    <ul className="flex flex-wrap gap-2 text-[12px]">
      {entries.map(([k, v]) => (
        <li key={k} className="border border-line-neutral px-2 py-0.5">
          <span className="text-dim">{humanize(k)}</span> <span className="tabular-nums text-ink">{num(v) ?? "—"}</span>
        </li>
      ))}
    </ul>
  );
}

/** ops.daily_summary.body rendered as readable sections (portal only). */
export function SummaryView({ summary }: { summary: DailySummary }) {
  const b = summary.body;
  const cases = isRecord(b.cases) ? b.cases : {};
  const money = isRecord(b.money) ? b.money : {};
  const live = isRecord(money.live_24h) ? money.live_24h : {};
  const deadlines = isRecord(b.deadlines) ? b.deadlines : {};
  const jobs = isRecord(b.jobs) ? b.jobs : {};
  const alerts = asRecords(b.alerts_firing);
  const failing = asRecords(jobs.failing);
  const runs = isRecord(jobs.runs_24h) ? jobs.runs_24h : {};
  const period = isRecord(b.period) ? b.period : {};

  return (
    <div className="space-y-5 text-[13px]">
      <p className="text-[12px] text-muted">
        Summary for <span className="text-ink">{summary.summary_date ?? "—"}</span>, generated <DateTime value={summary.generated_at} /> · period <DateTime value={period.from} relative={false} /> → <DateTime value={period.to} relative={false} /> ·{" "}
        <StatusBadge status={summary.delivery_state} label={summary.delivery_state === "portal_only" ? "portal only — no delivery channel configured" : summary.delivery_state ?? "—"} variant="muted" />
      </p>

      <section>
        <h3 className="eyebrow mb-2 text-dim">Cases</h3>
        <KeyValue
          columns={3}
          items={["opened_24h", "resolved_24h", "open_total", "unassigned", "overdue_due_at", "oldest_open"].map((k) => ({ key: k, value: scalar(k, cases[k]) }))}
        />
        <div className="mt-2 grid gap-3 sm:grid-cols-2">
          <div>
            <p className="eyebrow text-dim">Open by type</p>
            <div className="mt-1">
              <CountMap map={isRecord(cases.open_by_type) ? cases.open_by_type : {}} />
            </div>
          </div>
          <div>
            <p className="eyebrow text-dim">Open by priority</p>
            <div className="mt-1">
              <CountMap map={isRecord(cases.open_by_priority) ? cases.open_by_priority : {}} />
            </div>
          </div>
        </div>
      </section>

      <section>
        <h3 className="eyebrow mb-2 text-dim">Money — last 24 h ({str(money.currency) ?? "USD"}, {str(money.basis) ?? "UTC"})</h3>
        <KeyValue
          columns={3}
          items={[
            { key: "captured_cents", label: "Captured", value: scalar("captured_cents", live.captured_cents) },
            { key: "captured_count", label: "Captured payments", value: scalar("captured_count", live.captured_count) },
            { key: "refunded_cents", label: "Refunded", value: scalar("refunded_cents", live.refunded_cents) },
            { key: "released_to_connected_cents", label: "Released to connected account (not bank payouts)", value: scalar("released_to_connected_cents", live.released_to_connected_cents) },
            { key: "refunds_pending_count", label: "Refund pending cases", value: scalar("refunds_pending_count", live.refunds_pending_count) },
          ]}
        />
      </section>

      <section>
        <h3 className="eyebrow mb-2 text-dim">Deadlines</h3>
        <KeyValue columns={3} items={Object.entries(deadlines).map(([k, v]) => ({ key: k, value: scalar(k, v) }))} />
      </section>

      <section>
        <h3 className="eyebrow mb-2 text-dim">Jobs</h3>
        <KeyValue
          columns={3}
          items={[
            { key: "succeeded", label: "Runs succeeded (24 h)", value: scalar("succeeded", runs.succeeded) },
            { key: "failed", label: "Runs failed (24 h)", value: scalar("failed", runs.failed) },
            { key: "skipped", label: "Runs skipped (24 h)", value: scalar("skipped", runs.skipped) },
            { key: "last_detector_success_at", value: scalar("last_detector_success_at", jobs.last_detector_success_at) },
          ]}
        />
        {failing.length ? (
          <ul className="mt-2 space-y-1 text-[12px]">
            {failing.map((f, i) => (
              <li key={str(f.job_name) ?? i} className="border-l-2 border-danger pl-2">
                <code className="font-mono">{str(f.job_name)}</code> · {num(f.consecutive_failures) ?? 0} consecutive failure(s)
                {str(f.last_error) ? <span className="text-muted"> — {str(f.last_error)}</span> : null}
              </li>
            ))}
          </ul>
        ) : (
          <p className="mt-2 text-[12px] text-dim">No failing jobs.</p>
        )}
      </section>

      <section>
        <h3 className="eyebrow mb-2 text-dim">Alerts firing ({num(b.alerts_firing_count) ?? alerts.length})</h3>
        {alerts.length === 0 ? (
          <p className="text-[12px] text-dim">None.</p>
        ) : (
          <ul className="space-y-1 text-[12px]">
            {alerts.map((a, i) => (
              <li key={str(a.alert_key) ?? i} className="border-l-2 border-warning pl-2">
                <code className="font-mono">{str(a.alert_key)}</code> · {str(a.kind)} · first <DateTime value={a.first_fired_at} /> · ×{num(a.fire_count) ?? 1}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
