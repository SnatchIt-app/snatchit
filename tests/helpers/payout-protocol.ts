/**
 * tests/helpers/payout-protocol.ts — deterministic model of the two systems
 * the payout attempt protocol spans (migration 20260906120000):
 *
 *   • StripeTransfersMock — POST /v1/transfers with REAL idempotency-key
 *     semantics (same key within 24h → same object; after 24h the key is
 *     forgotten and a replay creates a SECOND transfer — the F08 hazard),
 *     transfer_group listing (GET /v1/transfers?transfer_group=…), the
 *     account/PI pre-flight probes, and fault injection (network error after
 *     create = lost response, 5xx, 409 in-flight, 4xx).
 *   • AttemptLedger — the payout_attempts RPCs (claim_payout_attempt,
 *     mark_payout_requested, record_payout_attempt_result,
 *     reconcile_payout_attempt) with the exact predicates of the migration,
 *     over in-memory transfers/payments/profiles rows, plus an `rpc()`
 *     adapter so the REAL edge handlers and _shared/payouts.ts can run
 *     against it through mockSupabase / loadPayoutsModule.
 *
 * Postgres and Stripe are separate systems; there is no cross-system
 * atomicity and this model claims none. It exists so every interleaving in
 * tests/payout-races.test.ts and the handler tests ends with exactly ONE
 * real Stripe transfer per obligation and a DB row that knows about it.
 */
import type { StripeCall } from './edge-vm';

export const HOUR = 3_600_000;
export const KEY_TTL_MS = 24 * HOUR;
export const LEASE_MS = 10 * 60_000;

// ── Stripe ───────────────────────────────────────────────────────────────────

export interface StripeTransferObj {
  id: string;
  amount: number;
  destination: string;
  transfer_group: string | null;
  metadata: Record<string, string>;
  source_transaction: string | null;
}

export type StripeFault =
  | { kind: 'network' }                 // fetch throws; nothing created
  | { kind: 'lost_response' }           // Stripe CREATES the transfer, then the response is lost
  | { kind: 'status'; status: number; type?: string; message?: string }; // non-2xx; nothing created (Stripe semantics for 4xx/5xx here)

export class StripeTransfersMock {
  now = 0;
  created = 0;
  posts = 0;
  transfers: StripeTransferObj[] = [];
  private byKey = new Map<string, { id: string; expiresAt: number; params: string }>();
  /** consumed by the NEXT POST /transfers */
  nextPostFault: StripeFault | null = null;
  /** GET /transfers listing fails */
  listFault: StripeFault | null = null;
  accountCapability: 'active' | 'inactive' = 'active';
  chargeRefunded = false;
  chargeAmount = 11000;
  /** livemode reported by the PI probe (a Stripe TEST key returns false) */
  piLivemode = true;
  amountRefunded = 0;

  advance(ms: number) { this.now += ms; }

  /** raw idempotent create — the model layer (payout-races) calls this directly */
  createTransfer(key: string, params: { amount: number; destination: string; transfer_group: string | null; metadata: Record<string, string>; source_transaction?: string | null }): StripeTransferObj {
    const p = JSON.stringify([params.amount, params.destination, params.transfer_group, params.metadata]);
    const known = this.byKey.get(key);
    if (known && known.expiresAt > this.now) {
      if (known.params !== p) throw Object.assign(new Error('Keys for idempotent requests can only be used with the same parameters they were first used with.'), { status: 400, type: 'idempotency_error' });
      return this.transfers.find((t) => t.id === known.id)!;
    }
    this.created += 1;
    const obj: StripeTransferObj = {
      id: `tr_${this.created}`, amount: params.amount, destination: params.destination,
      transfer_group: params.transfer_group, metadata: { ...params.metadata },
      source_transaction: params.source_transaction ?? null,
    };
    this.transfers.push(obj);
    this.byKey.set(key, { id: obj.id, expiresAt: this.now + KEY_TTL_MS, params: p });
    return obj;
  }

  listByGroup(group: string): StripeTransferObj[] {
    return this.transfers.filter((t) => t.transfer_group === group);
  }

