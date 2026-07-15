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
//          PRIOR_DISPUTE_LOSS, EVIDENCE_MISSING, PROOF_REJECTED,
//          SELLER_KYC_INCOMPLETE, NEW_SELLER_NO_HISTORY,
//          HIGH_VALUE_UNPROVEN_SELLER, HIGH_VALUE_PRIOR_DISPUTES,
//          MEDIUM_HOLD_EXPIRED_UNRESOLVED
//   MEDIUM → SELLER_UNPROVEN, SELLER_RISK_TIER_MEDIUM, PRIOR_DISPUTES,
//            BUYER_NEVER_VIEWED, UNSUPPORTED_PLATFORM, ROTATING_BARCODE,
//            HIGH_VALUE_ORDER, EVENT_DATE_UNKNOWN
//   RELEASE → LOW_RISK_ESTABLISHED_SELLER, HOLD_ELAPSED_POST_EVENT,
//             MEDIUM_HOLD_CAP_ELAPSED (weak-only reasons — see cap rules)
//   HOLD    → MEDIUM_HOLD_EXTENDED_POST_EVENT (strong reasons, near event:
//             bounded extension past the cap to the post-event grace)
//
// SIGNAL WEIGHTS — documented semantics:
//
//   buyer_viewed (transfers.buyer_viewed_at) is ENGAGEMENT EVIDENCE ONLY.
//   It records that the buyer opened the transfer screen. It is NEVER treated
//   as proof that tickets were received, accepted, valid, or that entry
//   occurred. Its only effect: its ABSENCE (BUYER_NEVER_VIEWED) is one
//   medium-risk signal that prevents silent LOW-tier release; its presence
//   never upgrades a decision past what the other signals allow. Positive
//   receipt proof remains exclusively the buyer's explicit confirmation
//   (confirm-and-release).
//
//   HIGH VALUE (base ≥ high_value_cents) is one signal among several, not
//   automatic proof of high risk — Miami festival/nightlife tickets routinely
//   exceed $200. It escalates to HIGH only in combination with an unproven
//   seller or prior disputes (missing evidence / rejected proof / incomplete
//   KYC are independently HIGH already). For an established, KYC-complete,
//   clean-history seller with accepted evidence it is a MEDIUM signal: the
//   payout holds to the post-event safe point instead of manual review.
//
//   ROTATING_BARCODE (Ticketmaster/AXS SafeTix) weakens screenshot evidence,
//   so it raises risk for UNPROVEN sellers only. An established seller with
//   clean history and accepted evidence is not demoted for platform choice
//   alone — the official-transfer flow on these platforms is itself sound.

// ── Cap behavior: which MEDIUM reasons may release at the operational cap ───
//
// The 7-day cap ends an INDEFINITE automated wait — it is not itself a
// release justification. Whether an expired cap releases, extends to the
// post-event point, or goes to an operator depends on WHY the transaction
// was medium:
//
//   WEAK (cap-releasable) — signals that do not question seller reliability,
//   ticket transferability, or provider support:
//     HIGH_VALUE_ORDER   (established, KYC-complete, clean seller — price
//                         alone; every reliability signal already passed)
//     BUYER_NEVER_VIEWED (engagement absence only — cap-releasable ONLY when
//                         the transfer evidence is corroborative, see below)
//
//   STRONG (never cap-release) — seller-reliability or transfer-completion
//   doubts that buyer silence cannot resolve:
//     SELLER_UNPROVEN, SELLER_RISK_TIER_MEDIUM, PRIOR_DISPUTES,
//     UNSUPPORTED_PLATFORM, ROTATING_BARCODE, EVENT_DATE_UNKNOWN
//   Unknown/future reason codes are treated as STRONG (conservative default).
//
// EVIDENCE STRENGTH (documented limitation): ALL transfer evidence today is a
// seller-uploaded screenshot. On rotating-barcode providers (Ticketmaster,
// AXS) a screenshot proves nothing about transfer acceptance, so it is NEVER
// "strong". On supported non-rotating platforms (dice, eventbrite, posh) the
// official-transfer confirmation screenshot is the strongest corroboration
// available and is accepted for cap purposes. No provider API corroboration
// exists; when it does, plug it in here.
//
// STRONG-reason outcomes at the cap: if the post-event point lands within one
// further cap-length (policy.medium_max_hold_days), extend the hold to the
// post-event grace (bounded extension — prevents a manual-review flood for a
// hold that would resolve itself days later); otherwise MANUAL_REVIEW. An
// unknown event date is always MANUAL_REVIEW — elapsed time alone never
// releases it.

export type MediumCapAction = 'RELEASE_AT_CAP' | 'HOLD_TO_POST_EVENT' | 'MANUAL_REVIEW';

