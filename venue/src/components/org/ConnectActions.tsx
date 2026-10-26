"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { refreshOrgConnect, startOrgOnboarding, type ConnectActionResult } from "@/lib/org/connect";
import { ACTION_LABEL, FAILURE_COPY, type ConnectAction, type ConnectSnapshot } from "@/lib/org/connect-contract";

/**
 * The two buttons: mint the Stripe link, or re-read the state. Both are one
 * POST to the `connect-onboarding` edge through a server action; the server
 * re-checks the caller's capability, so these buttons cannot grant anything.
 * A minted link is shown as a link for the operator to follow deliberately —
 * nothing here navigates on its own, because leaving mid-setup silently would
 * lose the operator's place.
 */
export function ConnectActions({ orgId, action, mayBind, needsStepUp, stepUpHref }: { orgId: string; action: ConnectAction; mayBind: boolean; needsStepUp: boolean; stepUpHref: string }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [result, setResult] = useState<ConnectActionResult | null>(null);
  const [link, setLink] = useState<{ url: string; label: string } | null>(null);

  const run = (fn: () => Promise<ConnectActionResult>, label: string) =>
    start(async () => {
      setResult(null);
      setLink(null);
      const r = await fn();
      setResult(r);
      if (r.ok && r.snapshot.url) setLink({ url: r.snapshot.url, label });
      if (r.ok) router.refresh();
    });

  const linkLabel = ACTION_LABEL[action];
  const binding = action === "set_up" || action === "continue";

  return (
    <div className="mt-4 space-y-3">
      <div className="flex flex-wrap gap-2">
        {action !== "none" ? (
          <button
            type="button"
            disabled={pending || (binding && !mayBind)}
            onClick={() => run(() => startOrgOnboarding(orgId, crypto.randomUUID()), linkLabel)}
            className="btn btn-primary min-h-11"
            title={binding && !mayBind ? "Only the organization's owner, after confirming it is them, can name the payout destination." : undefined}
          >
            {pending ? "Working…" : linkLabel}
          </button>
        ) : null}
        <button type="button" disabled={pending} onClick={() => run(() => refreshOrgConnect(orgId), "")} className="btn btn-soft min-h-11">
          {pending ? "Checking…" : "Check the state again"}
        </button>
      </div>

      {binding && needsStepUp ? (
        <p className="text-sm text-muted">
          Naming the payout destination needs a second step.{" "}
          <a href={stepUpHref} className="link">
            Confirm it is you
          </a>{" "}
          first; finance can read this page and start the setup, but the binding step is the owner&apos;s.
        </p>
      ) : null}

      {link ? (
        <p className="text-sm">
          <a href={link.url} target="_blank" rel="noopener noreferrer" className="link font-medium">
            {link.label || "Continue at Stripe"}
          </a>{" "}
          <span className="text-dim">opens Stripe in a new tab. Come back here and check the state again when you are done.</span>
        </p>
      ) : null}

      {result && !result.ok ? (
        <p role="alert" className="border-l-2 border-warning bg-warning-soft px-3 py-2 text-sm text-warning">
          {FAILURE_COPY[result.failure.kind]}
          {result.failure.detail ? <span className="mt-1 block text-xs opacity-80">{result.failure.detail}</span> : null}
        </p>
      ) : null}

      {result && result.ok ? <SnapshotNote snapshot={result.snapshot} /> : null}
    </div>
  );
}

function SnapshotNote({ snapshot }: { snapshot: ConnectSnapshot }) {
  return (
    <div role="status" className="border-l-2 border-line-strong bg-well px-3 py-2 text-sm">
      <p>
        Stripe says: <strong>{snapshot.status.replace(/_/g, " ")}</strong>
        {snapshot.last4 ? <span className="text-dim"> · account ending {snapshot.last4}</span> : null}
      </p>
      <ul className="mt-1 space-y-0.5 text-xs text-muted">
        <li>Transfers active: {snapshot.transfersActive === null ? "unknown" : snapshot.transfersActive ? "yes" : "no"}</li>
        <li>Payouts enabled: {snapshot.payoutsEnabled === null ? "unknown" : snapshot.payoutsEnabled ? "yes" : "no"}</li>
        <li>Details submitted: {snapshot.detailsSubmitted === null ? "unknown" : snapshot.detailsSubmitted ? "yes" : "no"}</li>
        {snapshot.disabledReason ? <li>Stripe is holding this account: {snapshot.disabledReason.replace(/_/g, " ")}</li> : null}
        {snapshot.requirementsDue.length > 0 ? <li>Stripe still needs: {snapshot.requirementsDue.join(", ")}</li> : null}
        {snapshot.requirementsDeadline ? <li>Deadline: {snapshot.requirementsDeadline}</li> : null}
      </ul>
      <p className="mt-1 text-xs text-dim">Read from Stripe just now. This says nothing about money having moved.</p>
    </div>
  );
}
