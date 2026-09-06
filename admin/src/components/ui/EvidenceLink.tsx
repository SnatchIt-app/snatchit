import { signEvidence } from "@/lib/storage";
import { humanize } from "@/lib/format";
import type { EvidenceRef } from "@/lib/types";

/**
 * Server component: signs a private storage path with the operator's own
 * session and renders an expiring link. On failure it says "evidence not
 * accessible" — the raw path is never shown.
 */
export async function EvidenceLink({ evidence }: { evidence: EvidenceRef }) {
  if (!evidence.path) return <span className="text-dim">none recorded</span>;
  const signed = await signEvidence(evidence.bucket, evidence.path);
  if (!signed.ok) {
    return (
      <span className="text-warning" title={`bucket ${evidence.bucket ?? "?"}`}>
        {signed.reason}
      </span>
    );
  }
  return (
    <a href={signed.url} target="_blank" rel="noopener noreferrer" className="link">
      Open ({evidence.bucket}, link expires in {Math.round(signed.expiresInSeconds / 60)} min)
    </a>
  );
}

export function EvidenceList({ items }: { items: EvidenceRef[] }) {
  const shown = items.filter((e) => e.path);
  if (shown.length === 0) return <p className="text-dim">No evidence files recorded.</p>;
  return (
    <dl className="grid grid-cols-1 gap-y-2">
      {shown.map((e) => (
        <div key={e.key} className="flex flex-wrap items-baseline gap-x-3 border-b border-line-neutral pb-2 text-[13px]">
          <dt className="eyebrow text-dim">{humanize(e.key.replace(/_path$/, ""))}</dt>
          <dd>
            <EvidenceLink evidence={e} />
          </dd>
        </div>
      ))}
    </dl>
  );
}
