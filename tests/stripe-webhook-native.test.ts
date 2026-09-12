/**
 * E3 — the stripe-webhook NATIVE PRIMARY branch and the `account.updated`
 * ORGANIZATION arm (owner rulings A2, A3, A6, A8).
 *
 * WHAT THIS PROVES, AND WHAT IT DOES NOT
 *   Every decision that decides whether tickets are minted, whether an order is
 *   cancelled, and whether Stripe retries lives in `stripe-webhook/native.ts`
 *   and is exercised here exactly. What is NOT provable from TypeScript, and is
 *   called out inline where it matters:
 *     • `venue.finalize_primary_order`'s own idempotency (the order-status
 *       re-check under lock at 085:1969, `payment_native_payment_uq`,
 *       `ownership_log_command_uq`) is enforced INSIDE Postgres and is
 *       unreachable from here. What IS testable is the command key the edge
 *       presents, which is what makes those DB guarantees bite across
 *       redeliveries — and that is tested.
 *     • the HMAC signature path is untouched by this work and is exercised by
 *       the existing deployment, not re-simulated here.
 *     • whether a given Postgres error string is ever actually raised is a
 *       property of the migrations, not of the classifier. The classifier is
 *       tested against the EXACT strings 082/085/093 raise, quoted inline.
 */
import { describe, expect, it } from 'vitest';
import {
  CANCEL_REASON_PAYMENT_FAILED,
  PAYMENT_ROW_GRACE_SECONDS,
  RAIL_NATIVE_PRIMARY,
  buildCancelCommandKey,
  buildFinalizeCommandKey,
  buildOrgSyncCommandKey,
  classifyCancelError,
  classifyFinalizeError,
  classifyOrgSyncError,
  decideAbsentPaymentRow,
  decideAccountUpdatedOutcome,
  decideClaimOutcome,
  deriveTransfersActive,
  dispositionForRoute,
  eventAgeSeconds,
  extractInstrumentFingerprint,
  interpretPaymentClaim,
  isConnectAccountRef,
  isTerminalPaymentIntent,
  isUuid,
  latestChargeId,
  observedAtIso,
  readNativeMetadata,
  resolveRail,
  selectAccountPlane,
  verifyNativePaymentRow,
  type PaymentRow,
} from '../supabase/functions/stripe-webhook/native';

const ORDER = '11111111-1111-4111-8111-111111111111';
const BUYER = '22222222-2222-4222-8222-222222222222';
const ORG   = '33333333-3333-4333-8333-333333333333';
const SESS  = '44444444-4444-4444-8444-444444444444';
const PI    = 'pi_3QabcDEF';
const ACCT  = 'acct_1QzzzXYZ';

/** Exactly what primary-checkout:974-979 puts on the PaymentIntent. */
const NATIVE_METADATA = {
  rail:       RAIL_NATIVE_PRIMARY,
  mode:       RAIL_NATIVE_PRIMARY,
  order_id:   ORDER,
  buyer_id:   BUYER,
  org_id:     ORG,
  session_id: SESS,
};

