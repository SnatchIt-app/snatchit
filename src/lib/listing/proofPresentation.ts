/**
 * src/lib/listing/proofPresentation.ts — what a buyer is told about a listing's ticket proof.
 *
 * Two states are worth saying, and they never overlap:
 *  - reviewed: a human approved the seller's proof (proof_status = 'approved', migration 033). Only
 *    then may anything say Snatch It reviewed it.
 *  - waived: the owner recorded a proof waiver for Snatch It's own inventory (migration 156:
 *    proof_waived_at/by/reason; the proof stays 'pending_review', never 'approved'). The buyer must
 *    see that BEFORE purchase — on the listing, the bid screen and the checkout pay face.
 * Rows read before 156 have no proof_waived_at and are simply not waived. The words are the owner's
 * (via A, matching web) and can change here only.
 */
export const PROOF_WAIVED_NOTICE = 'Ticket proof waived by Snatch It';
export const PROOF_REVIEWED_ROW = { label: 'Ownership proof', value: 'Reviewed by Snatch It' } as const;

export type ProofFacts = { proof_status?: string | null; proof_waived_at?: string | null } | null | undefined;

export function proofIsReviewed(l: ProofFacts): boolean {
  return l?.proof_status === 'approved';
}

export function proofIsWaived(l: ProofFacts): boolean {
  return !proofIsReviewed(l) && typeof l?.proof_waived_at === 'string' && l.proof_waived_at.trim().length > 0;
}
