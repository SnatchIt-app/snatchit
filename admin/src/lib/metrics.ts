import { formatMoney } from "@/lib/format";
import type { MoneyMetric } from "@/lib/types";

/**
 * How a money metric is shown. Pure and unit-tested: a metric whose value is
 * unknowable locally (value_cents = null) NEVER gets a number as its headline
 * — the upper bound is secondary text only.
 */
export type MetricDisplay = {
  /** Headline text in the tile. */
  headline: string;
  /** true when the headline is the honest placeholder rather than a figure. */
  unavailable: boolean;
  /** Secondary line: the bound + count when unavailable, count + range otherwise. */
  secondary: string | null;
  /** Server-provided caveat, shown verbatim when present. */
  note: string | null;
};

export const NOT_AVAILABLE_LOCALLY = "not available locally";

export type MetricFacts = Omit<MoneyMetric, "key" | "currency" | "source">;

export function metricDisplay(m: MetricFacts): MetricDisplay {
  if (!m.tracked) {
    return { headline: "not tracked", unavailable: true, secondary: m.definition, note: m.note };
  }
  const countText = m.count !== null ? `${m.count.toLocaleString("en-US")} row${m.count === 1 ? "" : "s"}` : null;
  const rangeText = m.from && m.to ? `${m.from} → ${m.to}` : m.basis === "now()" ? "point in time (now)" : m.basis;
  if (m.value_cents === null) {
    const bound = m.upper_bound_cents !== null ? `upper bound ${formatMoney(m.upper_bound_cents)}` : null;
    return {
      headline: NOT_AVAILABLE_LOCALLY,
      unavailable: true,
      secondary: [countText, bound, rangeText].filter(Boolean).join(" · ") || null,
      note: m.note,
    };
  }
  return {
    headline: formatMoney(m.value_cents),
    unavailable: false,
    secondary: [countText, rangeText].filter(Boolean).join(" · ") || null,
    note: m.note,
  };
}