export const WEAK_MEDIUM_REASONS = ['HIGH_VALUE_ORDER', 'BUYER_NEVER_VIEWED'];
export const STRONG_MEDIUM_REASONS = [
  'SELLER_UNPROVEN',
  'SELLER_RISK_TIER_MEDIUM',
  'PRIOR_DISPUTES',
  'UNSUPPORTED_PLATFORM',
  'ROTATING_BARCODE',
  'EVENT_DATE_UNKNOWN',
];

export interface MediumEvidenceState {
  hasEvidence: boolean;
  /** Ticketmaster/AXS — screenshots are not acceptance proof there. */
  rotatingBarcodePlatform: boolean;
  platformSupported: boolean;
}

export interface MediumEventState {
  eventDateKnown: boolean;
  /** Post-event safe point (event-day end + grace), ms epoch; null if unknown. */
  postEventPointMs: number | null;
  nowMs: number;
  /** Max further wait (ms) a strong-reason hold may extend past the cap. */
  extensionLimitMs: number;
}

export function classifyMediumCapAction(
  reasonCodes: string[],
  evidence: MediumEvidenceState,
  event: MediumEventState,
): MediumCapAction {
  // Unknown event dates never release from elapsed time alone.
  if (!event.eventDateKnown || event.postEventPointMs === null) return 'MANUAL_REVIEW';

  // Weak-only medium: every reason must be an explicitly documented weak
  // signal (unknown codes are conservative-strong by construction).
  const weakOnly = reasonCodes.every((r) => WEAK_MEDIUM_REASONS.includes(r));

  // Self-uploaded screenshots are corroborative only on supported,
  // non-rotating platforms — never for Ticketmaster/AXS.
  const evidenceStrong =
    evidence.hasEvidence && evidence.platformSupported && !evidence.rotatingBarcodePlatform;

  if (weakOnly && (!reasonCodes.includes('BUYER_NEVER_VIEWED') || evidenceStrong)) {
    return 'RELEASE_AT_CAP';
  }

  // Strong reasons (or weak signals lacking corroboration): a bounded
  // post-event extension when the event resolves soon; otherwise an operator.
  if (event.postEventPointMs <= event.nowMs + event.extensionLimitMs) {
    return 'HOLD_TO_POST_EVENT';
  }
  return 'MANUAL_REVIEW';
}

