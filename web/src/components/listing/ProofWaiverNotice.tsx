import { Icon } from "@/components/ui/Icon";
import { PROOF_WAIVED_NOTE } from "@/lib/listing-display";

/**
 * Shown before purchase on a listing whose ticket proof was waived (156): in the listing's
 * purchase panel and in the checkout order summary. States the fact only, with no claim of
 * verification or review.
 */
export function ProofWaiverNotice({ className = "" }: { className?: string }) {
  return (
    <div role="note" className={`flex gap-2.5 rounded-panel border border-line p-3.5 ${className}`}>
      <Icon name="info" size={18} className="mt-0.5 shrink-0 text-ink-2" />
      <div>
        <p className="text-[15px] font-semibold text-ink">{PROOF_WAIVED_NOTE}</p>
        <p className="t-body-sm mt-0.5 text-muted">No proof of ticket ownership was uploaded for this listing.</p>
      </div>
    </div>
  );
}
