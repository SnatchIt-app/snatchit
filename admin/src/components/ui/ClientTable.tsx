"use client";

import { Fragment, useId, useState, type ReactNode } from "react";
import { nextSort, viewIndices, type SortDir, type SortState, type SortValue } from "@/lib/table-view";
import { Alert } from "@/components/ui/Alert";

/**
 * The client half of DataTable. The server renders every cell and passes them
 * here as React elements (serialisable; no functions cross the boundary) with
 * each row's underlying sort values and its filter text. This component only
 * re-orders or hides the rows it was given: it never fetches, never changes
 * the server's row set, and the page's server-side filters stay where they
 * are. Sort headers are native buttons (Enter / Space work), the sorted column
 * carries aria-sort, and the status line says the order applies to this page
 * only. Without JavaScript the server's order renders and the controls are inert.
 */
export type ClientColumn = {
  key: string;
  header: ReactNode;
  /** Plain text of the header, for the button's label. */
  headerText: string;
  align?: "left" | "right";
  className?: string;
  sortable: boolean;
  firstDir: SortDir;
};

export type ClientRow = {
  key: string;
  cells: ReactNode[];
  sort: Record<string, SortValue>;
  filter: string;
  selected?: boolean;
  card?: ReactNode;
};

const DIR_WORD: Record<SortDir, string> = { asc: "ascending", desc: "descending" };

export function ClientTable({
  caption,
  columns,
  rows,
  dense = false,
  filterable = false,
  emptyText,
  defaultSort = null,
  hasCards = false,
}: {
  caption?: ReactNode;
  columns: ClientColumn[];
  rows: ClientRow[];
  dense?: boolean;
  filterable?: boolean;
  emptyText: string;
  /** The order to render first (also the SSR order); null = the server's order. */
  defaultSort?: SortState;
  /** Rows carry a `card`: show the cards below `md` and the table from `md` up. */
  hasCards?: boolean;
}) {
  const [sort, setSort] = useState<SortState>(defaultSort);
  const [query, setQuery] = useState("");
  const statusId = useId();
  const filterId = useId();
  const shown = viewIndices(rows, sort, query);
  const sortedColumn = sort ? columns.find((c) => c.key === sort.key) : undefined;
  const anySortable = columns.some((c) => c.sortable);
  const dir = (v: SortValue) => (v === null || v === undefined ? "" : String(v));

  const status = [
    sortedColumn && sort ? `Sorted by ${sortedColumn.headerText}, ${DIR_WORD[sort.dir]} — this page only` : anySortable ? "Server order — sort applies to this page only" : null,
    filterable ? `${shown.length} of ${rows.length} row${rows.length === 1 ? "" : "s"} shown` : null,
  ]
    .filter(Boolean)
    .join(" · ");

  const body =
    rows.length === 0 ? (
      <Alert state="empty" compact>
        {emptyText}
      </Alert>
    ) : shown.length === 0 ? (
      <Alert state="empty" compact title="No rows on this page match the filter.">
        <button type="button" className="link" onClick={() => setQuery("")}>
          Clear the filter
        </button>
      </Alert>
    ) : null;

  return (
    <div className="min-w-0">
      {anySortable || filterable ? (
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2 px-1 pb-2 text-[0.75rem]">
          {filterable ? (
            <label htmlFor={filterId} className="flex min-w-0 flex-wrap items-center gap-2 text-muted">
              <span>Filter rows on this page</span>
              <input
                id={filterId}
                type="search"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                autoComplete="off"
                spellCheck={false}
                aria-describedby={statusId}
                className="field min-h-9 w-[min(16rem,calc(100vw-4rem))] py-1 text-[0.8125rem]"
              />
            </label>
          ) : null}
          <p id={statusId} role="status" aria-live="polite" className="min-w-0 text-dim">
            {status}
          </p>
        </div>
      ) : null}

      {hasCards ? (
        shown.length === 0 ? (
          <div className="md:hidden">{body}</div>
        ) : (
          <ul className="flex flex-col gap-2 md:hidden" aria-label={typeof caption === "string" ? caption : undefined}>
            {shown.map((i) => (
              <li key={rows[i].key}>{rows[i].card}</li>
            ))}
          </ul>
        )
      ) : null}

      <div className={`overflow-x-auto ${hasCards ? "hidden md:block" : ""}`}>
        <table className={`data-table ${dense ? "text-[0.8125rem]" : ""}`}>
          {caption ? <caption className="sr-only">{caption}</caption> : null}
          <thead>
            <tr>
              {columns.map((c) => {
                const active = sort?.key === c.key;
                return (
                  <th key={c.key} scope="col" className={`${c.align === "right" ? "num" : ""} ${c.className ?? ""}`} aria-sort={active && sort ? DIR_WORD[sort.dir] : undefined}>
                    {c.sortable ? (
                      <button
                        type="button"
                        aria-label={`Sort by ${c.headerText}`}
                        onClick={() => setSort((s) => nextSort(s, c.key, c.firstDir))}
                        className={`inline-flex min-h-7 items-center gap-1 rounded-md uppercase tracking-[0.1em] transition-colors duration-150 hover:text-ink ${active ? "text-ink" : ""}`}
                      >
                        {c.header}
                        <span aria-hidden="true" className="text-dim">
                          {active && sort ? (sort.dir === "asc" ? "↑" : "↓") : "↕"}
                        </span>
                      </button>
                    ) : (
                      c.header
                    )}
                  </th>
                );
              })}
            </tr>
          </thead>
          <tbody>
            {body ? (
              <tr>
                <td colSpan={columns.length} className="p-0">
                  {body}
                </td>
              </tr>
            ) : (
              shown.map((i) => {
                const r = rows[i];
                return (
                  <tr key={r.key} aria-selected={r.selected} data-filter={filterable ? r.filter : undefined}>
                    {columns.map((c, ci) => (
                      <Fragment key={c.key}>
                        <td className={`${c.align === "right" ? "num" : ""} ${c.className ?? ""}`} data-sort-value={c.sortable ? dir(r.sort[c.key]) : undefined}>
                          {r.cells[ci]}
                        </td>
                      </Fragment>
                    ))}
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
