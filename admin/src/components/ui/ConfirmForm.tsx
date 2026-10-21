"use client";

import { useActionState, useId } from "react";
import { useFormStatus } from "react-dom";
import type { ReactNode } from "react";
import { submitActionForm, type ActionFormState } from "@/lib/actions";
import { IDEMPOTENCY_FIELD } from "@/lib/idempotency";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";
import { str, type ActionOutcome } from "@/lib/types";
import { RELIST_STALE_MESSAGE, relistOutcomeDetail, type RelistOutcomeDetail } from "@/lib/relist";

function SubmitButton({ label, pendingLabel, danger }: { label: string; pendingLabel: string; danger?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button type="submit" disabled={pending} aria-busy={pending} className={`btn btn-sm ${danger ? "btn-primary" : "btn-ghost"}`}>
      {pending ? pendingLabel : label}
    </button>
  );
}

/** Raw server values, never reformatted (a timestamp keeps its offset and microseconds). */
function FieldList({ caption, rows }: { caption: string; rows: { key: string; value: string | null }[] }) {
  return (
    <div className="mt-1">
      <p className="eyebrow text-dim">{caption}</p>
      <ul className="font-mono text-[11px]">
        {rows.map((r) => (
          <li key={r.key}>
            {r.key} <span className={r.value === null ? "text-dim" : "text-ink"}>{r.value ?? "null"}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** listing_relist answers that carry more than the generic text (migration 158). */
function RelistOutcome({ outcome, detail }: { outcome: ActionOutcome; detail: RelistOutcomeDetail }) {
  if (detail.kind === "stale") {
    return (
      <Alert state="stale" title={RELIST_STALE_MESSAGE} compact>
        {outcome.status === "rejected" && outcome.message && outcome.message !== RELIST_STALE_MESSAGE ? <p>{outcome.message}</p> : null}
        {detail.current ? <FieldList caption="The listing now (server row)" rows={detail.current} /> : null}
        <button type="button" className="link" onClick={() => window.location.reload()}>
          Reload now
        </button>
      </Alert>
    );
  }
  return (
    <Alert state="success" title="Recorded." compact>
      {outcome.status === "succeeded" && outcome.action_id ? (
        <a className="link" href={`/actions/${outcome.action_id}`}>
          Action {outcome.action_id.slice(0, 8)}
        </a>
      ) : null}
      {detail.relisted ? (
        <FieldList
          caption="Relisted"
          rows={[
            { key: "new_ends_at", value: str(detail.relisted.new_ends_at) },
            { key: "previous_ends_at", value: str(detail.relisted.previous_ends_at) },
          ]}
        />
      ) : null}
      {detail.before ? <FieldList caption="Listing as the server locked it (before)" rows={detail.before} /> : null}
    </Alert>
  );
}

export function OutcomeText({ outcome, actionType }: { outcome: ActionOutcome; actionType?: string }) {
  const relist = actionType === "listing_relist" ? relistOutcomeDetail(outcome) : null;
  if (relist) return <RelistOutcome outcome={outcome} detail={relist} />;
  switch (outcome.status) {
    case "succeeded":
      return (
        <Alert state="success" title="Recorded." compact>
          {outcome.action_id ? (
            <a className="link" href={`/actions/${outcome.action_id}`}>
              Action {outcome.action_id.slice(0, 8)}
            </a>
          ) : null}
        </Alert>
      );
    case "idempotent_replay":
      return (
        <Alert state="info" title="Already submitted — no second action was created." compact>
          {outcome.state ? (
            <>
              Current state: <StatusBadge status={outcome.state} />
            </>
          ) : null}
        </Alert>
      );
    case "awaiting_approval":
      return (
        <Alert state="warning" title="Awaiting a second operator's approval." compact>
          Nothing has changed yet.{" "}
          {outcome.action_id ? (
            <a className="link" href={`/actions/${outcome.action_id}`}>
              Track action
            </a>
          ) : null}
        </Alert>
      );
    case "processing":
      return (
        <Alert state="warning" title="Processing — the outcome is not yet known." compact>
          Do not resubmit.{" "}
          {outcome.action_id ? (
            <a className="link" href={`/actions/${outcome.action_id}`}>
              Check status
            </a>
          ) : null}
        </Alert>
      );
    case "rejected":
      if (outcome.reason === "stale_state") {
        return (
          <Alert state="stale" title="This record changed since you loaded it — reload." compact>
            {outcome.message}{" "}
            <button type="button" className="link" onClick={() => window.location.reload()}>
              Reload now
            </button>
          </Alert>
        );
      }
      return (
        <Alert state="failed" title={`Rejected: ${outcome.reason.replace(/_/g, " ")}`} compact>
          {outcome.message}
        </Alert>
      );
    case "failed":
      return (
        <Alert state="failed" title="Failed." compact>
          {outcome.error}
        </Alert>
      );
  }
}

/**
 * Mutation form for `ops.execute_action`. The envelope (action type, subject,
 * expected state, idempotency key) is fixed at render time by the Server
 * Component; the operator supplies a reason plus any `param.*` fields.
 * The result text is the server's answer — never an optimistic "done".
 */
export function ConfirmForm({
  idempotencyKey,
  actionType,
  subjectKind,
  subjectId = "",
  subjectRef,
  params,
  expected,
  revalidate,
  label,
  pendingLabel = "Submitting…",
  danger = false,
  reasonRequired = true,
  reasonLabel = "Reason",
  children,
  className = "",
}: {
  idempotencyKey: string;
  actionType: string;
  subjectKind: string;
  /** uuid subject; omit for ref-addressed subjects (job, setting) or a subject-less manual case. */
  subjectId?: string | null;
  /** ops.action.subject_ref — job name / setting key. */
  subjectRef?: string | null;
  params?: Record<string, unknown>;
  expected?: Record<string, unknown>;
  /** Path to revalidate after an authoritative outcome (usually the page). */
  revalidate?: string;
  label: string;
  pendingLabel?: string;
  danger?: boolean;
  reasonRequired?: boolean;
  reasonLabel?: string;
  /** Inputs named `param.<key>` become p_params entries. */
  children?: ReactNode;
  className?: string;
}) {
  const [state, formAction] = useActionState<ActionFormState, FormData>(submitActionForm, {});
  const reasonId = `${useId()}-reason`;

  return (
    <form action={formAction} className={`space-y-3 ${className}`}>
      <input type="hidden" name={IDEMPOTENCY_FIELD} value={idempotencyKey} />
      <input type="hidden" name="action_type" value={actionType} />
      <input type="hidden" name="subject_kind" value={subjectKind} />
      <input type="hidden" name="subject_id" value={subjectId ?? ""} />
      {subjectRef ? <input type="hidden" name="subject_ref" value={subjectRef} /> : null}
      <input type="hidden" name="params" value={JSON.stringify(params ?? {})} />
      <input type="hidden" name="expected" value={JSON.stringify(expected ?? {})} />
      <input type="hidden" name="reason_required" value={reasonRequired ? "1" : "0"} />
      {revalidate ? <input type="hidden" name="revalidate" value={revalidate} /> : null}

      {children}

      {reasonRequired ? (
        <div>
          <label htmlFor={reasonId} className="eyebrow block text-dim">
            {reasonLabel} <span aria-hidden="true">*</span>
          </label>
          <textarea id={reasonId} name="reason" required rows={2} maxLength={2000} className="field mt-1" placeholder="Why — this is written to the audit log." />
        </div>
      ) : null}

      <div className="flex items-center gap-3">
        <SubmitButton label={label} pendingLabel={pendingLabel} danger={danger} />
      </div>

      {state.invalid ? (
        <Alert state="failed" title={state.invalid} compact />
      ) : state.failure ? (
        <OpsFailureAlert failure={state.failure} fn={actionType === "approval_decide" ? "approve_action" : "execute_action"} />
      ) : state.outcome ? (
        <OutcomeText outcome={state.outcome} actionType={actionType} />
      ) : null}
    </form>
  );
}