  /** route for mockStripe(): the real _shared/payouts.ts talks to this */
  route = async (call: StripeCall): Promise<{ ok: boolean; status?: number; data: unknown }> => {
    if (call.method === 'GET' && call.path.startsWith('/accounts/')) {
      return { ok: true, data: { id: call.path.slice('/accounts/'.length), capabilities: { transfers: this.accountCapability }, details_submitted: true, payouts_enabled: true, requirements: {} } };
    }
    if (call.method === 'GET' && call.path.startsWith('/payment_intents/')) {
      return { ok: true, data: { status: 'succeeded', livemode: this.piLivemode, latest_charge: { id: 'ch_1', amount: this.chargeAmount, amount_refunded: this.amountRefunded, refunded: this.chargeRefunded } } };
    }
    if (call.method === 'GET' && call.path.startsWith('/transfers?')) {
      if (this.listFault) {
        const f = this.listFault; this.listFault = null;
        if (f.kind === 'network') throw new Error('network error');
        if (f.kind === 'status') return { ok: false, status: f.status, data: { error: { message: f.message ?? `HTTP ${f.status}` } } };
      }
      const params = new URL('https://x' + call.path).searchParams;
      if (params.get('destination')) {
        // legacy-aware pre-flight (payouts.ts findTransferByLegacyMetadata)
        const dest = params.get('destination')!;
        return { ok: true, data: { object: 'list', has_more: false, data: this.transfers.filter((t) => t.destination === dest) } };
      }
      const group = params.get('transfer_group') ?? '';
      return { ok: true, data: { object: 'list', data: this.listByGroup(group) } };
    }
    if (call.method === 'POST' && call.path === '/transfers') {
      this.posts += 1;
      const body = call.body as Record<string, string>;
      const fault = this.nextPostFault; this.nextPostFault = null;
      if (fault?.kind === 'network') throw new Error('network timeout');
      if (fault?.kind === 'status') return { ok: false, status: fault.status, data: { error: { type: fault.type ?? 'invalid_request_error', message: fault.message ?? `stripe ${fault.status}` } } };
      const metadata: Record<string, string> = {};
      for (const [k, v] of Object.entries(body)) {
        const m = k.match(/^metadata\[(.+)\]$/); if (m) metadata[m[1]] = v;
      }
      let obj: StripeTransferObj;
      try {
        obj = this.createTransfer(call.idempotencyKey ?? `nokey_${this.posts}`, {
          amount: Number(body.amount), destination: body.destination, transfer_group: body.transfer_group ?? null,
          metadata, source_transaction: body.source_transaction ?? null,
        });
      } catch (e) {
        const err = e as Error & { status?: number; type?: string };
        return { ok: false, status: err.status ?? 400, data: { error: { type: err.type, message: err.message } } };
      }
      if (fault?.kind === 'lost_response') throw new Error('network timeout after create');
      return { ok: true, data: { id: obj.id, amount: obj.amount, destination: obj.destination, metadata: obj.metadata } };
    }
    return { ok: false, status: 404, data: { error: { message: `unrouted ${call.method} ${call.path}` } } };
  };
}

// ── DB ───────────────────────────────────────────────────────────────────────

export type TransferStatus = 'pending' | 'seller_sent' | 'buyer_confirmed' | 'auto_released' | 'disputed' | 'expired' | 'reversed';
export interface TransferRow {
  id: string; payment_id: string; listing_id: string; seller_id: string; buyer_id: string;
  status: TransferStatus; payout_released_at: string | null; stripe_transfer_id: string | null;
  disputed_at: string | null; dispute_resolution: string | null; buyer_confirmed_at: string | null;
  payout_review_status: string | null;
}
export interface PaymentRow {
  id: string; status: string; stripe_livemode: boolean | null; stripe_payment_intent_id: string;
  amount: number; seller_fee: number;
}
export type AttemptState = 'claimed' | 'requested' | 'unknown' | 'succeeded' | 'failed' | 'reversal_required';
export interface AttemptRow {
  id: string; transfer_id: string; payment_id: string; attempt_no: number; state: AttemptState;
  destination: string; amount_cents: number; idempotency_key: string; stripe_transfer_id: string | null;
  actor: string; error: unknown; lease_expires_at: number; requested_at: number | null;
}
export interface DecisionRow { transfer_id: string; decision: string; reason_codes: string[]; evidence: Record<string, unknown> }

const RANK: Record<AttemptState, number> = { claimed: 0, requested: 1, unknown: 2, failed: 3, succeeded: 4, reversal_required: 5 };

export class AttemptLedger {
  /** DB twin of the sandbox switch (GUC app.allow_test_mode_money) — default off, like production */
  allowTestModeMoney = false;
  now = 0;
  transfers = new Map<string, TransferRow>();
  payments = new Map<string, PaymentRow>();
  profiles = new Map<string, { stripe_connect_id: string | null }>();
  attempts: AttemptRow[] = [];
  decisions: DecisionRow[] = [];
  /** injected failures, keyed by rpc name; consumed once */
  failNext = new Map<string, string>();
  private seq = 0;

  advance(ms: number) { this.now += ms; }

