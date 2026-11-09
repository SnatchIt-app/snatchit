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
      <p className="text-[0.8125rem] font-medium text-muted">{heading}</p>
      <p className={`mt-2 ${unavailable ? "text-[0.9375rem] font-medium text-dim" : "stat-num !text-[2rem] text-ink"}`}>{headline}</p>
      {note ? <p className="mt-1.5 text-[0.75rem] text-warning">{note}</p> : null}
      {sub ? <p className="mt-1 text-[0.75rem] text-dim">{sub}</p> : null}
    </>
  );
  if (href) {
    return (
      <Link href={href} className="group block h-full bg-[#fffdfa] p-5 transition-colors hover:bg-white focus-visible:bg-white">
        {body}
      </Link>
    );
  }
  return <div className={`h-full bg-[#fffdfa] p-5 ${unavailable ? "bg-[repeating-linear-gradient(135deg,transparent_0_6px,rgba(70,50,30,0.04)_6px_12px)]" : ""}`}>{body}</div>;
}

export function MetricGrid({ children, cols = 4 }: { children: ReactNode; cols?: 2 | 3 | 4 | 6 }) {
  const md = cols === 6 ? "md:grid-cols-6" : cols === 3 ? "md:grid-cols-3" : cols === 2 ? "md:grid-cols-2" : "md:grid-cols-4";
  // Grouped figures (approved concept): one quiet panel, cells divided by hairlines.
  return <div className={`grid grid-cols-1 gap-px overflow-hidden rounded-[var(--radius-panel)] border border-[rgba(70,50,30,0.09)] bg-[rgba(70,50,30,0.09)] min-[420px]:grid-cols-2 ${md}`}>{children}</div>;
}
