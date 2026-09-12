/**
 * KW — the stripe-webhook NATIVE dispute arm and the native routing of
 * `transfer.reversed` (KH §4.5 / §4.6 decision tables; DESIGN_096 §2.1/§2.2).
 *
 * WHAT THIS PROVES, AND WHAT IT DOES NOT
 *   Every decision that decides whether a Stripe dispute reaches
 *   `kernel.record_dispute_native` / `kernel.mark_dispute_state`, whether a
 *   transfer reversal reaches `kernel.record_payout_reversal`, and whether
 *   Stripe retries lives in `stripe-webhook/native-dispute.ts`, import-free,
 *   and is exercised here row-by-row against KH §4.5 and §4.6. What is NOT
 *   provable from TypeScript, and is called out inline where it matters:
 *     • the kernel verbs' own idempotency (`dispute_native_stripe_ref_uq`,
 *       `payout_reversal_stripe_ref_uq`, the append-only/absorbing triggers)
 *       is enforced INSIDE Postgres and is unreachable from here — 096's own
 *       pgTAP suite (162) is the proof for that half.
 *     • whether a given Postgres error string is ever actually raised is a
 *       property of the migrations, not of the classifier. The classifier is
 *       tested against the EXACT strings 088:887-892 / 096 raise, quoted
 *       inline in native-dispute.ts and reproduced here verbatim.
 *   Where KH §4.6's table names a verb (`mark_payout_transfer_state`,
 *   `hold_payout_transfer_reversed`) that the SHIPPED implementation does not
 *   call directly — DESIGN_096 §2.2 supersedes KH there: the native arm calls
 *   `kernel.record_payout_reversal` for every reversal fact, and that verb's
 *   own `held` / `ok` / `noop_replay` results are what `interpretReversalResult`
 *   and `classifyReversalError` are tested against below. Per the shared brief
 *   ("where this memo and a report disagree, this memo wins"), the DESIGN memo
 *   and the shipped code are what these tests pin — not the superseded rows.
 */
import { describe, expect, it } from 'vitest';
import {
  aggregateDecisions,
  buildDisputeCommandKey,
  buildReversalCommandKey,
  classifyDisputeError,
  classifyReversalError,
  COMMAND_KEY_RE,
  disputeEventKind,
  disputeMarkArgs,
  disputeRecordArgs,
  disputeStatusKnown,
  DISPUTE_LOSS_STATUSES,
  DISPUTE_STATUSES,
  DISPUTE_TERMINAL_STATUSES,
  evidenceDueAtIso,
  interpretMarkResult,
  interpretRecordResult,
  interpretReversalResult,
  isDisputeNotFound,
  isLossStatus,
  isTerminalDisputeStatus,
  isValidCommandKey,
  mergeReversals,
  planDisputeVerb,
  planReversalRecording,
  readInlineReversals,
  resolveDisputeRail,
  resolveTransferRail,
  TRANSFER_REF_RE,
  TRANSFER_REVERSAL_REF_RE,
  type DisputeLike,
  type DisputePaymentRow,
  type TransferLike,
} from '../supabase/functions/stripe-webhook/native-dispute';

// ── fixtures ────────────────────────────────────────────────────────────────

const PAYOUT = '11111111-1111-4111-8111-111111111111';
const PAYOUT_2 = '22222222-2222-4222-8222-222222222222';
const PAYMENT_ID = '99999999-9999-4999-8999-999999999999';
const PI = 'pi_3QabcDEF';
const CHARGE = 'ch_3QabcDEF';
const DISPUTE_EVENT_ID = 'evt_test0000000000000001';

function paymentRow(over: Partial<DisputePaymentRow> = {}): DisputePaymentRow {
  return { id: PAYMENT_ID, mode: 'native_primary', stripe_livemode: true, status: 'succeeded', ...over };
}

function disputeLike(over: Partial<DisputeLike> = {}): DisputeLike {
  return {
    id: 'dp_ABC123XYZ',
    charge: CHARGE,
    payment_intent: PI,
    amount: 5000,
    currency: 'usd',
    reason: 'fraudulent',
    status: 'needs_response',
    evidence_details: { due_by: 1700000000 },
    ...over,
  };
}

// ════════════════════════════════════════════════════════════════════════════
// 1. `resolveDisputeRail` — the discriminator (KH §4.2 / §4.5 pre-steps 0-3)
// ════════════════════════════════════════════════════════════════════════════

