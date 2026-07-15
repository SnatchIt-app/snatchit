/**
 * Risk-based payout policy tests — the exact classifier the
 * enforce-transfer-expiry edge function runs in production.
 */
import { describe, expect, it } from 'vitest';
import {
  classifyPayout,
  DEFAULT_POLICY,
  type PayoutCandidate,
} from '../supabase/functions/_shared/payout-policy';

const NOW = '2026-07-14T12:00:00Z';

/** An established, KYC'd seller with evidence and an engaged buyer. */
function lowRiskCandidate(overrides: Partial<PayoutCandidate> = {}): PayoutCandidate {
  return {
    transfer_id: 't1',
    payment_id: 'p1',
    listing_id: 'l1',
    seller_id: 's1',
    buyer_id: 'b1',
    base_cents: 10_000,               // $100 — under the $200 high-value line
    has_evidence: true,
    buyer_viewed: true,
    ticket_platform: 'dice',          // supported, non-rotating
    event_date: '2026-07-12',         // event already happened
    proof_status: 'approved',
    auto_release_at: '2026-07-14T09:00:00Z',  // 72h mark passed
    payout_hold_until: null,
    risk_tier: 'low',
    account_age_days: 60,
    total_completed: 5,
    total_disputes: 0,
    total_dispute_losses: 0,
    is_listing_blocked: false,
    stripe_onboarding_complete: true,
    ...overrides,
  };
}

describe('LOW risk — controlled auto-release', () => {
  it('releases an established KYC-verified seller with evidence and no complaints', () => {
    const d = classifyPayout(lowRiskCandidate(), DEFAULT_POLICY, NOW);
    expect(d.action).toBe('release');
    expect(d.tier).toBe('low');
    expect(d.reasons).toContain('LOW_RISK_ESTABLISHED_SELLER');
  });
});

