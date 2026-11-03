import type { ReactNode } from "react";

/**
 * Chart container: title, one-line definition (units · range · grain), the surface's
 * labels (period, timezone, currency, freshness — `meta`), the chart, and a data-table
 * twin that holds every plotted value (tooltips never gate data).
 *
 * Four states, each explicit (`data-state`): `ok` draws the plot; `empty` means every
 * period had zero rows (nothing is drawn rather than a flat line); `unavailable` means
 * the server returned no figure for this measure (nothing is drawn rather than an empty
 * chart, and it is not called empty); `error` means the read failed (an alert, never a
 * zero).
 */
export function ChartCard({
  title,
  description,
  meta,
  definition,
  state,
  children,
  table,
  footnote,
}: {
  title: string;
  /** Units, range and grain, e.g. "USD per day · Aug 16 – Sep 14 (UTC)". */
  description: ReactNode;
  /** The FigureMeta line for this chart. */
  meta?: ReactNode;
  /** What the measure is and is not. */
  definition?: ReactNode;
  state: { kind: "ok" } | { kind: "empty"; message: ReactNode } | { kind: "unavailable"; message: ReactNode } | { kind: "error"; message: ReactNode };
  children?: ReactNode;
  table?: { caption: string; head: string[]; rows: (string | number)[][] };
  footnote?: ReactNode;
}) {
  const isError = state.kind === "error";
  return (
    <figure className="rounded-[var(--radius-card)] border border-line bg-card p-5" data-state={state.kind}>
      <figcaption>
        <h3 className="title-section !text-[1.25rem]">{title}</h3>
        <p className="mt-0.5 text-[0.8125rem] text-dim">{description}</p>
        {meta ? <div className="mt-1">{meta}</div> : null}
      </figcaption>
      <div className="mt-4">
        {state.kind === "ok" ? (
          children
        ) : (
          <div
            role={isError ? "alert" : "status"}
            className={`flex min-h-[180px] flex-col items-center justify-center rounded-[var(--radius-control)] border border-dashed px-6 text-center text-[0.875rem] ${
              isError ? "border-danger/40 bg-danger-soft/40 text-ink" : "border-line-strong bg-canvas text-muted"
            }`}
          >
            <span aria-hidden="true" className={`mb-2 flex h-6 w-6 items-center justify-center rounded-full text-[0.75rem] font-bold ${isError ? "bg-danger-soft text-danger" : "bg-raised text-dim"}`}>
              {isError ? "✕" : state.kind === "unavailable" ? "?" : "–"}
            </span>
            {state.kind === "unavailable" ? <span className="mb-1 font-medium text-ink">Not available</span> : null}
            {state.message}
          </div>
        )}
      </div>
      {definition ? <p className="mt-3 text-[0.75rem] leading-relaxed text-dim">{definition}</p> : null}
      {footnote ? <p className="mt-1 text-[0.75rem] text-dim">{footnote}</p> : null}
      {table && state.kind === "ok" ? (
        <details className="mt-3 rounded-[var(--radius-control)] border border-line">
          <summary className="rounded-[var(--radius-control)] px-3 py-2 text-[0.8125rem] font-medium text-muted">View data table</summary>
          <div className="max-h-72 overflow-auto">
            <table className="data-table">
              <caption className="sr-only">{table.caption}</caption>
              <thead>
                <tr>
                  {table.head.map((h, i) => (
                    <th key={h} scope="col" className={i > 0 ? "num" : undefined}>
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {table.rows.map((r, ri) => (
                  <tr key={ri}>
                    {r.map((c, ci) => (
                      <td key={ci} className={ci > 0 ? "num" : undefined}>
                        {c}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </details>
      ) : null}
    </figure>
  );
}

/** Loading frame with the chart's final footprint (no layout jump when data arrives). */
export function ChartSkeleton({ title }: { title: string }) {
  return (
    <figure className="rounded-[var(--radius-card)] border border-line bg-card p-5" aria-busy="true">
      <figcaption>
        <h3 className="title-section !text-[1.25rem]">{title}</h3>
        <p className="mt-0.5 text-[0.8125rem] text-dim">Loading…</p>
      </figcaption>
      <div className="mt-4 h-[220px] animate-pulse rounded-[var(--radius-control)] bg-[linear-gradient(to_top,var(--color-raised)_1px,transparent_1px)] bg-[length:100%_55px]" role="status" aria-label={`Loading ${title}`} />
    </figure>
  );
}
