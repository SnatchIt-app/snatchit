/**
 * The labels every figure surface carries (owner requirement, 2026-10-22):
 * the date range covered, the currency, the timezone the dates are shown in,
 * the freshness of this read, and whether the current period is still
 * accumulating. Pure, no I/O; the components render what these return.
 *
 * Every claim here is taken from the formatters the console already uses:
 * `formatMoney` prints "… USD", `formatUtc` prints "… UTC", and the analytics
 * buckets are UTC calendar days (`isoDay` / `shortDay` read the UTC fields).
 */
import { formatUtc, parseDate } from "@/lib/format";
import { isoDay, parseIsoDay } from "@/lib/analytics-core";

/** The platform is single-currency; `formatMoney` prints this code after every amount. */
export const CURRENCY = "USD";

/** Every timestamp is UTC wall clock (`formatUtc`) and every period is a UTC calendar day (`isoDay`). */
export const TIMEZONE = "UTC";

/** The current UTC day is still accumulating rows; a period that includes it is not final. */
export const PARTIAL_LABEL = "includes today so far (partial)";

/** Counts with no date predicate (ops.today(), seller funds pending, job_health). */
export const POINT_IN_TIME_LABEL = "Point in time (now), not a period";

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function dayText(d: Date, withYear: boolean): string {
  const base = `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}`;
  return withYear ? `${base}, ${d.getUTCFullYear()}` : base;
}

/**
 * "Sep 23 – Oct 22, 2026" for two inclusive UTC calendar days; the year is
 * printed once unless the range crosses it. Malformed input is shown raw so
 * nothing is guessed.
 */
export function rangeLabel(from: string, to: string): string {
  const a = parseIsoDay(from);
  const b = parseIsoDay(to);
  if (!a || !b) return `${from} – ${to}`;
  if (from === to) return dayText(a, true);
  const sameYear = a.getUTCFullYear() === b.getUTCFullYear();
  return `${dayText(a, !sameYear)} – ${dayText(b, true)}`;
}

/**
 * Freshness of this read. The server's `computed_at` (its own clock when it
 * ran the aggregate) is the only honest "as of"; when the payload has none,
 * say so and give the console's read time, never the read time as if it were
 * the data's time.
 */
export function asOfLabel(computedAt: string | null | undefined, readAt: Date): string {
  const d = parseDate(computedAt ?? null);
  if (d) return `as of ${formatUtc(d, true)}`;
  return `as of: not stated by the server (read ${formatUtc(readAt, true)})`;
}

/** The read did not succeed: no freshness is claimed and nothing is shown. */
export function readFailedLabel(readAt: Date): string {
  return `read at ${formatUtc(readAt, true)} failed — nothing is shown`;
}

/** True when the range's last day is today (UTC) or later, i.e. still accumulating. */
export function isPartialPeriod(to: string, now: Date): boolean {
  if (!parseIsoDay(to)) return false;
  // ISO days compare lexically.
  return to >= isoDay(now);
}

/**
 * How one figure is shown. `empty` is a genuine aggregate with no rows (the
 * zero stays, labelled); `unavailable` is a measure the server did not return
 * (no figure is shown, not even a dash); `error` is a failed read.
 */
export type FigureState = { kind: "ok" } | { kind: "empty"; message: string } | { kind: "unavailable"; message: string } | { kind: "error"; message: string };

export const UNAVAILABLE_MESSAGE = "Not returned by the server for this period.";

/**
 * State of a KPI tile from the measure's value and row count. A null value is
 * unavailable; a known zero row count is empty; anything else — including a
 * zero sum whose count the server did not state — is a figure.
 */
export function tileState(value: number | null, count: number | null, noun: string, scope: "in this period" | "now" = "in this period"): FigureState {
  if (value === null) return { kind: "unavailable", message: UNAVAILABLE_MESSAGE };
  if (count === 0) return { kind: "empty", message: `No ${noun} ${scope}.` };
  return { kind: "ok" };
}
