import { ConfirmForm } from "@/components/ui/ConfirmForm";
import { newIdempotencyKey } from "@/lib/idempotency";
import { CASE_PRIORITIES } from "@/lib/types";

/**
 * Manual case (case_create). When a subject is given the case is attached to
 * it (payment / listing / user …); otherwise it is a free-standing case.
 * Manual cases are never auto-resolved by detectors.
 */
export function NewCaseForm({
  subjectKind = "none",
  subjectId,
  subjectRef,
  revalidate,
  defaultTitle,
}: {
  subjectKind?: string;
  subjectId?: string | null;
  subjectRef?: string | null;
  revalidate: string;
  defaultTitle?: string;
}) {
  const params: Record<string, unknown> = { subject_kind: subjectKind };
  if (subjectId) params.subject_id = subjectId;
  if (subjectRef) params.subject_ref = subjectRef;
  return (
    <ConfirmForm
      idempotencyKey={newIdempotencyKey()}
      actionType="case_create"
      subjectKind={subjectKind}
      subjectId={subjectId ?? ""}
      subjectRef={subjectRef ?? undefined}
      params={params}
      revalidate={revalidate}
      label="Open case"
      reasonLabel="Why this case is being opened"
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="sm:col-span-2">
          <label htmlFor={`case-title-${subjectId ?? "none"}`} className="eyebrow block text-dim">
            Title <span aria-hidden="true">*</span>
          </label>
          <input id={`case-title-${subjectId ?? "none"}`} name="param.title" required maxLength={200} defaultValue={defaultTitle} className="field mt-1" placeholder="What needs attention" />
        </div>
        <div className="sm:col-span-2">
          <label htmlFor={`case-summary-${subjectId ?? "none"}`} className="eyebrow block text-dim">
            Summary
          </label>
          <textarea id={`case-summary-${subjectId ?? "none"}`} name="param.summary" rows={2} maxLength={4000} className="field mt-1" placeholder="Context for whoever picks it up." />
        </div>
        <div>
          <label htmlFor={`case-priority-${subjectId ?? "none"}`} className="eyebrow block text-dim">
            Priority
          </label>
          <select id={`case-priority-${subjectId ?? "none"}`} name="param.priority" defaultValue="p3" className="field mt-1">
            {CASE_PRIORITIES.map((p) => (
              <option key={p} value={p}>
                {p.toUpperCase()}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={`case-due-${subjectId ?? "none"}`} className="eyebrow block text-dim">
            Due (UTC)
          </label>
          <input id={`case-due-${subjectId ?? "none"}`} type="datetime-local" name="param.due_at" className="field mt-1" />
        </div>
      </div>
    </ConfirmForm>
  );
}
