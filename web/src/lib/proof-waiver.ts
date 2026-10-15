/**
 * Owner proof waiver (migration 156): an admin listing their own inventory may publish without a
 * ticket-proof upload. The waiver is recorded on the listing (who, why; the database stamps
 * when), proof_status stays pending_review, and buyers see "Ticket proof waived by Snatch It" —
 * never "verified". The reason is an ordinary listings column, so it is readable through the
 * public API: keep it neutral (A/D N7, 2026-10-15). Shared by the /sell form and createListing.
 */
export const PROOF_WAIVER_DEFAULT_REASON = "Owner inventory; ticket proof waived by Snatch It.";

export const PROOF_WAIVER_REASON_HINT =
  "Recorded on the listing and readable through the public API. Keep it neutral. Buyers see “Ticket proof waived by Snatch It”.";

/** Matches 156's CHECK on proof_waiver_reason (1–300 characters). */
export const PROOF_WAIVER_REASON_MAX = 300;

export const PROOF_WAIVER_LABEL = "Owner exception: list without ticket proof (recorded waiver)";
