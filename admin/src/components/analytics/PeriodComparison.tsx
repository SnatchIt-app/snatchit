import { compareWindows, formatUsdExact, type Comparison, type MoneyFigures } from "@/lib/analytics-core";
import { CURRENCY, TIMEZONE } from "@/lib/figure-meta";

type Unit = "usd_cents" | "count";

/** The four period measures. Seller funds pending is point in time and bank payouts are not tracked, so neither is compared. */
const ROWS: { key: string; label: string; unit: Unit; pick: (f: MoneyFigures) => number | null }[] = [
  { key: "captured", label: "Captured sales", unit: "usd_cents", pick: (f) => f.capturedCents },
  { key: "fees", label: "Platform fees (gross)", unit: "usd_cents", pick: (f) => f.feesCents },
  { key: "refunds", label: "Fully refunded payments", unit: "count", pick: (f) => f.refundCount },
  { key: "released", label: "Seller funds released", unit: "usd_cents", pick: (f) => f.releasedCents },
];

const fmt = (unit: Unit, v: number) => (unit === "usd_cents" ? formatUsdExact(v) : v.toLocaleString("en-US"));

/** The signed change: "+$500.00 (+61%)", "−1 (−50%)", "±$0.00 (no change)", "+$22,500.00 (none in previous period)". */
export function changeText(c: Comparison, unit: Unit, previousRead: boolean): string {
  if (c.kind === "na") return previousRead ? "n/a — not returned by the server" : "n/a — previous period couldn't be read";
  const qualifier = c.pct === null ? "none in previous period" : c.pct === 0 ? "no change" : `${c.sign}${Math.abs(c.pct)}%`;
  return `${c.sign}${fmt(unit, Math.abs(c.change))} (${qualifier})`;
}

/**
 * The period-over-previous-period comparison ops.money_overview already
 * provides: the caller read both windows. Both periods are named in the
 * header, every change carries its sign, and a window that could not be read
 * is "n/a" — never a zero and never a change computed from a guess. The pair
 * of bars per row compares the SAME measure across the two periods (one
 * measure per axis); it is decorative, the cells carry the figures.
 */
export function PeriodComparison({
  currentLabel,
  previousLabel,
  current,
  previous,
}: {
  currentLabel: string;
  previousLabel: string;
  current: MoneyFigures;
  /** null = the previous window could not be read. */
  previous: MoneyFigures | null;
}) {
  return (
    <div className="overflow-x-auto">
      <table className="data-table text-[0.8125rem]">
        <caption className="sr-only">{`Period comparison: ${currentLabel} (current) against ${previousLabel} (previous). ${CURRENCY} amounts and counts over ${TIMEZONE} calendar days.`}</caption>
        <thead>
          <tr>
            <th scope="col">Measure</th>
            <th scope="col" className="num">{`${currentLabel} (current)`}</th>
            <th scope="col" className="num">{`${previousLabel} (previous)`}</th>
            <th scope="col">Change</th>
          </tr>
        </thead>
        <tbody>
          {ROWS.map((r) => {
            const cur = r.pick(current);
            const prev = previous ? r.pick(previous) : null;
            const c = compareWindows(cur, prev);
            const max = c.kind === "ok" ? Math.max(Math.abs(c.current), Math.abs(c.previous)) : 0;
            const width = (v: number) => (max === 0 ? 0 : Math.round((Math.abs(v) / max) * 100));
            return (
              <tr key={r.key}>
                <th scope="row" className="font-medium text-ink">
                  {r.label}
                </th>
                <td className="num">{cur === null ? "n/a" : fmt(r.unit, cur)}</td>
                <td className="num">{prev === null ? "n/a" : fmt(r.unit, prev)}</td>
                <td>
                  <span className={c.kind === "na" ? "text-muted" : "tabular-nums text-ink"}>{changeText(c, r.unit, previous !== null)}</span>
                  {c.kind === "ok" ? (
                    <div data-compare-bars="" aria-hidden="true" className="mt-1.5 flex w-full max-w-[12rem] flex-col gap-0.5">
                      <span className="h-1.5 rounded-full bg-[var(--color-series-1)]" style={{ width: `${width(c.current)}%` }} />
                      <span className="h-1.5 rounded-full bg-[var(--color-series-2)]" style={{ width: `${width(c.previous)}%` }} />
                    </div>
                  ) : null}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
