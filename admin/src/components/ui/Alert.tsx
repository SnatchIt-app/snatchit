import Link from "next/link";
import type { ReactNode } from "react";
import type { OpsFailure } from "@/lib/ops-errors";

export type AlertState = "loading" | "empty" | "denied" | "failed" | "stale" | "mfa" | "info" | "success" | "warning";

const STYLES: Record<AlertState, { tone: string; label: string; glyph: string }> = {
  loading: { tone: "bg-raised text-dim", label: "Loading", glyph: "…" },
  empty: { tone: "bg-raised text-dim", label: "Nothing here", glyph: "–" },
  denied: { tone: "bg-danger-soft text-danger", label: "Access denied", glyph: "✕" },
  failed: { tone: "bg-danger-soft text-danger", label: "Failed", glyph: "✕" },
  stale: { tone: "bg-warning-soft text-warning", label: "Stale", glyph: "!" },
  mfa: { tone: "bg-warning-soft text-warning", label: "Step-up required", glyph: "!" },
  info: { tone: "bg-info-soft text-info", label: "Info", glyph: "i" },
  success: { tone: "bg-success-soft text-success", label: "Done", glyph: "✓" },
  warning: { tone: "bg-warning-soft text-warning", label: "Warning", glyph: "!" },
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
      className={`flex gap-3 rounded-[var(--radius-control)] border border-line bg-card ${compact ? "px-3 py-2" : "px-4 py-3"} text-[14px]`}
    >
      <span aria-hidden="true" className={`mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[11px] font-bold ${s.tone}`}>
        {s.glyph}
      </span>
      <div className="min-w-0">
      <p className="font-medium text-ink">
        <span className="sr-only">{s.label}: </span>
        {title ?? s.label}
      </p>
      {children ? <div className="mt-0.5 text-[13px] text-muted">{children}</div> : null}
      {retryHref ? (
        <p className="mt-2">
          <Link href={retryHref} className="link text-[13px]">
            {retryLabel}
          </Link>
        </p>
      ) : null}
      </div>
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
  if (failure.kind === "paused") {
    return (
      <Alert state="warning" title="Actions are paused by a founder — read-only until re-enabled from System → Settings." retryHref="/system#setting-actions_enabled" retryLabel="Open settings">
        Nothing was changed. ops.setting <code className="font-mono">actions_enabled</code> is false; every mutation is refused until a platform_admin sets it back to true.
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
