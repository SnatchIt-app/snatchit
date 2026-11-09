"use client";

import { useActionState } from "react";
import { submitVenueApproval, type VenueApprovalFormState } from "@/lib/actions";
import { IDEMPOTENCY_FIELD } from "@/lib/idempotency";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";

const initialState: VenueApprovalFormState = {};

export function VenueApprovalForm({ commandKey }: { commandKey: string }) {
  const [state, action, pending] = useActionState(submitVenueApproval, initialState);
  return (
    <form action={action} className="max-w-xl space-y-3">
      <p className="text-sm text-dim">Use the venue ID from the venue dashboard link. Approval is recorded in the audit log. Ticket issuance is managed separately.</p>
      <input type="hidden" name={IDEMPOTENCY_FIELD} value={commandKey} />
      <label className="block text-sm">
        Venue ID
        <input name="venue" className="field mt-1 font-mono" required autoComplete="off" spellCheck={false} />
      </label>
      <label className="block text-sm">
        Type the venue ID again to confirm
        <input name="confirm" className="field mt-1 font-mono" required autoComplete="off" spellCheck={false} />
      </label>
      <label className="block text-sm">
        Reason
        <textarea name="reason" className="field mt-1" required rows={2} maxLength={2000} />
      </label>
      <button className="btn btn-primary" type="submit" disabled={pending}>
        {pending ? "Approving…" : "Approve venue"}
      </button>
      {state.invalid ? <Alert state="failed" title={state.invalid} compact /> : null}
      {state.failure ? <OpsFailureAlert failure={state.failure} fn="approve_venue" /> : null}
      {state.approvedVenue ? <Alert state="success" title="Venue approved" compact>{state.approvedVenue}</Alert> : null}
    </form>
  );
}
