"use client";

import { createContext, useActionState, useContext, useEffect, useId, useRef, type FormEvent, type MouseEvent, type ReactNode } from "react";
import { useFormStatus } from "react-dom";
import { submitActionForm, type ActionFormState } from "@/lib/actions";
import { IDEMPOTENCY_FIELD } from "@/lib/idempotency";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";
import { str, type ActionOutcome } from "@/lib/types";
import { RELIST_STALE_MESSAGE, relistOutcomeDetail, type RelistOutcomeDetail } from "@/lib/relist";

/**
 * While a submission is pending the button stays focusable (aria-disabled, not
 * disabled — a disabled button drops keyboard focus to the page) and a click is
 * swallowed; the form's own guard stops Enter. The idempotency key is unchanged.
 */
function SubmitButton({ label, pendingLabel, danger }: { label: string; pendingLabel: string; danger?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      aria-disabled={pending}
      aria-busy={pending}
      onClick={(e: MouseEvent<HTMLButtonElement>) => blockWhilePending(pending, e)}
      className={`btn btn-sm ${danger ? "btn-primary" : "btn-ghost"}`}
    >
      {pending ? pendingLabel : label}
    </button>
  );
}

/** Cancels a click or submit that arrives while a submission is still pending. Returns true when it cancelled. */
export function blockWhilePending(pending: boolean, e: { preventDefault: () => void }): boolean {
  if (!pending) return false;
  e.preventDefault();
  return true;
}

type HostValue = { formAction: (payload: FormData) => void; pending: boolean };
const OutcomeHostContext = createContext<HostValue | null>(null);

/**
 * Keeps the server's answer on screen across a remount of the form inside it.
 * Forms keyed on a record's version are replaced when a change (or a
 * stale_state refusal) re-renders the page — in the same render that delivers
 * the answer — so the answer must live above the key. The action state is held
 * here; the form posts exactly the same fields to the same server action; the
 * text shown is exactly what the server returned. Focus moves to the answer
 * when the replaced form took it.
 */
export function OutcomeHost({ actionType = "", children }: { actionType?: string; children: ReactNode }) {
  const [state, formAction, pending] = useActionState<ActionFormState, FormData>(submitActionForm, {});
  const box = useRef<HTMLDivElement>(null);
  const has = Boolean(state.invalid || state.failure || state.outcome);
  useEffect(() => {
    if (!has) return;
    const a = document.activeElement;
    if (!a || a === document.body) box.current?.focus();
  }, [state, has]);
  return (
    <OutcomeHostContext.Provider value={{ formAction, pending }}>
      {children}
      {has ? (
        <div ref={box} tabIndex={-1} className="mt-3 outline-none">
          <FormResult state={state} actionType={actionType} />
        </div>
      ) : null}
    </OutcomeHostContext.Provider>
  );
}

/** The server's answer to a submission: invalid input, a failed call, or the action outcome. */
function FormResult({ state, actionType }: { state: ActionFormState; actionType: string }) {
  if (state.invalid) return <Alert state="failed" title={state.invalid} compact />;
  if (state.failure) return <OpsFailureAlert failure={state.failure} fn={actionType === "approval_decide" ? "approve_action" : "execute_action"} />;
  if (state.outcome) return <OutcomeText outcome={state.outcome} actionType={actionType} />;
  return null;
}

/** Raw server values, never reformatted (a timestamp keeps its offset and microseconds). */
function FieldList({ caption, rows }: { caption: string; rows: { key: string; value: string | null }[] }) {
  return (
    <div className="mt-1">
      <p className="eyebrow text-dim">{caption}</p>
      <ul className="font-mono text-[0.6875rem]">
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
        {detail.current ? <FieldList caption="The listing as the server found it" rows={detail.current} /> : null}
        <button type="button" className="link" onClick={() => window.location.reload()}>
          Reload now
        </button>
      </Alert>
    );
  }
  const relisted = detail.relisted
    ? [
        { key: "new_ends_at", value: str(detail.relisted.new_ends_at) },
        { key: "previous_ends_at", value: str(detail.relisted.previous_ends_at) },
      ]
    : null;
  return (
    <Alert state="success" title="Recorded." compact>
      {outcome.status === "succeeded" && outcome.action_id ? (
        <a className="link" href={`/actions/${outcome.action_id}`}>
          Action {outcome.action_id.slice(0, 8)}
        </a>
      ) : null}
      {relisted ? <FieldList caption="Relisted (admin_relist_listing)" rows={relisted} /> : null}
      {detail.before ? <FieldList caption="The listing before the relist, as the server locked it" rows={detail.before} /> : null}
    </Alert>
  );
}

/**
 * The server's answer, in its words. `actionType` only adds what an action's
 * answer carries beyond the generic text (listing_relist: result.result /
 * result.before / result.current); every other answer renders the same for
 * every action, unknown codes included.
 */
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
      // A second founder's denial is a decision that was recorded, not a failure.
      if ((outcome.reason as string) === "denied") {
        return <Alert state="info" title="Denied — nothing changed." compact />;
      }
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
  const host = useContext(OutcomeHostContext);
  const [ownState, ownAction, ownPending] = useActionState<ActionFormState, FormData>(submitActionForm, {});
  const formAction = host ? host.formAction : ownAction;
  const pending = host ? host.pending : ownPending;
  const reasonId = `${useId()}-reason`;
  // Enter in a field while a submission is pending would submit again; the ref
  // also holds a same-tick double submit, before `pending` has re-rendered.
  const inFlight = useRef(false);
  useEffect(() => {
    if (!pending) inFlight.current = false;
  }, [pending, ownState]);
  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    if (blockWhilePending(pending || inFlight.current, e)) return;
    inFlight.current = true;
  };

  return (
    <form action={formAction} onSubmit={onSubmit} className={`space-y-3 ${className}`}>
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

      {host ? null : <FormResult state={ownState} actionType={actionType} />}
    </form>
  );
}
