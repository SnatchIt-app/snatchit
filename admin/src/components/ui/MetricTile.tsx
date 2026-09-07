import Link from "next/link";
import type { ReactNode } from "react";
import { NOT_AVAILABLE_LOCALLY } from "@/lib/metrics";

/**
 * One number with its definition attached (<abbr title>) — the console never
 * shows a figure the operator has to guess the meaning of. `notTracked`
 * renders the honest "not tracked" style instead of a value; `value={null}`
 * renders "not available locally" (with `note`) — a bound or estimate may be
 * passed as `sub`, never as the headline.
 */
export function MetricTile({
  label,
  value,
  definition,
  href,
  sub,
  note,
  notTracked = false,
}: {
  label: ReactNode;
  /** null = not knowable from local data. */
  value: ReactNode | null;
  definition?: string | null;
  href?: string | null;
  sub?: ReactNode;
  /** Caveat printed under the headline (e.g. why the value is unavailable). */
  note?: string | null;
  notTracked?: boolean;
}) {
  const unavailable = notTracked || value === null;
  const headline = notTracked ? "not tracked" : value === null ? NOT_AVAILABLE_LOCALLY : value;
  const heading = definition ? (
    <abbr title={definition} className="cursor-help no-underline">
      {label}
    </abbr>
  ) : (
    label
  );
  const body = (
    <>
      <p className="eyebrow text-dim">{heading}</p>
      <p className={`mt-1 ${unavailable ? "text-base font-semibold text-dim" : "text-xl font-bold text-ink"} tabular-nums`}>{headline}</p>
      {note ? <p className="mt-1 text-[11px] text-warning">{note}</p> : null}
      {sub ? <p className="mt-1 text-[11px] text-dim">{sub}</p> : null}
    </>
  );
  if (href) {
    return (
      <Link href={href} className="block bg-card p-3 transition-colors hover:bg-primary-soft focus-visible:bg-primary-soft">
        {body}
      </Link>
    );
  }
  return <div className={`bg-card p-3 ${unavailable ? "bg-[repeating-linear-gradient(135deg,transparent_0_6px,rgba(255,255,255,0.03)_6px_12px)]" : ""}`}>{body}</div>;
}

export function MetricGrid({ children, cols = 4 }: { children: ReactNode; cols?: 2 | 3 | 4 | 6 }) {
  const md = cols === 6 ? "md:grid-cols-6" : cols === 3 ? "md:grid-cols-3" : cols === 2 ? "md:grid-cols-2" : "md:grid-cols-4";
  return <div className={`grid grid-cols-2 gap-px border border-line-neutral bg-line-neutral ${md}`}>{children}</div>;
}
