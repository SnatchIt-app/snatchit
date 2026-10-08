"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { submitResumeRefund, type ResumeRefundState } from "@/lib/actions";
import { Alert } from "@/components/ui/Alert";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { executorRefusalLabel, labelFor, refundStateLabel } from "@/lib/format";

function Submit() {
  const { pending } = useFormStatus();
  return (
    <button type="submit" disabled={pending} aria-busy={pending} className="btn btn-sm btn-primary">
      {pending ? "Contacting executor…" : "Resume execution"}
    </button>
  );
}

/**
 * Re-drives a refund_execute action in `processing` / `unknown` through the
 * ops-refund-execute edge function (action-row driven; the only input is the
 * action id). The text shown is the executor's answer: 200 terminal, 202
 * accepted-by-Stripe-not-yet-succeeded, 409 refused with a reason. Stripe is
 * never called from the console.
 */
export function ResumeRefundForm({ actionId, state, refundStatus }: { actionId: string; state: string | undefined; refundStatus?: string | null }) {
  const [result, formAction] = useActionState<ResumeRefundState, FormData>(submitResumeRefund, {});
  return (
    <form action={formAction} className="space-y-3">
      <input type="hidden" name="action_id" value={actionId} />
      <p className="text-[12px] text-muted">
        Current state: <StatusBadge status={state} label={refundStateLabel(state, refundStatus)} />. The executor re-checks the enabled flag, the console pause, the approval and its hash, takes a short lease on the action, looks up any existing Stripe refund under idempotency key{" "}
        <code className="font-mono">ops_action_{actionId.slice(0, 8)}…</code>, and records the authoritative outcome. Safe to call more than once.
      </p>
      <Submit />
      {result.submitted ? (
        result.notDeployed ? (
          <Alert state="warning" title="Executor not deployed." compact>
            ops-refund-execute is not reachable{result.httpStatus ? ` (HTTP ${result.httpStatus})` : ""}. Follow the Stripe Dashboard SOP and record the outcome via engineering.
          </Alert>
        ) : result.refusedReason ? (
          <Alert state="warning" title={`Executor refused: ${executorRefusalLabel(result.refusedReason)}`} compact>
            <code className="font-mono text-[11px]">{result.refusedReason}</code>
            {result.message ? ` — ${result.message}` : null}
            {result.state ? (
              <>
                {" "}
                · state <StatusBadge status={result.state} label={refundStateLabel(result.state, result.refundStatus)} />
              </>
            ) : null}
            {result.httpStatus ? <span className="ml-2 font-mono text-[11px] text-dim">HTTP {result.httpStatus}</span> : null}
          </Alert>
        ) : result.error ? (
          <Alert state="failed" title={`Executor error: ${result.error}`} compact>
            {result.message}
            {result.state ? (
              <>
                {" "}
                · state <StatusBadge status={result.state} label={refundStateLabel(result.state, result.refundStatus)} />
              </>
            ) : null}
            {result.httpStatus ? <span className="ml-2 font-mono text-[11px] text-dim">HTTP {result.httpStatus}</span> : null}
          </Alert>
        ) : result.accepted ? (
          <Alert state="warning" title={result.refundStatus === "requires_action" ? "Requires action at Stripe — not succeeded." : "Accepted by Stripe, not yet succeeded."} compact>
            State: <StatusBadge status={result.state} label={refundStateLabel(result.state, result.refundStatus)} />
            {result.message ? ` — ${result.message}` : null}. The action stays in processing until Stripe reports the final outcome; do not treat this as a completed refund.{" "}
            <button type="button" className="link" onClick={() => window.location.reload()}>
              Reload
            </button>
          </Alert>
        ) : (
          <Alert state={result.state === "succeeded" ? "success" : result.state === "failed" || result.state === "unknown" ? "failed" : "info"} title="Executor answered." compact>
            State: <StatusBadge status={result.state} label={labelFor("action", result.state)} />
            {result.message ? ` — ${result.message}` : null}{" "}
            <button type="button" className="link" onClick={() => window.location.reload()}>
              Reload to see the recorded outcome
            </button>
          </Alert>
        )
      ) : null}
    </form>
  );
}
