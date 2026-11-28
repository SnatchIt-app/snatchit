import { formatEt, formatRelative, parseDate } from "@/lib/format";

/** Absolute Eastern Time (EST/EDT) with a relative hint. The UTC instant stays in dateTime and the hover. */
export function DateTime({ value, withSeconds = false, relative = true }: { value: unknown; withSeconds?: boolean; relative?: boolean }) {
  const d = parseDate(value);
  if (!d) return <span className="text-dim">—</span>;
  return (
    // The Eastern stamp and its relative hint each stay unbroken, but the line may break between them: in narrow
    // grid cells (key/value panels at tablet width) a single nowrap run pushed the whole page wider than the viewport.
    <time dateTime={d.toISOString()} title={d.toISOString()} className="tabular-nums">
      <span className="whitespace-nowrap">{formatEt(d, withSeconds)}</span>
      {relative ? (
        <>
          {" "}
          <span className="whitespace-nowrap text-dim">({formatRelative(d)})</span>
        </>
      ) : null}
    </time>
  );
}

/** Relative first, Eastern Time on hover/title (for dense tables). */
export function TimeAgo({ value }: { value: unknown }) {
  const d = parseDate(value);
  if (!d) return <span className="text-dim">—</span>;
  return (
    <time dateTime={d.toISOString()} title={formatEt(d, true)} className="whitespace-nowrap">
      {formatRelative(d)}
    </time>
  );
}
