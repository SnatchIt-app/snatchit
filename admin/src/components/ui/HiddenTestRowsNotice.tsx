/**
 * The single hook for DC-2's "N test records hidden" notice.
 *
 * The server-side exclusion of test rows (DC-1, migration 180) has not
 * landed, so no read returns such a count and nothing passes one here: every
 * chart, table and KPI renders exactly what the server returns. When DC-2
 * wires the server's count through, this is where it is shown — through
 * DataTable's `notice` slot for lists and FigureMeta's `notice` slot for
 * figures. The console never computes or estimates the count itself.
 */
export function HiddenTestRowsNotice({ count }: { count: number | null | undefined }) {
  if (typeof count !== "number" || !Number.isInteger(count) || count < 0) return null;
  return (
    <span role="note" className="text-[0.75rem] text-muted">
      {count.toLocaleString("en-US")} test record{count === 1 ? "" : "s"} hidden by the server
    </span>
  );
}
