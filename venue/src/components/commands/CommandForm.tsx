"use client";

import { useActionState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import type { CommandFormState } from "@/lib/events/forms";

/**
 * One shell for every command form: the hidden ids and the command key the
 * server page minted, the submit, and the answer rendered as what it is — a
 * receipt, a field problem, the server's refusal in the operator's words, or
 * "not enabled". Nothing is shown as saved without a receipt, and a replayed
 * command key is reported as already applied rather than as a second success.
 */
export type CommandIds = { orgId: string; venueId: string; eventId?: string };

const INITIAL: CommandFormState = { result: null };

export function CommandForm({
  action,
  ids,
  commandKey,
  extra,
  submitLabel,
  busyLabel,
  destructive = false,
  children,
}: {
  action: (prev: CommandFormState, fd: FormData) => Promise<CommandFormState>;
  ids: CommandIds;
  commandKey: string;
  extra?: Record<string, string | undefined>;
  submitLabel: string;
  busyLabel?: string;
  destructive?: boolean;
  children?: ReactNode;
}) {
  const router = useRouter();
  const [state, formAction, pending] = useActionState<CommandFormState, FormData>(async (prev, fd) => {
    const next = await action(prev, fd);
    if (next.result?.kind === "ok") router.refresh();
    return next;
  }, INITIAL);

  return (
    <form action={formAction} className="space-y-3">
      <input type="hidden" name="orgId" value={ids.orgId} />
      <input type="hidden" name="venueId" value={ids.venueId} />
      {ids.eventId ? <input type="hidden" name="eventId" value={ids.eventId} /> : null}
      <input type="hidden" name="commandKey" value={commandKey} />
      {extra
        ? Object.entries(extra)
            .filter(([, v]) => v !== undefined)
            .map(([k, v]) => <input key={k} type="hidden" name={k} value={v as string} />)
        : null}
      {children}
      {/* Field problems the dashboard caught before sending. */}
      {state.problems && state.problems.length > 0 ? (
        <ul role="alert" className="space-y-1 border-l-2 border-danger bg-primary-soft px-3 py-2 text-sm text-danger">
          {state.problems.map((p) => (
            <li key={`${p.field}-${p.message}`}>
              <span className="font-medium">{p.field.replace(/_/g, " ")}</span>: {p.message}
            </li>
          ))}
        </ul>
      ) : null}
      <Outcome state={state} />
      <button type="submit" disabled={pending} className={`btn min-h-11 ${destructive ? "btn-danger" : "btn-soft"}`}>
        {pending ? (busyLabel ?? "Sending…") : submitLabel}
      </button>
    </form>
  );
}

function Outcome({ state }: { state: CommandFormState }) {
  const r = state.result;
  if (!r) return null;
  if (r.kind === "ok") {
    const replayed = r.result.status === "noop_replay" || r.result.status === "noop";
    return (
      <p role="status" className="border-l-2 border-success bg-success-soft px-3 py-2 text-sm text-success">
        {replayed ? "Already applied — the server replayed this as a no-op, so nothing changed twice." : "Saved. The server recorded the change."}
      </p>
    );
  }
  if (r.kind === "refused") {
    return (
      <p role="alert" className="border-l-2 border-danger bg-primary-soft px-3 py-2 text-sm text-danger">
        {state.refusal ?? r.message}
      </p>
    );
  }
  return (
    <p role="alert" className="border-l-2 border-warning bg-warning-soft px-3 py-2 text-sm text-warning">
      {r.message}
    </p>
  );
}

export function Field({ label, name, hint, ...rest }: { label: string; name: string; hint?: string } & React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className="block text-sm">
      <span className="eyebrow block text-dim">{label}</span>
      <input name={name} className="field mt-1" {...rest} />
      {hint ? <span className="mt-1 block text-xs text-dim">{hint}</span> : null}
    </label>
  );
}

export function Select({ label, name, options, hint, ...rest }: { label: string; name: string; options: readonly (readonly [string, string])[]; hint?: string } & React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <label className="block text-sm">
      <span className="eyebrow block text-dim">{label}</span>
      <select name={name} className="field mt-1" {...rest}>
        {options.map(([v, l]) => (
          <option key={v} value={v}>
            {l}
          </option>
        ))}
      </select>
      {hint ? <span className="mt-1 block text-xs text-dim">{hint}</span> : null}
    </label>
  );
}
