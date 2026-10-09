/**
 * src/lib/profile/reputation.ts — the pure seller-reputation model.
 *
 * The public profile's trust panel derives a reputation tier from the
 * `get_profile_trust_stats` RPC. That derivation is pulled out here so it is
 * proven in isolation and can't drift. Sourced strictly from the RPC fields — no
 * hardcoded tiers, no invented data.
 *
 * Ladder: a lost dispute is the trust floor; under 5 completed sales is a new
 * seller; otherwise sales-volume × success-rate promote through Trusted → Top →
 * Elite. `null` stats (RPC failure) is handled by the screen as "unavailable",
 * which is distinct from "no history" (a zero would misrepresent an established
 * seller on the one screen whose job is trust).
 *
 * The same rule holds INSIDE a successful read: a seller with sales but no terminal transfer has no
 * success rate, so the rate is `null`, not 0 — a 0 would print as a rate AND fail every tier
 * gate, branding that seller "Needs review" on no evidence (B, batch 7: `null% transfer success`).
 */

import type { ProfileTrustStats, SellerReputationTier } from '@/src/types';

export interface Reputation {
  tier: SellerReputationTier;
  label: string;
  blurb: string;
  /** Rounded transfer-success percentage, or null when there is no history. */
  successRate: number | null;
}

export function deriveReputation(stats: ProfileTrustStats | null): Reputation {
  if (!stats) {
    return { tier: 'new_seller', label: 'New seller', blurb: 'No completed transfers yet', successRate: null };
  }

  const sales = stats.completed_sales;
  const denom = stats.seller_terminal_total;
  const num = stats.seller_terminal_successful;
  // No denominator, no rate. A 0 here is an INVENTED FAILURE twice over: it prints as a rate the
  // data does not carry, and it fails every tier gate below, which brands the seller "Needs
  // review". `null` is the same answer this module already gives for a failed read — unknown.
  const rate = denom > 0 ? num / denom : null;
  const ratePct = rate == null ? null : Math.round(rate * 100);

  // Any lost dispute → trust floor. Highest precedence after no-data.
  if (stats.disputes_lost > 0) {
    return {
      tier: 'needs_review',
      label: 'Needs review',
      blurb: `${stats.disputes_lost} lost dispute${stats.disputes_lost === 1 ? '' : 's'}${ratePct == null ? '' : ` · ${ratePct}% success`}`,
      successRate: ratePct,
    };
  }

  // Insufficient history → new seller.
  if (sales < 5) {
    return {
      tier: 'new_seller',
      label: 'New seller',
      blurb: sales === 0 ? 'No completed transfers yet' : `${sales} of 5 sales toward Trusted`,
      successRate: ratePct,
    };
  }

  // Volume, but no terminal transfer to judge it by. Neither the floor nor a promotion: both would
  // be verdicts on data that does not exist. The screen already prints "—" for a null rate.
  //
  // NOT reachable from `get_profile_trust_stats` as it stands (migration 031: the denominator's
  // status set is a strict superset of the one `completed_sales` counts, so denom >= sales for any
  // row the RPC returns) — but the type permits it and the ladder must not invent a verdict.
  // LABEL IS A TRUST-PRESENTATION CHOICE, flagged to the owner: "Unrated" claims neither newness
  // nor failure; "New seller" would contradict the sales count beside it; "Needs review" is the
  // invented failure this fix removes. Tier stays `new_seller` because its tone is the neutral one.
  if (rate == null) {
    return {
      tier: 'new_seller',
      label: 'Unrated',
      blurb: `${sales} sales · transfer success unavailable`,
      successRate: null,
    };
  }

  if (sales >= 100 && rate >= 0.99) {
    return { tier: 'elite', label: 'Elite seller', blurb: `${sales} sales · ${ratePct}% transfer success`, successRate: ratePct };
  }
  if (sales >= 25 && rate >= 0.98) {
    return { tier: 'top', label: 'Top seller', blurb: `${sales} sales · ${ratePct}% transfer success`, successRate: ratePct };
  }
  if (sales >= 5 && rate >= 0.95) {
    return { tier: 'trusted', label: 'Trusted seller', blurb: `${sales} sales · ${ratePct}% transfer success`, successRate: ratePct };
  }
  // Has volume but rate below the tier floor → review.
  return { tier: 'needs_review', label: 'Needs review', blurb: `${ratePct}% transfer success`, successRate: ratePct };
}

/** The V2 Badge tone for a tier — restrained, word-carried, never a rainbow. */
export function reputationTone(tier: SellerReputationTier): 'neutral' | 'success' | 'warning' | 'danger' {
  switch (tier) {
    case 'elite':
    case 'top':
    case 'trusted':      return 'success';
    case 'needs_review': return 'danger';
    case 'new_seller':   return 'neutral';
  }
}
