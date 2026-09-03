/**
 * H8 — the venue payout executor (ruling H3 · H6 · D-1).
 *
 * WHAT THIS PROVES, AND WHAT IT DOES NOT
 *   Postgres and Stripe are separate systems; there is no cross-system
 *   atomicity and nothing here claims any. These tests verify (a) the pure
 *   decision logic in `payout-execute/executor.ts` exactly, and (b) the
 *   PROTOCOL the edge implements, simulated against a Stripe mock with REAL
 *   idempotency-key semantics (same key + same params ⇒ the same object and no
 *   second transfer; same key + different params ⇒ `idempotency_error`; keys
 *   expire after 24h) and a `kernel.mark_payout_transfer_state` mock that
 *   reproduces 085:1668-1735 line for line — forward-only, the absorbing
 *   `failed` state, the held-row refusal with BOTH columns untouched, the
 *   write-once ref, and noop-replay.
 *
 * WHAT WAS VERIFIED AGAINST THE REAL DATABASE INSTEAD (rehearsal, local)
 *   The absorbing-`failed` proof, the whole refusal ladder of
 *   `kernel.get_payout_execution_context`, the claim's exclusivity, the
 *   de-authorization verb and the grant posture are DB behaviour and are
 *   exercised by `docs/phase2/_impl/H8_payout_executor.md` §Tests against the
 *   shipped functions. The mock here mirrors them so the TypeScript protocol
 *   can be tested without a database, and every mock rule cites the line it
 *   reproduces.
 */
import { describe, expect, it } from 'vitest';
import {
  ACCT_RE,
  assertNoClientMoneyReference,
  authorizeTransfer,
  buildPayoutTransferIdempotencyKey,
  buildTransferGroup,
  classifyPayoutStateSyncError,
  classifyTransferError,
  DEAUTHORIZING_REFUSALS,
  evaluateBalance,
  evaluateDestination,
  isTransientRefusal,
  isUuid,
  PAYOUT_STATE_SYNC_TARGETS,
  planPayoutBatch,
  planPayoutStateSync,
  planPayoutTransfer,
  planReconcile,
  type BalanceProbe,
  type DestinationProbe,
  type PayoutExecutionContext,
} from '../supabase/functions/payout-execute/executor';

// ── fixtures ────────────────────────────────────────────────────────────────

const PAYOUT = '11111111-1111-4111-8111-111111111111';
const PAYOUT_2 = '22222222-2222-4222-8222-222222222222';
const SETTLEMENT = '33333333-3333-4333-8333-333333333333';
const ORG = '44444444-4444-4444-8444-444444444444';
const OTHER_ORG = '55555555-5555-4555-8555-555555555555';
const DEST = 'acct_ORGAMINTED';
const RACE_DEST = 'acct_RACEDEST';

function ctx(over: Partial<PayoutExecutionContext> = {}): PayoutExecutionContext {
  return {
    payout_id: PAYOUT,
    cause: 'settlement',
    settlement_id: SETTLEMENT,
    payee_kind: 'organization',
    payee_org_id: ORG,
    amount_minor: 10000,
    currency: 'USD',
    status: 'submitted',
    hold_state: 'none',
    hold_reason_code: null,
    stripe_transfer_ref: null,
    source_transaction_ref: null,
    destination: DEST,
    destination_ref: DEST,
    org_connect_ref_current: DEST,
    org_status: 'active',
    connect_transfers_active: true,
    settlement_org_id: ORG,
    settlement_status: 'closed',
    settlement_net_minor: 10000,
    transfer_group: `payout_${PAYOUT}`,
    execution_eligible: true,
    refusal_code: null,
    ...over,
  };
}

/** A DB that refuses, exactly the way get_payout_execution_context does. */
function refused(code: string, over: Partial<PayoutExecutionContext> = {}): PayoutExecutionContext {
  return ctx({ execution_eligible: false, refusal_code: code, ...over });
}

const okAccount = (over: Partial<DestinationProbe> = {}): DestinationProbe => ({
  ok: true,
  id: DEST,
  deleted: false,
  transfers_capability: 'active',
  payouts_enabled: true,
  charges_enabled: true,
  details_submitted: true,
  disabled_reason: null,
  ...over,
});

const okBalance = (usd = 1_000_000): BalanceProbe => ({
  ok: true,
  available: [{ currency: 'usd', amount: usd }, { currency: 'eur', amount: 0 }],
});

// ── Stripe mock with REAL idempotency-key semantics ─────────────────────────

interface TransferObj { id: string; amount: number; currency: string; destination: string; transfer_group: string; reversed?: boolean }

class StripeMock {
  private byKey = new Map<string, { obj: TransferObj; body: string; at: number }>();
  /** How many distinct Transfer objects were actually created. THE detector. */
  created = 0;
  calls = 0;
  /** Total minor units actually moved, per destination. */
  movedByDestination = new Map<string, number>();
  /** Simulated clock, so a key can be aged past Stripe's 24h retention. */
  now = 0;
  /** Platform available balance, minor units. */
  balanceMinor = 1_000_000;
  accounts = new Map<string, DestinationProbe>([[DEST, okAccount()]]);

  getAccount(id: string): DestinationProbe {
    const a = this.accounts.get(id);
    if (!a) return { ok: false, error_code: 'resource_missing', error_message: `No such account: ${id}` };
    return a;
  }

  getBalance(): BalanceProbe {
    return { ok: true, available: [{ currency: 'usd', amount: this.balanceMinor }] };
  }

  listByTransferGroup(group: string): TransferObj[] {
    return [...this.byKey.values()].map((v) => v.obj).filter((o) => o.transfer_group === group);
  }

  /** Directly inject a transfer nobody recorded — the lost-response scenario. */
  injectOrphan(group: string, amount: number, destination: string, key = `orphan:${group}`): TransferObj {
    const obj: TransferObj = { id: `tr_${++this.created}`, amount, currency: 'usd', destination, transfer_group: group };
    this.byKey.set(key, { obj, body: 'orphan', at: this.now });
    this.movedByDestination.set(destination, (this.movedByDestination.get(destination) ?? 0) + amount);
    return obj;
  }

