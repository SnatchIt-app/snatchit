"use client";

import { useActionState, useId, useState } from "react";
import { useFormStatus } from "react-dom";
import { submitAlertAck, type AlertAckState } from "@/lib/actions";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button type="submit" disabled={pending} aria-busy={pending} className="btn btn-sm btn-ghost">
      {pending ? "Recording…" : "Acknowledge"}
    </button>
  );
}

/**
 * Records that a person has seen this firing alert (`ops.alert_ack`).
 *
 * Acknowledging is not fixing: the alert stays firing until the condition
 * clears, and it is not a delivery confirmation either. It covers THIS
 * incident only — if the condition clears and comes back, migration 146 opens
 * a new incident that needs its own acknowledgement.
 */
export function AlertAckForm({ alertKey, incidentSeq, revalidate }: { alertKey: string; incidentSeq?: number | null; revalidate?: string }) {
  const [state, formAction] = useActionState<AlertAckState, FormData>(submitAlertAck, {});
  const [open, setOpen] = useState(false);
  const noteId = `${useId()}-note`;

  if (state.acknowledgedAt) {
    return (
      <Alert state="success" title="Acknowledged." compact>
        {state.incidentSeq && state.incidentSeq > 1 ? `Incident #${state.incidentSeq}. ` : ""}
        The alert stays firing until the condition clears.
      </Alert>
    );
  }

  if (!open) {
    return (
      <button type="button" className="btn btn-sm btn-ghost" onClick={() => setOpen(true)}>
        Acknowledge{incidentSeq && incidentSeq > 1 ? ` incident #${incidentSeq}` : ""}
      </button>
    );
  }

  return (
    <form action={formAction} className="w-full space-y-2">
      <input type="hidden" name="alert_key" value={alertKey} />
      {revalidate ? <input type="hidden" name="revalidate" value={revalidate} /> : null}
      <label htmlFor={noteId} className="eyebrow block text-dim">
        Note (optional — written to the audit log)
      </label>
      <textarea id={noteId} name="note" rows={2} maxLength={2000} className="field" placeholder="Who is on it, and where the work is being tracked." />
      <div className="flex items-center gap-3">
        <SubmitButton />
        <button type="button" className="link text-[12px]" onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
      {state.invalid ? <Alert state="failed" title={state.invalid} compact /> : null}
      {state.refused ? <Alert state="failed" title="Not acknowledged." compact>{state.refused}</Alert> : null}
      {state.failure ? <OpsFailureAlert failure={state.failure} fn="alert_ack" /> : null}
    </form>
  );
}
