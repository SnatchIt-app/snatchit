"use client";

import { useActionState } from "react";
import { recordPrimaryRefundForm, type RefundFormState } from "@/lib/primary-refund-actions";
import { MANUAL_REFUND_NOTE } from "@/lib/primary-money";
import { formatMoney } from "@/lib/format";

/**
 * Recording a manual refund for one ticket order. The amount defaults to the
 * order's own total (a full refund is what voids every voidable ticket); the
 * reason and a typed confirmation are required, because this is what stops the
 * door admitting the tickets. The command key was minted when this form
 * rendered, so a second press replays rather than refunding twice.
 *
 * It moves no money, and says so above the button.
 */
const INITIAL: RefundFormState = { outcome: null };

export function PrimaryRefundForm({ orderId, maxMinor, commandKey }: { orderId: string; maxMinor: number | null; commandKey: string }) {
  const [state, action, pending] = useActionState<RefundFormState, FormData>(recordPrimaryRefundForm, INITIAL);
  const problem = (field: string) => state.problems?.find((p) => p.field === field)?.message;
  const done = state.outcome?.kind === "recorded" || state.outcome?.kind === "replayed";

  return (
    <form action={action} className="space-y-3">
      <input type="hidden" name="orderId" value={orderId} />
      <input type="hidden" name="commandKey" value={state.commandKey ?? commandKey} />
      {maxMinor !== null ? <input type="hidden" name="max_minor" value={maxMinor} /> : null}

      <p className="text-[0.8125rem] leading-relaxed text-muted">{MANUAL_REFUND_NOTE}</p>

      <label className="block text-sm">
        <span className="eyebrow block text-dim">Amount (cents)</span>
        <input
          name="amount_minor"
          type="number"
          min={1}
          step={1}
          max={maxMinor ?? undefined}
          required
          defaultValue={maxMinor ?? ""}
          className="field mt-1 w-40 tabular-nums"
          aria-describedby="amt-help"
        />
        <span id="amt-help" className="mt-1 block text-xs text-dim">
          {maxMinor !== null ? `The order's total is ${formatMoney(maxMinor)}. A full refund voids every voidable ticket; a partial refunds money only and voids nothing.` : "A full refund voids every voidable ticket; a partial voids nothing."}
        </span>
        {problem("amountMinor") ? <span className="mt-1 block text-xs text-danger">{problem("amountMinor")}</span> : null}
      </label>

      <label className="block text-sm">
        <span className="eyebrow block text-dim">Reason</span>
        <input name="reasonCode" required maxLength={80} placeholder="buyer_request" className="field mt-1" autoComplete="off" />
        {problem("reasonCode") ? <span className="mt-1 block text-xs text-danger">{problem("reasonCode")}</span> : null}
      </label>

      <label className="block text-sm">
        <span className="eyebrow block text-dim">Type REFUND to confirm</span>
        <input name="confirm" required className="field mt-1 w-40" autoComplete="off" />
        {problem("confirm") ? <span className="mt-1 block text-xs text-danger">{problem("confirm")}</span> : null}
      </label>

      {state.refusal ? (
        <p role="alert" className="border-l-2 border-danger bg-primary-soft px-3 py-2 text-sm text-danger">
          {state.refusal}
          {state.outcome?.kind === "refused" && state.outcome.detail ? <span className="mt-1 block text-xs opacity-80">The server said: {state.outcome.detail}</span> : null}
        </p>
      ) : null}

      {done ? (
        <p role="status" className="border-l-2 border-success bg-success-soft px-3 py-2 text-sm text-success">
          {state.outcome?.kind === "replayed"
            ? "Already recorded — the server replayed this key, so nothing was recorded twice."
            : `Recorded against your name${state.outcome?.kind === "recorded" && typeof state.outcome.voided === "number" ? `; ${state.outcome.voided} ticket${state.outcome.voided === 1 ? "" : "s"} voided` : ""}. Now refund the PaymentIntent in the Stripe Dashboard.`}
        </p>
      ) : null}

      <button type="submit" disabled={pending || done} className="btn btn-danger min-h-11">
        {pending ? "Recording…" : done ? "Recorded" : "Record this refund"}
      </button>
    </form>
  );
}
