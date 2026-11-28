"use client";

import { useId, useState, type ReactNode } from "react";
import { SegmentedControl, SegmentedControlItem } from "@astryxdesign/core/SegmentedControl";

export type ChartTable = { caption: string; head: string[]; rows: (string | number)[][] };
type View = "chart" | "table" | "cards";

/** Presentation only: each view receives the same exact values and makes no reads. */
export function ChartViews({ title, table, children }: { title: string; table: ChartTable; children: ReactNode }) {
  const [view, setView] = useState<View>("chart");
  const id = useId();
  return (
    <div>
      <div className="mb-4">
        <SegmentedControl value={view} onChange={(value) => { if (value === "chart" || value === "table" || value === "cards") setView(value); }} label={`${title} view`} size="sm">
          <SegmentedControlItem value="chart" label="Chart" aria-controls={id} />
          <SegmentedControlItem value="table" label="Table" aria-controls={id} />
          <SegmentedControlItem value="cards" label="Cards" aria-controls={id} />
        </SegmentedControl>
      </div>
      <div id={id} aria-label={`${title}: ${view}`}>
        <div hidden={view !== "chart"}>{children}</div>
        <div hidden={view !== "table"} className="max-h-80 overflow-auto rounded-[var(--radius-control)] border border-line" tabIndex={view === "table" ? 0 : -1} role="region" aria-label={table.caption}>
          <table className="data-table">
            <caption className="sr-only">{table.caption}</caption>
            <thead><tr>{table.head.map((heading, i) => <th key={heading} scope="col" className={i > 0 ? "num" : undefined}>{heading}</th>)}</tr></thead>
            <tbody>{table.rows.map((row, ri) => <tr key={ri}>{row.map((value, ci) => ci === 0 ? <th key={ci} scope="row">{value}</th> : <td key={ci} className="num">{value}</td>)}</tr>)}</tbody>
          </table>
        </div>
        <div hidden={view !== "cards"}>
          <ul className="grid max-h-80 grid-cols-1 gap-2 overflow-auto sm:grid-cols-2" aria-label={table.caption}>
            {table.rows.map((row, ri) => <li key={ri} className="rounded-[var(--radius-control)] border border-line bg-canvas p-3">
              <p className="text-[0.8125rem] font-medium">{row[0]}</p>
              <dl>{row.slice(1).map((value, ci) => <div key={ci} className="mt-2"><dt className="text-[0.75rem] text-dim">{table.head[ci + 1]}</dt><dd className="text-lg tabular-nums">{value}</dd></div>)}</dl>
            </li>)}
          </ul>
        </div>
      </div>
    </div>
  );
}
