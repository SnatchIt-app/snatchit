"use client";

import { useActionState, useId, useState } from "react";
import { useFormStatus } from "react-dom";
import { submitOperationalConfig, type MoneyFormState } from "@/lib/actions";
import { IDEMPOTENCY_FIELD } from "@/lib/idempotency";
import { OPERATIONAL_KEYS, operationalOutcomeText, showSetting, specFor, type OperationalKeySpec, type OperationalSetting } from "@/lib/operational-config";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";

/** The result is shown only for the key it was submitted for; a key change hides it. */
export function resultBelongsToKey(subjectKey: string | undefined, selectedKey: string): boolean {
  return subjectKey === selectedKey;
}

/** The one value control for the selected key. Extracted so each branch is render-testable without a DOM. */
export function OperationalValueInput({ spec, id }: { spec: OperationalKeySpec; id: string }) {
  if (spec.kind === "boolean") {
    return (
      <select id={id} name="value" required defaultValue="" className="field mt-1">
        <option value="" disabled>
          Choose…
        </option>
        <option value="true">true</option>
        <option value="false">false</option>
      </select>
    );
  }
  if (spec.kind === "integer") {
    return <input id={id} name="value" type="number" min={1} max={2147483647} step={1} required className="field mt-1" placeholder="6" />;
  }
  return <input id={id} name="value" type="text" required className="field mt-1 font-mono text-[0.75rem]" placeholder="10 minutes" />;
}

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button type="submit" disabled={pending} aria-busy={pending} className="btn btn-sm btn-primary">
      {pending ? "Applying…" : "Apply now"}
    </button>
  );
}

/**
 * Operational settings (registry 197): the four single-admin keys. Shows every
 * key's live value up front, then one form. The change applies at once for one
 * platform_admin at aal2 (no second founder), so the operator must type the key
 * name to confirm. The result text is the server's answer, never optimistic.
 */
export function OperationalSettingsForm({ settings, commandKey }: { settings: OperationalSetting[]; commandKey: string }) {
  const [state, formAction] = useActionState<MoneyFormState, FormData>(submitOperationalConfig, {});
  const [key, setKey] = useState("");
  const spec = specFor(key);
  const live = settings.find((s) => s.key === key);
  const base = useId();

  return (
    <div className="space-y-5">
      <table className="w-full text-left text-[0.75rem]">
        <caption className="eyebrow mb-2 text-left text-dim">Live values</caption>
        <thead>
          <tr className="border-b border-line-neutral text-dim">
            <th scope="col" className="py-1 pr-3 font-normal">Setting</th>
            <th scope="col" className="py-1 pr-3 font-normal">Key</th>
            <th scope="col" className="py-1 pr-3 font-normal">Live value</th>
            <th scope="col" className="py-1 font-normal">Version</th>
          </tr>
        </thead>
        <tbody>
          {OPERATIONAL_KEYS.map((k) => {
            const s = settings.find((x) => x.key === k.key);
            return (
              <tr key={k.key} className="border-b border-line-neutral">
                <td className="py-1.5 pr-3 text-ink">{k.label}</td>
                <td className="py-1.5 pr-3">
                  <code className="break-all font-mono text-[0.6875rem] text-dim">{k.key}</code>
                </td>
                <td className="py-1.5 pr-3">
                  <code className={`font-mono ${s && s.value !== null ? "text-ink" : "text-warning"}`}>{s ? showSetting(s.value) : "—"}</code>
                </td>
                <td className="py-1.5 tabular-nums text-dim">{s?.version ?? "—"}</td>
              </tr>
            );
          })}
        </tbody>
      </table>

      <form action={formAction} className="max-w-xl space-y-3">
        <input type="hidden" name={IDEMPOTENCY_FIELD} value={commandKey} />
        <div>
          <label htmlFor={`${base}-key`} className="eyebrow block text-dim">
            Setting <span aria-hidden="true">*</span>
          </label>
          <select id={`${base}-key`} name="key" required value={key} onChange={(e) => setKey(e.target.value)} className="field mt-1">
            <option value="">Choose a setting…</option>
            {OPERATIONAL_KEYS.map((k) => (
              <option key={k.key} value={k.key}>
                {k.label} ({k.key})
              </option>
            ))}
          </select>
          {spec ? (
            <p className="mt-1 text-[0.75rem] text-muted">
              {spec.help} Live: <code className="font-mono text-ink">{live ? showSetting(live.value) : "—"}</code>
            </p>
          ) : null}
        </div>
        {spec ? (
          <div key={spec.key}>
            <label htmlFor={`${base}-value`} className="eyebrow block text-dim">
              New value <span aria-hidden="true">*</span>
            </label>
            <OperationalValueInput spec={spec} id={`${base}-value`} />
          </div>
        ) : null}
        <div>
          <label htmlFor={`${base}-reason`} className="eyebrow block text-dim">
            Reason <span aria-hidden="true">*</span>
          </label>
          <textarea id={`${base}-reason`} name="reason" required rows={2} maxLength={2000} className="field mt-1" placeholder="Why — this is written to the audit log." />
        </div>
        <div>
          <label htmlFor={`${base}-confirm`} className="eyebrow block text-dim">
            Type the key to confirm <span aria-hidden="true">*</span>
          </label>
          <input id={`${base}-confirm`} name="confirm" required autoComplete="off" spellCheck={false} className="field mt-1 font-mono text-[0.75rem]" placeholder={spec?.key ?? "the key name"} />
        </div>
        <p className="text-[0.6875rem] text-dim">This applies immediately for one founder — these keys are not dual-control. An aal2 session is required on this path.</p>
        <SubmitButton />
        {resultBelongsToKey(state.subjectKey, key) ? (
          state.invalid ? (
            <Alert state="failed" title={state.invalid} compact />
          ) : state.failure ? (
            <OpsFailureAlert failure={state.failure} fn="set_operational_config" />
          ) : state.status ? (
            <Alert state={operationalOutcomeText(state.status)?.tone ?? "info"} title={operationalOutcomeText(state.status)?.title ?? `Answered: ${state.status}`} compact>
              {state.status === "ok" && state.appliedVersion != null ? <>Live version {state.appliedVersion}.</> : null}
            </Alert>
          ) : null
        ) : null}
      </form>
    </div>
  );
}
