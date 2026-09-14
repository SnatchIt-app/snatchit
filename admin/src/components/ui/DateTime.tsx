import { formatRelative, formatUtc, parseDate } from "@/lib/format";

/** Absolute UTC timestamp with a relative hint. */
export function DateTime({ value, withSeconds = false, relative = true }: { value: unknown; withSeconds?: boolean; relative?: boolean }) {
  const d = parseDate(value);
  if (!d) return <span className="text-dim">—</span>;
  return (
    // The UTC stamp and its relative hint each stay unbroken, but the line may break between them: in narrow
    // grid cells (key/value panels at tablet width) a single nowrap run pushed the whole page wider than the viewport.
    <time dateTime={d.toISOString()} title={d.toISOString()} className="tabular-nums">
      <span className="whitespace-nowrap">{formatUtc(d, withSeconds)}</span>
      {relative ? (
        <>
          {" "}
          <span className="whitespace-nowrap text-dim">({formatRelative(d)})</span>
        </>
      ) : null}
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
