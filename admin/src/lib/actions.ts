"use server";

import { revalidatePath } from "next/cache";
import { callOps } from "@/lib/ops";
import { isIdempotencyKey, IDEMPOTENCY_FIELD } from "@/lib/idempotency";
import { isRecord, parseApprovalDecision, str, toActionOutcome, type ActionOutcome, type ActionType, type ApprovalDecision } from "@/lib/types";
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

/** The first of `keys` holding a non-empty string. Not pick(): it stops at the first key present, even one that is null. */
function firstText(r: Record<string, unknown> | null, ...keys: string[]): string | null {
  for (const k of keys) {
    const v = str(r?.[k]);
    if (v) return v;
  }
  return null;
}

/**
 * A mutation answer with a status the console does not know (a status added
 * server-side after this build). Shown as a generic failure that keeps the
 * database's own words: the status, its code and its message. No code is
 * special-cased, so a refusal code added later renders the same way.
 */
function unrecognisedResponse(fn: "execute_action" | "approve_action", data: unknown): OpsFailure {
  const r = isRecord(data) ? data : null;
  const status = str(r?.status);
  const code = firstText(r, "reject_reason", "reason", "code");
  const message = firstText(r, "message", "detail", "error");
  return {
    ok: false,
    kind: "error",
    ...(code ? { code } : {}),
    message: `Unrecognised response from ${fn}${status ? ` (status ${status})` : ""}${message ? `: ${message}` : ""}`,
  };
}

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
  if (!outcome) return { submitted: true, failure: unrecognisedResponse("execute_action", res.data) };
  return { submitted: true, outcome };
}

/**
 * `ops.approve_action(p_action_id, p_decision, p_reason)` — the database
 * accepts exactly 'approve' | 'deny' and raises on anything else. The
 * decision is forwarded verbatim; parsing happens once, in submitActionForm.
 */
export async function approveAction(input: {
  actionId: string;
  decision: ApprovalDecision;
  reason: string;
}): Promise<ActionFormState> {
  const res = await callOps<unknown>("approve_action", {
    p_action_id: input.actionId,
    p_decision: input.decision,
    p_reason: input.reason,
  });
  if (!res.ok) return { submitted: true, failure: res };
  const outcome = toActionOutcome(res.data);
  if (!outcome) return { submitted: true, failure: unrecognisedResponse("approve_action", res.data) };
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
 * string -> null so "unassign"/"clear due" work; an empty `:optional` field
 * is left out, for "leave as is"). `reason` is the operator's
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
    if (coerced.value === undefined) continue; // `:optional` left empty: no change, so no key at all
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

  let state: ActionFormState;
  if (actionType === "approval_decide") {
    // Never default a decision: an unrecognised value must not approve.
    const decision = parseApprovalDecision(params.decision);
    if (!decision) return { submitted: true, failure: { ok: false, kind: "error", message: "invalid decision" } };
    if (typeof params.action_id !== "string" || !params.action_id) {
      return { submitted: true, invalid: "This form is missing its action envelope. Reload and try again." };
    }
    state = await approveAction({ actionId: params.action_id, decision, reason });
  } else {
    state = await executeAction({ idempotencyKey, actionType, subjectKind, subjectId: subjectId || null, subjectRef: subjectRef || null, params, reason, expected });
  }

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
  /** Authoritative ops.action state reported by the executor, when it answered. */
  state?: string;
  /** Stripe refund status when the executor reports one (pending / requires_action / succeeded …). */
  refundStatus?: string;
  /** HTTP 202: Stripe accepted the refund but it has not succeeded yet. */
  accepted?: boolean;
  actionId?: string;
  message?: string;
  /** The function is not deployed / not reachable (404/503/network). */
  notDeployed?: boolean;
  /** HTTP 409: ops.executor_claim refused (disabled, paused, claim_busy, approval_stale, terminal …). */
  refusedReason?: string;
  /** Any other failure (auth, 4xx, 5xx). */
  error?: string;
  httpStatus?: number;
};

type ExecutorReply = { action_id?: string; state?: string; refund_status?: string; message?: string; reason?: string; error?: string; detail?: string };

/**
 * Ask the edge function to (re)drive a `refund_execute` action that is in
 * processing / unknown. The function is action-row driven: the only input is
 * the action id. Stripe is never called from here. Replies: 200 terminal,
 * 202 accepted-not-succeeded (pending / requires_action), 409 `{reason}`
 * when the claim is refused, 422 provider failure.
 */
export async function resumeRefundExecution(actionId: string): Promise<ResumeRefundState> {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(actionId)) {
    return { submitted: true, error: "Invalid action id." };
  }
  const { callEdgeFunction } = await import("@/lib/edge-functions");
  const res = await callEdgeFunction<ExecutorReply>("ops-refund-execute", { action_id: actionId });
  if (!res.ok) {
    if (res.unreachable) {
      return { submitted: true, notDeployed: true, httpStatus: res.status, message: res.detail ?? res.error };
    }
    const data = (res.data ?? {}) as ExecutorReply;
    const reason = typeof data.reason === "string" ? data.reason : res.status === 409 ? res.error : undefined;
    return {
      submitted: true,
      httpStatus: res.status,
      error: res.error,
      refusedReason: reason,
      message: res.detail ?? (typeof data.message === "string" ? data.message : undefined),
      state: typeof data.state === "string" ? data.state : undefined,
      refundStatus: typeof data.refund_status === "string" ? data.refund_status : undefined,
      actionId: typeof data.action_id === "string" ? data.action_id : undefined,
    };
  }
  revalidatePath(`/actions/${actionId}`);
  return {
    submitted: true,
    httpStatus: res.status,
    accepted: res.status === 202,
    state: res.data.state,
    refundStatus: res.data.refund_status,
    actionId: res.data.action_id ?? actionId,
    message: res.data.message,
  };
}