function nativePaymentRow(over: Partial<PaymentRow> = {}): PaymentRow {
  return {
    id: '55555555-5555-4555-8555-555555555555',
    status: 'succeeded',
    mode: 'native_primary',
    listing_id: null,
    seller_id: null,
    buyer_id: BUYER,
    total: 11000,
    ...over,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
describe('rail dispatch — the third branch (spec §4:1206, keyed off metadata.rail)', () => {
  it('routes a well-formed primary-checkout PaymentIntent to the native branch', () => {
    expect(resolveRail(NATIVE_METADATA)).toEqual({ route: 'native_primary' });
  });

  it('routes every legacy resale shape to the untouched legacy selector', () => {
    // create-payment-intent sets NO `rail` key at all. Absence is the only
    // legitimate resale signal (primary-checkout:236-241).
    expect(resolveRail({ mode: 'buy_now', listing_id: 'x', seller_id: 'y' }).route).toBe('legacy_resale');
    expect(resolveRail({ mode: 'auction' }).route).toBe('legacy_resale');
    expect(resolveRail({}).route).toBe('legacy_resale');
    expect(resolveRail(null).route).toBe('legacy_resale');
    // An empty-string rail is absence, not a value.
    expect(resolveRail({ rail: '  ', mode: 'buy_now' }).route).toBe('legacy_resale');
  });

  it('fails CLOSED when rail and mode disagree — never dispatches on one of them', () => {
    // "THE TWO MUST NEVER DISAGREE … treat that as tampering or corruption and
    // fail closed" (primary-checkout:214-216).
    expect(resolveRail({ ...NATIVE_METADATA, mode: 'buy_now' }).route).toBe('rail_mode_mismatch');
    expect(resolveRail({ ...NATIVE_METADATA, mode: '' }).route).toBe('rail_mode_mismatch');
    // The reverse drift: mode claims the direct rail with no rail key.
    expect(resolveRail({ mode: RAIL_NATIVE_PRIMARY, order_id: ORDER }).route).toBe('rail_mode_mismatch');
  });

  it('refuses an unimplemented rail rather than falling through to a resale money path', () => {
    // A future `native_resale` must NOT run mark_listing_sold.
    const route = resolveRail({ rail: 'native_resale', mode: 'native_resale' });
    expect(route).toEqual({ route: 'unknown_rail', rail: 'native_resale' });
    expect(route.route).not.toBe('legacy_resale');
  });
});

describe('dispatch dispositions — which refusals cost Stripe three days of retries', () => {
  it('ACKs a rail/mode mismatch: no redelivery can change what the event says', () => {
    const d = dispositionForRoute({ route: 'rail_mode_mismatch', rail: 'native_primary', mode: 'buy_now' });
    expect(d).toEqual({ ack: true, alert: true, reason: 'rail_mode_mismatch' });
  });

  it('holds an unimplemented rail for replay, per the pinned fail-closed rule', () => {
    const d = dispositionForRoute({ route: 'unknown_rail', rail: 'native_resale' });
    expect(d.ack).toBe(false);   // "leave the event for replay"
    expect(d.alert).toBe(true);  // "fail closed, alert"
  });

  it('REGRESSION — a native_primary PaymentIntent no longer reaches the unknown-mode 500', () => {
    // Before this branch existed, `mode='native_primary'` fell through the
    // CLOSED two-branch legacy selection to its explicit error return, which
    // called finish(false, …) → HTTP 500 → Stripe retried for three days with
    // the buyer charged and no ticket minted. The native route is now taken
    // BEFORE that selector runs, and the route is not the legacy one.
    const route = resolveRail(NATIVE_METADATA);
    expect(route.route).toBe('native_primary');
    expect(route.route).not.toBe('legacy_resale');
    // And the one shape that still cannot be dispatched now ACKs instead of
    // retrying, so no native-labelled charge can retry for days any more.
    expect(dispositionForRoute(resolveRail({ mode: RAIL_NATIVE_PRIMARY })).ack).toBe(true);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('native metadata — order_id and buyer_id are load-bearing', () => {
  it('reads the full reference from a primary-checkout PaymentIntent', () => {
    const r = readNativeMetadata(NATIVE_METADATA);
    expect(r).toEqual({ ok: true, ref: { orderId: ORDER, buyerId: BUYER, orgId: ORG, sessionId: SESS } });
  });

  it('refuses a missing or malformed order_id / buyer_id rather than passing it to Postgres', () => {
    expect(readNativeMetadata({ ...NATIVE_METADATA, order_id: undefined })).toEqual({ ok: false, reason: 'missing_order_id' });
    expect(readNativeMetadata({ ...NATIVE_METADATA, order_id: 'not-a-uuid' })).toEqual({ ok: false, reason: 'missing_order_id' });
    expect(readNativeMetadata({ ...NATIVE_METADATA, buyer_id: '' })).toEqual({ ok: false, reason: 'missing_buyer_id' });
  });

  it('tolerates absent org_id / session_id — neither is load-bearing for issuance', () => {
    const r = readNativeMetadata({ rail: RAIL_NATIVE_PRIMARY, mode: RAIL_NATIVE_PRIMARY, order_id: ORDER, buyer_id: BUYER });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.ref).toMatchObject({ orgId: null, sessionId: null });
  });

  it('isUuid rejects the near-misses that would otherwise reach the database', () => {
    expect(isUuid(ORDER)).toBe(true);
    expect(isUuid(`${ORDER} `)).toBe(false);
    expect(isUuid(ORDER.replace(/-/g, ''))).toBe(false);
    expect(isUuid(null)).toBe(false);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('EXACT-ONCE — the command key is an invariant of the economic fact', () => {
  it('is identical for every delivery of every event about the same payment', () => {
    // This is the whole argument. finalize forwards the key to
    // issue_ticket_atoms as `key || ':' || order_item.id`, which lands under
    // ownership_log_command_uq. Two Stripe event ids naming the same PI must
    // present the SAME key or the mint's replay short-circuit misses.
    const first  = buildFinalizeCommandKey(ORDER, PI);
    const second = buildFinalizeCommandKey(ORDER, PI);
    expect(first).toBe(second);
    expect(first).not.toContain('evt_');
  });

  it('is distinct per order and per PaymentIntent', () => {
    expect(buildFinalizeCommandKey(ORDER, PI)).not.toBe(buildFinalizeCommandKey(BUYER, PI));
    expect(buildFinalizeCommandKey(ORDER, PI)).not.toBe(buildFinalizeCommandKey(ORDER, 'pi_other'));
  });

  it('never collides with the cancel key for the same order', () => {
    expect(buildFinalizeCommandKey(ORDER, PI)).not.toBe(buildCancelCommandKey(ORDER, PI));
  });

  it('keys the org sync on the delivery, because that RPC dedupes on time, not on the key', () => {
    expect(buildOrgSyncCommandKey('evt_1')).not.toBe(buildOrgSyncCommandKey('evt_2'));
  });

  it('produces non-empty keys — both RPCs reject a blank command key', () => {
    for (const k of [buildFinalizeCommandKey(ORDER, PI), buildCancelCommandKey(ORDER, PI), buildOrgSyncCommandKey('evt_1')]) {
      expect(k.trim().length).toBeGreaterThan(0);
    }
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('payments-row claim — replay, duplicate delivery, and out-of-order events', () => {
  it('a fresh claim proceeds to finalize', () => {
    const row = nativePaymentRow({ status: 'succeeded' });
    const outcome = interpretPaymentClaim(row, null);
    expect(outcome.kind).toBe('claimed');
    expect(decideClaimOutcome(outcome, 5)).toEqual({ ack: true, alert: false, reason: 'proceed_to_finalize' });
  });

  it('a duplicate delivery still proceeds — finalize is idempotent and returns the same atoms', () => {
    // The claim UPDATE matched 0 rows because the row is already succeeded.
    // Calling finalize anyway is CORRECT: it short-circuits to
    // idempotency_replay (085:1969-1975) and re-reports the original atom set.
    // Skipping it would strand an order whose first delivery died between the
    // claim and the RPC.
    const outcome = interpretPaymentClaim(null, nativePaymentRow({ status: 'succeeded' }));
    expect(outcome.kind).toBe('already_succeeded');
    expect(decideClaimOutcome(outcome, 5).ack).toBe(true);
    expect(decideClaimOutcome(outcome, 5).reason).toBe('proceed_to_finalize');
  });

  it('OUT OF ORDER: a refund that preceded the success never mints a ticket', () => {
    // R6 P2. The native claim carries .neq('status','refunded') so the refund
    // fact survives; the decision then refuses issuance outright rather than
    // letting finalize raise payment_unverified.
    const outcome = interpretPaymentClaim(null, nativePaymentRow({ status: 'refunded' }));
    expect(outcome.kind).toBe('refunded');
    const d = decideClaimOutcome(outcome, 5);
    expect(d).toEqual({ ack: true, alert: true, reason: 'out_of_order_refund_precedes_success' });
  });

  it('an unrecognised payment status is ACKed and alerted, never finalized', () => {
    const outcome = interpretPaymentClaim(null, nativePaymentRow({ status: 'cancelled' }));
    expect(outcome.kind).toBe('unexpected_status');
    expect(decideClaimOutcome(outcome, 5)).toEqual({ ack: true, alert: true, reason: 'payment_row_unexpected_status' });
  });

  it('a missing payments row is retried while the event is young, then ACKed and alerted', () => {
    // The cost of ACKing too early is a paid buyer with no tickets and no
    // retries left; the cost of retrying forever is a buried alert. Bounded.
    expect(decideAbsentPaymentRow(1).ack).toBe(false);
    expect(decideAbsentPaymentRow(PAYMENT_ROW_GRACE_SECONDS - 1).ack).toBe(false);
    expect(decideAbsentPaymentRow(PAYMENT_ROW_GRACE_SECONDS)).toEqual({
      ack: true, alert: true, reason: 'payment_row_absent_terminal',
    });
    // An undated event could be days old — take the conservative (terminal) side.
    expect(decideAbsentPaymentRow(Number.POSITIVE_INFINITY).ack).toBe(true);
  });

  it('eventAgeSeconds treats an unusable `created` as infinitely old', () => {
    const now = 1_700_000_000_000;
    expect(eventAgeSeconds(1_699_999_400, now)).toBe(600);
    expect(eventAgeSeconds(undefined, now)).toBe(Number.POSITIVE_INFINITY);
    expect(eventAgeSeconds(0, now)).toBe(Number.POSITIVE_INFINITY);
    // A future-dated event is age 0, never negative.
    expect(eventAgeSeconds(1_700_000_900, now)).toBe(0);
  });
});

describe('payments-row verification — one PaymentIntent maps to exactly one primary order', () => {
  it('accepts the shape the 093 rail-pairing CHECK permits', () => {
    const ref = { orderId: ORDER, buyerId: BUYER, orgId: ORG, sessionId: SESS };
    expect(verifyNativePaymentRow(nativePaymentRow(), ref)).toEqual({ ok: true });
  });

  it('refuses a resale payments row — a native PI must never finalize against one', () => {
    const ref = { orderId: ORDER, buyerId: BUYER, orgId: ORG, sessionId: SESS };
    const v = verifyNativePaymentRow(nativePaymentRow({ mode: 'buy_now', listing_id: 'l', seller_id: 's' }), ref);
    expect(v.ok).toBe(false);
    if (!v.ok) expect(v.decision).toEqual({ ack: true, alert: true, reason: 'payment_row_wrong_rail' });
  });

  it('refuses a native row carrying a listing or a seller — the CHECK would be gone', () => {
    const ref = { orderId: ORDER, buyerId: BUYER, orgId: ORG, sessionId: SESS };
    const withListing = verifyNativePaymentRow(nativePaymentRow({ listing_id: 'l' }), ref);
    const withSeller  = verifyNativePaymentRow(nativePaymentRow({ seller_id: 's' }), ref);
    expect(withListing.ok).toBe(false);
    expect(withSeller.ok).toBe(false);
    if (!withListing.ok) expect(withListing.decision.reason).toBe('payment_row_rail_pairing_violated');
  });

  it('refuses a row belonging to another buyer (C35, before the RPC re-asserts it)', () => {
    const ref = { orderId: ORDER, buyerId: BUYER, orgId: ORG, sessionId: SESS };
    const v = verifyNativePaymentRow(nativePaymentRow({ buyer_id: ORG }), ref);
    expect(v.ok).toBe(false);
    if (!v.ok) expect(v.decision.reason).toBe('payment_row_buyer_mismatch');
  });

  it('every verification failure ACKs — none of them can change on redelivery', () => {
    const ref = { orderId: ORDER, buyerId: BUYER, orgId: ORG, sessionId: SESS };
    for (const row of [
      nativePaymentRow({ mode: 'auction' }),
      nativePaymentRow({ listing_id: 'l' }),
      nativePaymentRow({ buyer_id: ORG }),
    ]) {
      const v = verifyNativePaymentRow(row, ref);
      expect(v.ok).toBe(false);
      if (!v.ok) expect(v.decision).toMatchObject({ ack: true, alert: true });
    }
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('finalize_primary_order error classification (085:1881-2082)', () => {
  // The exact strings 085 raises.
  const TERMINAL: Array<[string, string]> = [
    ['payment_unverified: payment 55… already carries a refund',                'finalize_payment_unverified'],
    ['payment_unverified: payment buyer does not match order buyer',            'finalize_payment_unverified'],
    ['payment_unverified: payment 55… (100 minor) does not cover order …',      'finalize_payment_unverified'],
    ['precondition_failed: buyer identity is erased — no acquisition',          'finalize_buyer_erased'],
    ['precondition_failed: order 11… is cancelled — only a pending order finalizes', 'finalize_order_not_pending'],
    ['oversell_rejected: item 9 needs 2 — batch 4 has no headroom',             'finalize_oversell'],
    ['precondition_failed: no reservation names a batch for item 9',            'finalize_no_reservation'],
    ['invalid_input: order id required',                                        'finalize_invalid_input'],
  ];

  it.each(TERMINAL)('ACKs and alerts on %s', (message, reason) => {
    expect(classifyFinalizeError({ message, code: 'P0001' })).toEqual({ ack: true, alert: true, reason });
  });

  it('ACKs a not_found order (P0002) — retrying will not conjure one', () => {
    const d = classifyFinalizeError({ message: 'not_found: order 11…', code: 'P0002' });
    expect(d).toEqual({ ack: true, alert: true, reason: 'finalize_order_not_found' });
  });

  it('RETRIES a missing signing key — provisioning one makes the next delivery mint', () => {
    const d = classifyFinalizeError({
      message: 'precondition_failed: no_active_signing_key — an active signing key must resolve…',
      code: 'P0001',
    });
    expect(d).toEqual({ ack: false, alert: true, reason: 'finalize_no_signing_key' });
  });

  it('RETRIES a missing GRANT — PFA-15/PFA-21 reachability is ops-fixable in the window', () => {
    expect(classifyFinalizeError({ message: 'permission denied for function finalize_primary_order', code: '42501' }))
      .toEqual({ ack: false, alert: true, reason: 'finalize_not_granted' });
  });

  it.each(['40001', '40P01', '08006', '53300', '57014', '58030', 'XX000'])(
    'RETRIES transient Postgres class %s',
    (code) => {
      expect(classifyFinalizeError({ message: 'could not serialize access', code }).ack).toBe(false);
    },
  );

  it('RETRIES anything unrecognised — fail toward not losing the money event', () => {
    expect(classifyFinalizeError({ message: 'something nobody predicted', code: 'P0001' }))
      .toEqual({ ack: false, alert: true, reason: 'finalize_unclassified' });
    expect(classifyFinalizeError(null).ack).toBe(false);
  });

  it('a terminal refusal is ALWAYS alerted — a silent ACK would lose the incident', () => {
    for (const [message] of TERMINAL) {
      expect(classifyFinalizeError({ message, code: 'P0001' }).alert).toBe(true);
    }
  });
});

describe('cancel_pending_order error classification (082:478-525)', () => {
  it('uses the closed set of one for the reason code', () => {
    expect(CANCEL_REASON_PAYMENT_FAILED).toBe('payment_failed');
  });

  it('ACKs order_not_pending — the order was PAID, money won, nothing to cancel', () => {
    expect(classifyCancelError({ message: 'precondition_failed: order_not_pending (status=paid)', code: 'P0001' }))
      .toEqual({ ack: true, alert: true, reason: 'cancel_order_not_pending' });
  });

  it('ACKs a not_found order and an invalid_input', () => {
    expect(classifyCancelError({ message: 'not_found: order 11…', code: 'P0002' }).ack).toBe(true);
    expect(classifyCancelError({ message: 'invalid_input: command key required', code: 'P0001' }).ack).toBe(true);
  });

  it('RETRIES transient failures and missing grants', () => {
    expect(classifyCancelError({ message: 'deadlock detected', code: '40P01' }).ack).toBe(false);
    expect(classifyCancelError({ message: 'permission denied', code: '42501' }).ack).toBe(false);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('PaymentIntent terminality — a decline is not a cancellation (spec §4)', () => {
  it('treats only status=canceled as terminal', () => {
    expect(isTerminalPaymentIntent({ status: 'canceled' })).toBe(true);
  });

  it('leaves the order pending for every retryable failure state', () => {
    // §3.1's retry contract: the buyer re-confirms the SAME PI in the SAME
    // PaymentSheet. Cancelling here would destroy an order still being paid for.
    for (const status of ['requires_payment_method', 'requires_action', 'processing', 'requires_confirmation']) {
      expect(isTerminalPaymentIntent({ status })).toBe(false);
    }
    expect(isTerminalPaymentIntent(null)).toBe(false);
    expect(isTerminalPaymentIntent({})).toBe(false);
  });

  it('never treats a succeeded PaymentIntent as terminal-for-cancel', () => {
    expect(isTerminalPaymentIntent({ status: 'succeeded' })).toBe(false);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('instrument fingerprint — advisory input, never a blocker', () => {
  it('reads the fingerprint off the type-named sub-object', () => {
    expect(extractInstrumentFingerprint({
      payment_method_details: { type: 'card', card: { fingerprint: 'fp_abc', last4: '4242' } },
    })).toBe('fp_abc');
  });

  it('returns null — the legitimate "no signal" — for every missing shape', () => {
    expect(extractInstrumentFingerprint(null)).toBeNull();
    expect(extractInstrumentFingerprint({})).toBeNull();
    expect(extractInstrumentFingerprint({ payment_method_details: { type: 'card' } })).toBeNull();
    expect(extractInstrumentFingerprint({ payment_method_details: { type: 'card', card: {} } })).toBeNull();
    expect(extractInstrumentFingerprint({ payment_method_details: { card: { fingerprint: 'x' } } })).toBeNull();
    expect(extractInstrumentFingerprint('pi_x')).toBeNull();
  });

  it('accepts latest_charge as an id or as an expanded object', () => {
    expect(latestChargeId({ latest_charge: 'ch_1' })).toBe('ch_1');
    expect(latestChargeId({ latest_charge: { id: 'ch_2' } })).toBe('ch_2');
    expect(latestChargeId({ latest_charge: null })).toBeNull();
    expect(latestChargeId({})).toBeNull();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('account.updated — plane selection (ruling A6)', () => {
  it('takes the org arm on connect-onboarding\'s explicit discriminator', () => {
    expect(selectAccountPlane({ snatchit_plane: 'organization', org_id: ORG }))
      .toEqual({ organization: true, orgId: ORG, explicitOrgTag: true });
  });

  it('takes the org arm on org_id alone (accounts predating the discriminator)', () => {
    expect(selectAccountPlane({ org_id: ORG })).toEqual({ organization: true, orgId: ORG, explicitOrgTag: false });
  });

  it('takes the org arm on the discriminator alone — the account ref is the primary selector', () => {
    const p = selectAccountPlane({ snatchit_plane: 'organization' });
    expect(p.organization).toBe(true);
    expect(p.orgId).toBeNull();
  });

  it('leaves an ordinary seller account entirely on the individual plane', () => {
    expect(selectAccountPlane({ user_id: BUYER })).toEqual({ organization: false, orgId: null, explicitOrgTag: false });
    expect(selectAccountPlane(null).organization).toBe(false);
  });

  it('does not accept a malformed org_id as a selector', () => {
    expect(selectAccountPlane({ org_id: 'not-a-uuid' })).toEqual({ organization: false, orgId: null, explicitOrgTag: false });
  });

  it('validates the acct_ ref the same way the RPC does (093:1337)', () => {
    expect(isConnectAccountRef(ACCT)).toBe(true);
    expect(isConnectAccountRef('acct_')).toBe(false);
    expect(isConnectAccountRef('cus_123')).toBe(false);
    expect(isConnectAccountRef(undefined)).toBe(false);
  });
});

describe('account.updated — transfers_active comes from the CAPABILITY (ruling A8)', () => {
  it('is true only when capabilities.transfers === "active"', () => {
    expect(deriveTransfersActive({ capabilities: { transfers: 'active' } })).toBe(true);
    expect(deriveTransfersActive({ capabilities: { transfers: 'pending' } })).toBe(false);
    expect(deriveTransfersActive({ capabilities: { transfers: 'inactive' } })).toBe(false);
    expect(deriveTransfersActive({ capabilities: {} })).toBe(false);
    expect(deriveTransfersActive({})).toBe(false);
    expect(deriveTransfersActive(null)).toBe(false);
  });

  it('IGNORES charges_enabled — it is false forever on a correct org account', () => {
    // connect-onboarding requests capabilities[transfers] and deliberately NOT
    // card_payments (:544). A gate on charges_enabled keeps every venue dark.
    expect(deriveTransfersActive({
      charges_enabled: false, payouts_enabled: false, details_submitted: true,
      capabilities: { transfers: 'active' },
    })).toBe(true);
  });

  it('IGNORES payouts_enabled — F §3.5 rules it explicitly not a sale gate', () => {
    expect(deriveTransfersActive({ payouts_enabled: false, capabilities: { transfers: 'active' } })).toBe(true);
    expect(deriveTransfersActive({ charges_enabled: true, payouts_enabled: true, capabilities: {} })).toBe(false);
  });

  it('is NON-MONOTONIC: a disabled account reports false and must stop selling', () => {
    const gained = deriveTransfersActive({ capabilities: { transfers: 'active' } });
    const lost   = deriveTransfersActive({ capabilities: { transfers: 'inactive' } });
    expect(gained).toBe(true);
    expect(lost).toBe(false);
  });
});

describe('account.updated — p_observed_at is the EVENT instant, not now()', () => {
  it('converts the event timestamp so a stale redelivery is recognised as older', () => {
    expect(observedAtIso(1_700_000_000)).toBe(new Date(1_700_000_000_000).toISOString());
  });

  it('passes null when the event carries no usable instant, letting the RPC default to now()', () => {
    expect(observedAtIso(undefined)).toBeNull();
    expect(observedAtIso(0)).toBeNull();
    expect(observedAtIso('1700000000')).toBeNull();
    expect(observedAtIso(Number.NaN)).toBeNull();
  });

  it('an older redelivery yields an earlier instant than a newer observation', () => {
    const older = observedAtIso(1_700_000_000)!;
    const newer = observedAtIso(1_700_000_600)!;
    expect(older < newer).toBe(true);
  });
});

describe('sync_org_connect_state error classification (093:1300-1404)', () => {
  it('ACKs a not_found org WITHOUT alerting — the onboarding bind has simply not landed yet', () => {
    // Safe to drop: the gate operand defaults FALSE, so a lost "gained"
    // observation only under-permits. A lost "lost" observation is impossible
    // here — losing a capability requires the org to already be bound.
    expect(classifyOrgSyncError({ message: 'not_found: organization for acct_1', code: 'P0002' }))
      .toEqual({ ack: true, alert: false, reason: 'org_sync_org_not_bound' });
  });

  it('ACKs and ALERTS the G-4/A9 refusal — the event names a superseded account', () => {
    expect(classifyOrgSyncError({
      message: 'conflict_locked: acct_1 is not the bound destination of org 33…', code: 'P0001',
    })).toEqual({ ack: true, alert: true, reason: 'org_sync_account_not_bound_destination' });
  });

  it('ACKs and ALERTS a malformed ref or a bad argument', () => {
    expect(classifyOrgSyncError({ message: 'precondition_failed: malformed_account_ref', code: 'P0001' }))
      .toMatchObject({ ack: true, alert: true });
    expect(classifyOrgSyncError({ message: 'invalid_input: transfers_active … may not be null', code: 'P0001' }))
      .toMatchObject({ ack: true, alert: true });
  });

  it('RETRIES transient failures — losing a capability-LOST observation leaves an org selling', () => {
    expect(classifyOrgSyncError({ message: 'connection failure', code: '08006' }).ack).toBe(false);
    expect(classifyOrgSyncError({ message: 'permission denied', code: '42501' }).ack).toBe(false);
    expect(classifyOrgSyncError({ message: 'unheard of', code: 'P0001' }).ack).toBe(false);
  });
});

describe('account.updated — a zero match is never reported as plain success', () => {
  it('reports the individual plane exactly as before when a profile matched', () => {
    expect(decideAccountUpdatedOutcome(1, 'skipped'))
      .toEqual({ matched: 'individual', alert: false, reason: 'individual_synced' });
  });

  it('reports the organization plane on ok and on noop_replay', () => {
    expect(decideAccountUpdatedOutcome(0, 'ok')).toMatchObject({ matched: 'organization', alert: false });
    expect(decideAccountUpdatedOutcome(0, 'noop_replay')).toMatchObject({ matched: 'organization', alert: false });
  });

  it('ALERTS when NEITHER plane matched — the exact hole this arm closes', () => {
    // Previously: `matched_profiles: 0` inside a cheerful success line, which is
    // how an org Connect account got created and then never monitored again.
    const o = decideAccountUpdatedOutcome(0, 'skipped');
    expect(o).toEqual({ matched: 'none', alert: true, reason: 'account_unmatched_on_both_planes' });
  });

  it('ALERTS an org-planed account that is bound to no organization', () => {
    expect(decideAccountUpdatedOutcome(0, 'org_not_bound'))
      .toEqual({ matched: 'none', alert: true, reason: 'org_account_not_bound_to_any_org' });
  });

  it('ALERTS a refused or failed org sync', () => {
    expect(decideAccountUpdatedOutcome(0, 'refused')).toMatchObject({ matched: 'none', alert: true });
    expect(decideAccountUpdatedOutcome(0, 'failed')).toMatchObject({ matched: 'none', alert: true });
  });

  it('ALERTS cross-plane reuse — one acct_ serving both an org and a seller profile (A7/A9)', () => {
    expect(decideAccountUpdatedOutcome(1, 'ok'))
      .toEqual({ matched: 'both', alert: true, reason: 'cross_plane_account_reuse' });
  });

  it('every outcome keeps the ACK contract — this function never asks Stripe to retry', () => {
    // It returns no `ack` at all: the account.updated arm always answers 2xx.
    for (const arm of ['skipped', 'ok', 'noop_replay', 'org_not_bound', 'refused', 'failed'] as const) {
      const o = decideAccountUpdatedOutcome(0, arm);
      expect(o).not.toHaveProperty('ack');
      expect(typeof o.reason).toBe('string');
    }
  });
});
