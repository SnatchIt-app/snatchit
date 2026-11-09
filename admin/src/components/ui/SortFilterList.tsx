"use client";

import { Fragment, useId, useState, type ReactNode } from "react";
import { viewIndices, type SortDir, type SortValue } from "@/lib/table-view";
import { Alert } from "@/components/ui/Alert";

/**
 * Client-side sort and filter for a list that is not a table (the Cases
 * queue). As with ClientTable, the server renders each item and passes it
 * down as an element with its underlying sort values and filter text; this
 * only re-orders or hides the items it was given, on this page, never
 * re-fetching and never touching the page's server-side filters. The sort is
 * a native select plus a direction button, the filter a labelled search field.
 */
export type ListItem = { key: string; node: ReactNode; sort: Record<string, SortValue>; filter: string };
export type SortOption = { key: string; label: string; firstDir?: SortDir };

const DIR_WORD: Record<SortDir, string> = { asc: "ascending", desc: "descending" };

export function SortFilterList({
  items,
  sortOptions,
  noun,
  listClassName,
  listDescribedBy,
}: {
  items: ListItem[];
  sortOptions: SortOption[];
  /** "cases" — used in the labels. */
  noun: string;
  listClassName?: string;
  listDescribedBy?: string;
}) {
  const [sortKey, setSortKey] = useState<string>("");
  const [dir, setDir] = useState<SortDir>("asc");
  const [query, setQuery] = useState("");
  const statusId = useId();
  const filterId = useId();
  const sortId = useId();
  const option = sortOptions.find((o) => o.key === sortKey);
  const shown = viewIndices(items, option ? { key: option.key, dir } : null, query);
  const status = `${option ? `Sorted by ${option.label}, ${DIR_WORD[dir]} — this page only` : "Server order"} · ${shown.length} of ${items.length} ${items.length === 1 ? noun.replace(/s$/, "") : noun} shown`;

  return (
    <div className="min-w-0">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2 border-b border-line px-3 py-2 text-[0.75rem] md:px-4">
        <label htmlFor={sortId} className="flex items-center gap-2 text-muted">
          <span>Sort</span>
          <select
            id={sortId}
            aria-label={`Sort ${noun} on this page`}
            value={sortKey}
            onChange={(e) => {
              const next = sortOptions.find((o) => o.key === e.target.value);
              setSortKey(e.target.value);
              setDir(next?.firstDir ?? "asc");
            }}
            className="field min-h-9 min-w-[9rem] py-1 text-[0.8125rem]"
          >
            <option value="">Server order</option>
            {sortOptions.map((o) => (
              <option key={o.key} value={o.key}>
                {o.label}
              </option>
            ))}
          </select>
        </label>
        <button type="button" aria-label={`Sort direction: ${DIR_WORD[dir]}`} onClick={() => setDir((d) => (d === "asc" ? "desc" : "asc"))} className="btn btn-ghost btn-sm">
          <span aria-hidden="true">{dir === "asc" ? "↑" : "↓"}</span>
          {DIR_WORD[dir]}
        </button>
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
            className="field min-h-9 w-[min(14rem,calc(100vw-4rem))] py-1 text-[0.8125rem]"
          />
        </label>
        <p id={statusId} role="status" aria-live="polite" className="min-w-0 text-dim">
          {status}
        </p>
      </div>
      {shown.length === 0 ? (
        <div className="p-3">
          <Alert state="empty" compact title={`No ${noun} on this page match the filter.`}>
            <button type="button" className="link" onClick={() => setQuery("")}>
              Clear the filter
            </button>
          </Alert>
        </div>
      ) : (
        <ul aria-describedby={listDescribedBy} className={listClassName}>
          {shown.map((i) => (
            <Fragment key={items[i].key}>{items[i].node}</Fragment>
          ))}
        </ul>
      )}
    </div>
  );
}
