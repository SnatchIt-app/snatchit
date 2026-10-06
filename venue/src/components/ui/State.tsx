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

/**
 * Spec §19.7 — errors carry the server's reason. Audit §P4: lead with what the
 * manager lost and what to do about it; the internal read name stays, as
 * secondary detail for whoever they call, not as the headline.
 */
export function ErrorState({ read, retryHref, lost = "This page" }: { read: string; retryHref: string; lost?: string }) {
  return (
    <div className="border border-danger/50 bg-primary-soft p-4" role="alert">
      <p className="font-bold">{lost} couldn&apos;t be loaded.</p>
      <p className="mt-1 text-sm text-muted">
        Nothing is shown rather than showing you numbers that might be out of date. Try again; if it keeps failing, the rest of the dashboard still works.
      </p>
      <a className="btn btn-ghost btn-sm mt-3" href={retryHref}>
        Try again
      </a>
      <p className="mt-3 text-xs text-dim">
        For support: the read that failed was <code className="font-mono">{read}</code>.
      </p>
    </div>
  );
}

/**
 * Spec §18 standard denial: existence, name and counts are NOT revealed.
 *
 * Audit §W2 — one denial component for both paths. It says what you were
 * trying to open, why your role cannot open it, who can change that, and
 * offers somewhere you *can* go, so a shared link is never a dead end. It
 * still reveals nothing about the resource itself: `surface` is the name of
 * the screen ("The door screen"), never the event, the venue or a count.
 */
export function DeniedState({
  surface = "This screen",
  roleLabel,
  reason,
  grantedBy = "A venue manager or an organization owner",
  alternative,
}: {
  surface?: string;
  roleLabel?: string;
  reason?: string;
  grantedBy?: string;
  alternative?: { label: string; href: string };
}) {
  return (
    <div className="mx-auto max-w-lg border border-line-neutral p-6" role="alert">
      <p className="text-lg font-bold">{surface} isn&apos;t open to you.</p>
      <p className="mt-2 text-sm text-muted">{reason ?? (roleLabel ? `Your role here is ${roleLabel}, and that role doesn't include this screen.` : "Your role at this venue doesn't include this screen.")}</p>
      <p className="mt-2 text-sm text-muted">
        {grantedBy} can give you access. Nothing about this screen&apos;s contents is shown either way — this is not a message about whether anything exists.
      </p>
      {alternative ? (
        <a className="btn btn-ghost btn-sm mt-4" href={alternative.href}>
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
