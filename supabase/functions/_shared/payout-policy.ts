/**
 * payout-policy.ts — deterministic, auditable risk classifier for seller
 * payout release when the buyer is SILENT after the seller marked sent.
 *
 * Replaces the blanket 72-hour auto-release. Buyer silence alone no longer
 * releases every transaction; it releases only LOW-risk ones. This module is
 * pure TypeScript with zero I/O so the exact production decision path is
 * unit-tested (tests/payout-policy.test.ts) and reproducible from the audit
 * record (payout_decisions stores the inputs in `evidence`).
 *
 * NOT in scope here (handled elsewhere):
 *   • Buyer positive confirmation  → confirm-and-release (always releases
 *     absent a dispute — strongest possible signal).
 *   • Open dispute                 → transfers.status='disputed' rows are
 *     never candidates (SQL WHERE status='seller_sent'), and both release
 *     paths independently refuse disputed transfers.
 *   • Unsent expiry (24h refund)   → unchanged Phase 1 behavior.
 *
 * DECISION OUTCOMES for a silent-buyer candidate past auto_release_at:
 *   release        → LOW risk: pay the seller now (controlled auto-release).
 *   hold           → MEDIUM risk: wait until an event-relative safe point
 *                    (post-event grace) before re-evaluating for release.
 *   manual_review  → HIGH risk: never auto-release; an operator must act.
 *
 * All thresholds come from the payout_policy DB row (single row, id=1) so
 * ops can tune without a deploy; defaults are documented on the table and
 * mirrored in DEFAULT_POLICY below.
 */

// ── Configuration (mirrors public.payout_policy row) ─────────────────────────

export interface PayoutPolicyConfig {
  /** Order value (cents) at or above which a silent-buyer payout is HIGH risk. */
  high_value_cents: number;
  /** Completed sales required before a seller qualifies for LOW risk. */
  low_min_completed_sales: number;
  /** Seller account age (days) required for LOW risk. */
  low_min_account_age_days: number;
  /** Hours after the event date before a MEDIUM hold releases. */
  post_event_grace_hours: number;
  /** Cap (days past auto_release_at) a MEDIUM hold may last before manual review. */
  medium_max_hold_days: number;
}

export const DEFAULT_POLICY: PayoutPolicyConfig = {
  high_value_cents: 20_000,       // $200+
  low_min_completed_sales: 3,
  low_min_account_age_days: 14,
  post_event_grace_hours: 24,
  medium_max_hold_days: 7,
};

// ── Candidate signals (all sourced from existing tables) ────────────────────

/** Platforms whose official transfer flows we recognize (migration 011 enum). */
export const SUPPORTED_PLATFORMS = ['dice', 'eventbrite', 'posh', 'axs', 'ticketmaster'];

/** Platforms using rotating/SafeTix-style barcodes — screenshots of a code
 *  prove nothing; only the official transfer works, so evidence is weaker. */
export const ROTATING_BARCODE_PLATFORMS = ['ticketmaster', 'axs'];

export interface PayoutCandidate {
  transfer_id: string;
  payment_id: string;
  listing_id: string;
  seller_id: string;
  buyer_id: string;
  /** payments.amount — base price in cents. */
  base_cents: number;
  /** transfers.transfer_evidence_path present? */
  has_evidence: boolean;
  /** transfers.buyer_viewed_at present? (buyer opened the transfer screen) */
  buyer_viewed: boolean;
  /** listings.ticket_platform */
  ticket_platform: string | null;
  /** listings.event_date as ISO date string (event day, local venue date). */
  event_date: string | null;
  /** listings.proof_status ('pending_review' | 'approved' | 'rejected') */
  proof_status: string | null;
  /** transfers.auto_release_at ISO timestamp (the original 72h mark). */
  auto_release_at: string;
  /** Existing MEDIUM hold deadline, if one was already set. */
  payout_hold_until: string | null;
  // seller_risk_scores (refreshed just before evaluation; null = no row)
  risk_tier: 'low' | 'medium' | 'high' | 'critical' | null;
  account_age_days: number | null;
  total_completed: number | null;
  total_disputes: number | null;
  total_dispute_losses: number | null;
  is_listing_blocked: boolean | null;
  // profiles
  stripe_onboarding_complete: boolean;
}

// ── Decision ─────────────────────────────────────────────────────────────────

export type PayoutRiskTier = 'low' | 'medium' | 'high';
export type PayoutAction = 'release' | 'hold' | 'manual_review';

export interface PayoutDecision {
  action: PayoutAction;
  tier: PayoutRiskTier;
  /** Machine reason codes, most significant first. */
  reasons: string[];
  /** For action='hold': when to re-evaluate (ISO). */
  hold_until: string | null;
}

// Reason codes (stable API for the audit trail / admin queue):
//   HIGH → SELLER_RISK_TIER_HIGH, SELLER_RISK_TIER_CRITICAL, SELLER_BLOCKED,
//          PRIOR_DISPUTE_LOSS, HIGH_VALUE_ORDER, EVIDENCE_MISSING,
//          PROOF_REJECTED, SELLER_KYC_INCOMPLETE, NEW_SELLER_NO_HISTORY,
//          MEDIUM_HOLD_EXPIRED_UNRESOLVED
//   MEDIUM → SELLER_UNPROVEN, SELLER_RISK_TIER_MEDIUM, PRIOR_DISPUTES,
//            BUYER_NEVER_VIEWED, UNSUPPORTED_PLATFORM, ROTATING_BARCODE,
//            EVENT_DATE_UNKNOWN
//   RELEASE → LOW_RISK_ESTABLISHED_SELLER, HOLD_ELAPSED_POST_EVENT

