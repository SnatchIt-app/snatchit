import type { ReadFailure } from "@/lib/db/read-result";

/**
 * Database-mode failures, stated explicitly (never a fixture substitution):
 * auth · permission · config · not_exposed · transport · error.
 */
export function DataSourceError({ failure, loginHref, retryHref }: { failure: ReadFailure; loginHref: string; retryHref: string }) {
  const code = failure.code ? <code className="font-mono text-xs"> [{failure.code}]</code> : null;
  switch (failure.kind) {
    case "auth":
      return (
        <div className="mx-auto max-w-md border border-line-neutral p-6 text-center" role="alert">
          <p className="text-lg font-bold">Sign in to continue</p>
          <p className="mt-1 text-sm text-muted">This dashboard reads as you. There is no session, or it has expired.{code}</p>
          <a className="btn btn-primary btn-sm mt-4" href={loginHref}>
            Sign in
          </a>
        </div>
      );
    case "permission":
      return (
        <div className="mx-auto max-w-md border border-line-neutral p-6 text-center" role="alert">
          <p className="text-lg font-bold">You don&apos;t have access to this.</p>
          <p className="mt-1 text-sm text-muted">The database refused the read for your account.{code}</p>
        </div>
      );
    case "not_exposed":
      return (
        <div className="border border-warning bg-warning/10 p-4" role="alert">
          <p className="font-bold">Database mode is not fully configured</p>
          <p className="mt-1 text-sm">
            The Data API does not expose the <code className="font-mono">venue_api</code> schema on this project, so <code className="font-mono">{failure.read}</code> cannot be read.{code} This is an owner configuration step; nothing was substituted.
          </p>
        </div>
      );
    case "config":
      return (
        <div className="border border-warning bg-warning/10 p-4" role="alert">
          <p className="font-bold">Database mode is not configured</p>
          <p className="mt-1 text-sm">{failure.message}{code}</p>
        </div>
      );
    case "transport":
      return (
        <div className="border border-danger/50 bg-primary-soft p-4" role="alert">
          <p className="font-bold">Couldn&apos;t reach the database</p>
          <p className="mt-1 text-sm text-muted">
            <code className="font-mono text-xs">{failure.read}</code>: {failure.message}.{code} Nothing is shown stale.
          </p>
          <a className="btn btn-ghost btn-sm mt-3" href={retryHref}>
            Retry
          </a>
        </div>
      );
    default:
      return (
        <div className="border border-danger/50 bg-primary-soft p-4" role="alert">
          <p className="font-bold">Couldn&apos;t load</p>
          <p className="mt-1 text-sm text-muted">
            <code className="font-mono text-xs">{failure.read}</code> failed: {failure.message}{code}
          </p>
          <a className="btn btn-ghost btn-sm mt-3" href={retryHref}>
            Retry
          </a>
        </div>
      );
  }
}

/** Surfaces that are fixture-only in this slice say so in database mode instead of showing sample data. */
export function NotWiredState({ surface }: { surface: string }) {
  return (
    <div className="border border-line-neutral p-6 text-center" role="status">
      <p className="font-bold">{surface} is not wired to the database yet</p>
      <p className="mt-1 text-sm text-muted">Slice 1 covers the events list and event setup (read side). Switch to fixture mode to review this surface&apos;s design; sample data is never shown in database mode.</p>
    </div>
  );
}
