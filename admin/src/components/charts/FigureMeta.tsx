import type { ReactNode } from "react";
import { asOfLabel, CURRENCY, isPartialPeriod, PARTIAL_LABEL, POINT_IN_TIME_LABEL, rangeLabel, readFailedLabel, REPORT_DAY_BASIS } from "@/lib/figure-meta";

/**
 * The one line every figure surface carries: the period (or "point in time")
 * and the calendar day it is counted in, the currency where money is shown, the
 * freshness of this read (its time carries EST/EDT) and the partial mark when the
 * period includes today. `readAt` is the time
 * the server component rendered the request — per request, never cached —
 * and is the only clock the partial mark is derived from.
 *
 * `notice` is the slot for DC-2's "N test records hidden" notice
 * (components/ui/HiddenTestRowsNotice.tsx); nothing passes it yet.
 */
export function FigureMeta({
  range,
  pointInTime = false,
  currency,
  computedAt,
  readAt,
  failed = false,
  notice,
  className = "",
}: {
  /** Inclusive calendar days the figures cover, in REPORT_DAY_BASIS (the server's day). */
  range?: { from: string; to: string };
  /** The figures have no date predicate (counts "now"). */
  pointInTime?: boolean;
  /** Pass CURRENCY for money surfaces; omit for counts. */
  currency?: typeof CURRENCY;
  /** The server's computed_at; null or undefined renders "not stated by the server". */
  computedAt?: string | null;
  /** Time of this read (server render). */
  readAt: Date;
  /** The read failed: no freshness and no partial mark are claimed. */
  failed?: boolean;
  notice?: ReactNode;
  className?: string;
}) {
  const parts: string[] = [];
  // The as-of time below prints its own EST/EDT, so only a period needs a day basis.
  if (pointInTime) parts.push(POINT_IN_TIME_LABEL);
  else if (range) parts.push(rangeLabel(range.from, range.to), `${REPORT_DAY_BASIS} calendar days`);
  if (currency) parts.push(currency);
  parts.push(failed ? readFailedLabel(readAt) : asOfLabel(computedAt, readAt));
  if (!failed && !pointInTime && range && isPartialPeriod(range.to, readAt)) parts.push(PARTIAL_LABEL);
  return (
    <p data-figure-meta="" className={`text-[0.75rem] leading-relaxed text-dim ${className}`}>
      {parts.join(" · ")}
      {notice ? <span className="block">{notice}</span> : null}
    </p>
  );
}
