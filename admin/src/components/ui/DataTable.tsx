import Link from "next/link";
import type { ReactNode } from "react";
import { Alert } from "@/components/ui/Alert";
import { ClientTable, type ClientColumn, type ClientRow } from "@/components/ui/ClientTable";
import type { SortDir, SortValue } from "@/lib/table-view";

export type Column<T> = {
  key: string;
  header: ReactNode;
  /** When set, the header becomes a link toggling ?sort=<sortKey>&dir=asc|desc (server-side sort). */
  sortKey?: string;
  align?: "left" | "right";
  className?: string;
  render: (row: T, index: number) => ReactNode;
  /**
   * Client-side sort (V-1 item 3): the row's underlying value for this column —
   * the recorded code, the integer cents, the ISO timestamp — never its
   * rendering. Opt-in per column; any column with one turns the table into a
   * ClientTable, which re-orders the server's rows on this page only.
   */
  sortValue?: (row: T) => SortValue;
  /** Plain text of the header for the sort button's label; required when `header` is not a string. */
  headerText?: string;
  /** Direction the first activation sorts in (counts and dates usually desc). */
  firstSortDir?: SortDir;
};

export type SearchParamsLike = Record<string, string | string[] | undefined>;

function withParams(basePath: string, sp: SearchParamsLike, patch: Record<string, string | null>): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(sp)) {
    const val = Array.isArray(v) ? v.join(",") : v;
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
 *
 * A table whose columns carry `sortValue`, or that sets `filterable`, renders
 * through ClientTable: the cells are still rendered here on the server and
 * passed down as elements, with each row's underlying values and filter text;
 * the client only re-orders or hides the rows it was given. The server's
 * pagination, caption and row set are unchanged, and the page's own
 * server-side filters are untouched.
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
  card,
  isSelected,
  filterable = false,
  filterText,
  defaultSort = null,
  notice,
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
  /** Phone layout: each row as a card. When set, the table shows from `md` up and the cards below it. */
  card?: (row: T, index: number) => ReactNode;
  /** Marks the row whose detail is open (aria-selected), e.g. the order shown in the drawer. */
  isSelected?: (row: T) => boolean;
  /** Client-side text filter over the rows on this page (never a re-fetch; the server-side filters stay). */
  filterable?: boolean;
  /** What the filter matches against; defaults to the sortable columns' values. */
  filterText?: (row: T) => string;
  /** The client-side order to render first; null = the server's order. */
  defaultSort?: { key: string; dir: SortDir } | null;
  /** DC-2's slot for the "N test records hidden" notice (components/ui/HiddenTestRowsNotice.tsx). Nothing passes it yet. */
  notice?: ReactNode;
}) {
  const currentSort = typeof searchParams.sort === "string" ? searchParams.sort : undefined;
  const currentDir = searchParams.dir === "asc" ? "asc" : "desc";
  const cur = searchParams[cursorParam];
  const hasCursor = typeof cur === "string" && cur !== "";

  const pagination =
    nextCursor || hasCursor ? (
      <nav aria-label="Pagination" className="mt-3 flex items-center justify-between px-1 text-[0.8125rem]">
        <span className="text-dim">
          {rows.length} row{rows.length === 1 ? "" : "s"}
          {hasCursor ? " (continued)" : ""}
        </span>
        <div className="flex gap-2">
          {hasCursor ? (
            <Link href={withParams(basePath, searchParams, { [cursorParam]: null })} className="btn btn-ghost btn-sm">
              First page
            </Link>
          ) : null}
          {nextCursor ? (
            <Link href={withParams(basePath, searchParams, { [cursorParam]: nextCursor })} className="btn btn-primary btn-sm" rel="next">
              Next page →
            </Link>
          ) : null}
        </div>
      </nav>
    ) : null;

  const sortable = columns.flatMap((c) => (c.sortValue ? [{ key: c.key, sortValue: c.sortValue }] : []));
  if (filterable || sortable.length > 0) {
    const clientColumns: ClientColumn[] = columns.map((c) => ({
      key: c.key,
      header: c.header,
      headerText: c.headerText ?? (typeof c.header === "string" ? c.header : c.key),
      align: c.align,
      className: c.className,
      sortable: Boolean(c.sortValue),
      firstDir: c.firstSortDir ?? "asc",
    }));
    const text = (v: SortValue) => (v === null || v === undefined ? "" : String(v));
    const clientRows: ClientRow[] = rows.map((row, i) => ({
      key: rowKey(row, i),
      cells: columns.map((c) => c.render(row, i)),
      sort: Object.fromEntries(sortable.map((c) => [c.key, c.sortValue(row)])),
      filter: filterText ? filterText(row) : sortable.map((c) => text(c.sortValue(row))).join(" "),
      selected: isSelected ? isSelected(row) : undefined,
      card: card ? card(row, i) : undefined,
    }));
    return (
      <div id={id}>
        {notice}
        <ClientTable caption={caption} columns={clientColumns} rows={clientRows} dense={dense} filterable={filterable} emptyText={emptyText} defaultSort={defaultSort} hasCards={Boolean(card)} />
        {pagination}
      </div>
    );
  }

  return (
    <div id={id}>
      {notice}
      {/*
        The panel supplies the frame; the table scrolls inside it rather than
        clipping its last column. `min-w-full` + `w-max` lets wide tables keep
        their columns readable instead of compressing them to nothing.
      */}
      {card ? (
        rows.length === 0 ? (
          <div className="md:hidden">
            <Alert state="empty" compact>
              {emptyText}
            </Alert>
          </div>
        ) : (
          <ul className="flex flex-col gap-2 md:hidden" aria-label={typeof caption === "string" ? caption : undefined}>
            {rows.map((row, i) => (
              <li key={rowKey(row, i)}>{card(row, i)}</li>
            ))}
          </ul>
        )
      ) : null}
      <div className={`overflow-x-auto ${card ? "hidden md:block" : ""}`}>
        <table className={`data-table ${dense ? "text-[0.8125rem]" : ""}`}>
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
                        className={`hover:text-primary-ink ${active ? "text-ink" : ""}`}
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
                <tr key={rowKey(row, i)} aria-selected={isSelected ? isSelected(row) : undefined}>
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
      {pagination}
    </div>
  );
}
