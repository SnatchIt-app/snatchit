"use server";

import { revalidatePath } from "next/cache";
import { callOps } from "@/lib/ops";
import { isIdempotencyKey, IDEMPOTENCY_FIELD } from "@/lib/idempotency";
import { isRecord, toActionOutcome, type ActionOutcome, type ActionType } from "@/lib/types";
import { coerceParam, parseParamField } from "@/lib/form-params";
import type { OpsFailure } from "@/lib/ops-errors";

export type ExecuteActionInput = {
  idempotencyKey: string;
  actionType: ActionType | string;
  subjectKind: string;
  /** uuid of the subject; null for subjects addressed by `subjectRef` (job, setting, none). */
  subjectId: string | null;
  /** ops.action.subject_ref — job name, setting key, webhook event id. */
  subjectRef?: string | null;
  params?: Record<string, unknown>;
  reason: string;
  expected?: Record<string, unknown>;
};

/**
 * What a mutation form renders after submit. `outcome` is the authoritative
 * server answer (§3.4 statuses); `failure` is transport/authz. Never both.
 */
export type ActionFormState = {
  submitted?: boolean;
  outcome?: ActionOutcome;
  failure?: OpsFailure;
  /** Client-side validation problem (e.g. missing reason). */
  invalid?: string;
};

export async function executeAction(input: ExecuteActionInput): Promise<ActionFormState> {
  if (!isIdempotencyKey(input.idempotencyKey)) {
    return { submitted: true, invalid: "Missing idempotency key — reload the page and try again." };
  }
  const res = await callOps<unknown>("execute_action", {
    p_idempotency_key: input.idempotencyKey,
    p_action_type: input.actionType,
    p_subject_kind: input.subjectKind,
    p_subject_id: input.subjectId || null,
    p_subject_ref: input.subjectRef || null,
    p_params: input.params ?? {},
    p_reason: input.reason,
    p_expected: input.expected ?? {},
  });
  if (!res.ok) return { submitted: true, failure: res };
  const outcome = toActionOutcome(res.data);
  if (!outcome) {
    return {
      submitted: true,
      failure: { ok: false, kind: "error", message: "Unrecognised response from execute_action" },
    };
  }
  return { submitted: true, outcome };
}

export async function approveAction(input: {
  actionId: string;
  decision: "approve" | "reject";
  reason: string;
}): Promise<ActionFormState> {
  const res = await callOps<unknown>("approve_action", {
    p_action_id: input.actionId,
    p_decision: input.decision,
    p_reason: input.reason,
  });
  if (!res.ok) return { submitted: true, failure: res };
  const outcome = toActionOutcome(res.data);
  if (!outcome) {
    return {
      submitted: true,
      failure: { ok: false, kind: "error", message: "Unrecognised response from approve_action" },
    };
  }
  return { submitted: true, outcome };
}

function parseJsonRecord(raw: FormDataEntryValue | null): Record<string, unknown> {
  if (typeof raw !== "string" || raw.trim() === "") return {};
  try {
    const v: unknown = JSON.parse(raw);
    return isRecord(v) ? v : {};
  } catch {
    return {};
  }
}

/**
 * Generic form-post adapter for ConfirmForm. Hidden inputs carry the action
 * envelope; visible inputs named `param.<key>` (or `param.<key>:<type>` for
 * boolean/number/integer/json coercion) become `p_params` entries (empty
 * string -> null so "unassign"/"clear due" work). `reason` is the operator's
 * justification (required unless the form opts out, in which case the note
 * body doubles as the reason).
 */
