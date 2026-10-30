/**
 * stripe-webhook/native-dispute.ts — pure, dependency-free decision logic for
 * the NATIVE PRIMARY arm of `charge.dispute.*` and for the native routing of
 * `transfer.reversed`.
 *
 * WHY THIS FILE EXISTS SEPARATELY
 *   Same reason as native.ts: `index.ts` imports over https and vitest cannot
 *   load it. Every decision that decides whether a Stripe dispute reaches
 *   `kernel.record_dispute_native` / `kernel.mark_dispute_state`, whether a
 *   transfer reversal reaches `kernel.record_payout_reversal`, and whether
 *   Stripe retries lives HERE, import-free (the one import is the `Decision`
 *   TYPE from ./native.ts, erased at compile time), so
 *   `tests/stripe-webhook-dispute.test.ts` can exercise every row of the
 *   decision tables in docs/phase2/_impl/KH_webhook_routing_idempotency.md
 *   §4.5 / §4.6 directly.
 *
 * THE RULE INHERITED FROM native.ts:13-28
 *   A non-2xx means "Stripe, deliver this again", and that is only right when
 *   a REDELIVERY COULD PLAUSIBLY SUCCEED. A Dispute event is a SNAPSHOT; a
 *   redelivery carries identical bytes. So `state_conflict` (the dispute is
 *   already terminal — 088:887-892), `not_found` from record (the payment is
 *   gone), `invalid_input` (the event or our argument is malformed) and an
 *   unknown status can NEVER be fixed by a retry: they are ACKed and ALERTED.
 *   A missing grant (42501), an unexposed schema (PGRST202) and a transient
 *   Postgres class ARE fixable inside the retry window and are retried.
 *
 * WHAT THE DISCRIMINATOR IS, AND WHAT IT IS NOT (KH P1-2)
 *   A Dispute object carries NO metadata of its own — `resolveRail` in
 *   native.ts reads `metadata.rail` off a PaymentIntent and would answer
 *   `legacy_resale` for every dispute. The rail is therefore DB-DERIVED:
 *   `public.payments.mode === 'native_primary'` for the dispute's
 *   `payment_intent`, read through the service client. Nothing in this file
 *   ever reads `metadata` off a Dispute.
 *
 * WHAT THIS ARM NEVER DOES
 *   • never books an organization obligation from the webhook (KH P1-6 — the
 *     chargeback line arm at the next settlement close is the producer);
 *   • never treats `won` as a release (PFA-31 — holds persist; log only);
 *   • never uses `mark_dispute_state` for `charge.dispute.created` (KH P1-4 —
 *     `mark` is unordered inside the open set and would regress a state);
 *   • never invents a `trr_` when a reversal list is empty.
 */

import type { Decision } from './native.ts';

