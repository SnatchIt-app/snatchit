import { formatRelative, formatUtc, parseDate } from "@/lib/format";

/** Absolute UTC timestamp with a relative hint. */
export function DateTime({ value, withSeconds = false, relative = true }: { value: unknown; withSeconds?: boolean; relative?: boolean }) {
  const d = parseDate(value);
  if (!d) return <span className="text-dim">—</span>;
  return (
    <time dateTime={d.toISOString()} title={d.toISOString()} className="whitespace-nowrap tabular-nums">
      {formatUtc(d, withSeconds)}
      {relative ? <span className="ml-1.5 text-dim">({formatRelative(d)})</span> : null}
    </time>
  );
}

/** Relative first, UTC on hover/title (for dense tables). */
export function TimeAgo({ value }: { value: unknown }) {
  const d = parseDate(value);
  if (!d) return <span className="text-dim">—</span>;
  return (
    <time dateTime={d.toISOString()} title={formatUtc(d, true)} className="whitespace-nowrap">
      {formatRelative(d)}
    </time>
  );
}
