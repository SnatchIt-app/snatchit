/**
 * A count per status over the rows a list read returned (V-1 item 2). Pure:
 * the rows are whatever the server answered for this page, so the breakdown is
 * a fact about those rows and is labelled with their scope by the caller. It
 * is never a new metric and never extrapolated to rows the page did not get.
 */

/** Rows whose status the server did not state are counted under this bucket, never dropped. */
export const NOT_STATED = "Not stated";

export type BreakdownItem = {
  /** The bucket's key; "" for rows with no stated value. */
  key: string;
  label: string;
  count: number;
  /** Share of the row total, 0..1. */
  share: number;
  /** The raw status used to tint the bucket; null when none. */
  tone: string | null;
};

export type Breakdown = { total: number; items: BreakdownItem[] };

/**
 * Buckets `rows` by `pick(row).key`. Most common first, ties in first-seen
 * order (stable), the "not stated" bucket last. `label` defaults to the key.
 */
export function breakdown<T>(rows: T[], pick: (row: T) => { key: string | null | undefined; label?: string | null; tone?: string | null }): Breakdown {
  const total = rows.length;
  const buckets = new Map<string, { label: string; count: number; order: number; tone: string | null }>();
  rows.forEach((row, i) => {
    const p = pick(row);
    const key = p.key ?? "";
    const existing = buckets.get(key);
    if (existing) {
      existing.count += 1;
      return;
    }
    buckets.set(key, { label: key === "" ? NOT_STATED : (p.label ?? key), count: 1, order: i, tone: p.tone ?? (key || null) });
  });
  const ranked = [...buckets.entries()].sort(([ka, a], [kb, b]) => {
    if ((ka === "") !== (kb === "")) return ka === "" ? 1 : -1;
    return b.count - a.count || a.order - b.order;
  });
  return {
    total,
    items: ranked.map(([key, b]) => ({ key, label: b.label, count: b.count, share: total === 0 ? 0 : b.count / total, tone: b.tone })),
  };
}
