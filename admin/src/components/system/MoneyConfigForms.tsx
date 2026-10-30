"use client";

import { useActionState, useId, useState } from "react";
import { useFormStatus } from "react-dom";
import { submitMoneyConfigDecision, submitMoneyConfigRequest, type MoneyFormState } from "@/lib/actions";
import { IDEMPOTENCY_FIELD } from "@/lib/idempotency";
import { decisionOutcomeText, requestOutcomeText, showValue, type MoneyKey } from "@/lib/money-config";
import type { ApprovalDecision } from "@/lib/types";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";

function SubmitButton({ label, pendingLabel, danger }: { label: string; pendingLabel: string; danger?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button type="submit" disabled={pending} aria-busy={pending} className={`btn btn-sm ${danger ? "btn-primary" : "btn-ghost"}`}>
      {pending ? pendingLabel : label}
    </button>
  );
}

function Result({ state, fn, kind }: { state: MoneyFormState; fn: string; kind: "request" | "decision" }) {
  if (state.invalid) return <Alert state="failed" title={state.invalid} compact />;
  if (state.failure) return <OpsFailureAlert failure={state.failure} fn={fn} />;
  if (!state.status) return null;
  const text = kind === "request" ? requestOutcomeText(state.status) : decisionOutcomeText(state.status);
  return (
    <Alert state={text?.tone ?? "info"} title={text?.title ?? `Answered: ${state.status}`} compact>
      {state.requestId ? <>Request {state.requestId.slice(0, 8)}. </> : null}
      {state.appliedVersion != null ? <>Live version {state.appliedVersion}.</> : null}
    </Alert>
  );
}

/**
 * Request a money-key change (ops.request_platform_config). The key list and
 * current values come from ops.list_config_approvals; the value is typed as
 * JSON so its type is explicit. The server decides parked vs applied.
 */
export function MoneyRequestForm({ moneyKeys, commandKey }: { moneyKeys: MoneyKey[]; commandKey: string }) {
  const [state, formAction] = useActionState<MoneyFormState, FormData>(submitMoneyConfigRequest, {});
  const [key, setKey] = useState("");
  const current = moneyKeys.find((k) => k.key === key);
  const base = useId();

  return (
    // React resets a <form action> once the action completes; clear the controlled key with it, or the
    // "Current:" line would describe a key the reset picker no longer shows.
    <form action={formAction} onReset={() => setKey("")} className="space-y-3">
      <input type="hidden" name={IDEMPOTENCY_FIELD} value={commandKey} />
      <div>
        <label htmlFor={`${base}-key`} className="eyebrow block text-dim">
          Money key <span aria-hidden="true">*</span>
        </label>
        <select id={`${base}-key`} name="key" required value={key} onChange={(e) => setKey(e.target.value)} className="field mt-1">
          <option value="">Choose a key…</option>
          {moneyKeys.map((k) => (
            <option key={k.key} value={k.key}>
              {k.key}
            </option>
          ))}
        </select>
        {current ? (
          <p className="mt-1 text-[12px] text-muted">
            Current: <code className="font-mono text-ink">{showValue(current.value)}</code> <span className="text-dim">(version {current.version ?? "—"})</span>
          </p>
        ) : null}
      </div>
      <div>
        <label htmlFor={`${base}-value`} className="eyebrow block text-dim">
          New value (JSON) <span aria-hidden="true">*</span>
        </label>
        <input
          id={`${base}-value`}
          key={key}
          name="value"
          required
          defaultValue={current && current.value !== null ? JSON.stringify(current.value) : ""}
          className="field mt-1 font-mono text-[12px]"
          placeholder='2500 · "24 hours" · true'
        />
        <p className="mt-1 text-[11px] text-dim">Text values need double quotes. Interval keys take a string such as &quot;24 hours&quot;; a bare number would be read as seconds and is refused.</p>
      </div>
      <div>
        <label htmlFor={`${base}-reason`} className="eyebrow block text-dim">
          Reason <span aria-hidden="true">*</span>
        </label>
        <textarea id={`${base}-reason`} name="reason" required rows={2} maxLength={2000} className="field mt-1" placeholder="Why — this is written to the audit log." />
      </div>
      <SubmitButton label="Request change" pendingLabel="Requesting…" danger />
      <Result state={state} fn="request_platform_config" kind="request" />
    </form>
  );
}

/** Approve or deny one request (kernel.approve_refund_request). */
export function MoneyDecisionForm({
  requestId,
  decision,
  commandKey,
  label,
  danger = false,
}: {
  requestId: string;
  decision: ApprovalDecision;
  commandKey: string;
  label: string;
  danger?: boolean;
}) {
  const [state, formAction] = useActionState<MoneyFormState, FormData>(submitMoneyConfigDecision, {});
  const reasonId = `${useId()}-reason`;
  return (
    <form action={formAction} className="space-y-3">
      <input type="hidden" name={IDEMPOTENCY_FIELD} value={commandKey} />
      <input type="hidden" name="request_id" value={requestId} />
      <input type="hidden" name="decision" value={decision} />
      <div>
        <label htmlFor={reasonId} className="eyebrow block text-dim">
          {decision === "approve" ? "Approval reason" : "Denial reason"} <span aria-hidden="true">*</span>
        </label>
        <textarea id={reasonId} name="reason" required rows={2} maxLength={2000} className="field mt-1" placeholder="Why — this is written to the audit log." />
      </div>
      <SubmitButton label={label} pendingLabel="Submitting…" danger={danger} />
      <Result state={state} fn="approve_refund_request" kind="decision" />
    </form>
  );
}