  seedReleasable(opts: { transferId?: string; status?: TransferStatus; destination?: string } = {}) {
    const t = opts.transferId ?? 't1';
    this.payments.set('p1', { id: 'p1', status: 'succeeded', stripe_livemode: true, stripe_payment_intent_id: 'pi_1', amount: 10000, seller_fee: 1000 });
    this.profiles.set('seller-1', { stripe_connect_id: opts.destination ?? 'acct_A' });
    this.transfers.set(t, {
      id: t, payment_id: 'p1', listing_id: 'l1', seller_id: 'seller-1', buyer_id: 'buyer-1',
      status: opts.status ?? 'seller_sent', payout_released_at: null, stripe_transfer_id: null,
      disputed_at: null, dispute_resolution: null, buyer_confirmed_at: null, payout_review_status: null,
    });
    return this.transfers.get(t)!;
  }

  // migration 039 apply_auto_release(): seller_sent + unpaid + not manual_review
  applyAutoRelease(transferId: string): boolean {
    const row = this.transfers.get(transferId)!;
    if (row.status !== 'seller_sent' || row.payout_released_at !== null || row.payout_review_status === 'manual_review') return false;
    row.status = 'auto_released'; row.payout_review_status = null;
    return true;
  }
  // migration 002 confirm_transfer_received(): seller_sent → buyer_confirmed
  confirmTransferReceived(transferId: string): boolean {
    const row = this.transfers.get(transferId)!;
    if (row.status === 'buyer_confirmed' || row.status === 'auto_released') return true;
    if (row.status !== 'seller_sent') return false;
    row.status = 'buyer_confirmed'; row.buyer_confirmed_at = `t${this.now}`;
    return true;
  }
  // 056a freeze_transfer_for_dispute(): unpaid + not disputed
  freezeForDispute(transferId: string): boolean {
    const row = this.transfers.get(transferId)!;
    if (row.payout_released_at !== null || row.status === 'disputed') return false;
    row.status = 'disputed'; row.disputed_at = `t${this.now}`;
    return true;
  }
  // 065 resolve_transfer_dispute(seller_win) on an unpaid row
  resolveSellerWin(transferId: string) {
    const row = this.transfers.get(transferId)!;
    row.dispute_resolution = 'resolved_seller_paid';
    if (row.payout_released_at === null) { row.disputed_at = null; row.status = 'buyer_confirmed'; }
  }

  openAttempt(transferId: string): AttemptRow | undefined {
    return this.attempts.find((a) => a.transfer_id === transferId && ['claimed', 'requested', 'unknown'].includes(a.state));
  }

  // claim_payout_attempt()
  claim(transferId: string, actor: string) {
    const t = this.transfers.get(transferId);
    if (!t) throw new Error('TRANSFER_NOT_FOUND');
    const open = this.openAttempt(transferId);
    if (open) {
      if (open.lease_expires_at > this.now) throw new Error('PAYOUT_ATTEMPT_IN_PROGRESS');
      open.lease_expires_at = this.now + LEASE_MS;
      return this.claimRow(open, true);
    }
    if (t.payout_released_at !== null || t.stripe_transfer_id !== null ||
        this.attempts.some((a) => a.transfer_id === transferId && (a.state === 'succeeded' || a.state === 'reversal_required'))) {
      throw new Error('ALREADY_RELEASED');
    }
    if (t.disputed_at !== null && t.dispute_resolution !== 'resolved_seller_paid') throw new Error('DISPUTED');
    if (!['buyer_confirmed', 'auto_released'].includes(t.status)) throw new Error('TRANSFER_NOT_RELEASABLE');
    const p = this.payments.get(t.payment_id);
    if (!p || p.status !== 'succeeded') throw new Error('PAYMENT_NOT_SUCCEEDED');
    if (p.stripe_livemode !== true && !(p.stripe_livemode === false && this.allowTestModeMoney)) throw new Error('PAYMENT_NOT_LIVE');
    const dest = this.profiles.get(t.seller_id)?.stripe_connect_id;
    if (!dest) throw new Error('SELLER_NOT_ONBOARDED');
    const amount = p.amount - p.seller_fee;
    if (amount <= 0) throw new Error('PAYOUT_AMOUNT_INVALID');
    const no = this.attempts.filter((a) => a.transfer_id === transferId).reduce((m, a) => Math.max(m, a.attempt_no), 0) + 1;
    const row: AttemptRow = {
      id: `att_${++this.seq}`, transfer_id: transferId, payment_id: p.id, attempt_no: no, state: 'claimed',
      destination: dest, amount_cents: amount, idempotency_key: `payout_${transferId}_a${no}`,
      stripe_transfer_id: null, actor, error: null, lease_expires_at: this.now + LEASE_MS, requested_at: null,
    };
    this.attempts.push(row);
    return this.claimRow(row, false);
  }
  private claimRow(a: AttemptRow, needsReconcile: boolean) {
    const p = this.payments.get(a.payment_id)!;
    return { attempt_id: a.id, attempt_no: a.attempt_no, idempotency_key: a.idempotency_key, destination: a.destination,
             amount_cents: a.amount_cents, source_charge_id: null, payment_intent_id: p.stripe_payment_intent_id, needs_reconcile: needsReconcile };
  }