export function classifyPayout(
  c: PayoutCandidate,
  policy: PayoutPolicyConfig,
  nowIso: string,
): PayoutDecision {
  const now = new Date(nowIso).getTime();
  const highReasons: string[] = [];
  const mediumReasons: string[] = [];

  // ── HIGH-risk signals: never auto-release, operator must act ──────────────
  if (c.risk_tier === 'critical') highReasons.push('SELLER_RISK_TIER_CRITICAL');
  if (c.risk_tier === 'high') highReasons.push('SELLER_RISK_TIER_HIGH');
  if (c.is_listing_blocked) highReasons.push('SELLER_BLOCKED');
  if ((c.total_dispute_losses ?? 0) > 0) highReasons.push('PRIOR_DISPUTE_LOSS');
  if (c.base_cents >= policy.high_value_cents) highReasons.push('HIGH_VALUE_ORDER');
  if (!c.has_evidence) highReasons.push('EVIDENCE_MISSING');
  if (c.proof_status === 'rejected') highReasons.push('PROOF_REJECTED');
  if (!c.stripe_onboarding_complete) highReasons.push('SELLER_KYC_INCOMPLETE');
  // Brand-new seller with zero history: silence is not enough.
  if ((c.total_completed ?? 0) === 0 && (c.account_age_days ?? 0) < 7) {
    highReasons.push('NEW_SELLER_NO_HISTORY');
  }

  if (highReasons.length > 0) {
    return { action: 'manual_review', tier: 'high', reasons: highReasons, hold_until: null };
  }

  // ── MEDIUM-risk signals: hold to an event-relative safe point ─────────────
  const established =
    (c.total_completed ?? 0) >= policy.low_min_completed_sales &&
    (c.account_age_days ?? 0) >= policy.low_min_account_age_days;
  if (!established) mediumReasons.push('SELLER_UNPROVEN');
  if (c.risk_tier === 'medium') mediumReasons.push('SELLER_RISK_TIER_MEDIUM');
  if ((c.total_disputes ?? 0) > 0) mediumReasons.push('PRIOR_DISPUTES');
  if (!c.buyer_viewed) mediumReasons.push('BUYER_NEVER_VIEWED');
  if (!c.ticket_platform || !SUPPORTED_PLATFORMS.includes(c.ticket_platform)) {
    mediumReasons.push('UNSUPPORTED_PLATFORM');
  }
  if (c.ticket_platform && ROTATING_BARCODE_PLATFORMS.includes(c.ticket_platform)) {
    mediumReasons.push('ROTATING_BARCODE');
  }

  if (mediumReasons.length > 0) {
    // Safe release point: after the event has happened plus a grace window —
    // if the tickets were bad, the buyer had the event itself to notice.
    const holdCap = new Date(
      new Date(c.auto_release_at).getTime() + policy.medium_max_hold_days * 86_400_000,
    );

    if (!c.event_date) {
      // Without an event date there is no "post-event" moment to verify
      // against — hold to the cap, then require an operator (never a blind
      // release on a timer).
      mediumReasons.push('EVENT_DATE_UNKNOWN');
      if (now >= holdCap.getTime()) {
        return {
          action: 'manual_review',
          tier: 'high',
          reasons: ['MEDIUM_HOLD_EXPIRED_UNRESOLVED', ...mediumReasons],
          hold_until: null,
        };
      }
      return { action: 'hold', tier: 'medium', reasons: mediumReasons, hold_until: holdCap.toISOString() };
    }

    // event_date is a DATE (venue-local); treat end-of-day UTC as the event
    // end, then add the grace window.
    const eventEnd = new Date(`${c.event_date}T23:59:59Z`);
    const target = new Date(eventEnd.getTime() + policy.post_event_grace_hours * 3_600_000);

    if (target.getTime() <= now) {
      // The safe point has already passed with no dispute and no complaint —
      // controlled release.
      return {
        action: 'release',
        tier: 'medium',
        reasons: ['HOLD_ELAPSED_POST_EVENT', ...mediumReasons],
        hold_until: null,
      };
    }

    if (target.getTime() > holdCap.getTime()) {
      // Event is too far out to keep the seller waiting indefinitely on a
      // buyer who went silent — cap the hold, then require an operator.
      return {
        action: 'manual_review',
        tier: 'high',
        reasons: ['MEDIUM_HOLD_EXPIRED_UNRESOLVED', ...mediumReasons],
        hold_until: null,
      };
    }

    return {
      action: 'hold',
      tier: 'medium',
      reasons: mediumReasons,
      hold_until: target.toISOString(),
    };
  }

  // ── LOW risk: established KYC'd seller, evidence present, buyer engaged ────
  return {
    action: 'release',
    tier: 'low',
    reasons: ['LOW_RISK_ESTABLISHED_SELLER'],
    hold_until: null,
  };
}
