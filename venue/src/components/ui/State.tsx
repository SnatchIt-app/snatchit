import type { ReactNode } from "react";

/** Spec §18 — every surface declares loading · empty · error · permission-denied. These are the shared renderers. */

export function Skeleton({ rows = 5, className = "" }: { rows?: number; className?: string }) {
  return (
    <div className={`space-y-2 ${className}`} role="status" aria-live="polite" aria-label="Loading">
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="skel" style={{ width: `${88 - (i % 3) * 14}%` }} />
      ))}
      <span className="sr-only">Loading…</span>
    </div>
  );
}

export function EmptyState({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="border border-line-neutral p-6 text-center">
      <p className="text-muted">{title}</p>
      {children ? <div className="mt-3 flex justify-center gap-2">{children}</div> : null}
    </div>
  );
}

/** Spec §19.7 — errors carry the server's reason; the preview names the read that failed. */
export function ErrorState({ read, retryHref }: { read: string; retryHref: string }) {
  return (
    <div className="border border-danger/50 bg-primary-soft p-4" role="alert">
      <p className="font-bold">Couldn&apos;t load</p>
      <p className="mt-1 text-sm text-muted">
        The read <code className="font-mono text-xs">{read}</code> failed. Nothing on this surface is shown stale-optimistic.
      </p>
      <a className="btn btn-ghost btn-sm mt-3" href={retryHref}>
        Retry
      </a>
    </div>
  );
}

/** Spec §18 standard denial: existence, name and counts are NOT revealed. */
export function DeniedState({ alternative }: { alternative?: { label: string; href: string } }) {
  return (
    <div className="mx-auto max-w-md border border-line-neutral p-8 text-center" role="alert">
      <p className="text-lg font-bold">You don&apos;t have access to this.</p>
      {alternative ? (
        <a className="link mt-3 inline-block text-sm" href={alternative.href}>
          {alternative.label}
        </a>
      ) : null}
    </div>
  );
}

export function PartialCell({ why }: { why: string }) {
  return (
    <span className="text-dim" title={why} aria-label={why}>
      —
    </span>
  );
}

/** Spec §3.2 — below `lg` the money/capacity/price/role surfaces are read-only. */
export function LargerScreenBanner() {
  return <p className="border border-warning/40 bg-warning/10 px-3 py-2 text-xs text-warning lg:hidden">Open on a larger screen to edit. This view is read-only on tablet and phone.</p>;
}
