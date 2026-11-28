import Link from "next/link";

/**
 * DC-2: what the console says about test records, and only from what the
 * server (DC-1, migration 180) sent. The console never computes, estimates
 * or infers a count; a server without 180 sends nothing and nothing shows.
 */

/** "N test records hidden by the server", optionally with the server's per-kind breakdown. Shown only for a server-sent integer. */
export function HiddenTestRowsNotice({ count, breakdown }: { count: number | null | undefined; breakdown?: Record<string, number> | null }) {
  if (typeof count !== "number" || !Number.isInteger(count) || count < 0) return null;
  const parts = breakdown ? Object.entries(breakdown).filter(([, n]) => Number.isInteger(n) && n > 0) : [];
  return (
    <span role="note" className="text-[0.75rem] text-muted">
      {count.toLocaleString("en-US")} test record{count === 1 ? "" : "s"} hidden by the server
      {parts.length > 0 ? ` (${parts.map(([k, n]) => `${k.replace(/_/g, " ")} ${n.toLocaleString("en-US")}`).join(", ")})` : ""}
    </span>
  );
}

/** The badge on a row or a detail the server classified as test. Never shown for null (unclassified or pre-180). */
export function TestRecordBadge({ isTest }: { isTest: boolean | null | undefined }) {
  if (isTest !== true) return null;
  return (
    <span role="note" className="inline-flex items-center rounded-full border border-warning/40 bg-warning-soft px-2 py-0.5 text-[0.6875rem] font-medium uppercase tracking-wide text-warning">
      Test record
    </span>
  );
}

/**
 * The line under a list whose rows the server classified (every row carries
 * `is_test`): test rows are not in this list; the restricted view has them.
 * On a server without 180 no row carries the key, and the line stays off.
 */
export function TestDataFooter({ rows }: { rows: readonly { is_test?: boolean | null }[] }) {
  if (rows.length === 0 || !rows.some((r) => r.is_test === true || r.is_test === false)) return null;
  return (
    <span role="note" className="text-[0.75rem] text-muted">
      Test records are excluded by the server.{" "}
      <Link href="/system/test-data" className="link">
        Restricted view
      </Link>
    </span>
  );
}

export const RESTRICTED_VIEW_TITLE = "Test records (restricted view)";
