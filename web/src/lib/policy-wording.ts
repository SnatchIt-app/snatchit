/**
 * The policy sentences the web app shows, verbatim from the owner's canonical text:
 * docs/release/packages/RC3_20261013/POLICY_WORDING.md (owner ruling 2026-10-13) on
 * release/candidate-20260918. §2 holds the sentences, §4 M1 the two short forms the website
 * uses too, §5 the web rows. Change a sentence there first, then here; never paraphrase.
 */

/** §4 M1, refund short form (the 24-hour non-delivery refund). */
export const REFUND_SHORT =
  "If the seller doesn't send within 24 hours, the order is cancelled and a full refund is issued automatically.";

/** §4 M1, payout short form: buyer confirmation, or the risk-checked 72-hour release. */
export const PAYOUT_SHORT =
  "The seller isn't paid until you confirm your tickets arrived, or until the 72-hour window passes and the order clears Snatch It's risk checks.";

/** §2 P4. */
export const REPORT_FREEZES_PAYOUT = "Reporting a problem freezes the seller's payout while we review.";

/** §5 (home and /sell): the fee base is the sale price, and the payout is not unconditional. */
export const SELLER_TERMS =
  "You keep 90% of the sale price. Your payout starts when the buyer confirms, or after the 72-hour window and Snatch It's risk checks.";

/** §5 PayoutSetup: the app's payout-setup.tsx sentence (a payout follows the order's release, not the sale). */
export const PAYOUT_CONNECTED =
  "Your account is connected. After an order is released, we send your payout (the sale price, less the seller fee and any refund) to your Stripe account.";

/** §5 buyer report: the app's own confirmation sentence (A, 2026-10-13: P4, a report freezes the payout). */
export const REPORT_CONFIRM =
  "Report a problem? This freezes the seller's payout and opens a case for our team.";

/** §5 seller pending alert, after the countdown. */
export const SELLER_MISSED_DEADLINE = "Miss it and the order is cancelled and the buyer's refund is issued automatically.";