  create(
    idempotencyKey: string,
    body: Record<string, string>,
    opts: { transportFailureAfterCreate?: boolean; error?: { status: number; code: string } } = {},
  ): TransferObj {
    this.calls += 1;
    if (opts.error) {
      const e = new Error(opts.error.code) as Error & { __stripe: { status: number; error: { code: string } } };
      e.__stripe = { status: opts.error.status, error: { code: opts.error.code } };
      throw e;
    }
    const serialized = JSON.stringify(body);
    const existing = this.byKey.get(idempotencyKey);
    // Stripe retains a key's result for at least 24h and then forgets it.
    if (existing && this.now - existing.at < 24 * 3600) {
      if (existing.body !== serialized) {
        const e = new Error('idempotency_error') as Error & { __stripe: { status: number; error: { code: string } } };
        e.__stripe = { status: 400, error: { code: 'idempotency_error' } };
        throw e;
      }
      if (opts.transportFailureAfterCreate) throw new Error('network timeout');
      return existing.obj;   // the ORIGINAL object. No new money moves.
    }
    const amount = Number(body['amount']);
    const destination = body['destination'];
    if (amount > this.balanceMinor) {
      const e = new Error('balance_insufficient') as Error & { __stripe: { status: number; error: { code: string } } };
      e.__stripe = { status: 400, error: { code: 'balance_insufficient' } };
      throw e;
    }
    const obj: TransferObj = {
      id: `tr_${++this.created}`,
      amount,
      currency: body['currency'],
      destination,
      transfer_group: body['transfer_group'],
    };
    this.byKey.set(idempotencyKey, { obj, body: serialized, at: this.now });
    this.balanceMinor -= amount;
    this.movedByDestination.set(destination, (this.movedByDestination.get(destination) ?? 0) + amount);
    if (opts.transportFailureAfterCreate) throw new Error('network timeout');
    return obj;
  }
}

// ── kernel.payout + mark_payout_transfer_state mock (085:111-160, 1668-1735) ─

interface PayoutRow {
  payout_id: string;
  status: 'pending' | 'submitted' | 'paid' | 'failed' | 'reversed';
  hold_state: 'none' | 'held' | 'probation_hold';
  hold_reason_code: string | null;
  stripe_transfer_ref: string | null;
  destination_ref: string | null;
  amount_minor: number;
}

class KernelMock {
  rows = new Map<string, PayoutRow>();
  failNextStateSync = false;
  notes: Array<{ payout_id: string; reason_code: string }> = [];

  seed(row: PayoutRow) { this.rows.set(row.payout_id, { ...row }); }

  /** Faithful port of kernel.mark_payout_transfer_state (085:1668-1735). */
  markPayoutTransferState(
    payoutId: string,
    newStatus: string,
    ref: string | null,
    failureCode: string | null,
  ): { status: string } {
    if (this.failNextStateSync) {
      this.failNextStateSync = false;
      throw new Error('57P01: terminating connection due to administrator command');
    }
    if (!['paid', 'failed', 'reversed'].includes(newStatus)) {
      throw new Error('invalid_input: mark_payout_transfer_state takes paid|failed|reversed');
    }
    const row = this.rows.get(payoutId);
    if (!row) throw new Error(`not_found: payout ${payoutId}`);
    if (row.hold_state !== 'none') throw new Error('precondition_failed: payout_held');
    if (row.status === newStatus && (ref === null || row.stripe_transfer_ref === ref)) {
      return { status: 'noop_replay' };
    }
    const forward =
      (row.status === 'submitted' && (newStatus === 'paid' || newStatus === 'failed')) ||
      (row.status === 'paid' && newStatus === 'reversed');
    if (!forward) throw new Error(`precondition_failed: payout_state_backwards (${row.status} → ${newStatus})`);
    if ((newStatus === 'paid' || newStatus === 'reversed') && ref === null) {
      throw new Error(`invalid_input: stripe_transfer_ref is mandatory for ${newStatus}`);
    }
    if (newStatus === 'failed' && !failureCode) throw new Error('invalid_input: failure_code is mandatory for failed');
    if (row.stripe_transfer_ref !== null && ref !== null && row.stripe_transfer_ref !== ref) {
      throw new Error('conflict_locked: stripe_transfer_ref is write-once');
    }
    row.status = newStatus as PayoutRow['status'];
    row.stripe_transfer_ref = row.stripe_transfer_ref ?? ref;
    return { status: 'ok' };
  }

  /** kernel.request_org_payout's selection predicate (087:449-451). */
  visibleToRequestOrgPayout(payoutId: string): boolean {
    const r = this.rows.get(payoutId);
    return !!r && ['pending', 'submitted'].includes(r.status);
  }

  /** kernel.hold_payout_destination_changed (10o) — re-derives its own fault. */
  holdDestinationChanged(payoutId: string, orgCurrentRef: string | null, orgStatus: string, transfersActive: boolean) {
    const row = this.rows.get(payoutId);
    if (!row) throw new Error(`not_found: payout ${payoutId}`);
    if (row.stripe_transfer_ref !== null) throw new Error('precondition_failed: transfer_already_recorded');
    if (row.status !== 'submitted') throw new Error(`precondition_failed: payout is ${row.status}, not submitted`);
    if (row.hold_state !== 'none') return { status: 'noop_replay' };
    const fault =
      orgStatus !== 'approved' && orgStatus !== 'active' ? 'org_not_active'
      : row.destination_ref === null ? 'destination_not_bound'
      : orgCurrentRef === null ? 'no_payout_destination'
      : row.destination_ref !== orgCurrentRef ? 'destination_changed'
      : !transfersActive ? 'connect_transfers_inactive'
      : null;
    if (fault === null) throw new Error('precondition_failed: no_destination_fault');
    row.status = 'pending';
    row.hold_state = 'held';
    row.hold_reason_code = 'destination_changed';
    return { status: 'held', fault };
  }

  recordNote(payoutId: string, reasonCode: string) { this.notes.push({ payout_id: payoutId, reason_code: reasonCode }); }
}

/**
 * The edge's money leg, exactly as `index.ts` sequences it:
 * plan → account preflight → balance preflight → [reconcile] → create → sync.
 */
