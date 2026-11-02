"use server";

import "server-only";

import { revalidatePath } from "next/cache";
import { requireOperator } from "@/lib/auth/session";
import { callOps, type OpsResult } from "@/lib/ops";
import {
  mintRefundKey,
  REFUND_REFUSAL_COPY,
  refundRefusalCopy,
  toPrimaryReconciliation,
  toRefundOutcome,
  validateRefundInput,
  type FieldProblem,
  type PrimaryReconciliation,
  type RefundOutcome,
} from "@/lib/primary-money";

/**
 * Ticket (primary) order money — the console side of migration 189.
 *
 * Both calls are `ops.*` under the operator's own JWT, like every other read
 * and action in this console: `ops.primary_reconciliation(p_from, p_to)` and
 * `ops.record_primary_refund(p_order_id, p_amount_minor, p_reason_code,
 * p_command_key)`. The server asserts the role and the aal2 session and the
 * console pause switch; this module adds nothing and bypasses nothing.
 *
 * Recording a refund VOIDS the order's voidable tickets and writes the refund
 * row. It moves no money — refunds are manual by owner decision — so nothing
 * here may report a refund as paid.
 */
export type ReconciliationResult = { ok: true; data: PrimaryReconciliation } | (OpsResult<unknown> & { ok: false });

export async function readPrimaryReconciliation(from?: string | null, to?: string | null): Promise<ReconciliationResult> {
  const day = (v: string | null | undefined) => (typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : null);
  const res = await callOps<unknown>("primary_reconciliation", { p_from: day(from), p_to: day(to) });
  if (!res.ok) return res;
  const data = toPrimaryReconciliation(res.data);
  if (!data) return { ok: false, kind: "error", message: "Unrecognised payload from ops.primary_reconciliation()" };
  return { ok: true, data };
}

export type RefundFormState = {
  outcome: RefundOutcome | null;
  problems?: FieldProblem[];
  /** The server's refusal in the operator's words, when it refused. */
  refusal?: string;
  /** The key this attempt used, so a retry re-sends the same one. */
  commandKey?: string;
};

/**
 * One refund record. The command key is minted per form render and travels as a
 * hidden field, so pressing the button twice — or retrying after a lost answer
 * — re-sends the SAME key and the server replays it instead of refunding twice.
 */
export async function recordPrimaryRefundForm(_prev: RefundFormState, fd: FormData): Promise<RefundFormState> {
  await requireOperator();
  const text = (k: string) => {
    const v = fd.get(k);
    return typeof v === "string" ? v.trim() : "";
  };
  const orderId = text("orderId");
  const commandKey = text("commandKey");
  const reasonCode = text("reasonCode");
  const raw = text("amount_minor");
  const amountMinor = /^\d+$/.test(raw) ? Number(raw) : Number.NaN;
  const maxRaw = text("max_minor");
  const max = /^\d+$/.test(maxRaw) ? Number(maxRaw) : null;

  // A typed confirmation, because this voids tickets the door would otherwise admit.
  if (text("confirm").toUpperCase() !== "REFUND") return { outcome: null, problems: [{ field: "confirm", message: 'Type "REFUND" to confirm.' }], commandKey };

  const problems = validateRefundInput({ orderId, amountMinor, reasonCode, commandKey }, max);
  if (problems.length > 0) return { outcome: null, problems, commandKey };

  const res = await callOps<unknown>("record_primary_refund", { p_order_id: orderId, p_amount_minor: amountMinor, p_reason_code: reasonCode, p_command_key: commandKey });
  if (!res.ok) {
    // The console's own classification first (it knows denied / step-up / paused from the
    // error shape); only a generic error carries a message worth reading for a token.
    const refusal =
      res.kind === "denied"
        ? REFUND_REFUSAL_COPY.insufficient_privilege
        : res.kind === "mfa"
          ? REFUND_REFUSAL_COPY.step_up_required
          : res.kind === "paused"
            ? REFUND_REFUSAL_COPY.actions_disabled
            : refundRefusalCopy(res.message);
    return { outcome: { kind: "refused", reason: res.kind }, refusal, commandKey };
  }

  const outcome = toRefundOutcome(res.data);
  if (outcome.kind === "recorded" || outcome.kind === "replayed") revalidatePath("/money/ticket-orders");
  return { outcome, refusal: outcome.kind === "refused" ? refundRefusalCopy(outcome.reason) : undefined, commandKey };
}

/** A fresh key for a form render. Exported because a "use server" module may only export async functions. */
export async function newRefundKey(): Promise<string> {
  return mintRefundKey(crypto.randomUUID());
}
