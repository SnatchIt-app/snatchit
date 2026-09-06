import Link from "next/link";
import type { ReactNode } from "react";
import type { OpsFailure } from "@/lib/ops-errors";

export type AlertState = "loading" | "empty" | "denied" | "failed" | "stale" | "mfa" | "info" | "success" | "warning";

const STYLES: Record<AlertState, { border: string; label: string }> = {
  loading: { border: "border-line-neutral", label: "Loading" },
  empty: { border: "border-line-neutral", label: "Nothing here" },
  denied: { border: "border-danger", label: "Access denied" },
  failed: { border: "border-danger", label: "Failed" },
  stale: { border: "border-warning", label: "Stale" },
  mfa: { border: "border-warning", label: "Step-up required" },
  info: { border: "border-info", label: "Info" },
  success: { border: "border-success", label: "Done" },
  warning: { border: "border-warning", label: "Warning" },
};

/**
 * Every non-happy state in the console goes through here so the wording and
 * the retry affordance are consistent. Text always carries the state — never
 * colour alone.
 */
export function Alert({
  state,
  title,
  children,
  retryHref,
  retryLabel = "Retry",
  compact = false,
}: {
  state: AlertState;
  title?: ReactNode;
  children?: ReactNode;
  retryHref?: string;
  retryLabel?: string;
  compact?: boolean;
}) {
  const s = STYLES[state];
  return (
    <div
      role={state === "failed" || state === "denied" ? "alert" : "status"}
      aria-live="polite"
      className={`border-l-2 ${s.border} bg-card ${compact ? "px-3 py-2" : "px-4 py-3"} text-[13px]`}
    >
      <p className="font-semibold text-ink">
        <span className="eyebrow mr-2 text-dim">{s.label}</span>
        {title}
      </p>
      {children ? <div className="mt-1 text-muted">{children}</div> : null}
      {retryHref ? (
        <p className="mt-2">
          <Link href={retryHref} className="link text-[12px]">
            {retryLabel}
          </Link>
        </p>
      ) : null}
    </div>
  );
}

/** Render an OpsFailure with the right state and copy. */
export function OpsFailureAlert({ failure, retryHref, fn }: { failure: OpsFailure; retryHref?: string; fn?: string }) {
  if (failure.kind === "denied") {
    return (
      <Alert state="denied" title="Your account is not allowed to do this.">
        The database refused the call ({fn ? `ops.${fn}` : "ops"}). If you were recently granted a role, sign out
        and back in.
      </Alert>
    );
  }
  if (failure.kind === "mfa") {
    return (
      <Alert state="mfa" title="Re-verify with your authenticator to continue." retryHref="/mfa" retryLabel="Go to MFA">
        The database requires a fresh aal2 session for this operation.
      </Alert>
    );
  }
  return (
    <Alert state="failed" title={failure.unavailable ? "RPC not available yet" : "Request failed"} retryHref={retryHref}>
      {failure.message}
      {failure.code ? <span className="ml-2 font-mono text-[11px] text-dim">{failure.code}</span> : null}
    </Alert>
  );
}