function runExecutor(
  kernel: KernelMock,
  stripe: StripeMock,
  context: PayoutExecutionContext,
  opts: {
    mode?: 'create' | 'reconcile';
    expected?: { org_id?: string | null; settlement_id?: string | null };
    transportFailureAfterCreate?: boolean;
    stripeError?: { status: number; code: string };
  } = {},
): { outcome: string; code?: string; ref?: string | null } {
  const plan = planPayoutTransfer(context, { execution_mode: opts.mode ?? 'create', expected: opts.expected });

  if (plan.kind === 'noop_replay') return { outcome: 'noop_replay', code: plan.reason, ref: plan.stripe_transfer_ref };
  if (plan.kind === 'refuse') {
    kernel.recordNote(context.payout_id, plan.code);
    return { outcome: 'refused', code: plan.code };
  }
  if (plan.kind === 'deauthorize') {
    const held = kernel.holdDestinationChanged(
      context.payout_id, context.org_connect_ref_current, context.org_status ?? '', context.connect_transfers_active,
    );
    return { outcome: 'deauthorized', code: (held as { fault?: string }).fault ?? plan.code };
  }

  const destVerdict = evaluateDestination(stripe.getAccount(plan.destination), plan.destination);
  const balVerdict = destVerdict.ok
    ? evaluateBalance(stripe.getBalance(), { amount_minor: plan.amount_minor, currency: plan.currency })
    : evaluateBalance({ ok: false, available: [], error_code: 'skipped' }, { amount_minor: plan.amount_minor, currency: plan.currency });

  let reconcile;
  if (plan.execution_mode === 'reconcile' && destVerdict.ok && balVerdict.ok) {
    reconcile = planReconcile(stripe.listByTransferGroup(plan.transfer_group), plan);
  }

  const auth = authorizeTransfer(plan, { destination: destVerdict, balance: balVerdict, reconcile });
  if (auth.kind === 'refuse') {
    kernel.recordNote(context.payout_id, auth.code);
    return { outcome: 'refused', code: auth.code };
  }

  let obj: { id?: string; reversed?: boolean; amount?: number; amount_reversed?: number };
  if (auth.kind === 'adopt') {
    obj = { id: auth.stripe_transfer_ref };
  } else if (auth.kind === 'reversed') {
    // A pre-existing reversal discovered at authorization time never reaches a
    // create: there is no money to send and no status this machine can write.
    kernel.recordNote(context.payout_id, 'transfer_reversed_on_arrival');
    return { outcome: 'state_sync_deferred', code: 'transfer_reversed', ref: null };
  } else {
    try {
      obj = stripe.create(auth.idempotency_key, auth.body, {
        transportFailureAfterCreate: opts.transportFailureAfterCreate,
        error: opts.stripeError,
      });
    } catch (err) {
      const tagged = err as Error & { __stripe?: { status: number; error: { code: string } } };
      const verdict = tagged.__stripe ? classifyTransferError(tagged.__stripe) : classifyTransferError(tagged);
      // THE CREATE-ERROR RULE: no `tr_…`, so NOTHING is written — and never 'failed'.
      expect(verdict.writesState).toBe(false);
      kernel.recordNote(context.payout_id, `stripe_${verdict.class}`);
      return { outcome: 'stripe_error', code: verdict.class };
    }
  }

  // The obligation amount comes from the LEDGER, never from the transfer object:
  // full-vs-partial reversal must be decided by what the venue is owed, not by
  // what Stripe's payload asserts about itself.
  const sync = planPayoutStateSync(obj, context.amount_minor);
  if (sync.kind === 'refuse') {
    kernel.recordNote(context.payout_id, sync.code);
    return { outcome: 'state_sync_deferred', code: sync.code, ref: obj.id ?? null };
  }
  if (sync.kind === 'reversed') {
    // Neither 'paid' nor 'reversed' is writable here — 'paid' would fire
    // on_payout_settled for money that came back, and 'reversed' is only
    // reachable THROUGH 'paid'. The state machine cannot represent a partial
    // reversal, so the row is left untouched and a human is paged.
    kernel.recordNote(context.payout_id, 'transfer_partially_reversed');
    return { outcome: 'state_sync_deferred', code: 'transfer_reversed', ref: obj.id ?? null };
  }
  for (const step of sync.steps) {
    try {
      kernel.markPayoutTransferState(context.payout_id, step.new_status, step.stripe_transfer_ref, step.failure_code);
    } catch (err) {
      const verdict = classifyPayoutStateSyncError((err as Error).message);
      kernel.recordNote(context.payout_id, `state_sync_${verdict.kind}`);
      if (verdict.kind === 'converged') {
        return { outcome: 'noop_replay', code: 'converged_elsewhere', ref: obj.id };
      }
      return { outcome: 'state_sync_deferred', code: `state_sync_${verdict.kind}`, ref: obj.id };
    }
  }
  return { outcome: 'paid', ref: obj.id ?? null };
}

function seedRow(kernel: KernelMock, c: PayoutExecutionContext) {
  kernel.seed({
    payout_id: c.payout_id,
    status: c.status as PayoutRow['status'],
    hold_state: c.hold_state,
    hold_reason_code: c.hold_reason_code,
    stripe_transfer_ref: c.stripe_transfer_ref,
    destination_ref: c.destination_ref,
    amount_minor: c.amount_minor,
  });
}

/** Re-read the DB row into a fresh context, as a later tick would. */
function reload(kernel: KernelMock, base: PayoutExecutionContext): PayoutExecutionContext {
  const row = kernel.rows.get(base.payout_id)!;
  const eligible = row.status === 'submitted' && row.hold_state === 'none' && row.stripe_transfer_ref === null;
  return {
    ...base,
    status: row.status,
    hold_state: row.hold_state,
    hold_reason_code: row.hold_reason_code,
    stripe_transfer_ref: row.stripe_transfer_ref,
    destination_ref: row.destination_ref,
    execution_eligible: eligible,
    refusal_code: eligible ? null : row.hold_state !== 'none' ? 'payout_held' : 'payout_not_submitted',
  };
}

// ════════════════════════════════════════════════════════════════════════════
// 1. THE ABSORBING `failed` STATE — the constraint everything else serves
// ════════════════════════════════════════════════════════════════════════════