describe('resolveDisputeRail — DB-derived, never metadata (a Dispute carries none)', () => {
  it('pre-step (0): a null payment_intent is legacy by construction', () => {
    const route = resolveDisputeRail(paymentRow(), disputeLike({ payment_intent: null }), true);
    expect(route).toEqual({ route: 'legacy', why: 'no_payment_intent' });
  });

  it('pre-step (1): no payments row for the PI is legacy — the legacy arm already tolerates a null paymentId', () => {
    expect(resolveDisputeRail(null, disputeLike(), true)).toEqual({ route: 'legacy', why: 'payment_row_absent' });
    expect(resolveDisputeRail(undefined, disputeLike(), true)).toEqual({ route: 'legacy', why: 'payment_row_absent' });
  });

  it('pre-step (2): mode !== native_primary (buy_now / auction) is legacy', () => {
    const route = resolveDisputeRail(paymentRow({ mode: 'buy_now' }), disputeLike(), true);
    expect(route).toEqual({ route: 'legacy', why: 'legacy_mode' });
  });

  it('native mode + livemode true on both sides ⇒ native', () => {
    const route = resolveDisputeRail(paymentRow({ mode: 'native_primary', stripe_livemode: true }), disputeLike(), true);
    expect(route).toEqual({ route: 'native', paymentId: PAYMENT_ID });
  });

  it('pre-step (3): native mode but event.livemode !== true ⇒ ack+alert native_dispute_not_livemode, legacy still runs', () => {
    const route = resolveDisputeRail(paymentRow({ stripe_livemode: true }), disputeLike(), false);
    expect(route.route).toBe('not_livemode');
    if (route.route === 'not_livemode') {
      expect(route.paymentId).toBe(PAYMENT_ID);
      expect(route.decision).toEqual({ ack: true, alert: true, reason: 'native_dispute_not_livemode' });
    }
  });

  it('pre-step (3), the other side: native mode but the ROW is not livemode ⇒ same not_livemode route', () => {
    const route = resolveDisputeRail(paymentRow({ stripe_livemode: false }), disputeLike(), true);
    expect(route.route).toBe('not_livemode');
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 2. Dispute status vocabulary — the 088:200-202 CHECK set, nothing else
// ════════════════════════════════════════════════════════════════════════════

describe('disputeStatusKnown — pre-step (4), the 8-label CHECK set only', () => {
  it('accepts exactly the 8 labels the kernel CHECK admits', () => {
    expect(DISPUTE_STATUSES).toHaveLength(8);
    for (const s of DISPUTE_STATUSES) expect(disputeStatusKnown(s)).toBe(true);
  });

  it('rejects Stripe\'s newer "prevented" — redelivery cannot fix an unrecognized status', () => {
    expect(disputeStatusKnown('prevented')).toBe(false);
  });

  it('rejects garbage and non-strings', () => {
    expect(disputeStatusKnown('resolved')).toBe(false);
    expect(disputeStatusKnown(undefined)).toBe(false);
    expect(disputeStatusKnown(null)).toBe(false);
    expect(disputeStatusKnown(42)).toBe(false);
  });

  it('terminal set is exactly won/lost/warning_closed/charge_refunded (088:878)', () => {
    expect(DISPUTE_TERMINAL_STATUSES).toEqual(['won', 'lost', 'warning_closed', 'charge_refunded']);
    for (const s of DISPUTE_TERMINAL_STATUSES) expect(isTerminalDisputeStatus(s)).toBe(true);
    expect(isTerminalDisputeStatus('needs_response')).toBe(false);
    expect(isTerminalDisputeStatus('prevented')).toBe(false);
  });

  it('loss set is exactly lost/charge_refunded — the two the chargeback arm reads as money lost', () => {
    expect(DISPUTE_LOSS_STATUSES).toEqual(['lost', 'charge_refunded']);
    expect(isLossStatus('lost')).toBe(true);
    expect(isLossStatus('charge_refunded')).toBe(true);
    expect(isLossStatus('won')).toBe(false);
    expect(isLossStatus('warning_closed')).toBe(false);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 3. Event kind and verb plan
// ════════════════════════════════════════════════════════════════════════════

describe('disputeEventKind / planDisputeVerb', () => {
  it('created ⇒ record only, never mark (KH P1-4)', () => {
    expect(disputeEventKind('charge.dispute.created')).toBe('created');
    expect(planDisputeVerb('created')).toEqual({ kind: 'record' });
  });

  it('updated, funds_withdrawn, funds_reinstated all ride the updated verb plan', () => {
    expect(disputeEventKind('charge.dispute.updated')).toBe('updated');
    expect(disputeEventKind('charge.dispute.funds_withdrawn')).toBe('updated');
    expect(disputeEventKind('charge.dispute.funds_reinstated')).toBe('updated');
    expect(planDisputeVerb('updated')).toEqual({ kind: 'mark_then_record', reissueMarkOnceOnReplay: true });
  });

  it('closed ⇒ mark_then_record too', () => {
    expect(disputeEventKind('charge.dispute.closed')).toBe('closed');
    expect(planDisputeVerb('closed')).toEqual({ kind: 'mark_then_record', reissueMarkOnceOnReplay: true });
  });

  it('any other event type is not a dispute event', () => {
    expect(disputeEventKind('charge.refunded')).toBeNull();
    expect(disputeEventKind('transfer.reversed')).toBeNull();
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 4. Command keys — `wh_dispute_<kind>:<event.id>`, ≤64, regex-safe
// ════════════════════════════════════════════════════════════════════════════

describe('buildDisputeCommandKey', () => {
  it('builds the exact documented shape for each event kind', () => {
    expect(buildDisputeCommandKey('created', DISPUTE_EVENT_ID)).toBe(`wh_dispute_created:${DISPUTE_EVENT_ID}`);
    expect(buildDisputeCommandKey('updated', DISPUTE_EVENT_ID)).toBe(`wh_dispute_updated:${DISPUTE_EVENT_ID}`);
    expect(buildDisputeCommandKey('closed', DISPUTE_EVENT_ID)).toBe(`wh_dispute_closed:${DISPUTE_EVENT_ID}`);
  });

  it('is always ≤ 64 chars and matches the audit regex, even for a foreign/oversized event id', () => {
    const foreign = 'evt_' + 'x'.repeat(200);
    const key = buildDisputeCommandKey('updated', foreign);
    expect(key.length).toBeLessThanOrEqual(64);
    expect(isValidCommandKey(key)).toBe(true);
    expect(COMMAND_KEY_RE.test(key)).toBe(true);
  });

  it('sanitizes characters outside the audit alphabet rather than throwing', () => {
    const key = buildDisputeCommandKey('created', 'evt/weird id!');
    expect(isValidCommandKey(key)).toBe(true);
  });
});

describe('buildReversalCommandKey', () => {
  it('uses the literal form when it fits within 64 chars', () => {
    const key = buildReversalCommandKey('evt_short', 'trr_short');
    expect(key).toBe('wh_transfer_reversed:evt_short:trr_short');
    expect(isValidCommandKey(key)).toBe(true);
  });

  it('falls back to the compact form (prefixes dropped) when the literal form would exceed 64 chars', () => {
    const evt = 'evt_' + '1'.repeat(24);
    const trr = 'trr_' + '2'.repeat(24);
    const literal = `wh_transfer_reversed:${evt}:${trr}`;
    expect(literal.length).toBeGreaterThan(64);
    const key = buildReversalCommandKey(evt, trr);
    expect(key.length).toBeLessThanOrEqual(64);
    expect(isValidCommandKey(key)).toBe(true);
    // The compact form must still distinguish two different trr ids on the same event.
    const other = buildReversalCommandKey(evt, 'trr_' + '3'.repeat(24));
    expect(other).not.toBe(key);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 5. `disputeRecordArgs` / `disputeMarkArgs` / `evidenceDueAtIso`
// ════════════════════════════════════════════════════════════════════════════

describe('disputeRecordArgs', () => {
  it('builds record_dispute_native args in declaration order, currency defaulted to usd, evidence_due_at as ISO', () => {
    const commandKey = buildDisputeCommandKey('created', DISPUTE_EVENT_ID);
    const result = disputeRecordArgs(disputeLike(), commandKey);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.args).toEqual({
        p_stripe_dispute_ref: 'dp_ABC123XYZ',
        p_stripe_charge_ref: CHARGE,
        p_stripe_pi_ref: PI,
        p_amount_minor: 5000,
        p_currency: 'usd',
        p_reason: 'fraudulent',
        p_status: 'needs_response',
        p_evidence_due_at: evidenceDueAtIso(1700000000),
        p_command_key: commandKey,
      });
    }
  });

  it('a malformed dispute object is refused ACK+alert, never a raw 22P02 dressed as a retry', () => {
    const commandKey = buildDisputeCommandKey('created', DISPUTE_EVENT_ID);
    for (const bad of [
      disputeLike({ id: undefined }),
      disputeLike({ charge: undefined }),
      disputeLike({ reason: undefined }),
      disputeLike({ status: 'prevented' }),
      disputeLike({ amount: -1 }),
    ]) {
      const result = disputeRecordArgs(bad, commandKey);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.decision).toEqual({ ack: true, alert: true, reason: 'native_dispute_event_malformed' });
    }
  });

  it('a missing evidence_details.due_by yields a null p_evidence_due_at, not a throw', () => {
    const commandKey = buildDisputeCommandKey('closed', DISPUTE_EVENT_ID);
    const result = disputeRecordArgs(disputeLike({ evidence_details: null }), commandKey);
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.args.p_evidence_due_at).toBeNull();
  });
});

describe('disputeMarkArgs', () => {
  it('builds mark_dispute_state args', () => {
    const key = buildDisputeCommandKey('updated', DISPUTE_EVENT_ID);
    expect(disputeMarkArgs('dp_ABC123XYZ', 'under_review', key)).toEqual({
      p_stripe_dispute_ref: 'dp_ABC123XYZ',
      p_new_status: 'under_review',
      p_command_key: key,
    });
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 6. `classifyDisputeError` — KH §4.5 "any" rows, quoted from 088:887-892 etc.
// ════════════════════════════════════════════════════════════════════════════

describe('classifyDisputeError', () => {
  it('state_conflict (088:887-892) on an `updated` event ⇒ ack+alert native_dispute_stale_update, never retried', () => {
    const decision = classifyDisputeError(
      { code: 'P0001', message: 'state_conflict: dispute dp_x is terminal (lost) — mark refused' },
      { verb: 'mark', eventKind: 'updated' },
    );
    expect(decision).toEqual({ ack: true, alert: true, reason: 'native_dispute_stale_update' });
  });

  it('state_conflict on a `closed` event ⇒ ack+alert native_dispute_terminal_conflict', () => {
    const decision = classifyDisputeError(
      { code: 'P0001', message: 'state_conflict: dispute dp_x is terminal (won) — mark refused' },
      { verb: 'mark', eventKind: 'closed' },
    );
    expect(decision).toEqual({ ack: true, alert: true, reason: 'native_dispute_terminal_conflict' });
  });

  it('not_found (P0002) from `record` ⇒ ack+alert native_dispute_payment_not_found', () => {
    const decision = classifyDisputeError(
      { code: 'P0002', message: 'not_found: no payment for payment intent pi_x' },
      { verb: 'record', eventKind: 'created' },
    );
    expect(decision).toEqual({ ack: true, alert: true, reason: 'native_dispute_payment_not_found' });
  });

  it('not_found (P0002) from `mark` after the fallback was exhausted ⇒ ack+alert native_dispute_race_unresolved', () => {
    const decision = classifyDisputeError(
      { code: 'P0002', message: 'not_found: dispute dp_x' },
      { verb: 'mark', eventKind: 'updated' },
    );
    expect(decision).toEqual({ ack: true, alert: true, reason: 'native_dispute_race_unresolved' });
  });

  it('isDisputeNotFound recognizes both P0002 and a bare "not_found" message', () => {
    expect(isDisputeNotFound({ code: 'P0002' })).toBe(true);
    expect(isDisputeNotFound({ message: 'not_found: dispute dp_x' })).toBe(true);
    expect(isDisputeNotFound({ code: 'P0001', message: 'invalid_input: x' })).toBe(false);
    expect(isDisputeNotFound(null)).toBe(false);
  });

  it('invalid_input (P0001) ⇒ ack+alert native_dispute_invalid_input', () => {
    const decision = classifyDisputeError(
      { code: 'P0001', message: 'invalid_input: dispute.status=prevented is not recognized' },
      { verb: 'record', eventKind: 'created' },
    );
    expect(decision).toEqual({ ack: true, alert: true, reason: 'native_dispute_invalid_input' });
  });

  it('42501 (missing GRANT) and PGRST202 (schema not exposed) ⇒ retry+alert (ops-fixable)', () => {
    expect(classifyDisputeError({ code: '42501', message: 'permission denied' }, { verb: 'record', eventKind: 'created' }))
      .toEqual({ ack: false, alert: true, reason: 'native_dispute_not_granted' });
    expect(classifyDisputeError({ code: 'PGRST202', message: 'could not find the function' }, { verb: 'mark', eventKind: 'updated' }))
      .toEqual({ ack: false, alert: true, reason: 'native_dispute_not_granted' });
  });

  it('transient Postgres classes (40001, 53300, 57P01, 08006, XX000) ⇒ retry, no alert', () => {
    for (const code of ['40001', '53300', '57P01', '08006', '40P01', '55P03', 'XX000']) {
      expect(classifyDisputeError({ code, message: 'transient' }, { verb: 'record', eventKind: 'created' }))
        .toEqual({ ack: false, alert: false, reason: 'native_dispute_transient' });
    }
  });

  it('an unclassified error ⇒ retry+alert (fail toward not losing the money event)', () => {
    expect(classifyDisputeError({ code: '', message: 'a completely novel error' }, { verb: 'record', eventKind: 'created' }))
      .toEqual({ ack: false, alert: true, reason: 'native_dispute_unclassified' });
    expect(classifyDisputeError(null, { verb: 'mark', eventKind: 'closed' }))
      .toEqual({ ack: false, alert: true, reason: 'native_dispute_unclassified' });
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 7. KH §4.5 DECISION TABLE — walked row by row through the result
//    interpreters (`interpretRecordResult` / `interpretMarkResult`)
// ════════════════════════════════════════════════════════════════════════════

describe('KH §4.5 decision table — created', () => {
  it('none → record → ok, linked:true ⇒ ack, no alert', () => {
    const outcome = interpretRecordResult(
      { status: 'ok', dispute_id: 'dp_x', linked: true },
      { eventKind: 'created', payloadStatus: 'needs_response' },
    );
    expect(outcome.decision).toEqual({ ack: true, alert: false, reason: 'native_dispute_recorded_created' });
  });

  it('none → record → ok, linked:false (no-link arm) ⇒ ack + alert native_dispute_no_link', () => {
    const outcome = interpretRecordResult(
      { status: 'ok', dispute_id: 'dp_x', linked: false },
      { eventKind: 'created', payloadStatus: 'needs_response' },
    );
    expect(outcome.decision).toEqual({ ack: true, alert: true, reason: 'native_dispute_no_link' });
    expect(outcome.flags).toContain('native_dispute_no_link');
  });

  it('none, payload status terminal → record → ok, zero legs ⇒ ack + alert native_dispute_recorded_terminal', () => {
    const outcome = interpretRecordResult(
      { status: 'ok', dispute_id: 'dp_x', linked: true },
      { eventKind: 'created', payloadStatus: 'won' },
    );
    expect(outcome.decision).toEqual({ ack: true, alert: true, reason: 'native_dispute_recorded_terminal' });
  });

  it('exists (any status) → record → noop_replay ⇒ ack, no mark issued (P1-4)', () => {
    const outcome = interpretRecordResult({ status: 'noop_replay', dispute_id: 'dp_x' }, { eventKind: 'created', payloadStatus: 'lost' });
    expect(outcome.rpcStatus).toBe('noop_replay');
    expect(outcome.decision).toEqual({ ack: true, alert: false, reason: 'native_dispute_record_replay' });
  });
});

describe('KH §4.5 decision table — updated', () => {
  it('open → mark(open state) → ok/noop_replay ⇒ ack, no alert', () => {
    const ok = interpretMarkResult({ status: 'ok', dispute_id: 'dp_x', dispute_status: 'under_review' }, { eventKind: 'updated', newStatus: 'under_review' });
    expect(ok.decision).toEqual({ ack: true, alert: false, reason: 'native_dispute_state_synced' });
    const replay = interpretMarkResult({ status: 'noop_replay' }, { eventKind: 'updated', newStatus: 'under_review' });
    expect(replay.decision).toEqual({ ack: true, alert: false, reason: 'native_dispute_mark_replay' });
  });

  it('open → mark(terminal) → ok ⇒ ack; lost|charge_refunded ⇒ alert native_dispute_lost (loss visible, no booking — P1-6)', () => {
    for (const status of ['lost', 'charge_refunded'] as const) {
      const outcome = interpretMarkResult({ status: 'ok', dispute_id: 'dp_x' }, { eventKind: 'updated', newStatus: status });
      expect(outcome.decision).toEqual({ ack: true, alert: true, reason: 'native_dispute_lost' });
    }
  });

  it('open → mark(terminal won/warning_closed) → ok ⇒ ack, log only — holds persist, won releases nothing (PFA-31)', () => {
    for (const status of ['won', 'warning_closed'] as const) {
      const outcome = interpretMarkResult({ status: 'ok', dispute_id: 'dp_x' }, { eventKind: 'updated', newStatus: status });
      expect(outcome.decision).toEqual({ ack: true, alert: false, reason: `native_dispute_closed_${status}` });
    }
  });

  it('terminal, same status → mark → noop_replay ⇒ ack', () => {
    const outcome = interpretMarkResult({ status: 'noop_replay' }, { eventKind: 'updated', newStatus: 'lost' });
    expect(outcome.decision).toEqual({ ack: true, alert: false, reason: 'native_dispute_mark_replay' });
  });

  it('terminal, different status → mark → P0001 state_conflict ⇒ ack + alert native_dispute_stale_update, never retried', () => {
    const decision = classifyDisputeError(
      { code: 'P0001', message: 'state_conflict: dispute dp_x is terminal (won) — mark refused' },
      { verb: 'mark', eventKind: 'updated' },
    );
    expect(decision).toEqual({ ack: true, alert: true, reason: 'native_dispute_stale_update' });
  });
});

describe('KH §4.5 decision table — closed', () => {
  it('none → mark P0002 → record(terminal) → ok, zero legs ⇒ ack + alert native_dispute_closed_before_created (freeze inverted, G5 exposure)', () => {
    const outcome = interpretRecordResult(
      { status: 'ok', dispute_id: 'dp_x', linked: true },
      { eventKind: 'closed', payloadStatus: 'lost' },
    );
    // Both the terminal flag and the loss flag apply; the FIRST is what wins the reason.
    expect(outcome.flags[0]).toBe('native_dispute_closed_before_created');
    expect(outcome.flags).toContain('native_dispute_lost');
    expect(outcome.decision).toEqual({ ack: true, alert: true, reason: 'native_dispute_closed_before_created' });
  });

  it('open → mark(terminal) → ok ⇒ ack; lost|charge_refunded ⇒ alert; won|warning_closed ⇒ log only', () => {
    expect(interpretMarkResult({ status: 'ok' }, { eventKind: 'closed', newStatus: 'charge_refunded' }).decision)
      .toEqual({ ack: true, alert: true, reason: 'native_dispute_lost' });
    expect(interpretMarkResult({ status: 'ok' }, { eventKind: 'closed', newStatus: 'won' }).decision)
      .toEqual({ ack: true, alert: false, reason: 'native_dispute_closed_won' });
  });

  it('terminal, same status → mark → noop_replay ⇒ ack', () => {
    expect(interpretMarkResult({ status: 'noop_replay' }, { eventKind: 'closed', newStatus: 'lost' }).decision)
      .toEqual({ ack: true, alert: false, reason: 'native_dispute_mark_replay' });
  });

  it('terminal, different status → mark → state_conflict ⇒ ack + alert native_dispute_terminal_conflict', () => {
    const decision = classifyDisputeError(
      { code: 'P0001', message: 'state_conflict: dispute dp_x is terminal (lost) — mark refused' },
      { verb: 'mark', eventKind: 'closed' },
    );
    expect(decision).toEqual({ ack: true, alert: true, reason: 'native_dispute_terminal_conflict' });
  });
});

describe('a 2xx body this file cannot read is retried, never trusted as a silent success', () => {
  it('record returns neither ok nor noop_replay ⇒ ack:false, alert:true (the write may have landed; replay converges)', () => {
    const outcome = interpretRecordResult({ dispute_id: 'dp_x' }, { eventKind: 'created', payloadStatus: 'needs_response' });
    expect(outcome.decision).toEqual({ ack: false, alert: true, reason: 'native_dispute_record_unreadable' });
  });
  it('mark returns neither ok nor noop_replay ⇒ ack:false, alert:true', () => {
    const outcome = interpretMarkResult({ dispute_id: 'dp_x' }, { eventKind: 'updated', newStatus: 'lost' });
    expect(outcome.decision).toEqual({ ack: false, alert: true, reason: 'native_dispute_mark_unreadable' });
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 8. `resolveTransferRail` — KH §4.6 / KE §4.3 (a Transfer carries its OWN
//    metadata, unlike a Dispute — no DB lookup)
// ════════════════════════════════════════════════════════════════════════════

function transferLike(over: Partial<TransferLike> = {}): TransferLike {
  return {
    id: 'tr_ABC123XYZ',
    amount: 10000,
    currency: 'usd',
    destination: 'acct_ORGDEST01',
    reversed: false,
    amount_reversed: 0,
    transfer_group: `payout_${PAYOUT}`,
    metadata: { source: 'payout-execute', payout_id: PAYOUT, settlement_id: 'x', org_id: 'y' },
    reversals: { data: [], has_more: false },
    ...over,
  };
}

describe('resolveTransferRail', () => {
  it('native metadata (source=payout-execute + uuid payout_id) ⇒ native via metadata', () => {
    expect(resolveTransferRail(transferLike())).toEqual({ route: 'native', payoutId: PAYOUT, via: 'metadata' });
  });

  it('legacy metadata (metadata.transfer_id present, no group) ⇒ legacy', () => {
    const route = resolveTransferRail(
      transferLike({ metadata: { transfer_id: 't_legacy1' }, transfer_group: undefined }),
    );
    expect(route).toEqual({ route: 'legacy' });
  });

  it('transfer_group ~ ^payout_<uuid>$ with no metadata at all ⇒ native via transfer_group (group-only)', () => {
    const route = resolveTransferRail(transferLike({ metadata: {}, transfer_group: `payout_${PAYOUT}` }));
    expect(route).toEqual({ route: 'native', payoutId: PAYOUT, via: 'transfer_group' });
  });

  it('group and metadata AGREE ⇒ native, group is not required to defer to metadata', () => {
    const route = resolveTransferRail(
      transferLike({ metadata: { source: 'payout-execute', payout_id: PAYOUT }, transfer_group: `payout_${PAYOUT}` }),
    );
    expect(route).toEqual({ route: 'native', payoutId: PAYOUT, via: 'metadata' });
  });

  it('group and metadata name DIFFERENT payouts ⇒ ambiguous group_metadata_disagree', () => {
    const route = resolveTransferRail(
      transferLike({ metadata: { source: 'payout-execute', payout_id: PAYOUT }, transfer_group: `payout_${PAYOUT_2}` }),
    );
    expect(route.route).toBe('ambiguous');
    if (route.route === 'ambiguous') {
      expect(route.why).toBe('group_metadata_disagree');
      expect(route.decision).toEqual({ ack: true, alert: true, reason: 'transfer_rail_ambiguous' });
    }
  });

  it('BOTH native metadata and legacy metadata claim the object ⇒ ambiguous both_rails', () => {
    const route = resolveTransferRail(
      transferLike({ metadata: { source: 'payout-execute', payout_id: PAYOUT, transfer_id: 't_legacy1' } }),
    );
    expect(route.route).toBe('ambiguous');
    if (route.route === 'ambiguous') expect(route.why).toBe('both_rails');
  });

  it('NEITHER rail claims the object ⇒ ambiguous neither', () => {
    const route = resolveTransferRail(transferLike({ metadata: {}, transfer_group: undefined }));
    expect(route.route).toBe('ambiguous');
    if (route.route === 'ambiguous') expect(route.why).toBe('neither');
  });

  it('partial native metadata (source without a uuid payout_id, or vice versa) ⇒ ambiguous native_metadata_incomplete', () => {
    const sourceOnly = resolveTransferRail(transferLike({ metadata: { source: 'payout-execute' }, transfer_group: undefined }));
    expect(sourceOnly.route).toBe('ambiguous');
    if (sourceOnly.route === 'ambiguous') expect(sourceOnly.why).toBe('native_metadata_incomplete');

    const idOnly = resolveTransferRail(transferLike({ metadata: { payout_id: PAYOUT }, transfer_group: undefined }));
    expect(idOnly.route).toBe('ambiguous');
    if (idOnly.route === 'ambiguous') expect(idOnly.why).toBe('native_metadata_incomplete');
  });

  it('a non-uuid metadata.payout_id does not count as native metadata', () => {
    const route = resolveTransferRail(
      transferLike({ metadata: { source: 'payout-execute', payout_id: 'not-a-uuid' }, transfer_group: undefined }),
    );
    expect(route.route).toBe('ambiguous');
  });

  it('null/undefined transfer ⇒ ambiguous neither, never throws', () => {
    expect(resolveTransferRail(null).route).toBe('ambiguous');
    expect(resolveTransferRail(undefined).route).toBe('ambiguous');
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 9. `readInlineReversals` / `mergeReversals`
// ════════════════════════════════════════════════════════════════════════════

describe('readInlineReversals', () => {
  it('no reversals object ⇒ empty list, ok, hasMore false', () => {
    expect(readInlineReversals(transferLike({ reversals: null }))).toEqual({ ok: true, reversals: [], hasMore: false });
  });

  it('reads well-formed trr_ entries and carries has_more through', () => {
    const t = transferLike({ reversals: { data: [{ id: 'trr_ONE00001', amount: 4000 }], has_more: true } });
    expect(readInlineReversals(t)).toEqual({ ok: true, reversals: [{ id: 'trr_ONE00001', amount: 4000 }], hasMore: true });
  });

  it('a non-array reversals.data is unreadable, not silently empty', () => {
    const t = transferLike({ reversals: { data: 'not-an-array' as unknown, has_more: false } });
    const result = readInlineReversals(t);
    expect(result.ok).toBe(false);
  });

  it('a malformed reversal entry (bad id or non-positive amount) makes the WHOLE list unreadable', () => {
    expect(readInlineReversals(transferLike({ reversals: { data: [{ id: 'not-trr', amount: 100 }], has_more: false } })).ok).toBe(false);
    expect(readInlineReversals(transferLike({ reversals: { data: [{ id: 'trr_X', amount: 0 }], has_more: false } })).ok).toBe(false);
    expect(readInlineReversals(transferLike({ reversals: { data: [{ id: 'trr_X', amount: -5 }], has_more: false } })).ok).toBe(false);
  });

  it('TRANSFER_REVERSAL_REF_RE / TRANSFER_REF_RE match the shapes documented', () => {
    expect(TRANSFER_REVERSAL_REF_RE.test('trr_ABC123')).toBe(true);
    expect(TRANSFER_REVERSAL_REF_RE.test('tr_ABC123')).toBe(false);
    expect(TRANSFER_REF_RE.test('tr_ABC123')).toBe(true);
    expect(TRANSFER_REF_RE.test('trr_ABC123')).toBe(false);
  });
});

describe('mergeReversals', () => {
  it('de-duplicates by trr_ id across the inline page and any paged reads', () => {
    const first = [{ id: 'trr_A', amount: 100 }, { id: 'trr_B', amount: 200 }];
    const more = [{ id: 'trr_B', amount: 200 }, { id: 'trr_C', amount: 300 }];
    expect(mergeReversals(first, more)).toEqual([
      { id: 'trr_A', amount: 100 },
      { id: 'trr_B', amount: 200 },
      { id: 'trr_C', amount: 300 },
    ]);
  });

  it('is a no-op on two empty lists', () => {
    expect(mergeReversals([], [])).toEqual([]);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 10. `planReversalRecording` — the record_payout_reversal call-builder
// ════════════════════════════════════════════════════════════════════════════

describe('planReversalRecording', () => {
  it('builds one record_payout_reversal call per reversal fact, in declaration order, with p_observed as evidence only', () => {
    const t = transferLike({ amount: 10000, amount_reversed: 10000, reversed: true });
    const plan = planReversalRecording(t, PAYOUT, [{ id: 'trr_ONE00001', amount: 10000 }], DISPUTE_EVENT_ID);
    expect(plan.kind).toBe('record');
    if (plan.kind === 'record') {
      expect(plan.calls).toHaveLength(1);
      expect(plan.calls[0]).toEqual({
        p_payout_id: PAYOUT,
        p_stripe_transfer_ref: 'tr_ABC123XYZ',
        p_stripe_reversal_ref: 'trr_ONE00001',
        p_amount_minor: 10000,
        p_observed: { transfer_amount_minor: 10000, amount_reversed: 10000, reversed: true, event_id: DISPUTE_EVENT_ID },
        p_command_key: buildReversalCommandKey(DISPUTE_EVENT_ID, 'trr_ONE00001'),
      });
    }
  });

  it('one call per reversal fact for a multi-reversal event', () => {
    const t = transferLike({ amount: 10000, amount_reversed: 10000, reversed: true });
    const plan = planReversalRecording(
      t, PAYOUT,
      [{ id: 'trr_A0000001', amount: 6000 }, { id: 'trr_B0000001', amount: 4000 }],
      DISPUTE_EVENT_ID,
    );
    expect(plan.kind).toBe('record');
    if (plan.kind === 'record') expect(plan.calls.map((c) => c.p_stripe_reversal_ref)).toEqual(['trr_A0000001', 'trr_B0000001']);
  });

  it('a malformed transfer.id ⇒ decision ack+alert native_reversal_transfer_ref_malformed, no calls built', () => {
    const t = transferLike({ id: 'not-a-transfer' });
    const plan = planReversalRecording(t, PAYOUT, [{ id: 'trr_ONE00001', amount: 100 }], DISPUTE_EVENT_ID);
    expect(plan.kind).toBe('decision');
    if (plan.kind === 'decision') expect(plan.decision).toEqual({ ack: true, alert: true, reason: 'native_reversal_transfer_ref_malformed' });
  });

  it('a non-uuid payoutId ⇒ decision ack+alert native_reversal_payout_id_malformed', () => {
    const plan = planReversalRecording(transferLike(), 'not-a-uuid', [{ id: 'trr_ONE00001', amount: 100 }], DISPUTE_EVENT_ID);
    expect(plan.kind).toBe('decision');
    if (plan.kind === 'decision') expect(plan.decision.reason).toBe('native_reversal_payout_id_malformed');
  });

  it('an unreadable amount_reversed ⇒ decision ack+alert native_reversal_amount_unreadable', () => {
    const t = transferLike({ amount_reversed: 'NaN' as unknown as number });
    const plan = planReversalRecording(t, PAYOUT, [{ id: 'trr_ONE00001', amount: 100 }], DISPUTE_EVENT_ID);
    expect(plan.kind).toBe('decision');
    if (plan.kind === 'decision') expect(plan.decision.reason).toBe('native_reversal_amount_unreadable');
  });

  it('an empty reversal list while amount_reversed > 0 ⇒ ack+alert reversal_list_empty — a trr_ is NEVER invented', () => {
    const t = transferLike({ amount_reversed: 5000, reversed: false });
    const plan = planReversalRecording(t, PAYOUT, [], DISPUTE_EVENT_ID);
    expect(plan.kind).toBe('decision');
    if (plan.kind === 'decision') expect(plan.decision).toEqual({ ack: true, alert: true, reason: 'reversal_list_empty' });
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 11. `interpretReversalResult` / `classifyReversalError` — DESIGN §2.2's
//     `record_payout_reversal` outcomes (supersedes the KH §4.6 verb names)
// ════════════════════════════════════════════════════════════════════════════

describe('interpretReversalResult', () => {
  it('ok + fully_reversed ⇒ ack, no alert, native_reversal_recorded_full', () => {
    expect(interpretReversalResult({ status: 'ok', fully_reversed: true })).toEqual({ ack: true, alert: false, reason: 'native_reversal_recorded_full' });
  });
  it('ok, not fully reversed ⇒ native_reversal_recorded_partial', () => {
    expect(interpretReversalResult({ status: 'ok', fully_reversed: false })).toEqual({ ack: true, alert: false, reason: 'native_reversal_recorded_partial' });
  });
  it('held (the submitted-ref-not-yet-stored race, KE §4.3) ⇒ ack, no alert — the hold verb itself notifies', () => {
    expect(interpretReversalResult({ status: 'held' })).toEqual({ ack: true, alert: false, reason: 'native_reversal_held' });
  });
  it('noop_replay ⇒ ack, no alert', () => {
    expect(interpretReversalResult({ status: 'noop_replay' })).toEqual({ ack: true, alert: false, reason: 'native_reversal_replay' });
  });
  it('an unrecognized status in a 2xx body ⇒ ack:false, alert:true (retry converges on noop_replay)', () => {
    expect(interpretReversalResult({ status: 'mystery' })).toEqual({ ack: false, alert: true, reason: 'native_reversal_result_unreadable' });
    expect(interpretReversalResult(null)).toEqual({ ack: false, alert: true, reason: 'native_reversal_result_unreadable' });
  });
});

describe('classifyReversalError', () => {
  it('payout_failed_reconcile_required (the reconcile pass owns failed rows) ⇒ ack+alert', () => {
    expect(classifyReversalError({ message: 'precondition_failed: payout_failed_reconcile_required — payout p is failed and carries tr_x' }))
      .toEqual({ ack: true, alert: true, reason: 'native_reversal_payout_failed_reconcile_required' });
  });
  it('payout_not_executed ⇒ ack+alert', () => {
    expect(classifyReversalError({ message: 'precondition_failed: payout_not_executed' }))
      .toEqual({ ack: true, alert: true, reason: 'native_reversal_payout_not_executed' });
  });
  it('conflict_locked (reversal ref bound elsewhere) ⇒ ack+alert', () => {
    expect(classifyReversalError({ message: 'conflict_locked: reversal_ref_bound_elsewhere' }))
      .toEqual({ ack: true, alert: true, reason: 'native_reversal_conflict_locked' });
  });
  it('not_found / P0002 ⇒ ack+alert', () => {
    expect(classifyReversalError({ code: 'P0002', message: 'not_found: payout p' }))
      .toEqual({ ack: true, alert: true, reason: 'native_reversal_payout_not_found' });
  });
  it('a generic precondition_failed (e.g. payout_held) ⇒ ack+alert native_reversal_precondition_failed', () => {
    expect(classifyReversalError({ message: 'precondition_failed: payout_held' }))
      .toEqual({ ack: true, alert: true, reason: 'native_reversal_precondition_failed' });
  });
  it('invalid_input ⇒ ack+alert', () => {
    expect(classifyReversalError({ message: 'invalid_input: command_key must match ^[A-Za-z0-9._:-]{1,64}$' }))
      .toEqual({ ack: true, alert: true, reason: 'native_reversal_invalid_input' });
  });
  it('42501 / PGRST202 ⇒ retry+alert', () => {
    expect(classifyReversalError({ code: '42501' })).toEqual({ ack: false, alert: true, reason: 'native_reversal_not_granted' });
    expect(classifyReversalError({ code: 'PGRST202' })).toEqual({ ack: false, alert: true, reason: 'native_reversal_not_granted' });
  });
  it('transient Postgres classes ⇒ retry, no alert', () => {
    for (const code of ['40001', '53300', '57P01', '08006']) {
      expect(classifyReversalError({ code })).toEqual({ ack: false, alert: false, reason: 'native_reversal_transient' });
    }
  });
  it('unclassified ⇒ retry+alert', () => {
    expect(classifyReversalError({ message: 'a completely novel error' })).toEqual({ ack: false, alert: true, reason: 'native_reversal_unclassified' });
    expect(classifyReversalError(null)).toEqual({ ack: false, alert: true, reason: 'native_reversal_unclassified' });
  });
});

describe('aggregateDecisions', () => {
  it('empty ⇒ ack+alert with the fallback reason (no reversal was recordable)', () => {
    expect(aggregateDecisions([])).toEqual({ ack: true, alert: true, reason: 'native_reversal_nothing_recorded' });
  });
  it('any single ack:false makes the whole delivery retry (every verb call is idempotent on trr_, so replay converges)', () => {
    const decisions = [
      { ack: true, alert: false, reason: 'native_reversal_recorded_full' },
      { ack: false, alert: false, reason: 'native_reversal_transient' },
    ];
    expect(aggregateDecisions(decisions)).toEqual({ ack: false, alert: false, reason: 'native_reversal_transient' });
  });
  it('all ack, any alert ⇒ ack:true, alert:true, reason is the first alerted one', () => {
    const decisions = [
      { ack: true, alert: false, reason: 'native_reversal_recorded_full' },
      { ack: true, alert: true, reason: 'native_reversal_held' },
    ];
    expect(aggregateDecisions(decisions)).toEqual({ ack: true, alert: true, reason: 'native_reversal_held' });
  });
  it('all plain ⇒ ack:true, alert:false, reason is the first', () => {
    const decisions = [
      { ack: true, alert: false, reason: 'native_reversal_recorded_full' },
      { ack: true, alert: false, reason: 'native_reversal_recorded_partial' },
    ];
    expect(aggregateDecisions(decisions)).toEqual({ ack: true, alert: false, reason: 'native_reversal_recorded_full' });
  });
});
