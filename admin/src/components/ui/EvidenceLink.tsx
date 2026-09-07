"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { openEvidence, type OpenEvidenceState } from "@/lib/evidence-actions";
import { humanize } from "@/lib/format";
import type { EvidenceItem, EvidenceSlot, EvidenceSubjectKind } from "@/lib/types";

function OpenButton() {
  const { pending } = useFormStatus();
  return (
    <button type="submit" disabled={pending} aria-busy={pending} className="btn btn-ghost btn-sm">
      {pending ? "Opening…" : "Open evidence · audited"}
    </button>
  );
}

/**
 * "Open evidence · audited": posts {subjectKind, subjectId, slot} to the
 * openEvidence server action, which calls ops.evidence_access() (operator +
 * aal2 re-checked in Postgres, path resolved from the record, evidence.viewed
 * audit row written), signs the resolved object with the operator's session
 * and redirects to the short-lived URL. No bucket or path ever comes from
 * this component.
 */
export function EvidenceLink({ subjectKind, subjectId, slot, recorded }: { subjectKind: EvidenceSubjectKind; subjectId: string; slot: EvidenceSlot; recorded: boolean }) {
  const [state, formAction] = useActionState<OpenEvidenceState, FormData>(openEvidence, {});
  if (!recorded) return <span className="text-dim">none recorded</span>;
  return (
    <form action={formAction} className="inline-flex flex-wrap items-center gap-2">
      <input type="hidden" name="subject_kind" value={subjectKind} />
      <input type="hidden" name="subject_id" value={subjectId} />
      <input type="hidden" name="slot" value={slot} />
      <OpenButton />
      {state.error ? (
        <span role="alert" className="text-warning">
          {state.error}
          {state.code === "no_evidence" ? " (nothing recorded in this slot)" : state.code === "paused" || state.code === "denied" || state.code === "mfa" ? ` (${state.code})` : null}
        </span>
      ) : null}
    </form>
  );
}

function PublicLink({ url, recorded }: { url: string | null; recorded: boolean }) {
  if (!recorded || !url) return <span className="text-dim">none recorded</span>;
  return (
    <a href={url} target="_blank" rel="noopener noreferrer" className="link">
      Open (public bucket)
    </a>
  );
}

/**
 * Evidence panel. `publicBase` is the storage public-object origin
 * (`${SUPABASE_URL}/storage/v1/object/public`) for the cover image only;
 * every private slot goes through EvidenceLink.
 */
export function EvidenceList({ items, publicBase }: { items: EvidenceItem[]; publicBase: string | null }) {
  const shown = items.filter((e) => e.recorded);
  if (shown.length === 0) return <p className="text-dim">No evidence files recorded.</p>;
  return (
    <div>
      <dl className="grid grid-cols-1 gap-y-2">
        {shown.map((e) => (
          <div key={e.key} className="flex flex-wrap items-baseline gap-x-3 border-b border-line-neutral pb-2 text-[13px]">
            <dt className="eyebrow text-dim">{humanize(e.key.replace(/_path$/, ""))}</dt>
            <dd>
              {e.kind === "audited" ? (
                <EvidenceLink subjectKind={e.subjectKind} subjectId={e.subjectId} slot={e.slot} recorded={e.recorded} />
              ) : e.kind === "public" ? (
                <PublicLink url={publicBase && e.path ? `${publicBase}/${e.bucket}/${e.path.split("/").map(encodeURIComponent).join("/")}` : null} recorded={e.recorded} />
              ) : (
                <span className="text-warning">evidence not accessible</span>
              )}
            </dd>
          </div>
        ))}
      </dl>
      <p className="mt-2 text-[11px] text-dim">Opening a private file is recorded in the audit log (evidence.viewed) with your identity; the link expires within minutes.</p>
    </div>
  );
}
