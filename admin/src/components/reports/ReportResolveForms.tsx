import { ConfirmForm, OutcomeHost } from "@/components/ui/ConfirmForm";
import { DateTime } from "@/components/ui/DateTime";
import { newIdempotencyKey } from "@/lib/idempotency";
import type { Report } from "@/lib/types";

/**
 * Triage buttons for one report: Reviewing → Actioned / Dismissed. Each is a
 * separate form (own idempotency key) carrying the status we rendered so a
 * concurrent change is rejected as stale_state.
 */
export function ReportResolveForms({ report, revalidate, compact = false }: { report: Report; revalidate: string; compact?: boolean }) {
  if (!report.id) return null;
  const closed = report.status === "actioned" || report.status === "dismissed";
  const targets: { status: string; label: string; danger?: boolean }[] = [
    ...(report.status === "reviewing" ? [] : [{ status: "reviewing", label: "Mark reviewing" }]),
    { status: "actioned", label: "Actioned", danger: true },
    { status: "dismissed", label: "Dismiss" },
  ];
  // OutcomeHost keeps the server's answer visible after the forms re-key on the new status.
  return (
    <OutcomeHost actionType="report_resolve">
      {closed ? (
        <span className="text-[0.75rem] text-dim">closed{report.resolved_at ? <> <DateTime value={report.resolved_at} /></> : null}</span>
      ) : (
    <div className={`flex flex-col gap-3 ${compact ? "min-w-[220px]" : ""}`}>
      {targets.map((t) => (
        <ConfirmForm
          key={`${report.id}-${t.status}-${report.status}`}
          idempotencyKey={newIdempotencyKey()}
          actionType="report_resolve"
          subjectKind="report"
          subjectId={report.id}
          params={{ status: t.status }}
          expected={{ status: report.status }}
          revalidate={revalidate}
          label={t.label}
          danger={t.danger}
          reasonLabel={`Reason (${t.status})`}
          className="border-l border-line-neutral pl-3"
        />
      ))}
    </div>
      )}
    </OutcomeHost>
  );
}
