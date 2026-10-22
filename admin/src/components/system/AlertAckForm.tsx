"use client";

import { useActionState, useId, type MouseEvent } from "react";
import { useFormStatus } from "react-dom";
import { submitAlertAck, type AlertAckState } from "@/lib/actions";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";
import { blockWhilePending } from "@/components/ui/ConfirmForm";

/** Stays focusable while pending (aria-disabled, as ConfirmForm's button does); a click then is swallowed. */
function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button type="submit" aria-disabled={pending} aria-busy={pending} onClick={(e: MouseEvent<HTMLButtonElement>) => blockWhilePending(pending, e)} className="btn btn-sm btn-ghost">
      {pending ? "Recording…" : "Record acknowledgement"}
    </button>
  );
}

/**
 * What an acknowledgement's slot shows: the action's result, the form, or
 * nothing. The result outlives the refresh that comes back with the action
 * (revalidatePath) and marks the row acknowledged, so the operator still reads
 * it, and it gives way only when the row moves on to an incident newer than
 * the one acknowledged (which needs its own acknowledgement).
 */
export function alertAckView(state: AlertAckState, row: { incidentSeq: number; acknowledged: boolean }): "result" | "form" | "none" {
  if (state.acknowledgedAt) {
    const acked = state.incidentSeq ?? state.shownIncidentSeq;
    if (acked === undefined || acked >= row.incidentSeq) return "result";
  }
  return row.acknowledged ? "none" : "form";
}

/** The action's answer: a success, or — when the database acknowledged another incident than the one shown — a warning in the action's words. */
export function AlertAckResult({ state }: { state: AlertAckState }) {
  if (state.warning) {
    return (
      <Alert state="warning" title="Acknowledged, but not the incident this page showed." compact>
        {state.warning} The alert stays firing until the condition clears.
      </Alert>
    );
  }
  return (
    <Alert state="success" title="Acknowledged." compact>
      {state.incidentSeq && state.incidentSeq > 1 ? `Incident #${state.incidentSeq}. ` : ""}
      The alert stays firing until the condition clears.
    </Alert>
  );
}

/**
 * Records that a person has seen this firing alert (`ops.alert_ack`, migration
 * 146). Port of PR #89's control, as a disclosure like the case controls, so
 * the form is in the page without JavaScript.
 *
 * Acknowledging is not fixing: the alert stays firing until the condition
 * clears, and it is not a delivery confirmation either. It covers THIS
 * incident only — if the condition clears and comes back, 146 opens a new
 * incident that needs its own acknowledgement. The form posts the incident it
 * shows, and the action warns when the database acknowledged another one.
 *
 * AlertList renders this for acknowledged rows too (`acknowledged`), so the
 * component — and the result held in its state — stays mounted across the
 * refresh that hides the form.
 */
export function AlertAckForm({ alertKey, incidentSeq, acknowledged = false, revalidate }: { alertKey: string; incidentSeq: number; acknowledged?: boolean; revalidate?: string }) {
  const [state, formAction] = useActionState<AlertAckState, FormData>(submitAlertAck, {});
  const noteId = `${useId()}-note`;
  const view = alertAckView(state, { incidentSeq, acknowledged });

  if (view === "none") return null;
  if (view === "result") {
    return (
      <div className="mt-2">
        <AlertAckResult state={state} />
      </div>
    );
  }

  return (
    <div className="mt-2">
      <details className="group">
        <summary className="btn btn-sm btn-ghost cursor-pointer [&::marker]:hidden [&::-webkit-details-marker]:hidden">
          Acknowledge{incidentSeq > 1 ? ` incident #${incidentSeq}` : ""}
        </summary>
        <form action={formAction} className="mt-2 flex w-full flex-col gap-2">
          <input type="hidden" name="alert_key" value={alertKey} />
          <input type="hidden" name="incident_seq" value={incidentSeq} />
          {revalidate ? <input type="hidden" name="revalidate" value={revalidate} /> : null}
          <label htmlFor={noteId} className="eyebrow block text-dim">
            Note (optional — written to the audit log)
          </label>
          <textarea id={noteId} name="note" rows={2} maxLength={2000} className="field" placeholder="Who is on it, and where the work is being tracked." />
          <div className="flex items-center gap-3">
            <SubmitButton />
          </div>
          {state.invalid ? <Alert state="failed" title={state.invalid} compact /> : null}
          {state.refused ? (
            <Alert state="failed" title="Not acknowledged." compact>
              {state.refused}
            </Alert>
          ) : null}
          {state.failure ? <OpsFailureAlert failure={state.failure} fn="alert_ack" /> : null}
        </form>
      </details>
    </div>
  );
}