export async function submitResumeRefund(_prev: ResumeRefundState, formData: FormData): Promise<ResumeRefundState> {
  const actionId = String(formData.get("action_id") ?? "");
  return resumeRefundExecution(actionId);
}

// ---------------------------------------------------------------------------
// Alert acknowledgement (ops.alert_ack, migration 146) — port of PR #89
// ---------------------------------------------------------------------------

/**
 * Acknowledging is NOT part of the action engine: `ops.alert_ack(p_alert_key
 * text, p_note text default null)` is its own function, gated by
 * `ops.assert_reader()` and audited by itself (`alert.acknowledged`). It
 * records that a PERSON has seen a firing alert — the one thing neither a
 * database row nor a confirmed delivery can tell you. It does not recover the
 * alert: the condition still has to clear on its own.
 */
export type AlertAckState = {
  submitted?: boolean;
  /** The alert as it stands after the call. */
  acknowledgedAt?: string;
  /** The incident that was acknowledged, when the database reports one. */
  incidentSeq?: number;
  /** The incident the page showed when the operator pressed Acknowledge (the form's hidden incident_seq). */
  shownIncidentSeq?: number;
  /**
   * Set when the database acknowledged a different incident from the one shown
   * (or did not say which): `ops.alert_ack` acknowledges whatever incident the
   * row holds when the call arrives, so a re-fire after the page loaded is
   * acknowledged unseen. The acknowledgement stands; this says so.
   */
  warning?: string;
  failure?: OpsFailure;
  invalid?: string;
  /** ops.alert_ack's own refusal (unknown key, already recovered), in its words. */
  refused?: string;
};

function otherIncidentWarning(shown: number, acknowledged: number | undefined): string | undefined {
  const check = "Read the alert as it stands now before relying on that acknowledgement.";
  if (acknowledged === undefined) return `The database did not report which incident it acknowledged; this page showed incident #${shown}. ${check}`;
  if (acknowledged === shown) return undefined;
  if (acknowledged > shown) return `A new incident #${acknowledged} opened since you loaded this page, which showed incident #${shown}; it is now acknowledged. ${check}`;
  return `The database acknowledged incident #${acknowledged}, not incident #${shown} that this page showed. ${check}`;
}

/** The form's hidden incident_seq: a positive whole number, or null. */
function incidentSeqField(raw: FormDataEntryValue | null): number | null {
  return typeof raw === "string" && /^[1-9]\d{0,9}$/.test(raw.trim()) ? Number(raw.trim()) : null;
}

/**
 * `shownIncidentSeq` is the incident the page showed. 146's alert_ack takes no
 * expected incident, so the comparison happens on its answer: a mismatch is
 * reported as a warning (the acknowledgement has already been recorded).
 */
export async function acknowledgeAlert(alertKey: string, note: string, shownIncidentSeq?: number): Promise<AlertAckState> {
  if (!alertKey) return { submitted: true, invalid: "This form is missing its alert key. Reload and try again." };
  if (note.length > 2000) return { submitted: true, invalid: "Note is too long (2000 characters max)." };
  const res = await callOps<unknown>("alert_ack", { p_alert_key: alertKey, p_note: note || null });
  if (!res.ok) {
    // 146 raises P0002 'not_found: no alert …' and P0001 'precondition_failed:
    // … nothing to acknowledge': the function's own refusals, not a fault.
    // Anything else stays the generic failure mapOpsError built (the
    // database's message and code, verbatim).
    const message = res.kind === "error" ? res.message : undefined;
    if (message && /no alert|nothing to acknowledge/i.test(message)) {
      return { submitted: true, refused: message };
    }
    return { submitted: true, failure: res };
  }
  const row = isRecord(res.data) ? res.data : {};
  const acknowledgedAt = typeof row.acknowledged_at === "string" ? row.acknowledged_at : undefined;
  if (!acknowledgedAt) {
    return { submitted: true, failure: { ok: false, kind: "error", message: "Unrecognised response from alert_ack" } };
  }
  const incidentSeq = typeof row.incident_seq === "number" ? row.incident_seq : undefined;
  const warning = shownIncidentSeq === undefined ? undefined : otherIncidentWarning(shownIncidentSeq, incidentSeq);
  return {
    submitted: true,
    acknowledgedAt,
    incidentSeq,
    ...(shownIncidentSeq !== undefined ? { shownIncidentSeq } : {}),
    ...(warning ? { warning } : {}),
  };
}

export async function submitAlertAck(_prev: AlertAckState, formData: FormData): Promise<AlertAckState> {
  const alertKey = String(formData.get("alert_key") ?? "");
  const note = String(formData.get("note") ?? "").trim();
  const shown = incidentSeqField(formData.get("incident_seq"));
  if (shown === null) return { submitted: true, invalid: "This form does not say which incident it acknowledges. Reload and try again." };
  const state = await acknowledgeAlert(alertKey, note, shown);
  const revalidate = formData.get("revalidate");
  if (state.acknowledgedAt && typeof revalidate === "string" && revalidate.startsWith("/")) {
    revalidatePath(revalidate);
  }
  return state;
}