  private setState(a: AttemptRow, s: AttemptState) {
    if (s !== a.state && RANK[s] <= RANK[a.state]) throw new Error(`payout_attempts.state may only advance: ${a.state} -> ${s}`);
    a.state = s;
  }

  // mark_payout_requested()
  markRequested(attemptId: string): boolean {
    const a = this.attempts.find((x) => x.id === attemptId);
    if (!a || a.state !== 'claimed') return false;
    this.setState(a, 'requested'); a.requested_at = this.now;
    return true;
  }

  // record_payout_attempt_result()
  record(attemptId: string, stripeTransferId: string | null, outcome: 'succeeded' | 'failed_not_created' | 'unknown', error: unknown = null) {
    const a = this.attempts.find((x) => x.id === attemptId);
    if (!a) throw new Error('ATTEMPT_NOT_FOUND');
    const t = this.transfers.get(a.transfer_id)!;
    if (outcome === 'unknown') {
      if (['claimed', 'requested', 'unknown'].includes(a.state)) { this.setState(a, 'unknown'); a.error = error ?? a.error; a.lease_expires_at = this.now + LEASE_MS; }
      return { attempt_id: a.id, state: a.state, stripe_transfer_id: a.stripe_transfer_id, recorded: false };
    }
    if (outcome === 'failed_not_created') {
      if (['claimed', 'requested', 'unknown'].includes(a.state)) { this.setState(a, 'failed'); a.error = error ?? a.error; }
      return { attempt_id: a.id, state: a.state, stripe_transfer_id: a.stripe_transfer_id, recorded: false };
    }
    if (!stripeTransferId) throw new Error('STRIPE_TRANSFER_ID_REQUIRED');
    if (a.stripe_transfer_id && a.stripe_transfer_id !== stripeTransferId) throw new Error('ATTEMPT_TRANSFER_MISMATCH');
    if (a.state === 'succeeded' || a.state === 'reversal_required') {
      return { attempt_id: a.id, state: a.state, stripe_transfer_id: a.stripe_transfer_id, recorded: false };
    }
    // ALWAYS write the transfer row (money moved)
    let recorded = false;
    if (t.stripe_transfer_id === null || t.stripe_transfer_id === stripeTransferId) {
      t.stripe_transfer_id = stripeTransferId; t.payout_released_at = t.payout_released_at ?? `t${this.now}`; recorded = true;
    }
    const reasons: string[] = [];
    let state: AttemptState = 'succeeded';
    if (t.disputed_at !== null && t.dispute_resolution !== 'resolved_seller_paid') { state = 'reversal_required'; reasons.push('PAID_DURING_DISPUTE'); }
    if (!recorded) { state = 'reversal_required'; reasons.push('DUPLICATE_TRANSFER'); }
    this.setState(a, state); a.stripe_transfer_id = stripeTransferId;
    if (state === 'reversal_required' && !this.decisions.some((d) => d.transfer_id === t.id && d.evidence.attempt_id === a.id)) {
      this.decisions.push({ transfer_id: t.id, decision: 'manual_review', reason_codes: reasons, evidence: { attempt_id: a.id, stripe_transfer_id: stripeTransferId } });
    }
    return { attempt_id: a.id, state: a.state, stripe_transfer_id: a.stripe_transfer_id, recorded, transfer_id: t.id };
  }

  // reconcile_payout_attempt()
  reconcile(attemptId: string, foundTransferId: string | null) {
    return foundTransferId
      ? this.record(attemptId, foundTransferId, 'succeeded', { reconciled: true })
      : this.record(attemptId, null, 'failed_not_created', { reconciled: true, reason: 'not_found_on_stripe' });
  }

  /** supabase-js `rpc()` adapter (PostgREST shapes: RETURNS TABLE → array, jsonb → object, boolean → boolean) */
  rpc = async (name: string, params: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }> => {
    const injected = this.failNext.get(name);
    if (injected) { this.failNext.delete(name); return { data: null, error: { message: injected } }; }
    try {
      switch (name) {
        case 'claim_payout_attempt':         return { data: [this.claim(params.p_transfer_id as string, params.p_actor as string)], error: null };
        case 'mark_payout_requested':        return { data: this.markRequested(params.p_attempt_id as string), error: null };
        case 'record_payout_attempt_result': return { data: this.record(params.p_attempt_id as string, (params.p_stripe_transfer_id as string | null) ?? null, params.p_outcome as 'succeeded', params.p_error), error: null };
        case 'reconcile_payout_attempt':     return { data: this.reconcile(params.p_attempt_id as string, (params.p_found_transfer_id as string | null) ?? null), error: null };
        default: return { data: null, error: { message: `AttemptLedger: unhandled rpc ${name}` } };
      }
    } catch (e) {
      return { data: null, error: { message: (e as Error).message } };
    }
  };
}
