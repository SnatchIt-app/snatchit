import Link from "next/link";
import type { ReactNode } from "react";
import { Alert } from "@/components/ui/Alert";

export type Column<T> = {
  key: string;
  header: ReactNode;
  /** When set, the header becomes a link toggling ?sort=<sortKey>&dir=asc|desc. */
  sortKey?: string;
  align?: "left" | "right";
  className?: string;
  render: (row: T, index: number) => ReactNode;
};

export type SearchParamsLike = Record<string, string | string[] | undefined>;

function withParams(basePath: string, sp: SearchParamsLike, patch: Record<string, string | null>): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(sp)) {
    const val = Array.isArray(v) ? v[0] : v;
    if (val !== undefined && val !== "") q.set(k, val);
  }
  for (const [k, v] of Object.entries(patch)) {
    if (v === null) q.delete(k);
    else q.set(k, v);
  }
  const s = q.toString();
  return s ? `${basePath}?${s}` : basePath;
}

/**
 * Server-rendered table. Sorting and keyset pagination are plain links so the
 * page works without JS and every state is a URL. Wide content scrolls
 * inside the container — the page body never scrolls horizontally.
 */
export function DataTable<T>({
  columns,
  rows,
  rowKey,
  basePath,
  searchParams = {},
  nextCursor,
  emptyText = "No rows.",
  caption,
  dense = false,
  cursorParam = "cursor",
  id,
}: {
  columns: Column<T>[];
  rows: T[];
  rowKey: (row: T, index: number) => string;
  basePath: string;
  searchParams?: SearchParamsLike;
  nextCursor?: string | null;
  emptyText?: string;
  caption?: ReactNode;
  dense?: boolean;
  /** Query param carrying this table's keyset cursor (distinct per table when a page has several). */
  cursorParam?: string;
  /** Anchor id so deep links (/system#jobs) land on the table. */
  id?: string;
}) {
  const currentSort = typeof searchParams.sort === "string" ? searchParams.sort : undefined;
  const currentDir = searchParams.dir === "asc" ? "asc" : "desc";
  const cur = searchParams[cursorParam];
  const hasCursor = typeof cur === "string" && cur !== "";

  return (
    <div id={id}>
      <div className="overflow-x-auto border border-line-neutral">
        <table className={`data-table ${dense ? "text-[12px]" : ""}`}>
          {caption ? <caption className="sr-only">{caption}</caption> : null}
          <thead>
            <tr>
              {columns.map((c) => {
                const active = c.sortKey && currentSort === c.sortKey;
                const nextDir = active && currentDir === "desc" ? "asc" : "desc";
                return (
                  <th
                    key={c.key}
                    scope="col"
                    className={`${c.align === "right" ? "num" : ""} ${c.className ?? ""}`}
                    aria-sort={active ? (currentDir === "asc" ? "ascending" : "descending") : undefined}
                  >
                    {c.sortKey ? (
                      <Link
                        href={withParams(basePath, searchParams, { sort: c.sortKey, dir: nextDir, [cursorParam]: null })}
                        className={`hover:text-primary ${active ? "text-ink" : ""}`}
                      >
                        {c.header}
                        <span aria-hidden="true" className="ml-1 text-dim">
                          {active ? (currentDir === "asc" ? "↑" : "↓") : "↕"}
                        </span>
                      </Link>
                    ) : (
                      c.header
                    )}
                  </th>
                );
              })}
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 ? (
              <tr>
                <td colSpan={columns.length} className="p-0">
                  <Alert state="empty" compact>
                    {emptyText}
                  </Alert>
                </td>
              </tr>
            ) : (
              rows.map((row, i) => (
                <tr key={rowKey(row, i)}>
                  {columns.map((c) => (
                    <td key={c.key} className={`${c.align === "right" ? "num" : ""} ${c.className ?? ""}`}>
                      {c.render(row, i)}
                    </td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
      {nextCursor || hasCursor ? (
        <nav aria-label="Pagination" className="mt-3 flex items-center justify-between text-[12px]">
          <span className="text-dim">
            {rows.length} row{rows.length === 1 ? "" : "s"}
            {hasCursor ? " (continued)" : ""}
          </span>
          <div className="flex gap-3">
            {hasCursor ? (
              <Link href={withParams(basePath, searchParams, { [cursorParam]: null })} className="link">
                First page
              </Link>
            ) : null}
            {nextCursor ? (
              <Link href={withParams(basePath, searchParams, { [cursorParam]: nextCursor })} className="link" rel="next">
                Next →
              </Link>
            ) : null}
          </div>
        </nav>
      ) : null}
    </div>
  );
}