export function classifyPayout(
  c: PayoutCandidate,
  policy: PayoutPolicyConfig,
  nowIso: string,
): PayoutDecision {
  const now = new Date(nowIso).getTime();
  const highReasons: string[] = [];
  const mediumReasons: string[] = [];

  const established =
    (c.total_completed ?? 0) >= policy.low_min_completed_sales &&
    (c.account_age_days ?? 0) >= policy.low_min_account_age_days;
  const highValue = c.base_cents >= policy.high_value_cents;

  // ── HIGH-risk signals: never auto-release, operator must act ──────────────
  if (c.risk_tier === 'critical') highReasons.push('SELLER_RISK_TIER_CRITICAL');
  if (c.risk_tier === 'high') highReasons.push('SELLER_RISK_TIER_HIGH');
  if (c.is_listing_blocked) highReasons.push('SELLER_BLOCKED');
  if ((c.total_dispute_losses ?? 0) > 0) highReasons.push('PRIOR_DISPUTE_LOSS');
  if (!c.has_evidence) highReasons.push('EVIDENCE_MISSING');
  if (c.proof_status === 'rejected') highReasons.push('PROOF_REJECTED');
  if (!c.stripe_onboarding_complete) highReasons.push('SELLER_KYC_INCOMPLETE');
  // Brand-new seller with zero history: silence is not enough.
  if ((c.total_completed ?? 0) === 0 && (c.account_age_days ?? 0) < 7) {
    highReasons.push('NEW_SELLER_NO_HISTORY');
  }
  // High value is HIGH only in combination with another independent concern.
  if (highValue && !established) highReasons.push('HIGH_VALUE_UNPROVEN_SELLER');
  if (highValue && (c.total_disputes ?? 0) > 0) highReasons.push('HIGH_VALUE_PRIOR_DISPUTES');

  if (highReasons.length > 0) {
    return { action: 'manual_review', tier: 'high', reasons: highReasons, hold_until: null };
  }

  // ── MEDIUM-risk signals: hold to an event-relative safe point ─────────────
  if (!established) mediumReasons.push('SELLER_UNPROVEN');
  if (c.risk_tier === 'medium') mediumReasons.push('SELLER_RISK_TIER_MEDIUM');
  if ((c.total_disputes ?? 0) > 0) mediumReasons.push('PRIOR_DISPUTES');
  // Engagement evidence only — see SIGNAL WEIGHTS above.
  if (!c.buyer_viewed) mediumReasons.push('BUYER_NEVER_VIEWED');
  if (!c.ticket_platform || !SUPPORTED_PLATFORMS.includes(c.ticket_platform)) {
    mediumReasons.push('UNSUPPORTED_PLATFORM');
  }
  // Rotating barcodes weaken evidence for unproven sellers only.
  if (!established && c.ticket_platform && ROTATING_BARCODE_PLATFORMS.includes(c.ticket_platform)) {
    mediumReasons.push('ROTATING_BARCODE');
  }
  // High value for an established, clean, KYC'd seller: post-event hold.
  if (highValue) mediumReasons.push('HIGH_VALUE_ORDER');

  if (mediumReasons.length > 0) {
    // Hold cap: never keep a seller waiting more than medium_max_hold_days
    // past the original auto_release_at on a silent buyer.
    const holdCap = new Date(
      new Date(c.auto_release_at).getTime() + policy.medium_max_hold_days * 86_400_000,
    );

    if (!c.event_date) {
      // Without an event date there is no "post-event" moment to verify
      // against — hold to the cap, then require an operator (never a blind
      // release on a timer). listings.event_date is NOT NULL in the schema,
      // so this branch is defensive only.
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

    // TIMEZONE HANDLING (documented limitation): listings store event_date as
    // a bare DATE and event_time as a venue-local TIME with NO timezone. We
    // do not invent precision. The "event day is over" moment is taken as
    // event_date + 36h UTC (noon UTC the following day ≈ 7-8am in Miami),
    // which conservatively covers 11:59 PM starts, UTC-offset boundaries, and
    // nightlife sets running past 5am ET. All comparisons happen in UTC.
    // Postponed/rescheduled events are NOT detectable from the schema; the
    // hold cap plus the buyer's dispute window is the mitigation, and a
    // reschedule that updates event_date re-enters this calculation on the
    // next evaluation.
    const eventDayEnd = new Date(new Date(`${c.event_date}T00:00:00Z`).getTime() + 36 * 3_600_000);
    const target = new Date(eventDayEnd.getTime() + policy.post_event_grace_hours * 3_600_000);

    if (target.getTime() <= now) {
      // The post-event safe point has passed with no dispute and no
      // complaint — controlled release.
      return {
        action: 'release',
        tier: 'medium',
        reasons: ['HOLD_ELAPSED_POST_EVENT', ...mediumReasons],
        hold_until: null,
      };
    }

    if (now >= holdCap.getTime()) {
      // The operational cap has expired with the event still ahead. The cap
      // ends the indefinite automated wait — it is NOT a release
      // justification by itself. What happens next depends on WHY this
      // transaction was medium (see classifyMediumCapAction docs above).
      const capAction = classifyMediumCapAction(
        mediumReasons,
        {
          hasEvidence: c.has_evidence,
          rotatingBarcodePlatform:
            c.ticket_platform !== null && ROTATING_BARCODE_PLATFORMS.includes(c.ticket_platform),
          platformSupported:
            c.ticket_platform !== null && SUPPORTED_PLATFORMS.includes(c.ticket_platform),
        },
        {
          eventDateKnown: true,
          postEventPointMs: target.getTime(),
          nowMs: now,
          extensionLimitMs: policy.medium_max_hold_days * 86_400_000,
        },
      );

      if (capAction === 'RELEASE_AT_CAP') {
        // Weak-only signals (documented cap-releasable set) with every
        // supporting condition passed — controlled release.
        return {
          action: 'release',
          tier: 'medium',
          reasons: ['MEDIUM_HOLD_CAP_ELAPSED', ...mediumReasons],
          hold_until: null,
        };
      }

      if (capAction === 'HOLD_TO_POST_EVENT') {
        // Strong reasons, but the event resolves within one more cap-length:
        // bounded extension to the post-event grace instead of an operator.
        return {
          action: 'hold',
          tier: 'medium',
          reasons: ['MEDIUM_HOLD_EXTENDED_POST_EVENT', ...mediumReasons],
          hold_until: target.toISOString(),
        };
      }

      // Seller-reliability / transfer-risk unresolved and the event is too
      // far out — an operator decides; silence never pays this one.
      return {
        action: 'manual_review',
        tier: 'high',
        reasons: ['MEDIUM_HOLD_EXPIRED_UNRESOLVED', ...mediumReasons],
        hold_until: null,
      };
    }

    // Hold to the earlier of the post-event point and the cap.
    const holdUntil = target.getTime() <= holdCap.getTime() ? target : holdCap;
    return {
      action: 'hold',
      tier: 'medium',
      reasons: mediumReasons,
      hold_until: holdUntil.toISOString(),
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
