/**
 * Client-side view of one page of rows (V-1 item 3): sorting by a column's
 * underlying value and a text filter. Pure, no I/O, no React. The rows are
 * whatever the server returned for this page; a view only re-orders or hides
 * them, never re-fetches and never changes the set.
 */

export type SortValue = string | number | boolean | null | undefined;
export type SortDir = "asc" | "desc";
export type SortState = { key: string; dir: SortDir } | null;

/**
 * The next state after activating a column's header: none → the column's
 * first direction → the other direction → none (back to the server's order).
 * Activating another column starts that column at its first direction.
 */
export function nextSort(current: SortState, key: string, firstDir: SortDir = "asc"): SortState {
  if (!current || current.key !== key) return { key, dir: firstDir };
  if (current.dir === firstDir) return { key, dir: firstDir === "asc" ? "desc" : "asc" };
  return null;
}

const isBlank = (v: SortValue): boolean => v === null || v === undefined || v === "";

const collator = new Intl.Collator("en", { numeric: true, sensitivity: "base" });

/** Compare two present values: numbers numerically, booleans false < true, everything else as natural case-insensitive text. */
export function compareValues(a: Exclude<SortValue, null | undefined>, b: Exclude<SortValue, null | undefined>): number {
  if (typeof a === "number" && typeof b === "number") return a - b;
  if (typeof a === "boolean" && typeof b === "boolean") return Number(a) - Number(b);
  return collator.compare(String(a), String(b));
}

/**
 * Indices of `values` in display order. Stable (ties keep the server's order
 * in both directions) and blanks — null, undefined, "" — last in both
 * directions, so a column of mostly-empty values never floats the empties.
 */
export function sortedIndices(values: SortValue[], dir: SortDir): number[] {
  const idx = values.map((_, i) => i);
  idx.sort((i, j) => {
    const a = values[i];
    const b = values[j];
    const ab = isBlank(a);
    const bb = isBlank(b);
    if (ab || bb) return ab && bb ? i - j : ab ? 1 : -1;
    const c = compareValues(a as Exclude<SortValue, null | undefined>, b as Exclude<SortValue, null | undefined>);
    return (dir === "asc" ? c : -c) || i - j;
  });
  return idx;
}

/** Every whitespace-separated word of `query` must appear in `text`, case-insensitively; a blank query matches everything. */
export function matchesFilter(text: string, query: string): boolean {
  const words = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
  if (words.length === 0) return true;
  const hay = text.toLowerCase();
  return words.every((w) => hay.includes(w));
}

export type ViewRow = { sort: Record<string, SortValue>; filter: string };

/** Indices of the rows to show, in order: the filter first, then the sort (or the server's order when there is none). */
export function viewIndices(rows: ViewRow[], sort: SortState, query: string): number[] {
  const kept = rows.map((_, i) => i).filter((i) => matchesFilter(rows[i].filter, query));
  if (!sort) return kept;
  const order = sortedIndices(
    kept.map((i) => rows[i].sort[sort.key]),
    sort.dir,
  );
  return order.map((k) => kept[k]);
}
