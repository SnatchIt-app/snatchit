import { ConfirmForm } from "@/components/ui/ConfirmForm";
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
  if (closed) return <span className="text-[12px] text-dim">closed {report.resolved_at ? "" : ""}</span>;
  const targets: { status: string; label: string; danger?: boolean }[] = [
    ...(report.status === "reviewing" ? [] : [{ status: "reviewing", label: "Mark reviewing" }]),
    { status: "actioned", label: "Actioned", danger: true },
    { status: "dismissed", label: "Dismiss" },
  ];
  return (
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
  );
}