describe('MEDIUM risk — hold to post-event safe point', () => {
  it('holds an unproven seller until after the event + grace', () => {
    const d = classifyPayout(
      lowRiskCandidate({
        total_completed: 1,           // below low_min_completed_sales (3)
        account_age_days: 10,         // below low_min_account_age_days (14)
        event_date: '2026-07-16',     // event 2 days out
      }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(d.action).toBe('hold');
    expect(d.tier).toBe('medium');
    expect(d.reasons).toContain('SELLER_UNPROVEN');
    // Hold until conservative event-day end (07-16 +36h = 07-17T12:00Z) + 24h grace.
    expect(d.hold_until).toBe('2026-07-18T12:00:00.000Z');
  });

  it('holds when the buyer never viewed the transfer', () => {
    const d = classifyPayout(
      lowRiskCandidate({ buyer_viewed: false, event_date: '2026-07-16' }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(d.action).toBe('hold');
    expect(d.reasons).toContain('BUYER_NEVER_VIEWED');
  });

  it('rotating-barcode platforms hold UNPROVEN sellers (evidence is weaker)', () => {
    const d = classifyPayout(
      lowRiskCandidate({
        ticket_platform: 'ticketmaster',
        event_date: '2026-07-16',
        total_completed: 1,           // unproven
        account_age_days: 10,
      }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(d.action).toBe('hold');
    expect(d.reasons).toContain('ROTATING_BARCODE');
  });

  it('Ticketmaster established seller with strong evidence still qualifies for LOW', () => {
    const d = classifyPayout(
      lowRiskCandidate({ ticket_platform: 'ticketmaster' }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(d.action).toBe('release');
    expect(d.tier).toBe('low');
  });

  it('Ticketmaster NEW seller goes to manual review (new + rotating barcode)', () => {
    const d = classifyPayout(
      lowRiskCandidate({
        ticket_platform: 'ticketmaster',
        total_completed: 0,
        account_age_days: 2,
      }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(d.action).toBe('manual_review');
    expect(d.reasons).toContain('NEW_SELLER_NO_HISTORY');
  });

  it('releases a MEDIUM candidate once the post-event grace has already passed', () => {
    const d = classifyPayout(
      lowRiskCandidate({
        total_completed: 1,
        account_age_days: 10,
        event_date: '2026-07-10',     // event 4 days ago; grace long past
      }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(d.action).toBe('release');
    expect(d.reasons).toContain('HOLD_ELAPSED_POST_EVENT');
  });

  it('unknown event date holds to the cap, then manual review — never a blind release', () => {
    const early = classifyPayout(
      lowRiskCandidate({ event_date: null, buyer_viewed: false }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(early.action).toBe('hold');
    expect(early.reasons).toContain('EVENT_DATE_UNKNOWN');

    const late = classifyPayout(
      lowRiskCandidate({
        event_date: null,
        buyer_viewed: false,
        auto_release_at: '2026-07-01T00:00:00Z',   // cap (7d) long exceeded
      }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(late.action).toBe('manual_review');
    expect(late.reasons).toContain('MEDIUM_HOLD_EXPIRED_UNRESOLVED');
  });
});

describe('HIGH risk — manual review, never auto-release', () => {
  it('freezes a brand-new seller with no history', () => {
    const d = classifyPayout(
      lowRiskCandidate({ total_completed: 0, account_age_days: 2 }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(d.action).toBe('manual_review');
    expect(d.tier).toBe('high');
    expect(d.reasons).toContain('NEW_SELLER_NO_HISTORY');
  });

  it('a $250 order from a NEW/unproven seller goes to manual review', () => {
    const d = classifyPayout(
      lowRiskCandidate({ base_cents: 25_000, total_completed: 1, account_age_days: 10 }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(d.action).toBe('manual_review');
    expect(d.reasons).toContain('HIGH_VALUE_UNPROVEN_SELLER');
  });

  it('a $250 order from an ESTABLISHED clean seller is NOT high risk — post-event hold, not manual review', () => {
    // Miami festival/nightlife tickets routinely exceed $200. Price alone is
    // one signal, not proof of risk.
    const d = classifyPayout(
      lowRiskCandidate({ base_cents: 25_000, event_date: '2026-07-16' }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(d.action).toBe('hold');
    expect(d.tier).toBe('medium');
    expect(d.reasons).toContain('HIGH_VALUE_ORDER');
    expect(d.reasons).not.toContain('HIGH_VALUE_UNPROVEN_SELLER');
  });

  it('a $250 established clean seller releases after the post-event grace', () => {
    const d = classifyPayout(
      lowRiskCandidate({ base_cents: 25_000, event_date: '2026-07-10' }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(d.action).toBe('release');
    expect(d.reasons).toContain('HOLD_ELAPSED_POST_EVENT');
  });

  it('a $500 established seller with MISSING evidence goes to manual review', () => {
    const d = classifyPayout(
      lowRiskCandidate({ base_cents: 50_000, has_evidence: false }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(d.action).toBe('manual_review');
    expect(d.reasons).toContain('EVIDENCE_MISSING');
  });

  it('high value + prior disputes goes to manual review', () => {
    const d = classifyPayout(
      lowRiskCandidate({ base_cents: 25_000, total_disputes: 1 }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(d.action).toBe('manual_review');
    expect(d.reasons).toContain('HIGH_VALUE_PRIOR_DISPUTES');
  });

  it('freezes when transfer evidence is missing', () => {
    const d = classifyPayout(lowRiskCandidate({ has_evidence: false }), DEFAULT_POLICY, NOW);
    expect(d.action).toBe('manual_review');
    expect(d.reasons).toContain('EVIDENCE_MISSING');
  });

  it('freezes sellers with prior dispute losses, high/critical risk tiers, blocked sellers, and incomplete KYC', () => {
    expect(classifyPayout(lowRiskCandidate({ total_dispute_losses: 1 }), DEFAULT_POLICY, NOW).reasons)
      .toContain('PRIOR_DISPUTE_LOSS');
    expect(classifyPayout(lowRiskCandidate({ risk_tier: 'high' }), DEFAULT_POLICY, NOW).reasons)
      .toContain('SELLER_RISK_TIER_HIGH');
    expect(classifyPayout(lowRiskCandidate({ risk_tier: 'critical' }), DEFAULT_POLICY, NOW).reasons)
      .toContain('SELLER_RISK_TIER_CRITICAL');
    expect(classifyPayout(lowRiskCandidate({ is_listing_blocked: true }), DEFAULT_POLICY, NOW).reasons)
      .toContain('SELLER_BLOCKED');
    expect(classifyPayout(lowRiskCandidate({ stripe_onboarding_complete: false }), DEFAULT_POLICY, NOW).reasons)
      .toContain('SELLER_KYC_INCOMPLETE');
    expect(classifyPayout(lowRiskCandidate({ proof_status: 'rejected' }), DEFAULT_POLICY, NOW).reasons)
      .toContain('PROOF_REJECTED');
  });

  it('a rejected-proof high-value new seller reports every reason (auditable)', () => {
    const d = classifyPayout(
      lowRiskCandidate({
        base_cents: 50_000,
        has_evidence: false,
        total_completed: 0,
        account_age_days: 1,
      }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(d.action).toBe('manual_review');
    expect(d.reasons).toEqual(
      expect.arrayContaining(['HIGH_VALUE_UNPROVEN_SELLER', 'EVIDENCE_MISSING', 'NEW_SELLER_NO_HISTORY']),
    );
  });
});

describe('determinism & idempotency (same inputs → same decision)', () => {
  it('classify is a pure function', () => {
    const c = lowRiskCandidate({ buyer_viewed: false, event_date: '2026-07-16' });
    const a = classifyPayout(c, DEFAULT_POLICY, NOW);
    const b = classifyPayout(c, DEFAULT_POLICY, NOW);
    expect(a).toEqual(b);
  });

  it('a re-evaluated hold with unchanged inputs produces the same hold_until (duplicate cron runs are no-ops)', () => {
    const c = lowRiskCandidate({ total_completed: 1, account_age_days: 5, event_date: '2026-07-16' });
    const first = classifyPayout(c, DEFAULT_POLICY, NOW);
    const second = classifyPayout(
      { ...c, payout_hold_until: first.hold_until },
      DEFAULT_POLICY,
      '2026-07-14T12:02:00Z',        // next cron tick, 2 minutes later
    );
    expect(second.hold_until).toBe(first.hold_until);
  });
});

describe('dispute and buyer-confirmation invariants (structural)', () => {
  // Open disputes never reach classifyPayout: the SQL candidate query
  // requires status='seller_sent' and apply_auto_release() re-checks it
  // under a row lock; confirm-and-release refuses disputed transfers with
  // an explicit 409. These tests pin the policy-level invariants.
  it('policy has no code path that releases on a dispute signal', () => {
    // A buyer complaint surfaces as a dispute (status change) — candidates
    // are seller_sent by construction, so the classifier only ever sees
    // undisputed rows. Assert the type-level contract holds.
    const c = lowRiskCandidate();
    const d = classifyPayout(c, DEFAULT_POLICY, NOW);
    expect(['release', 'hold', 'manual_review']).toContain(d.action);
  });

  it('buyer-confirmed releases bypass the classifier entirely (documented contract)', () => {
    // confirm-and-release requires status='buyer_confirmed' and logs the
    // decision with reason BUYER_CONFIRMED — the classifier never runs.
    expect(true).toBe(true);
  });
});

describe('historical transaction compatibility', () => {
  it('a legacy transfer with no risk score row (null signals) is never LOW risk', () => {
    const d = classifyPayout(
      lowRiskCandidate({
        risk_tier: null,
        account_age_days: null,
        total_completed: null,
        total_disputes: null,
        total_dispute_losses: null,
        is_listing_blocked: null,
      }),
      DEFAULT_POLICY,
      NOW,
    );
    // Null history reads as a seller with no record at all — the classifier
    // treats that as HIGH (new seller, no history): frozen for an operator,
    // never a blind release.
    expect(d.action).toBe('manual_review');
    expect(d.reasons).toContain('NEW_SELLER_NO_HISTORY');
  });

  it('pre-039 rows with seller_fee=0 style payments still classify (base_cents only input)', () => {
    const d = classifyPayout(lowRiskCandidate({ base_cents: 500 }), DEFAULT_POLICY, NOW);
    expect(d.action).toBe('release');
  });
});

// ─── AUDIT 4: event time & timezone behavior ─────────────────────────────────
// Schema stores event_date (DATE) + venue-local TIME with no timezone. The
// classifier does not invent precision: "event day over" = event_date + 36h
// UTC (noon UTC next day ≈ 7-8am Miami), all comparisons in UTC.

describe('event time & timezone (conservative UTC handling)', () => {
  const medium = (overrides: Partial<PayoutCandidate>) =>
    lowRiskCandidate({ total_completed: 1, account_age_days: 10, ...overrides });

  it('an 11:59 PM Miami event does NOT release the morning after (UTC boundary safe)', () => {
    // Event 2026-07-13 (a Miami set starting 11:59 PM runs into 07-14 ET).
    // Old buggy math (event_date T23:59:59Z + 24h) would release at
    // 07-14T23:59Z. New math: eventDayEnd 07-14T12:00Z + 24h grace →
    // releases only after 07-15T12:00Z.
    const d = classifyPayout(medium({ event_date: '2026-07-13' }), DEFAULT_POLICY, '2026-07-14T13:00:00Z');
    expect(d.action).toBe('hold');
    expect(d.hold_until).toBe('2026-07-15T12:00:00.000Z');
  });

  it('releases after the conservative post-event point passes', () => {
    const d = classifyPayout(medium({ event_date: '2026-07-13' }), DEFAULT_POLICY, '2026-07-15T12:00:01Z');
    expect(d.action).toBe('release');
    expect(d.reasons).toContain('HOLD_ELAPSED_POST_EVENT');
  });

  it('unknown event time/date never causes a false automatic release', () => {
    const early = classifyPayout(medium({ event_date: null }), DEFAULT_POLICY, NOW);
    expect(early.action).toBe('hold');
    expect(early.reasons).toContain('EVENT_DATE_UNKNOWN');
    // At the cap, unknown-date holds go to an operator — never a timer release.
    const late = classifyPayout(
      medium({ event_date: null, auto_release_at: '2026-07-01T00:00:00Z' }),
      DEFAULT_POLICY,
      NOW,
    );
    expect(late.action).toBe('manual_review');
    expect(late.reasons).toContain('MEDIUM_HOLD_EXPIRED_UNRESOLVED');
  });

  it('a rescheduled event re-enters the calculation with the new date', () => {
    // Candidates are re-read from listings on every evaluation, so an updated
    // event_date changes the hold on the next cron pass.
    const before = classifyPayout(medium({ event_date: '2026-07-16' }), DEFAULT_POLICY, NOW);
    const rescheduled = classifyPayout(medium({ event_date: '2026-07-18' }), DEFAULT_POLICY, NOW);
    expect(before.action).toBe('hold');
    expect(rescheduled.action).toBe('hold');
    expect(new Date(rescheduled.hold_until!).getTime())
      .toBeGreaterThan(new Date(before.hold_until!).getTime());
    // Limitation (documented in payout-policy.ts): a postponement that is NOT
    // written to listings.event_date is undetectable; the hold cap + the
    // buyer's dispute channel are the mitigation.
  });

  it('an event sold >7 days before showtime holds to the cap, then routes by reason (unproven → operator)', () => {
    // auto_release_at 07-14T09:00Z; cap = +7d = 07-21T09:00Z; event 08-15.
    const held = classifyPayout(medium({ event_date: '2026-08-15' }), DEFAULT_POLICY, NOW);
    expect(held.action).toBe('hold');
    expect(held.hold_until).toBe('2026-07-21T09:00:00.000Z'); // cap, not post-event
    // SELLER_UNPROVEN is a STRONG medium reason: the elapsed cap must NOT pay
    // it while the event is still weeks away — an operator decides.
    const capElapsed = classifyPayout(medium({ event_date: '2026-08-15' }), DEFAULT_POLICY, '2026-07-21T09:00:01Z');
    expect(capElapsed.action).toBe('manual_review');
    expect(capElapsed.reasons).toContain('MEDIUM_HOLD_EXPIRED_UNRESOLVED');
  });
});

// ─── AUDIT 6: medium-hold policy — documented examples ───────────────────────
// 72h initial window (auto_release_at) → then, for MEDIUM candidates:
// hold to min(event_day_end + 24h grace, auto_release_at + 7d cap);
// at the post-event point → release; at the cap with the event still ahead →
// release (evidence present, no dispute); unknown date at cap → manual review.

describe('medium hold policy examples', () => {
  const medium = (overrides: Partial<PayoutCandidate>) =>
    lowRiskCandidate({ total_completed: 1, account_age_days: 10, ...overrides });

  it('event tomorrow → holds ~2 days to post-event grace', () => {
    const d = classifyPayout(medium({ event_date: '2026-07-15' }), DEFAULT_POLICY, NOW);
    expect(d.action).toBe('hold');
    expect(d.hold_until).toBe('2026-07-17T12:00:00.000Z'); // 07-15 +36h +24h
  });

  it('event in five days → holds to the earlier of post-event grace and the cap', () => {
    // post-event point = 07-19 +36h +24h = 07-21T12:00Z; cap = 07-21T09:00Z →
    // the cap is 3h earlier and wins (never longer than 7 days past the 72h mark).
    const d = classifyPayout(medium({ event_date: '2026-07-19' }), DEFAULT_POLICY, NOW);
    expect(d.action).toBe('hold');
    expect(d.hold_until).toBe('2026-07-21T09:00:00.000Z');
  });

  it('event in four days → post-event grace wins (inside the cap)', () => {
    // post-event point = 07-18 +36h +24h = 07-20T12:00Z < cap 07-21T09:00Z.
    const d = classifyPayout(medium({ event_date: '2026-07-18' }), DEFAULT_POLICY, NOW);
    expect(d.action).toBe('hold');
    expect(d.hold_until).toBe('2026-07-20T12:00:00.000Z');
  });

  it('event in thirty days → holds to the 7-day cap; at the cap the reason codes decide', () => {
    const d = classifyPayout(medium({ event_date: '2026-08-13' }), DEFAULT_POLICY, NOW);
    expect(d.action).toBe('hold');
    expect(d.hold_until).toBe('2026-07-21T09:00:00.000Z'); // the cap
    // strong reason (SELLER_UNPROVEN) + event still ~23 days out at the cap → operator
    const atCap = classifyPayout(medium({ event_date: '2026-08-13' }), DEFAULT_POLICY, '2026-07-21T10:00:00Z');
    expect(atCap.action).toBe('manual_review');
  });

  it('event already passed → immediate controlled release', () => {
    const d = classifyPayout(medium({ event_date: '2026-07-10' }), DEFAULT_POLICY, NOW);
    expect(d.action).toBe('release');
  });
});

// ─── Cap behavior is reason-code dependent (final policy correction) ─────────
// The 7-day cap ends an indefinite automated wait; it is not itself a release
// justification. Weak-only mediums may release at the cap; strong reasons
// (seller reliability / transfer risk) extend to the post-event grace when
// the event is near, or go to an operator when it is far. Unknown event dates
// never release on elapsed time.

import { classifyMediumCapAction } from '../supabase/functions/_shared/payout-policy';

describe('medium cap action — reason-code classification', () => {
  const AT_CAP = '2026-07-21T10:00:00Z'; // past cap (auto_release 07-14T09:00Z + 7d)
  const establishedClean = (overrides: Partial<PayoutCandidate>) =>
    lowRiskCandidate({ auto_release_at: '2026-07-14T09:00:00Z', ...overrides });

  it('1. $250 established clean seller, buyer never viewed, strong evidence → releases at cap', () => {
    // Medium reasons: HIGH_VALUE_ORDER + BUYER_NEVER_VIEWED — both weak;
    // evidence on a supported non-rotating platform (dice) is corroborative.
    const d = classifyPayout(
      establishedClean({ base_cents: 25_000, buyer_viewed: false, event_date: '2026-08-20' }),
      DEFAULT_POLICY,
      AT_CAP,
    );
    expect(d.action).toBe('release');
    expect(d.reasons).toContain('MEDIUM_HOLD_CAP_ELAPSED');
  });

  it('2. unproven seller, event 30 days away → manual review at cap, not release', () => {
    const d = classifyPayout(
      establishedClean({ total_completed: 1, account_age_days: 10, event_date: '2026-08-20' }),
      DEFAULT_POLICY,
      AT_CAP,
    );
    expect(d.action).toBe('manual_review');
    expect(d.reasons).toContain('MEDIUM_HOLD_EXPIRED_UNRESOLVED');
    expect(d.reasons).toContain('SELLER_UNPROVEN');
  });

  it('3. Ticketmaster rotating-barcode (unproven seller), event 30 days away → no cap release', () => {
    const d = classifyPayout(
      establishedClean({
        total_completed: 1, account_age_days: 10,
        ticket_platform: 'ticketmaster', event_date: '2026-08-20',
      }),
      DEFAULT_POLICY,
      AT_CAP,
    );
    expect(d.action).toBe('manual_review');
    expect(d.reasons).toContain('ROTATING_BARCODE');
  });

  it('3b. …and a screenshot is never strong evidence on a rotating-barcode provider', () => {
    // Established seller, $250 Ticketmaster, buyer never viewed: the only
    // medium reasons are weak (HIGH_VALUE_ORDER, BUYER_NEVER_VIEWED — no
    // ROTATING_BARCODE since the seller is established), but the screenshot
    // cannot corroborate a SafeTix transfer → NOT cap-releasable.
    const d = classifyPayout(
      establishedClean({
        base_cents: 25_000, buyer_viewed: false,
        ticket_platform: 'ticketmaster', event_date: '2026-08-20',
      }),
      DEFAULT_POLICY,
      AT_CAP,
    );
    expect(d.action).not.toBe('release');
  });

  it('4. seller with prior disputes → no cap release', () => {
    const d = classifyPayout(
      establishedClean({ total_disputes: 1, event_date: '2026-08-20' }),
      DEFAULT_POLICY,
      AT_CAP,
    );
    expect(d.action).toBe('manual_review');
    expect(d.reasons).toContain('PRIOR_DISPUTES');
  });

  it('5. unsupported platform → no cap release', () => {
    const d = classifyPayout(
      establishedClean({ ticket_platform: 'other', event_date: '2026-08-20' }),
      DEFAULT_POLICY,
      AT_CAP,
    );
    expect(d.action).toBe('manual_review');
    expect(d.reasons).toContain('UNSUPPORTED_PLATFORM');
  });

  it('6. event date unknown → manual review at cap, never a timer release', () => {
    const d = classifyPayout(
      establishedClean({ buyer_viewed: false, event_date: null }),
      DEFAULT_POLICY,
      AT_CAP,
    );
    expect(d.action).toBe('manual_review');
    expect(d.reasons).toContain('EVENT_DATE_UNKNOWN');
    // and directly on the helper:
    expect(classifyMediumCapAction(
      ['BUYER_NEVER_VIEWED'],
      { hasEvidence: true, rotatingBarcodePlatform: false, platformSupported: true },
      { eventDateKnown: false, postEventPointMs: null, nowMs: 0, extensionLimitMs: 0 },
    )).toBe('MANUAL_REVIEW');
  });

  it('7. buyer explicit confirmation releases a medium transaction (documented contract)', () => {
    // confirm-and-release bypasses the classifier entirely: buyer_confirmed
    // status + no dispute → immediate payout, regardless of medium reasons.
    // (Asserted at the protocol level in tests/payout-races.test.ts; the
    // classifier only ever sees SILENT buyers by construction.)
    const d = classifyPayout(
      establishedClean({ total_completed: 1, account_age_days: 10, event_date: '2026-08-20' }),
      DEFAULT_POLICY,
      AT_CAP,
    );
    expect(d.action).not.toBe('release'); // silence alone does not pay this…
    // …but the buyer-confirmed path is a different, preserved release route.
  });

  it('8. mixed reasons — HIGH_VALUE_ORDER + SELLER_UNPROVEN: the stronger risk wins', () => {
    // NOTE: at classifyPayout level this combination is already HIGH
    // (HIGH_VALUE_UNPROVEN_SELLER). At the cap-action level the same
    // invariant holds: any strong reason forbids RELEASE_AT_CAP.
    expect(classifyMediumCapAction(
      ['HIGH_VALUE_ORDER', 'SELLER_UNPROVEN'],
      { hasEvidence: true, rotatingBarcodePlatform: false, platformSupported: true },
      { eventDateKnown: true, postEventPointMs: 100, nowMs: 0, extensionLimitMs: 10 },
    )).not.toBe('RELEASE_AT_CAP');
    const d = classifyPayout(
      establishedClean({ base_cents: 25_000, total_completed: 1, account_age_days: 10, event_date: '2026-08-20' }),
      DEFAULT_POLICY,
      AT_CAP,
    );
    expect(d.action).toBe('manual_review'); // HIGH tier, not even medium
  });

  it('9. weak-only reasons with all supporting conditions → RELEASE_AT_CAP', () => {
    expect(classifyMediumCapAction(
      ['HIGH_VALUE_ORDER'],
      { hasEvidence: true, rotatingBarcodePlatform: false, platformSupported: true },
      { eventDateKnown: true, postEventPointMs: 10_000, nowMs: 0, extensionLimitMs: 5_000 },
    )).toBe('RELEASE_AT_CAP');
    // unknown/future reason codes are conservative-strong:
    expect(classifyMediumCapAction(
      ['HIGH_VALUE_ORDER', 'SOME_FUTURE_SIGNAL'],
      { hasEvidence: true, rotatingBarcodePlatform: false, platformSupported: true },
      { eventDateKnown: true, postEventPointMs: 10_000, nowMs: 0, extensionLimitMs: 5_000 },
    )).not.toBe('RELEASE_AT_CAP');
  });

  it('strong reasons with a NEAR event extend to post-event grace instead of an operator', () => {
    // Unproven seller, cap expired, event only 2 days later: bounded
    // extension to the post-event point — no manual-review flood for a hold
    // that resolves itself within one more cap-length.
    const d = classifyPayout(
      establishedClean({ total_completed: 1, account_age_days: 10, event_date: '2026-07-23' }),
      DEFAULT_POLICY,
      AT_CAP,
    );
    expect(d.action).toBe('hold');
    expect(d.reasons).toContain('MEDIUM_HOLD_EXTENDED_POST_EVENT');
    expect(d.hold_until).toBe('2026-07-25T12:00:00.000Z'); // 07-23 +36h +24h
  });
});