export async function submitActionForm(_prev: ActionFormState, formData: FormData): Promise<ActionFormState> {
  const idempotencyKey = String(formData.get(IDEMPOTENCY_FIELD) ?? "");
  const actionType = String(formData.get("action_type") ?? "");
  const subjectKind = String(formData.get("subject_kind") ?? "");
  const subjectId = String(formData.get("subject_id") ?? "");
  const subjectRef = String(formData.get("subject_ref") ?? "");
  const reasonRequired = formData.get("reason_required") !== "0";
  const revalidate = formData.get("revalidate");

  const params: Record<string, unknown> = parseJsonRecord(formData.get("params"));
  for (const [k, v] of formData.entries()) {
    const field = parseParamField(k);
    if (!field || typeof v !== "string") continue;
    const coerced = coerceParam(field.type, v);
    if (!coerced.ok) return { submitted: true, invalid: `${field.key}: ${coerced.error}` };
    params[field.key] = coerced.value;
  }
  const expected = parseJsonRecord(formData.get("expected"));

  let reason = String(formData.get("reason") ?? "").trim();
  if (!reason && !reasonRequired) {
    const body = params.body ?? params.note ?? params.text;
    reason = typeof body === "string" ? body : "";
  }
  // job_retry / setting_set / case_create(none) address their subject by ref
  // (or nothing at all); everything else needs a uuid subject.
  const refAddressed = actionType === "job_retry" || actionType === "setting_set" || (actionType === "case_create" && subjectKind === "none");
  if (!actionType || !subjectKind || (!subjectId && !refAddressed)) {
    return { submitted: true, invalid: "This form is missing its action envelope. Reload and try again." };
  }
  if (!reason) return { submitted: true, invalid: "A reason is required." };
  if (reason.length > 2000) return { submitted: true, invalid: "Reason is too long (2000 characters max)." };

  const state = await (actionType === "approval_decide" && typeof params.action_id === "string"
    ? approveAction({
        actionId: params.action_id,
        decision: params.decision === "reject" ? "reject" : "approve",
        reason,
      })
    : executeAction({ idempotencyKey, actionType, subjectKind, subjectId: subjectId || null, subjectRef: subjectRef || null, params, reason, expected }));

  if (state.outcome && typeof revalidate === "string" && revalidate.startsWith("/")) {
    revalidatePath(revalidate);
  }
  return state;
}

// ---------------------------------------------------------------------------
// Refund executor resume (ops-refund-execute edge function)
// ---------------------------------------------------------------------------

export type ResumeRefundState = {
  submitted?: boolean;
  /** Authoritative state reported by the executor, when it answered. */
  state?: string;
  actionId?: string;
  message?: string;
  /** The function is not deployed / not reachable (404/503/network). */
  notDeployed?: boolean;
  /** Any other failure (auth, 4xx, 5xx). */
  error?: string;
  httpStatus?: number;
};

/**
 * Ask the edge function to (re)drive a `refund_execute` action that is in
 * processing / succeeded_at_provider / unknown. The function is action-row
 * driven: the only input is the action id. Stripe is never called from here.
 */
export async function resumeRefundExecution(actionId: string): Promise<ResumeRefundState> {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(actionId)) {
    return { submitted: true, error: "Invalid action id." };
  }
  const { callEdgeFunction } = await import("@/lib/edge-functions");
  const res = await callEdgeFunction<{ action_id?: string; state?: string; message?: string }>("ops-refund-execute", { action_id: actionId });
  if (!res.ok) {
    if (res.unreachable) {
      return { submitted: true, notDeployed: true, httpStatus: res.status, message: res.detail ?? res.error };
    }
    const data = res.data ?? {};
    return {
      submitted: true,
      httpStatus: res.status,
      error: res.error,
      message: res.detail,
      state: typeof data.state === "string" ? data.state : undefined,
      actionId: typeof data.action_id === "string" ? data.action_id : undefined,
    };
  }
  revalidatePath(`/actions/${actionId}`);
  return {
    submitted: true,
    httpStatus: res.status,
    state: res.data.state,
    actionId: res.data.action_id ?? actionId,
    message: res.data.message,
  };
}

export async function submitResumeRefund(_prev: ResumeRefundState, formData: FormData): Promise<ResumeRefundState> {
  const actionId = String(formData.get("action_id") ?? "");
  return resumeRefundExecution(actionId);
}