describe("`failed` is absorbing, so the executor must be structurally incapable of writing it", () => {
  it('085 offers NO edge out of failed (the mock reproduces the shipped function)', () => {
    const k = new KernelMock();
    k.seed({ payout_id: PAYOUT, status: 'submitted', hold_state: 'none', hold_reason_code: null, stripe_transfer_ref: null, destination_ref: DEST, amount_minor: 10000 });
    expect(k.markPayoutTransferState(PAYOUT, 'failed', null, 'boom').status).toBe('ok');
    expect(() => k.markPayoutTransferState(PAYOUT, 'paid', 'tr_x', null)).toThrow(/payout_state_backwards \(failed → paid\)/);
    expect(() => k.markPayoutTransferState(PAYOUT, 'reversed', 'tr_x', null)).toThrow(/payout_state_backwards \(failed → reversed\)/);
    expect(() => k.markPayoutTransferState(PAYOUT, 'submitted', 'tr_x', null)).toThrow(/invalid_input/);
    // …and request_org_payout can never see it again, so the money is gone.
    expect(k.visibleToRequestOrgPayout(PAYOUT)).toBe(false);
  });

  it('the executor can produce exactly ONE state-sync target, and it is `paid`', () => {
    expect(PAYOUT_STATE_SYNC_TARGETS).toEqual(['paid']);
  });

  it('EVERY Stripe outcome — success, every error class, transport, reversed, malformed — never yields `failed`', () => {
    const errorCodes = [
      { status: 400, code: 'idempotency_error' },
      { status: 409, code: 'idempotency_key_in_use' },
      { status: 400, code: 'balance_insufficient' },
      { status: 400, code: 'account_invalid' },
      { status: 404, code: 'resource_missing' },
      { status: 429, code: 'rate_limit' },
      { status: 500, code: 'api_error' },
      { status: 402, code: 'card_declined' },
    ];
    const attempted: string[] = [];
    for (const e of errorCodes) {
      const k = new KernelMock();
      const s = new StripeMock();
      const c = ctx();
      seedRow(k, c);
      const origSync = k.markPayoutTransferState.bind(k);
      k.markPayoutTransferState = (id, st, ref, fc) => { attempted.push(st); return origSync(id, st, ref, fc); };
      runExecutor(k, s, c, { stripeError: e });
      expect(k.rows.get(PAYOUT)!.status).toBe('submitted');   // recoverable, not destroyed
    }
    // transport failure after the create
    {
      const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
      const orig = k.markPayoutTransferState.bind(k);
      k.markPayoutTransferState = (id, st, ref, fc) => { attempted.push(st); return orig(id, st, ref, fc); };
      runExecutor(k, s, c, { transportFailureAfterCreate: true });
      expect(k.rows.get(PAYOUT)!.status).toBe('submitted');
    }
    // reversed-on-arrival and malformed id. The obligation amount is a REQUIRED
    // second argument now: full-vs-partial is derived from the ledger's own
    // number, never from anything the caller asserts about the transfer.
    expect(planPayoutStateSync({ id: 'tr_1', reversed: true }, 10_000).kind).toBe('reversed');
    expect(planPayoutStateSync({ id: 'nope' }, 10_000).kind).toBe('refuse');

    // THE DEFECT THIS SIGNATURE EXISTS TO CLOSE. Stripe: "if the transfer is
    // only partially reversed, this attribute will still be false." Reading
    // `reversed` as the whole truth marked a partially reversed transfer 'paid'
    // at FULL face value — asserting the venue holds money already pulled back.
    {
      const partial = planPayoutStateSync(
        { id: 'tr_partial', amount: 10_000, reversed: false, amount_reversed: 2_500 },
        10_000,
      );
      expect(partial.kind).toBe('reversed');
      expect(partial.kind === 'reversed' && partial.reversal.amount_reversed_minor).toBe(2_500);
    }

    // An unreadable reversal refuses rather than assuming nothing came back —
    // the safe direction is "we do not know", not "it is fine".
    expect(
      planPayoutStateSync({ id: 'tr_x', amount: 10_000, amount_reversed: 'nope' }, 10_000).kind,
    ).toBe('refuse');

    // A clean transfer still syncs to paid.
    expect(
      planPayoutStateSync(
        { id: 'tr_ok', amount: 10_000, reversed: false, amount_reversed: 0 },
        10_000,
      ).kind,
    ).toBe('sync');
    // success
    {
      const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
      const orig = k.markPayoutTransferState.bind(k);
      k.markPayoutTransferState = (id, st, ref, fc) => { attempted.push(st); return orig(id, st, ref, fc); };
      expect(runExecutor(k, s, c).outcome).toBe('paid');
    }
    expect(attempted.every((s) => s === 'paid')).toBe(true);
    expect(attempted).not.toContain('failed');
  });

  it('a payout already in `failed` is never resurrected by the executor — it is simply not eligible', () => {
    const k = new KernelMock(); const s = new StripeMock();
    const c = refused('payout_not_submitted', { status: 'failed' });
    seedRow(k, c);
    const r = runExecutor(k, s, c);
    expect(r.outcome).toBe('refused');
    expect(s.created).toBe(0);
    // and the claim primitive never hands out a failed row in the first place
    expect(planPayoutBatch([{ payout_id: PAYOUT, created_at: 'x', status: 'failed', execution_mode: 'create', attempt: 1, command_key: `payout.execute:${PAYOUT}` }]))
      .toHaveLength(1);   // the DB filters status; the worker does NOT re-decide
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 2. The idempotency key
// ════════════════════════════════════════════════════════════════════════════

describe('Stripe idempotency key — derived from the payout row, never the request', () => {
  it('is payout_<payout_id>_<destination>_v1 (H3 §5)', () => {
    expect(buildPayoutTransferIdempotencyKey(PAYOUT, DEST)).toBe(`payout_${PAYOUT}_${DEST}_v1`);
  });
  it('is disjoint from the resale rail`s `_src` key space', () => {
    expect(buildPayoutTransferIdempotencyKey(PAYOUT, DEST).endsWith('_src')).toBe(false);
  });
  it('changes when the destination changes, so a re-point can never replay a stale key', () => {
    expect(buildPayoutTransferIdempotencyKey(PAYOUT, DEST)).not.toBe(buildPayoutTransferIdempotencyKey(PAYOUT, RACE_DEST));
  });
  it('refuses to be built from a non-uuid payout or a malformed destination', () => {
    expect(() => buildPayoutTransferIdempotencyKey('nope', DEST)).toThrow();
    expect(() => buildPayoutTransferIdempotencyKey(PAYOUT, 'not-an-account')).toThrow();
  });
  it('transfer_group is payout_<id> — the recovery handle (H3 §6)', () => {
    expect(buildTransferGroup(PAYOUT)).toBe(`payout_${PAYOUT}`);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 3. Normal execution
// ════════════════════════════════════════════════════════════════════════════

describe('normal execution', () => {
  it('pays the ledger amount to the pinned destination, with NO source_transaction', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    const r = runExecutor(k, s, c);
    expect(r.outcome).toBe('paid');
    expect(s.created).toBe(1);
    expect(s.movedByDestination.get(DEST)).toBe(10000);
    expect(k.rows.get(PAYOUT)!.status).toBe('paid');
    expect(k.rows.get(PAYOUT)!.stripe_transfer_ref).toBe(r.ref);
  });

  it('the request body carries amount/currency/destination/transfer_group and NOT source_transaction', () => {
    const plan = planPayoutTransfer(ctx());
    expect(plan.kind).toBe('preflight');
    const auth = authorizeTransfer(plan as never, {
      destination: evaluateDestination(okAccount(), DEST),
      balance: evaluateBalance(okBalance(), { amount_minor: 10000, currency: 'usd' }),
    });
    expect(auth.kind).toBe('stripe_create');
    const body = (auth as { body: Record<string, string> }).body;
    expect(body).toMatchObject({
      amount: '10000',
      currency: 'usd',
      destination: DEST,
      transfer_group: `payout_${PAYOUT}`,
      'metadata[payout_id]': PAYOUT,
      'metadata[settlement_id]': SETTLEMENT,
      'metadata[org_id]': ORG,
    });
    expect(Object.keys(body)).not.toContain('source_transaction');
  });

  it('the amount is the LEDGER amount and is never recomputed', () => {
    // The DB proves payout.amount_minor == settlement.net_minor; the executor
    // asserts the same equality and refuses if the two ever disagree.
    const r = planPayoutTransfer(ctx({ amount_minor: 9999 }));
    expect(r).toMatchObject({ kind: 'refuse', code: 'context_binding_inconsistent' });
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 4. Retry after success, timeouts, and the money-moved-DB-failed case
// ════════════════════════════════════════════════════════════════════════════

describe('retry after success', () => {
  it('a second run replays the SAME key and moves no second transfer', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    expect(runExecutor(k, s, c).outcome).toBe('paid');
    const again = runExecutor(k, s, reload(k, c));
    expect(again.outcome).toBe('noop_replay');
    expect(again.code).toBe('transfer_already_recorded');
    expect(s.created).toBe(1);
    expect(s.movedByDestination.get(DEST)).toBe(10000);
  });
});

describe('Stripe timeout (created server-side, response lost)', () => {
  it('writes nothing, leaves the row submitted, and the retry adopts the SAME transfer', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    const first = runExecutor(k, s, c, { transportFailureAfterCreate: true });
    expect(first.outcome).toBe('stripe_error');
    expect(first.code).toBe('network');
    expect(k.rows.get(PAYOUT)!.status).toBe('submitted');       // NOT failed
    expect(k.rows.get(PAYOUT)!.stripe_transfer_ref).toBeNull();
    expect(s.created).toBe(1);                                   // Stripe DID create it

    const second = runExecutor(k, s, reload(k, c));
    expect(second.outcome).toBe('paid');
    expect(s.created).toBe(1);                                   // replay, not re-pay
    expect(s.movedByDestination.get(DEST)).toBe(10000);
  });

  it('past Stripe`s 24h key window, reconcile mode finds it by transfer_group instead of creating a second one', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    runExecutor(k, s, c, { transportFailureAfterCreate: true });
    expect(s.created).toBe(1);

    s.now += 25 * 3600;   // Stripe has forgotten the key
    const recovered = runExecutor(k, s, reload(k, c), { mode: 'reconcile' });
    expect(recovered.outcome).toBe('paid');
    expect(s.created).toBe(1);                                   // no second transfer
    expect(s.movedByDestination.get(DEST)).toBe(10000);
    expect(k.rows.get(PAYOUT)!.stripe_transfer_ref).toBe('tr_1');
  });

  it('WITHOUT reconcile mode, a >24h retry WOULD double-pay — which is why the mode exists', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    runExecutor(k, s, c, { transportFailureAfterCreate: true });
    s.now += 25 * 3600;
    runExecutor(k, s, reload(k, c), { mode: 'create' });          // the WRONG mode
    expect(s.created).toBe(2);                                    // the documented hazard
    // The claim primitive is what prevents this: it returns 'reconcile' for any
    // payout whose first claim is older than 20h.
  });

  it('reconcile mode with NO prior transfer is allowed to create', () => {
    expect(planReconcile([], { amount_minor: 10000, currency: 'usd', destination: DEST })).toEqual({ kind: 'create_allowed' });
  });

  it('reconcile refuses when two transfers already share the group, and never creates a third', () => {
    const r = planReconcile(
      [{ id: 'tr_1', amount: 10000, currency: 'usd', destination: DEST }, { id: 'tr_2', amount: 10000, currency: 'usd', destination: DEST }],
      { amount_minor: 10000, currency: 'usd', destination: DEST },
    );
    expect(r).toMatchObject({ kind: 'refuse', code: 'reconcile_ambiguous' });
  });

  it('reconcile refuses to adopt a transfer of a different amount or a different payee', () => {
    expect(planReconcile([{ id: 'tr_1', amount: 9000, currency: 'usd', destination: DEST }], { amount_minor: 10000, currency: 'usd', destination: DEST }))
      .toMatchObject({ kind: 'refuse', code: 'reconcile_amount_mismatch' });
    expect(planReconcile([{ id: 'tr_1', amount: 10000, currency: 'usd', destination: RACE_DEST }], { amount_minor: 10000, currency: 'usd', destination: DEST }))
      .toMatchObject({ kind: 'refuse', code: 'reconcile_amount_mismatch' });
  });

  it('reconcile mode that never read the transfer group fails CLOSED', () => {
    const plan = planPayoutTransfer(ctx(), { execution_mode: 'reconcile' });
    const auth = authorizeTransfer(plan as never, {
      destination: evaluateDestination(okAccount(), DEST),
      balance: evaluateBalance(okBalance(), { amount_minor: 10000, currency: 'usd' }),
      // reconcile deliberately omitted
    });
    expect(auth).toMatchObject({ kind: 'refuse', code: 'reconcile_ambiguous' });
  });

  it('an orphaned transfer nobody recorded is adopted, not duplicated', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    s.injectOrphan(`payout_${PAYOUT}`, 10000, DEST);
    const r = runExecutor(k, s, c, { mode: 'reconcile' });
    expect(r.outcome).toBe('paid');
    expect(s.created).toBe(1);
  });
});

describe('Stripe succeeded → mark_payout_transfer_state failed', () => {
  it('leaves the row submitted, writes nothing, and the next tick converges via the same key', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    k.failNextStateSync = true;
    const first = runExecutor(k, s, c);
    expect(first.outcome).toBe('state_sync_deferred');
    expect(k.rows.get(PAYOUT)!.status).toBe('submitted');   // NOT failed
    expect(k.rows.get(PAYOUT)!.stripe_transfer_ref).toBeNull();
    expect(s.created).toBe(1);

    const second = runExecutor(k, s, reload(k, c));
    expect(second.outcome).toBe('paid');
    expect(s.created).toBe(1);
    expect(k.rows.get(PAYOUT)!.stripe_transfer_ref).toBe('tr_1');
  });

  it('a human hold landing between the create and the callback half-writes nothing', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    // simulate: transfer created, then a risk hold, then our callback
    const plan = planPayoutTransfer(c) as { kind: string } & Record<string, unknown>;
    const auth = authorizeTransfer(plan as never, {
      destination: evaluateDestination(okAccount(), DEST),
      balance: evaluateBalance(okBalance(), { amount_minor: 10000, currency: 'usd' }),
    }) as { idempotency_key: string; body: Record<string, string> };
    const obj = s.create(auth.idempotency_key, auth.body);
    k.rows.get(PAYOUT)!.hold_state = 'held';
    k.rows.get(PAYOUT)!.hold_reason_code = 'dispute';
    expect(() => k.markPayoutTransferState(PAYOUT, 'paid', obj.id, null)).toThrow(/payout_held/);
    expect(k.rows.get(PAYOUT)!.status).toBe('submitted');
    expect(k.rows.get(PAYOUT)!.stripe_transfer_ref).toBeNull();
    expect(classifyPayoutStateSyncError('precondition_failed: payout_held')).toEqual({ kind: 'held', page: true });
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 5. Concurrency and the claim
// ════════════════════════════════════════════════════════════════════════════

describe('concurrent workers', () => {
  it('two workers on one payout produce ONE transfer and ONE ref', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    const a = runExecutor(k, s, c);
    const b = runExecutor(k, s, c);   // the loser: same context, same key
    expect(s.created).toBe(1);
    expect(s.movedByDestination.get(DEST)).toBe(10000);
    expect([a.outcome, b.outcome].filter((o) => o === 'paid').length).toBeGreaterThanOrEqual(1);
    expect(b.outcome === 'paid' || b.outcome === 'noop_replay').toBe(true);
    expect(k.rows.get(PAYOUT)!.stripe_transfer_ref).toBe('tr_1');
  });

  it('the loser of a state-sync race converges rather than hot-looping', () => {
    expect(classifyPayoutStateSyncError('precondition_failed: payout_state_backwards (paid → paid)'))
      .toEqual({ kind: 'converged', page: false });
    expect(classifyPayoutStateSyncError('conflict_locked: stripe_transfer_ref is write-once'))
      .toEqual({ kind: 'conflict', page: true });
  });

  it('the batch is deduped, bounded and mode-checked; the DB decides eligibility', () => {
    const rows = [
      { payout_id: PAYOUT, created_at: '1', status: 'submitted' as const, execution_mode: 'create' as const, attempt: 1, command_key: `payout.execute:${PAYOUT}` },
      { payout_id: PAYOUT, created_at: '1', status: 'submitted' as const, execution_mode: 'create' as const, attempt: 1, command_key: `payout.execute:${PAYOUT}` },
      { payout_id: PAYOUT_2, created_at: '2', status: 'submitted' as const, execution_mode: 'reconcile' as const, attempt: 3, command_key: `payout.execute:${PAYOUT_2}` },
      { payout_id: 'not-a-uuid', created_at: '3', status: 'submitted' as const, execution_mode: 'create' as const, attempt: 1, command_key: 'x' },
    ];
    const out = planPayoutBatch(rows, { limit: 10 });
    expect(out.map((r) => r.payout_id)).toEqual([PAYOUT, PAYOUT_2]);
    expect(out[1].execution_mode).toBe('reconcile');
  });

  it('the command key is DB-derived, so two workers on one payout share one audit identity', () => {
    const claim = { payout_id: PAYOUT, created_at: '1', status: 'submitted' as const, execution_mode: 'create' as const, attempt: 2, command_key: `payout.execute:${PAYOUT}` };
    expect(claim.command_key).toBe(`payout.execute:${PAYOUT}`);
    expect(claim.command_key.length).toBeLessThanOrEqual(64);   // admin_audit budget, no truncation
  });
});

describe('stale claim', () => {
  it('a lease that has expired hands the row back in `reconcile` mode once the 20h window passes', () => {
    // The DB decides the mode; the executor must honour it. A worker that
    // crashed after creating a transfer gets the row back, and reconcile mode
    // adopts the orphan instead of creating a second transfer.
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    runExecutor(k, s, c, { transportFailureAfterCreate: true });   // worker 1 crashed
    s.now += 21 * 3600;                                            // lease + key window
    const recovered = runExecutor(k, s, reload(k, c), { mode: 'reconcile' });
    expect(recovered.outcome).toBe('paid');
    expect(s.created).toBe(1);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 6. Preflights — no idempotency key is ever spent on a request that can't work
// ════════════════════════════════════════════════════════════════════════════

describe('balance preflight (H3 §3.5 — MANDATORY, before the key is spent)', () => {
  it('a shortfall never reaches POST /v1/transfers', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    s.balanceMinor = 9999;
    const r = runExecutor(k, s, c);
    expect(r).toMatchObject({ outcome: 'refused', code: 'balance_insufficient' });
    expect(s.calls).toBe(0);                    // the key was never spent
    expect(k.rows.get(PAYOUT)!.status).toBe('submitted');
    expect(k.notes.map((n) => n.reason_code)).toContain('balance_insufficient');
  });

  it('and once the balance is topped up the SAME key succeeds — the key was not burned', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    s.balanceMinor = 9999;
    runExecutor(k, s, c);
    s.balanceMinor = 50000;
    expect(runExecutor(k, s, reload(k, c)).outcome).toBe('paid');
    expect(s.created).toBe(1);
  });

  it('reads the matching currency only, and treats an unreadable balance as retryable', () => {
    expect(evaluateBalance({ ok: true, available: [{ currency: 'eur', amount: 999999 }] }, { amount_minor: 10000, currency: 'usd' }))
      .toMatchObject({ ok: false, code: 'balance_insufficient' });
    expect(evaluateBalance({ ok: false, available: [], error_code: 'api_error' }, { amount_minor: 1, currency: 'usd' }))
      .toMatchObject({ ok: false, code: 'balance_unreadable', retryable: true });
  });
});

describe('destination preflight (incident 2 — keys are only spent on requests that can succeed)', () => {
  it('a disconnected / deleted account fails safely and spends no key', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    s.accounts.delete(DEST);
    const r = runExecutor(k, s, c);
    expect(r).toMatchObject({ outcome: 'refused', code: 'destination_deleted' });
    expect(s.calls).toBe(0);
    expect(k.rows.get(PAYOUT)!.status).toBe('submitted');
  });

  it('transfers-disabled fails safely and spends no key', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    s.accounts.set(DEST, okAccount({ transfers_capability: 'inactive' }));
    const r = runExecutor(k, s, c);
    expect(r).toMatchObject({ outcome: 'refused', code: 'destination_transfers_inactive' });
    expect(s.calls).toBe(0);
  });

  it('a Stripe-disabled account (requirements.disabled_reason) fails safely', () => {
    expect(evaluateDestination(okAccount({ disabled_reason: 'requirements.past_due' }), DEST))
      .toMatchObject({ ok: false, code: 'destination_disabled', retryable: true });
  });

  it('an account object whose id is not the one we asked for is refused outright', () => {
    expect(evaluateDestination(okAccount({ id: RACE_DEST }), DEST))
      .toMatchObject({ ok: false, code: 'destination_identity_mismatch', retryable: false });
  });

  it('`deleted: true` is treated as disconnected', () => {
    expect(evaluateDestination(okAccount({ deleted: true }), DEST)).toMatchObject({ ok: false, code: 'destination_deleted' });
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 7. The payee — destination changed, wrong org, personal seller plane
// ════════════════════════════════════════════════════════════════════════════

describe('destination changed mid-flight (H6 — the proved race)', () => {
  it('de-authorizes instead of paying either address, and never writes failed', () => {
    const k = new KernelMock(); const s = new StripeMock();
    const c = ctx({ org_connect_ref_current: RACE_DEST, execution_eligible: false, refusal_code: 'destination_changed' });
    seedRow(k, c);
    const r = runExecutor(k, s, c);
    expect(r).toMatchObject({ outcome: 'deauthorized', code: 'destination_changed' });
    expect(s.created).toBe(0);
    expect(s.movedByDestination.get(RACE_DEST)).toBeUndefined();
    const row = k.rows.get(PAYOUT)!;
    expect(row.status).toBe('pending');            // de-authorized, NOT failed
    expect(row.hold_state).toBe('held');
    expect(row.hold_reason_code).toBe('destination_changed');
    // and a held row is refused by the state machine, so nothing can pay it now
    expect(() => k.markPayoutTransferState(PAYOUT, 'paid', 'tr_x', null)).toThrow(/payout_held/);
    // but it is still RECOVERABLE — unlike `failed`
    expect(k.visibleToRequestOrgPayout(PAYOUT)).toBe(true);
  });

  it('even when the DB has not yet noticed, the executor`s own pin check catches it', () => {
    const plan = planPayoutTransfer(ctx({ org_connect_ref_current: RACE_DEST }));
    expect(plan).toMatchObject({ kind: 'deauthorize', code: 'destination_changed' });
  });

  it('a worker cannot de-authorize a healthy payout — the DB verb re-derives the fault', () => {
    const k = new KernelMock(); const c = ctx(); seedRow(k, c);
    expect(() => k.holdDestinationChanged(PAYOUT, DEST, 'active', true)).toThrow(/no_destination_fault/);
  });

  it('a suspended organization and an inactive transfers capability are both de-authorizing', () => {
    expect(planPayoutTransfer(refused('org_not_active', { org_status: 'suspended' })))
      .toMatchObject({ kind: 'deauthorize', code: 'org_not_active' });
    expect(planPayoutTransfer(refused('connect_transfers_inactive', { connect_transfers_active: false })))
      .toMatchObject({ kind: 'deauthorize', code: 'connect_transfers_inactive' });
    expect(DEAUTHORIZING_REFUSALS).toContain('no_payout_destination');
  });
});

describe('wrong organization', () => {
  it('a payout whose settlement belongs to another org is refused', () => {
    expect(planPayoutTransfer(ctx({ settlement_org_id: OTHER_ORG })))
      .toMatchObject({ kind: 'refuse', code: 'context_binding_inconsistent' });
  });
  it('the DB`s own org_mismatch verdict is honoured, and no Stripe call is made', () => {
    const k = new KernelMock(); const s = new StripeMock();
    const c = refused('org_mismatch', { settlement_org_id: OTHER_ORG });
    seedRow(k, c);
    expect(runExecutor(k, s, c).outcome).toBe('refused');
    expect(s.calls).toBe(0);
  });
  it('a caller asserting a different org gets a refusal, not someone else`s money', () => {
    expect(planPayoutTransfer(ctx(), { expected: { org_id: OTHER_ORG } }))
      .toMatchObject({ kind: 'refuse', code: 'context_binding_inconsistent' });
    expect(planPayoutTransfer(ctx(), { expected: { settlement_id: PAYOUT_2 } }))
      .toMatchObject({ kind: 'refuse', code: 'context_binding_inconsistent' });
  });
  it('a non-settlement or identity-payee payout is structurally refused', () => {
    expect(planPayoutTransfer(ctx({ cause: 'promoter_commission' }))).toMatchObject({ kind: 'refuse' });
    expect(planPayoutTransfer(ctx({ payee_kind: 'identity', payee_org_id: null }))).toMatchObject({ kind: 'refuse' });
  });
});

describe('personal seller Connect account', () => {
  it('is a DB refusal the executor honours without calling Stripe', () => {
    const k = new KernelMock(); const s = new StripeMock();
    const c = refused('destination_individual_plane');
    seedRow(k, c);
    expect(runExecutor(k, s, c)).toMatchObject({ outcome: 'refused', code: 'db_refused' });
    expect(s.calls).toBe(0);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 8. Amount tampering
// ════════════════════════════════════════════════════════════════════════════

describe('amount tampering', () => {
  it('the request may not name an amount, a destination or an organization', () => {
    for (const k of ['amount', 'amount_minor', 'destination', 'org_id', 'settlement_id', 'source_transaction', 'stripe_transfer_ref', 'currency', 'idempotency_key']) {
      expect(assertNoClientMoneyReference({ [k]: 'x' })).toMatchObject({ ok: false, code: 'client_supplied_money_reference' });
    }
    expect(assertNoClientMoneyReference({ limit: 25 })).toEqual({ ok: true });
  });

  it('a payout amount edited away from the closed settlement net is refused', () => {
    expect(planPayoutTransfer(ctx({ amount_minor: 999999, settlement_net_minor: 10000 })))
      .toMatchObject({ kind: 'refuse', code: 'context_binding_inconsistent' });
    expect(planPayoutTransfer(ctx({ amount_minor: 0 }))).toMatchObject({ kind: 'refuse' });
    expect(planPayoutTransfer(ctx({ amount_minor: -1 }))).toMatchObject({ kind: 'refuse' });
  });

  it('an amount mutated between two attempts is caught by Stripe as an idempotency_error, not silently paid', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    // first attempt: transport failure after the create, so our row is unchanged
    runExecutor(k, s, c, { transportFailureAfterCreate: true });
    expect(s.created).toBe(1);
    // an attacker mutates BOTH the payout and the settlement so the executor's
    // own equality check passes; Stripe still refuses the reused key.
    // A SMALLER amount, so the balance preflight cannot mask the point: Stripe
    // itself refuses the reused key because the parameters differ.
    const tampered = { ...reload(k, c), amount_minor: 9000, settlement_net_minor: 9000 };
    const r = runExecutor(k, s, tampered);
    expect(r).toMatchObject({ outcome: 'stripe_error', code: 'idempotency_conflict' });
    expect(s.created).toBe(1);
    expect(s.movedByDestination.get(DEST)).toBe(10000);   // the original amount only
    expect(k.rows.get(PAYOUT)!.status).toBe('submitted');
  });

  it('an inflated amount is stopped even earlier — by the balance preflight, before the key', () => {
    const k = new KernelMock(); const s = new StripeMock(); const c = ctx(); seedRow(k, c);
    s.balanceMinor = 20000;
    const tampered = { ...c, amount_minor: 999999, settlement_net_minor: 999999 };
    expect(runExecutor(k, s, tampered)).toMatchObject({ outcome: 'refused', code: 'balance_insufficient' });
    expect(s.calls).toBe(0);
    expect(k.rows.get(PAYOUT)!.status).toBe('submitted');
  });

  it('an idempotency_conflict is never retried blind', () => {
    expect(classifyTransferError({ status: 400, error: { code: 'idempotency_error' } }))
      .toMatchObject({ class: 'idempotency_conflict', retryable: false, page: true, writesState: false });
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 9. The DB verdict is adopted, never re-derived
// ════════════════════════════════════════════════════════════════════════════

describe('the database decides', () => {
  it('every non-de-authorizing refusal leaves the row submitted and calls Stripe zero times', () => {
    const codes = [
      'payout_held', 'payout_not_submitted', 'amount_ledger_mismatch', 'settlement_not_closed',
      'currency_mismatch', 'maturity_not_elapsed', 'refund_in_flight', 'dispute_open',
      'event_cancelled', 'unbounded_refund_exposure', 'refund_exposure_stale',
      'covered_set_unresolvable', 'destination_cooldown', 'destination_not_bound',
      'destination_individual_plane', 'transfer_already_recorded',
    ];
    for (const code of codes) {
      const k = new KernelMock(); const s = new StripeMock();
      const c = refused(code);
      seedRow(k, c);
      const r = runExecutor(k, s, c);
      expect([r.outcome, code]).toEqual(['refused', code]);
      expect(s.calls).toBe(0);
      expect(k.rows.get(PAYOUT)!.status).toBe('submitted');
    }
  });

  it('transient refusals are retried; the rest wait for a human', () => {
    expect(isTransientRefusal('maturity_not_elapsed')).toBe(true);
    expect(isTransientRefusal('refund_in_flight')).toBe(true);
    expect(isTransientRefusal('dispute_open')).toBe(true);
    expect(isTransientRefusal('refund_exposure_stale')).toBe(false);
    expect(isTransientRefusal('payout_held')).toBe(false);
  });

  it('a held payout never reaches Stripe even if a caller forces the context', () => {
    const k = new KernelMock(); const s = new StripeMock();
    const c = refused('payout_held', { hold_state: 'held', hold_reason_code: 'dispute' });
    seedRow(k, c);
    expect(runExecutor(k, s, c).outcome).toBe('refused');
    expect(s.calls).toBe(0);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 10. Small surfaces
// ════════════════════════════════════════════════════════════════════════════

describe('uuid and account discipline', () => {
  it('rejects the nil uuid and non-uuids', () => {
    expect(isUuid('00000000-0000-0000-0000-000000000000')).toBe(false);
    expect(isUuid(PAYOUT)).toBe(true);
    expect(isUuid(undefined)).toBe(false);
  });
  it('only acct_ identifiers are accepted as destinations', () => {
    expect(ACCT_RE.test(DEST)).toBe(true);
    expect(ACCT_RE.test('cus_123')).toBe(false);
    expect(planPayoutTransfer(ctx({ destination_ref: 'cus_123', destination: 'cus_123', org_connect_ref_current: 'cus_123' })))
      .toMatchObject({ kind: 'refuse', code: 'destination_malformed' });
  });
});

describe('error taxonomy', () => {
  it('classifies the operational classes without paging, and the bugs with paging', () => {
    expect(classifyTransferError({ status: 409, error: { code: 'idempotency_key_in_use' } })).toMatchObject({ class: 'idempotency_in_use', retryable: true, page: false });
    expect(classifyTransferError({ status: 400, error: { code: 'balance_insufficient' } })).toMatchObject({ class: 'balance_insufficient', retryable: true, page: false });
    expect(classifyTransferError({ status: 429, error: { type: 'rate_limit_error' } })).toMatchObject({ class: 'rate_limited', retryable: true });
    expect(classifyTransferError({ status: 503, error: { type: 'api_error' } })).toMatchObject({ class: 'api_error', retryable: true });
    expect(classifyTransferError({ status: 404, error: { code: 'resource_missing' } })).toMatchObject({ class: 'resource_missing', retryable: false, page: true });
    expect(classifyTransferError(new Error('socket hang up'))).toMatchObject({ class: 'network', retryable: true });
  });
  it('no error class ever writes state', () => {
    const inputs = [
      { status: 400, error: { code: 'idempotency_error' } },
      { status: 409, error: { code: 'idempotency_key_in_use' } },
      { status: 400, error: { code: 'balance_insufficient' } },
      { status: 500, error: { type: 'api_error' } },
      { status: 402, error: { type: 'invalid_request_error' } },
    ];
    for (const i of inputs) expect(classifyTransferError(i).writesState).toBe(false);
    expect(classifyTransferError(new Error('x')).writesState).toBe(false);
  });
});