// ─────────────────────────────────────────────────────────────────────────────
// 0. Shared shapes and small predicates
// ─────────────────────────────────────────────────────────────────────────────

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
/** `kernel.record_dispute_native` (088:775) and `record_payout_reversal` (DESIGN §1.3). */
export const COMMAND_KEY_RE = /^[A-Za-z0-9._:-]{1,64}$/;
const COMMAND_KEY_MAX = 64;
/** Stripe Transfer / Transfer Reversal ids. Same shapes 095:688 and DESIGN §1.1 enforce. */
export const TRANSFER_REF_RE = /^tr_[A-Za-z0-9]+$/;
export const TRANSFER_REVERSAL_REF_RE = /^trr_[A-Za-z0-9]+$/;
/** `payout_<uuid>` — executor.ts:364-366 `buildTransferGroup`. */
const TRANSFER_GROUP_RE = /^payout_([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$/;

/** The `public.payments.mode` member for the direct rail (093 widened CHECK). */
export const PAYMENTS_MODE_NATIVE_PRIMARY = 'native_primary';

function isUuidLike(value: unknown): value is string {
  return typeof value === 'string' && UUID_RE.test(value);
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

export interface PgErrorLike {
  message?: string | null;
  code?: string | null;
}

/** native.ts:377-383, repeated verbatim so this file stays import-free at runtime. */
function isTransientPgCode(code: string): boolean {
  if (code.startsWith('08')) return true; // connection exception
  if (code.startsWith('53')) return true; // insufficient resources
  if (code.startsWith('57')) return true; // operator intervention / query canceled
  if (code.startsWith('58')) return true; // system error
  return code === '40001' || code === '40P01' || code === '55P03' || code === 'XX000';
}

/** 42501 (a missing GRANT) or PGRST202 (the kernel schema / function is not exposed). Ops-fixable. */
function isPrivilegeOrExposureError(code: string, message: string): boolean {
  if (code === '42501' || code === 'PGRST202') return true;
  if (message.includes('insufficient_privilege') || message.includes('permission denied')) return true;
  return message.includes('could not find the function');
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. DISPUTE STATUS VOCABULARY — the 088:200-202 CHECK set, nothing else
// ─────────────────────────────────────────────────────────────────────────────

export const DISPUTE_STATUSES = [
  'warning_needs_response',
  'warning_under_review',
  'warning_closed',
  'needs_response',
  'under_review',
  'won',
  'lost',
  'charge_refunded',
] as const;
export type DisputeStatus = (typeof DISPUTE_STATUSES)[number];

/** 088:878 `v_terminal`. Absorbing in `mark_dispute_state`. */
export const DISPUTE_TERMINAL_STATUSES = ['won', 'lost', 'warning_closed', 'charge_refunded'] as const;

/** The two labels the 093:1136-1215 chargeback arm reads as money lost. */
export const DISPUTE_LOSS_STATUSES = ['lost', 'charge_refunded'] as const;

/**
 * Anything outside the CHECK set — including Stripe's newer `prevented` — is a
 * status the kernel refuses with `invalid_input` (088:770-772). Sending it would
 * be an ACKed incident either way; refusing here keeps the refusal legible and
 * costs no round trip.
 */
export function disputeStatusKnown(status: unknown): status is DisputeStatus {
  return typeof status === 'string' && (DISPUTE_STATUSES as readonly string[]).includes(status);
}

export function isTerminalDisputeStatus(status: unknown): boolean {
  return typeof status === 'string' && (DISPUTE_TERMINAL_STATUSES as readonly string[]).includes(status);
}

export function isLossStatus(status: unknown): boolean {
  return typeof status === 'string' && (DISPUTE_LOSS_STATUSES as readonly string[]).includes(status);
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. EVENT KIND — which verb each `charge.dispute.*` event maps to
// ─────────────────────────────────────────────────────────────────────────────

export type DisputeEventKind = 'created' | 'updated' | 'closed';

/**
 * `funds_withdrawn` / `funds_reinstated` carry the full Dispute object and a
 * status; on the native arm they are a STATUS SYNC and nothing more, so they
 * ride the `updated` verb plan. Any other type is not a dispute event.
 */
export function disputeEventKind(eventType: unknown): DisputeEventKind | null {
  switch (eventType) {
    case 'charge.dispute.created':
      return 'created';
    case 'charge.dispute.updated':
    case 'charge.dispute.funds_withdrawn':
    case 'charge.dispute.funds_reinstated':
      return 'updated';
    case 'charge.dispute.closed':
      return 'closed';
    default:
      return null;
  }
}

export type DisputeVerbPlan =
  /** `created` ⇒ `record_dispute_native` only. NEVER `mark` (KH P1-4, B4). */
  | { kind: 'record' }
  /**
   * `updated` / `closed` ⇒ `mark_dispute_state`; on P0002 fall back to
   * `record_dispute_native` at the payload's status (KH B1-B2, C1-C2); if THAT
   * answers `noop_replay` a concurrent `created` won the insert race
   * (088:799-803, KH P2-7) and `mark` is re-issued exactly once.
   */
  | { kind: 'mark_then_record'; reissueMarkOnceOnReplay: true };

export function planDisputeVerb(eventKind: DisputeEventKind): DisputeVerbPlan {
  if (eventKind === 'created') return { kind: 'record' };
  return { kind: 'mark_then_record', reissueMarkOnceOnReplay: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. THE DISCRIMINATOR — DB-derived, never metadata (KH §4.2 / §4.5 pre-steps)
// ─────────────────────────────────────────────────────────────────────────────

/** Exactly the projection index.ts selects off `public.payments` for a dispute. */
export const DISPUTE_PAYMENT_COLUMNS = 'id, mode, stripe_livemode, status';

export interface DisputePaymentRow {
  id: string;
  mode: string | null;
  stripe_livemode: boolean | null;
  status: string | null;
}

export interface DisputeLike {
  id?: unknown;
  charge?: unknown;
  payment_intent?: unknown;
  amount?: unknown;
  currency?: unknown;
  reason?: unknown;
  status?: unknown;
  evidence_details?: { due_by?: unknown } | null;
}

export type DisputeRailRoute =
  /** Run the native arm against this payments row. */
  | { route: 'native'; paymentId: string }
  /** Legacy only. `why` is for the log line. */
  | { route: 'legacy'; why: 'no_payment_intent' | 'payment_row_absent' | 'legacy_mode' }
  /**
   * A native row, but the event or the row is not live (KH P2-3, mirrors
   * `rowIsLiveActionable`). No native write; ACK + alert; the legacy arm still
   * runs, exactly as it does today.
   */
  | { route: 'not_livemode'; paymentId: string; decision: Decision };

export function resolveDisputeRail(
  paymentRow: DisputePaymentRow | null | undefined,
  dispute: DisputeLike | null | undefined,
  eventLivemode: unknown,
): DisputeRailRoute {
  // (0) A null PI is legacy by construction (KH P2-5): primary-checkout always
  //     writes a PaymentIntent, and `record_dispute_native` raises P0002 on NULL.
  if (!nonEmptyString(dispute?.payment_intent)) return { route: 'legacy', why: 'no_payment_intent' };
  // (1) No row: the legacy arm already tolerates `paymentId = null`.
  if (!paymentRow || !nonEmptyString(paymentRow.id)) return { route: 'legacy', why: 'payment_row_absent' };
  // (2) `mode` is an exact discriminator: {buy_now, auction} are legacy by the
  //     093:2995-3006 CHECK; nothing else is possible at rest.
  if (paymentRow.mode !== PAYMENTS_MODE_NATIVE_PRIMARY) return { route: 'legacy', why: 'legacy_mode' };
  // (3) The livemode gate. `record_dispute_native` enforces neither rail nor
  //     livemode (KH H), so the edge is the only guard and it fails closed.
  if (eventLivemode !== true || paymentRow.stripe_livemode !== true) {
    return {
      route: 'not_livemode',
      paymentId: paymentRow.id,
      decision: { ack: true, alert: true, reason: 'native_dispute_not_livemode' },
    };
  }
  return { route: 'native', paymentId: paymentRow.id };
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. COMMAND KEYS — audit-only for both verbs, bounded by the 088:775 regex
// ─────────────────────────────────────────────────────────────────────────────

/** Replace anything outside the audit alphabet; never throws on a strange id. */
function sanitizeKeyPart(value: unknown): string {
  const s = typeof value === 'string' ? value : String(value ?? '');
  return s.replace(/[^A-Za-z0-9._:-]/g, '_');
}

/**
 * `wh_dispute_<created|updated|closed>:<event.id>` (KH P2-8). Keyed on the
 * DELIVERY, not the dispute: neither verb dedupes on the key (`record` replays
 * by `stripe_dispute_ref`, `mark` is forward-only), so the key's only job is to
 * name the delivery in the immutable audit. A Stripe event id is `evt_` + 24
 * chars, so the full key is 47 chars; the slice is a belt for a foreign id.
 */
export function buildDisputeCommandKey(eventKind: DisputeEventKind, eventId: unknown): string {
  const key = `wh_dispute_${eventKind}:${sanitizeKeyPart(eventId)}`;
  return key.slice(0, COMMAND_KEY_MAX);
}

/**
 * `wh_transfer_reversed:<event.id>:<trr>` (DESIGN §2.2). With real Stripe ids
 * (`evt_` + 24, `trr_` + 24) the literal form is 78 chars, over the 64-char
 * audit bound — and a blind truncation would cut the REVERSAL id, the one part
 * that distinguishes two reversals delivered in one event. So when the literal
 * form does not fit, the compact form `wh_trrev:<evt-id>:<trr-id>` with the
 * `evt_`/`trr_` prefixes dropped (58 chars) is used instead, and only then is
 * anything sliced. `record_payout_reversal` replays on `trr_`, never on this
 * key (DESIGN §1.3), so the key remains audit-only either way.
 */
export function buildReversalCommandKey(eventId: unknown, reversalId: unknown): string {
  const evt = sanitizeKeyPart(eventId);
  const trr = sanitizeKeyPart(reversalId);
  const literal = `wh_transfer_reversed:${evt}:${trr}`;
  if (literal.length <= COMMAND_KEY_MAX) return literal;
  const compact = `wh_trrev:${evt.replace(/^evt_/, '')}:${trr.replace(/^trr_/, '')}`;
  return compact.slice(0, COMMAND_KEY_MAX);
}

export function isValidCommandKey(key: unknown): key is string {
  return typeof key === 'string' && COMMAND_KEY_RE.test(key);
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. RPC ARGUMENTS — the exact parameter names of the two kernel verbs
// ─────────────────────────────────────────────────────────────────────────────

/** `kernel.record_dispute_native(...)` — 088:758-760, in declaration order. */
export interface RecordDisputeArgs {
  p_stripe_dispute_ref: string;
  p_stripe_charge_ref: string;
  p_stripe_pi_ref: string | null;
  p_amount_minor: number;
  p_currency: string;
  p_reason: string;
  p_status: string;
  p_evidence_due_at: string | null;
  p_command_key: string;
}

/** `kernel.mark_dispute_state(...)` — 088:881. */
export interface MarkDisputeArgs {
  p_stripe_dispute_ref: string;
  p_new_status: string;
  p_command_key: string;
}

/** Stripe's `evidence_details.due_by` is epoch seconds; the column is timestamptz. */
export function evidenceDueAtIso(dueBy: unknown): string | null {
  if (typeof dueBy !== 'number' || !Number.isFinite(dueBy) || dueBy <= 0) return null;
  return new Date(dueBy * 1000).toISOString();
}

export type DisputeArgsResult =
  | { ok: true; args: RecordDisputeArgs }
  | { ok: false; decision: Decision; detail: string };

/**
 * Builds the `record_dispute_native` call from the Dispute object. Every
 * `charge.dispute.*` event carries the FULL Dispute (KH §4.4 last paragraph),
 * so record-at-terminal from `.closed` is well-formed. A malformed object is an
 * event defect: ACK + alert, never a 22P02 dressed up as a retry.
 */
export function disputeRecordArgs(dispute: DisputeLike, commandKey: string): DisputeArgsResult {
  const refuse = (detail: string): DisputeArgsResult => ({
    ok: false,
    decision: { ack: true, alert: true, reason: 'native_dispute_event_malformed' },
    detail,
  });
  if (!nonEmptyString(dispute?.id)) return refuse('dispute.id missing');
  if (!nonEmptyString(dispute.charge)) return refuse('dispute.charge missing');
  if (!nonEmptyString(dispute.reason)) return refuse('dispute.reason missing');
  if (!disputeStatusKnown(dispute.status)) return refuse(`dispute.status=${String(dispute.status)}`);
  const amount = Number(dispute.amount);
  if (!Number.isInteger(amount) || amount < 0) return refuse(`dispute.amount=${String(dispute.amount)}`);
  if (!isValidCommandKey(commandKey)) return refuse(`command_key=${commandKey}`);
  return {
    ok: true,
    args: {
      p_stripe_dispute_ref: dispute.id,
      p_stripe_charge_ref: dispute.charge,
      p_stripe_pi_ref: nonEmptyString(dispute.payment_intent) ? dispute.payment_intent : null,
      p_amount_minor: amount,
      // 088:778 upper-cases and validates; Stripe reports lowercase ISO codes.
      p_currency: nonEmptyString(dispute.currency) ? dispute.currency : 'usd',
      p_reason: dispute.reason,
      p_status: dispute.status,
      p_evidence_due_at: evidenceDueAtIso(dispute.evidence_details?.due_by),
      p_command_key: commandKey,
    },
  };
}

export function disputeMarkArgs(disputeRef: string, newStatus: DisputeStatus, commandKey: string): MarkDisputeArgs {
  return { p_stripe_dispute_ref: disputeRef, p_new_status: newStatus, p_command_key: commandKey };
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. ERROR CLASSIFICATION — KH §4.5, rows "any"
// ─────────────────────────────────────────────────────────────────────────────

export type DisputeVerb = 'record' | 'mark';

/** `not_found` / P0002 — 088:790 (record: no payment), 088:886 (mark: no dispute). */
export function isDisputeNotFound(err: PgErrorLike | null | undefined): boolean {
  const code = (err?.code ?? '').trim();
  const message = (err?.message ?? '').toLowerCase();
  return code === 'P0002' || message.includes('not_found');
}

/**
 * The classifier for BOTH kernel dispute verbs. Quoted strings are the exact
 * raises:
 *   088:887-892  `state_conflict: dispute % is terminal (%) — % refused`   → ACK + alert
 *   088:790-792  `not_found: no payment for payment intent %` (P0002)     → ACK + alert (record)
 *   088:886      `not_found: dispute %` (P0002)                           → the CALLER's fallback for mark;
 *                                                                           reaching here means the fallback
 *                                                                           was exhausted → ACK + alert
 *   088:766-782  `invalid_input: …` (P0001)                                → ACK + alert
 *   42501 / PGRST202                                                       → RETRY + alert
 *   transient PG classes                                                   → RETRY
 *   anything else                                                          → RETRY + alert
 */
export function classifyDisputeError(
  err: PgErrorLike | null | undefined,
  ctx: { verb: DisputeVerb; eventKind: DisputeEventKind },
): Decision {
  const message = (err?.message ?? '').toLowerCase();
  const code = (err?.code ?? '').trim();

  if (code && isTransientPgCode(code)) {
    return { ack: false, alert: false, reason: 'native_dispute_transient' };
  }
  if (isPrivilegeOrExposureError(code, message)) {
    return { ack: false, alert: true, reason: 'native_dispute_not_granted' };
  }
  if (message.includes('state_conflict')) {
    // A redelivery carries the same status; the row is terminal forever.
    const reason = ctx.eventKind === 'closed' ? 'native_dispute_terminal_conflict' : 'native_dispute_stale_update';
    return { ack: true, alert: true, reason };
  }
  if (isDisputeNotFound(err)) {
    const reason = ctx.verb === 'record' ? 'native_dispute_payment_not_found' : 'native_dispute_race_unresolved';
    return { ack: true, alert: true, reason };
  }
  if (message.includes('invalid_input')) {
    return { ack: true, alert: true, reason: 'native_dispute_invalid_input' };
  }
  return { ack: false, alert: true, reason: 'native_dispute_unclassified' };
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. RESULT INTERPRETATION — the "RPC result → response" columns of §4.5
// ─────────────────────────────────────────────────────────────────────────────

export interface RecordDisputeResult {
  status?: unknown;
  dispute_id?: unknown;
  atoms_held?: unknown;
  atoms_skipped?: unknown;
  payouts_held?: unknown;
  linked?: unknown;
}

export interface MarkDisputeResult {
  status?: unknown;
  dispute_id?: unknown;
  dispute_status?: unknown;
}

export interface DisputeArmOutcome {
  /** `ok` = this delivery wrote the row/transition; `noop_replay` = it already existed. */
  rpcStatus: 'ok' | 'noop_replay';
  disputeId: string | null;
  decision: Decision;
  /** Every alert-worthy observation, for the log line. `decision.reason` is the first. */
  flags: string[];
}

/**
 * `record_dispute_native` succeeded. The alerts the RPC cannot raise itself:
 *   linked:false          — the no-link arm ran (088:854-859 audits; the edge pages)
 *   terminal payload      — recorded with ZERO freeze legs (093:655-657 "freeze
 *                           inverted relative to risk"): `closed` before `created`
 *                           is its own reason; a `created` that is already terminal
 *                           is the other
 *   lost|charge_refunded  — loss visible; NO booking from here (KH P1-6)
 * A `noop_replay` is a plain ACK: a late `created` after a fallback record, or a
 * redelivery, changes nothing (KH A5/B3/C3).
 */
export function interpretRecordResult(
  data: RecordDisputeResult | null | undefined,
  ctx: { eventKind: DisputeEventKind; payloadStatus: string },
): DisputeArmOutcome {
  const disputeId = nonEmptyString(data?.dispute_id) ? data.dispute_id : null;
  if (data?.status === 'noop_replay') {
    return {
      rpcStatus: 'noop_replay',
      disputeId,
      decision: { ack: true, alert: false, reason: 'native_dispute_record_replay' },
      flags: [],
    };
  }
  if (data?.status !== 'ok') {
    // A 2xx from PostgREST with a body we cannot read. The write may have
    // landed; a retry converges on noop_replay, so retrying is safe and right.
    return {
      rpcStatus: 'ok',
      disputeId,
      decision: { ack: false, alert: true, reason: 'native_dispute_record_unreadable' },
      flags: ['record_unreadable'],
    };
  }
  const flags: string[] = [];
  if (isTerminalDisputeStatus(ctx.payloadStatus)) {
    flags.push(ctx.eventKind === 'closed' ? 'native_dispute_closed_before_created' : 'native_dispute_recorded_terminal');
  }
  if (data.linked === false) flags.push('native_dispute_no_link');
  if (isLossStatus(ctx.payloadStatus)) flags.push('native_dispute_lost');
  if (flags.length > 0) {
    return { rpcStatus: 'ok', disputeId, decision: { ack: true, alert: true, reason: flags[0] }, flags };
  }
  return {
    rpcStatus: 'ok',
    disputeId,
    decision: { ack: true, alert: false, reason: `native_dispute_recorded_${ctx.eventKind}` },
    flags,
  };
}

/**
 * `mark_dispute_state` succeeded (`ok` or `noop_replay`). The only alert is a
 * visible LOSS. `won` and `warning_closed` are logged and release NOTHING
 * (PFA-31 — holds persist until a resolution verb that is parked).
 */
export function interpretMarkResult(
  data: MarkDisputeResult | null | undefined,
  ctx: { eventKind: DisputeEventKind; newStatus: string },
): DisputeArmOutcome {
  const disputeId = nonEmptyString(data?.dispute_id) ? data.dispute_id : null;
  if (data?.status === 'noop_replay') {
    return {
      rpcStatus: 'noop_replay',
      disputeId,
      decision: { ack: true, alert: false, reason: 'native_dispute_mark_replay' },
      flags: [],
    };
  }
  if (data?.status !== 'ok') {
    return {
      rpcStatus: 'ok',
      disputeId,
      decision: { ack: false, alert: true, reason: 'native_dispute_mark_unreadable' },
      flags: ['mark_unreadable'],
    };
  }
  if (isLossStatus(ctx.newStatus)) {
    return {
      rpcStatus: 'ok',
      disputeId,
      decision: { ack: true, alert: true, reason: 'native_dispute_lost' },
      flags: ['native_dispute_lost'],
    };
  }
  if (isTerminalDisputeStatus(ctx.newStatus)) {
    // won | warning_closed — a fact, not a release.
    return {
      rpcStatus: 'ok',
      disputeId,
      decision: { ack: true, alert: false, reason: `native_dispute_closed_${ctx.newStatus}` },
      flags: [],
    };
  }
  return {
    rpcStatus: 'ok',
    disputeId,
    decision: { ack: true, alert: false, reason: 'native_dispute_state_synced' },
    flags: [],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. `transfer.reversed` — RAIL RESOLUTION (KH §4.6, KE §4.3)
// ─────────────────────────────────────────────────────────────────────────────

export interface TransferLike {
  id?: unknown;
  amount?: unknown;
  currency?: unknown;
  destination?: unknown;
  reversed?: unknown;
  amount_reversed?: unknown;
  transfer_group?: unknown;
  metadata?: Record<string, unknown> | null;
  reversals?: { data?: unknown; has_more?: unknown } | null;
}

export type TransferRailRoute =
  | { route: 'native'; payoutId: string; via: 'metadata' | 'transfer_group' }
  | { route: 'legacy' }
  | { route: 'ambiguous'; why: 'both_rails' | 'group_metadata_disagree' | 'native_metadata_incomplete' | 'neither'; decision: Decision };

/**
 * A Transfer DOES carry its own metadata, so — unlike a dispute — the rail is
 * read off the object, with no DB lookup (KE §4.3: a lookup by `tr_` is
 * ambiguous until 096's unique index lands).
 *
 *   native metadata  = `metadata.source === 'payout-execute'` AND uuid `metadata.payout_id`
 *                      (executor.ts:772-776)
 *   legacy metadata  = `metadata.transfer_id` present (payouts.ts:135-143), no group
 *   group            = `transfer_group ~ ^payout_<uuid>$` (executor.ts:364-366)
 *
 * The group wins when it AGREES with the metadata; when they name different
 * payouts, or when both rails claim the object, or neither does, nothing is
 * guessed: ACK + alert `transfer_rail_ambiguous`.
 */
export function resolveTransferRail(transfer: TransferLike | null | undefined): TransferRailRoute {
  const meta = transfer?.metadata ?? {};
  const source = typeof meta.source === 'string' ? meta.source : '';
  const metaPayoutId = isUuidLike(meta.payout_id) ? meta.payout_id : null;
  const nativeMetadata = source === 'payout-execute' && metaPayoutId !== null;
  const nativeMetadataPartial = !nativeMetadata && (source === 'payout-execute' || metaPayoutId !== null);
  const legacyMetadata = nonEmptyString(meta.transfer_id);
  const groupMatch = typeof transfer?.transfer_group === 'string' ? TRANSFER_GROUP_RE.exec(transfer.transfer_group) : null;
  const groupPayoutId = groupMatch ? groupMatch[1] : null;

  const ambiguous = (why: Extract<TransferRailRoute, { route: 'ambiguous' }>['why']): TransferRailRoute => ({
    route: 'ambiguous',
    why,
    decision: { ack: true, alert: true, reason: 'transfer_rail_ambiguous' },
  });

  const claimsNative = nativeMetadata || nativeMetadataPartial || groupPayoutId !== null;
  if (claimsNative && legacyMetadata) return ambiguous('both_rails');

  if (nativeMetadata) {
    if (groupPayoutId !== null && groupPayoutId.toLowerCase() !== (metaPayoutId as string).toLowerCase()) {
      return ambiguous('group_metadata_disagree');
    }
    return { route: 'native', payoutId: metaPayoutId as string, via: 'metadata' };
  }
  if (groupPayoutId !== null) {
    if (metaPayoutId !== null && metaPayoutId.toLowerCase() !== groupPayoutId.toLowerCase()) {
      return ambiguous('group_metadata_disagree');
    }
    return { route: 'native', payoutId: groupPayoutId, via: 'transfer_group' };
  }
  if (nativeMetadataPartial) return ambiguous('native_metadata_incomplete');
  if (legacyMetadata) return { route: 'legacy' };
  return ambiguous('neither');
}

// ─────────────────────────────────────────────────────────────────────────────
// 9. `transfer.reversed` — THE REVERSAL LIST AND THE VERB ARGUMENTS
// ─────────────────────────────────────────────────────────────────────────────

export interface ReversalFact {
  id: string;
  amount: number;
}

export type ReversalListResult =
  | { ok: true; reversals: ReversalFact[]; hasMore: boolean }
  | { ok: false; detail: string };

/**
 * Reads `reversals.data[]` off the event's Transfer object. A malformed entry
 * (no `trr_` id, a non-positive or non-integer amount) makes the whole list
 * unreadable rather than being silently dropped — dropping one is how a Σ ends
 * up short of `amount_reversed`, and the verb refuses that anyway
 * (`reversals_incomplete`, DESIGN §1.7).
 */
export function readInlineReversals(transfer: TransferLike | null | undefined): ReversalListResult {
  const list = transfer?.reversals;
  if (list == null) return { ok: true, reversals: [], hasMore: false };
  if (!Array.isArray(list.data)) return { ok: false, detail: 'reversals.data is not an array' };
  const out: ReversalFact[] = [];
  for (const raw of list.data as unknown[]) {
    const r = raw as { id?: unknown; amount?: unknown } | null;
    const id = r?.id;
    const amount = Number(r?.amount);
    if (typeof id !== 'string' || !TRANSFER_REVERSAL_REF_RE.test(id)) return { ok: false, detail: `reversal id ${String(id)}` };
    if (!Number.isInteger(amount) || amount <= 0) return { ok: false, detail: `reversal ${id} amount ${String(r?.amount)}` };
    out.push({ id, amount });
  }
  return { ok: true, reversals: out, hasMore: list.has_more === true };
}

/** Merge the inline page with any pages read over the wire, de-duplicated by `trr_`. */
export function mergeReversals(first: ReversalFact[], more: ReversalFact[]): ReversalFact[] {
  const seen = new Set<string>();
  const out: ReversalFact[] = [];
  for (const r of [...first, ...more]) {
    if (seen.has(r.id)) continue;
    seen.add(r.id);
    out.push(r);
  }
  return out;
}

/** `kernel.record_payout_reversal(...)` — DESIGN §1.3, in declaration order. */
export interface RecordPayoutReversalArgs {
  p_payout_id: string;
  p_stripe_transfer_ref: string;
  p_stripe_reversal_ref: string;
  p_amount_minor: number;
  p_observed: {
    transfer_amount_minor: number | null;
    amount_reversed: number | null;
    reversed: boolean;
    event_id: string;
  };
  p_command_key: string;
}

export type ReversalRecordingPlan =
  | { kind: 'record'; calls: RecordPayoutReversalArgs[] }
  | { kind: 'decision'; decision: Decision; detail: string };

/**
 * One `record_payout_reversal` call per reversal fact. The transfer's own
 * `amount` / `amount_reversed` / `reversed` ride along as EVIDENCE in
 * `p_observed` (never a predicate — DESIGN §1.1). An empty list while
 * `amount_reversed > 0` is ACKed + alerted: a `trr_` is never invented.
 */
export function planReversalRecording(
  transfer: TransferLike | null | undefined,
  payoutId: string,
  reversals: ReversalFact[],
  eventId: unknown,
): ReversalRecordingPlan {
  const transferRef = transfer?.id;
  if (typeof transferRef !== 'string' || !TRANSFER_REF_RE.test(transferRef)) {
    return {
      kind: 'decision',
      decision: { ack: true, alert: true, reason: 'native_reversal_transfer_ref_malformed' },
      detail: `transfer.id=${String(transferRef)}`,
    };
  }
  if (!isUuidLike(payoutId)) {
    return {
      kind: 'decision',
      decision: { ack: true, alert: true, reason: 'native_reversal_payout_id_malformed' },
      detail: `payout_id=${String(payoutId)}`,
    };
  }
  const amountReversedRaw = transfer?.amount_reversed;
  const amountReversed = amountReversedRaw == null ? null : Number(amountReversedRaw);
  if (amountReversed !== null && (!Number.isFinite(amountReversed) || amountReversed < 0)) {
    return {
      kind: 'decision',
      decision: { ack: true, alert: true, reason: 'native_reversal_amount_unreadable' },
      detail: `amount_reversed=${String(amountReversedRaw)}`,
    };
  }
  if (reversals.length === 0) {
    // Stripe says money came back but names no reversal object. Nothing can be
    // recorded truthfully; a human reads the Dashboard.
    return {
      kind: 'decision',
      decision: { ack: true, alert: true, reason: 'reversal_list_empty' },
      detail: `amount_reversed=${String(amountReversed)} reversed=${String(transfer?.reversed)}`,
    };
  }
  const transferAmountRaw = Number(transfer?.amount);
  const transferAmount = Number.isFinite(transferAmountRaw) ? transferAmountRaw : null;
  const eventIdStr = typeof eventId === 'string' ? eventId : String(eventId ?? '');
  return {
    kind: 'record',
    calls: reversals.map((r) => ({
      p_payout_id: payoutId,
      p_stripe_transfer_ref: transferRef,
      p_stripe_reversal_ref: r.id,
      p_amount_minor: r.amount,
      p_observed: {
        transfer_amount_minor: transferAmount,
        amount_reversed: amountReversed,
        reversed: transfer?.reversed === true,
        event_id: eventIdStr,
      },
      p_command_key: buildReversalCommandKey(eventId, r.id),
    })),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 10. `record_payout_reversal` — result and error classification (DESIGN §2.2)
// ─────────────────────────────────────────────────────────────────────────────

export interface RecordPayoutReversalResult {
  status?: unknown;
  payout_id?: unknown;
  payout_status?: unknown;
  total_reversed_minor?: unknown;
  fully_reversed?: unknown;
}

/** `ok` / `held` / `noop_replay` ⇒ ACK. Anything else in a 2xx body is unreadable ⇒ retry (converges on noop_replay). */
export function interpretReversalResult(data: RecordPayoutReversalResult | null | undefined): Decision {
  switch (data?.status) {
    case 'ok':
      return { ack: true, alert: false, reason: data.fully_reversed === true ? 'native_reversal_recorded_full' : 'native_reversal_recorded_partial' };
    case 'held':
      // The submitted-ref-not-yet-stored race (KE §4.3): the verb held the row;
      // a human releases it. Recorded, not paged — the hold verb itself notifies.
      return { ack: true, alert: false, reason: 'native_reversal_held' };
    case 'noop_replay':
      return { ack: true, alert: false, reason: 'native_reversal_replay' };
    default:
      return { ack: false, alert: true, reason: 'native_reversal_result_unreadable' };
  }
}

/**
 * Quoted from DESIGN §1.3 (the verb is being implemented concurrently; these
 * are its contracted raise strings):
 *   `precondition_failed: payout_failed_reconcile_required` → ACK + alert (the reconcile pass owns failed rows)
 *   `precondition_failed: payout_not_executed`              → ACK + alert
 *   `precondition_failed: not an organization settlement payout` → ACK + alert
 *   `conflict_locked: reversal_ref_bound_elsewhere`         → ACK + alert
 *   `not_found` / P0002                                     → ACK + alert
 *   `invalid_input`                                         → ACK + alert
 *   42501 / PGRST202                                        → RETRY + alert
 *   transient                                               → RETRY
 *   anything else                                           → RETRY + alert
 */
export function classifyReversalError(err: PgErrorLike | null | undefined): Decision {
  const message = (err?.message ?? '').toLowerCase();
  const code = (err?.code ?? '').trim();

  if (code && isTransientPgCode(code)) {
    return { ack: false, alert: false, reason: 'native_reversal_transient' };
  }
  if (isPrivilegeOrExposureError(code, message)) {
    return { ack: false, alert: true, reason: 'native_reversal_not_granted' };
  }
  if (message.includes('payout_failed_reconcile_required')) {
    return { ack: true, alert: true, reason: 'native_reversal_payout_failed_reconcile_required' };
  }
  if (message.includes('payout_not_executed')) {
    return { ack: true, alert: true, reason: 'native_reversal_payout_not_executed' };
  }
  if (message.includes('conflict_locked')) {
    return { ack: true, alert: true, reason: 'native_reversal_conflict_locked' };
  }
  if (code === 'P0002' || message.includes('not_found')) {
    return { ack: true, alert: true, reason: 'native_reversal_payout_not_found' };
  }
  if (message.includes('precondition_failed')) {
    return { ack: true, alert: true, reason: 'native_reversal_precondition_failed' };
  }
  if (message.includes('invalid_input')) {
    return { ack: true, alert: true, reason: 'native_reversal_invalid_input' };
  }
  return { ack: false, alert: true, reason: 'native_reversal_unclassified' };
}

/**
 * One event may carry several reversals and therefore several decisions. A
 * single `ack:false` makes the whole delivery retry (every verb call is
 * idempotent on `trr_`, so the replay converges); otherwise any alert is kept;
 * the reason is the first non-plain one so the log names what went wrong.
 */
export function aggregateDecisions(decisions: Decision[], fallbackReason = 'native_reversal_nothing_recorded'): Decision {
  if (decisions.length === 0) return { ack: true, alert: true, reason: fallbackReason };
  const retry = decisions.find((d) => !d.ack);
  if (retry) return { ack: false, alert: decisions.some((d) => d.alert), reason: retry.reason };
  const alerted = decisions.find((d) => d.alert);
  if (alerted) return { ack: true, alert: true, reason: alerted.reason };
  return { ack: true, alert: false, reason: decisions[0].reason };
}
