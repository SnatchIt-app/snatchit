import type { BreakdownItem } from "@/lib/breakdown";
import { statusVariant, type BadgeVariant } from "@/components/ui/StatusBadge";

/** Bar and swatch fills from the status vocabulary's tones; the brand series colour for anything else. */
const FILL: Record<BadgeVariant, string> = {
  neutral: "bg-[var(--color-series-1)]",
  ok: "bg-[var(--color-success)]",
  warn: "bg-[var(--color-warning)]",
  danger: "bg-[var(--color-danger)]",
  info: "bg-[var(--color-info)]",
  muted: "bg-[var(--color-series-2)]",
};

const pct = (share: number) => Math.round(share * 100);

/**
 * One measure — a count of rows — broken down by status: a stacked bar (decorative)
 * and the legend that is the accessible form, each bucket with its count and share.
 * The scope ("on this page") is part of the label because the rows are one page of a
 * list read, never the whole table. No rows is an explicit empty state, not an empty bar.
 */
export function StatusBreakdown({ title, noun, scope, total, items }: { title: string; noun: string; scope: string; total: number; items: BreakdownItem[] }) {
  return (
    <div data-breakdown="" className="min-w-0">
      <p className="flex flex-wrap items-baseline justify-between gap-x-3 text-[0.8125rem]">
        <span className="font-medium text-ink">{title}</span>
        <span className="text-dim">
          {total.toLocaleString("en-US")} {noun} {scope}
        </span>
      </p>
      {total === 0 ? (
        <p role="status" className="mt-1 text-[0.8125rem] text-muted">
          No {noun} {scope}.
        </p>
      ) : (
        <>
          <div data-breakdown-bar="" aria-hidden="true" className="mt-2 flex h-2.5 w-full overflow-hidden rounded-full bg-[rgba(70,50,30,0.08)]">
            {items.map((it) => (
              <span key={it.key} className={`h-full ${FILL[statusVariant(it.tone)]}`} style={{ width: `${pct(it.share)}%` }} />
            ))}
          </div>
          <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-[0.75rem]">
            {items.map((it) => (
              <li key={it.key} className="flex items-baseline gap-1.5">
                <span aria-hidden="true" className={`inline-block h-2 w-2 shrink-0 rounded-full ${FILL[statusVariant(it.tone)]}`} />
                <span className="text-muted">{it.label}</span>
                <span className="tabular-nums text-ink">{it.count.toLocaleString("en-US")}</span>
                <span className="tabular-nums text-dim">({pct(it.share)}%)</span>
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}
