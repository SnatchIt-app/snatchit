import type { ReactNode } from "react";
import { Icon, type IconName } from "@/components/ui/Icon";

function StateCard({ icon, tone = "neutral", children, role }: { icon: IconName; tone?: "neutral" | "danger"; children: ReactNode; role?: "alert" }) {
  return (
    <div className="panel enter mx-auto flex max-w-xl flex-col items-center px-6 py-12 text-center md:px-10" role={role}>
      <span className={`grid h-12 w-12 place-items-center rounded-full ${tone === "danger" ? "bg-[rgba(196,29,21,0.08)] text-danger" : "bg-[#f5f3ef] text-ink"}`}>
        <Icon name={icon} size={22} />
      </span>
      {children}
    </div>
  );
}

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
    <StateCard icon="calendar">
      <p className="mt-4 max-w-md text-[1rem] font-medium leading-relaxed">{title}</p>
      {children ? <div className="mt-5 flex flex-wrap items-center justify-center gap-3">{children}</div> : null}
    </StateCard>
  );
}

/**
 * Spec §19.7 — errors carry the server's reason. Audit §P4: lead with what the
 * manager lost and what to do about it; the internal read name stays, as
 * secondary detail for whoever they call, not as the headline.
 */
export function ErrorState({ read, retryHref, lost = "This page" }: { read: string; retryHref: string; lost?: string }) {
  return (
    <StateCard icon="alert" tone="danger" role="alert">
      <p className="title-section mt-4 text-[1.25rem]">{lost} couldn&apos;t be loaded.</p>
      <p className="mt-2 max-w-md text-[0.9375rem] leading-relaxed text-muted">
        Nothing is shown rather than showing you numbers that might be out of date. Try again; if it keeps failing, the rest of the dashboard still works.
      </p>
      <a className="btn btn-primary mt-6" href={retryHref}>
        Try again
      </a>
      <details className="mt-5 text-[0.8125rem] text-muted">
        <summary className="inline-flex min-h-8 items-center gap-1 hover:text-ink">For support</summary>
        <p className="mt-1">
          The read that failed was <code className="font-mono">{read}</code>.
        </p>
      </details>
    </StateCard>
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
    <StateCard icon="users" role="alert">
      <p className="title-section mt-4 text-[1.25rem]">{surface} isn&apos;t open to you.</p>
      <p className="mt-3 max-w-md text-[0.9375rem] leading-relaxed text-muted">{reason ?? (roleLabel ? `Your role here is ${roleLabel}, and that role doesn't include this screen.` : "Your role at this venue doesn't include this screen.")}</p>
      <p className="mt-2 max-w-md text-[0.875rem] leading-relaxed text-muted">
        {grantedBy} can give you access. Nothing about this screen&apos;s contents is shown either way — this is not a message about whether anything exists.
      </p>
      {alternative ? (
        <a className="btn btn-primary mt-6" href={alternative.href}>
          {alternative.label}
        </a>
      ) : null}
    </StateCard>
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
  // Measured at 4.35:1 as warning-on-warning-tint, under AA. The tinted band
  // goes; a left rule carries the same signal and the text sits on white,
  // which is how the error and denied states already read.
  return (
    <p className="border-l-2 border-warning py-1.5 pl-3 text-sm text-muted lg:hidden">
      <span className="font-semibold text-ink">Read-only on this screen size.</span> Open on a larger screen to make changes here.
    </p>
  );
}
