import Link from "next/link";
import { subjectHref } from "@/lib/routes";
import { shortId } from "@/lib/format";

/**
 * A subject id rendered as a monospace link to its detail page (when one
 * exists). `full` shows the whole uuid; default shows the 8-char prefix with
 * the full id in the title attribute.
 */
export function IdLink({
  kind,
  id,
  subjectRef,
  label,
  full = false,
  className = "",
}: {
  kind: string | null | undefined;
  id: string | null | undefined;
  /** subject_ref for ref-addressed subjects (job name, setting key). */
  subjectRef?: string | null;
  label?: string | null;
  full?: boolean;
  className?: string;
}) {
  if (!id && !subjectRef) return <span className="text-dim">—</span>;
  const href = subjectHref(kind, id, subjectRef);
  const text = label ?? (full ? id ?? subjectRef : shortId(id ?? subjectRef));
  const inner = (
    <code className={`font-mono text-[12px] ${className}`} title={id ?? subjectRef ?? undefined}>
      {text}
    </code>
  );
  return href ? (
    <Link href={href} className="link">
      {inner}
    </Link>
  ) : (
    inner
  );
}

/** Masked person: display name (or short id) linking to /users/:id, with masked contact as a hint. */
export function PartyLink({
  id,
  displayName,
  emailMasked,
  meId,
}: {
  id: string | null | undefined;
  displayName?: string | null;
  emailMasked?: string | null;
  meId?: string;
}) {
  if (!id) return <span className="text-dim">—</span>;
  const label = id === meId ? "me" : displayName || shortId(id);
  return (
    <span className="inline-flex flex-wrap items-baseline gap-1">
      <Link href={`/users/${id}`} className="link" title={id}>
        {label}
      </Link>
      {emailMasked ? <span className="text-[11px] text-dim">{emailMasked}</span> : null}
    </span>
  );
}
