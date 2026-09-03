/**
 * payout-execute/executor.ts — pure, dependency-free payout execution logic.
 *
 * WHY THIS FILE EXISTS SEPARATELY
 *   Deno edge modules import over https, which vitest cannot load. Every
 *   decision that decides whether real money moves lives here, import-free, so
 *   `tests/payout-executor.test.ts` can exercise it directly. `index.ts` is the
 *   I/O shell: HTTP, auth, the Supabase client, Stripe, Sentry. Same split as
 *   `refund-execute/executor.ts` vs its `index.ts`, and as
 *   `_shared/payout-logic.ts` vs `_shared/payouts.ts`.
 *
 * WHAT THIS EXECUTOR IS
 *   The caller of `kernel.mark_payout_transfer_state` (085:1668) for
 *   `cause='settlement'` payouts — the ONE seam that turns a closed venue
 *   settlement into money in the venue's bank. Ruling H3 fixes its shape:
 *   ONE `kernel.payout` row → ONE Stripe Transfer → ONE `stripe_transfer_ref`,
 *   with NO `source_transaction` (the settlement rail draws the platform's
 *   available balance; see H3 §3).
 *
 * ═════════════════════════════════════════════════════════════════════════════
 * THE ONE RULE THAT OUTRANKS EVERYTHING ELSE HERE: NEVER WRITE 'failed'.
 * ═════════════════════════════════════════════════════════════════════════════
 *   `kernel.mark_payout_transfer_state` permits ONLY submitted→paid|failed and
 *   paid→reversed. There is NO edge out of 'failed'. Verified by execution
 *   against the shipped function on a rehearsal database:
 *     submitted→failed   ⇒ ok
 *     failed→paid        ⇒ 'precondition_failed: payout_state_backwards (failed → paid)'
 *     failed→reversed    ⇒ 'precondition_failed: payout_state_backwards (failed → reversed)'
 *     failed→submitted   ⇒ 'invalid_input: ... takes paid|failed|reversed'
 *   `kernel.request_org_payout` only ever selects `status in ('pending','submitted')`,
 *   and `kernel.close_settlement` mints `on conflict (idempotency_key) do nothing`
 *   on `'settlement:'||settlement_id` and is forward-only, so no re-mint is
 *   possible. A `failed` settlement payout therefore PERMANENTLY DESTROYS the
 *   venue's obligation: the money is owed, unpayable and unrecoverable, with no
 *   operator exit. This is not a style preference — it is the difference
 *   between a recoverable hang and destroyed money.
 *
 *   So: every ordinary non-success leaves the row `submitted`,
 *   `stripe_transfer_ref` NULL, and records an audit row
 *   (`kernel.record_payout_execution_note`). The type of `planPayoutStateSync`
 *   admits exactly one target — `'paid'` — so 'failed' is not reachable from
 *   this module by any input. `PAYOUT_STATE_SYNC_TARGETS` exists so a test can
 *   assert that structurally rather than by inspection.
 *
 *   THE ONE EXCEPTION, AND IT IS NOT A FAILURE: when the DATABASE reports
 *   `destination_changed` / `org_not_active` / `connect_transfers_inactive`,
 *   the executor calls `kernel.hold_payout_destination_changed`, which returns
 *   the payout to `pending` + `held`. That is a DE-AUTHORIZATION — strictly
 *   less capable than `submitted`, reversible by `kernel.release_payout` — not
 *   a terminal state, and it still never writes 'failed'.
 *
 * THE INVARIANT
 *   PAYOUT-ROW-DRIVEN, and the decision is the DATABASE'S.
 *   `kernel.get_payout_execution_context(payout_id)` returns
 *   `execution_eligible` and a `refusal_code`; this module does not re-derive
 *   eligibility, does not recompute money, and cannot choose a destination, an
 *   amount or an organization. There is no request field for any of them and
 *   `assertNoClientMoneyReference` refuses a request that smuggles one in.
 *
 * ORDER OF OPERATIONS (never reordered — every step is a lesson)
 *   1. Claim            `kernel.claim_payouts_for_execution` (lease + mode)
 *   2. Context          `kernel.get_payout_execution_context` (the verdict)
 *   3. Account preflight    GET /v1/accounts/{dest}     — incident 2
 *   4. Balance preflight    GET /v1/balance             — H3 §3.5 / incident 3
 *   5. Reconcile (mode='reconcile' only)
 *                           GET /v1/transfers?transfer_group=payout_<id>
 *   6. Create               POST /v1/transfers          — the key is spent HERE
 *   7. Record           `kernel.mark_payout_transfer_state(..., 'paid', tr.id, ...)`
 *   Steps 1-5 are side-effect-free at Stripe, so an abort before 6 costs
 *   nothing and spends no idempotency key. That ordering is enforced by the
 *   TYPES: `planPayoutTransfer` cannot produce an idempotency key — only
 *   `authorizeTransfer`, which requires BOTH preflight results, can.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

export type PayoutStatus = 'pending' | 'submitted' | 'paid' | 'failed' | 'reversed';
export type PayoutHoldState = 'none' | 'held' | 'probation_hold';
export type PayoutExecutionMode = 'create' | 'reconcile';

/**
 * Everything the executor is allowed to know about one payout, assembled
 * SERVER-SIDE by `kernel.get_payout_execution_context`. Every field is
 * DB-derived. Nothing here ever comes from the request body.
 */
export interface PayoutExecutionContext {
  payout_id: string;
  cause: string;
  /** kernel.payout.cause_ref — the venue.settlement this pays. */
  settlement_id: string;
  payee_kind: string;
  payee_org_id: string | null;
  /** The obligation, from the ledger. NEVER recomputed here. */
  amount_minor: number;
  currency: string;
  status: PayoutStatus;
  hold_state: PayoutHoldState;
  hold_reason_code: string | null;
  stripe_transfer_ref: string | null;
  /** H3 §3: NULL on the settlement rail, always. Funded from platform balance. */
  source_transaction_ref: string | null;
  /** The PINNED payee (kernel.payout.destination_ref). This is what gets sent. */
  destination: string | null;
  destination_ref: string | null;
  /** The organization's CURRENT ref, for the fail-closed cross-check. */
  org_connect_ref_current: string | null;
  org_status: string | null;
  connect_transfers_active: boolean;
  settlement_org_id: string | null;
  settlement_status: string | null;
  settlement_net_minor: number | null;
  /** `payout_<payout_id>` — the only durable handle back to a lost transfer. */
  transfer_group: string;
  /** THE DATABASE'S VERDICT. Not re-derived here. */
  execution_eligible: boolean;
  refusal_code: string | null;
}

/** One row of `kernel.claim_payouts_for_execution`. */
export interface PayoutClaim {
  payout_id: string;
  created_at: string;
  status: PayoutStatus;
  execution_mode: PayoutExecutionMode;
  attempt: number;
  /** DB-derived: `payout.execute:<payout_id>`. Never minted by the worker. */
  command_key: string;
}

/** Stripe Account probe result, captured as audit evidence. */
export interface DestinationProbe {
  ok: boolean;
  id?: string | null;
  deleted?: boolean | null;
  transfers_capability?: string | null;
  payouts_enabled?: boolean | null;
  charges_enabled?: boolean | null;
  details_submitted?: boolean | null;
  disabled_reason?: string | null;
  error_code?: string | null;
  error_message?: string | null;
}

/** Stripe Balance probe result. */
export interface BalanceProbe {
  ok: boolean;
  /** available[] entries, minor units, by lower-cased currency. */
  available: Array<{ currency: string; amount: number }>;
  error_code?: string | null;
  error_message?: string | null;
}

export type PayoutRefusalCode =
  | 'malformed_payout_id'
  | 'context_missing'
  | 'client_supplied_money_reference'
  // mirrored DB verdicts (the DB is authoritative; these are its codes)
  | 'db_refused'
  // executor-side structural checks over the context the DB returned
  | 'context_binding_inconsistent'
  | 'amount_not_positive'
  | 'currency_unsupported'
  | 'destination_malformed'
  // preflight refusals — NO idempotency key is spent for any of these
  | 'destination_unreadable'
  | 'destination_deleted'
  | 'destination_transfers_inactive'
  | 'destination_disabled'
  | 'destination_identity_mismatch'
  | 'balance_unreadable'
  | 'balance_insufficient'
  | 'reconcile_ambiguous'
  | 'reconcile_amount_mismatch';

/** The DB refusals that mean "the payee is no longer authorized", not "wait". */
export const DEAUTHORIZING_REFUSALS = [
  'destination_changed',
  'org_not_active',
  'connect_transfers_inactive',
  'no_payout_destination',
] as const;

export type PayoutPlan =
  | {
      /**
       * Everything the DB and the context allow. Carries NO idempotency key on
       * purpose: the key may only be built once both preflights have passed.
       */
      kind: 'preflight';
      payout_id: string;
      destination: string;
      amount_minor: number;
      currency: string;
      transfer_group: string;
      settlement_id: string;
      org_id: string;
      execution_mode: PayoutExecutionMode;
    }
  | { kind: 'noop_replay'; reason: 'already_paid' | 'transfer_already_recorded'; stripe_transfer_ref: string | null }
  | {
      kind: 'deauthorize';
      /** The DB's own code. The de-authorization verb re-derives the fault itself. */
      code: (typeof DEAUTHORIZING_REFUSALS)[number];
      detail: string;
    }
  | { kind: 'refuse'; code: PayoutRefusalCode; detail: string; retryable: boolean };

export type TransferAuthorization =
  | {
      kind: 'stripe_create';
      idempotency_key: string;
      /** Exactly the form body for POST /v1/transfers. */
      body: Record<string, string>;
      amount_minor: number;
      destination: string;
    }
  | { kind: 'adopt'; stripe_transfer_ref: string; detail: string }
  /**
   * A Transfer for this payout exists and its money has come back — wholly or
   * in part. Not a payment, not an error. See `TransferReversal`.
   */
  | { kind: 'reversed'; reversal: TransferReversal; detail: string }
  | { kind: 'refuse'; code: PayoutRefusalCode; detail: string; retryable: boolean };

/**
 * WHAT A REVERSED TRANSFER IS, AND WHY THE BOOLEAN WAS NEVER ENOUGH.
 *
 * Stripe's `Transfer.reversed` is FULL reversal only — the API reference is
 * explicit that "if the transfer is only partially reversed, this attribute
 * will still be false". The money lives in `amount_reversed`, and `amount` is
 * NOT reduced by a reversal. So a partially reversed transfer read as clean:
 * `planPayoutStateSync` synced it to 'paid' at FULL FACE VALUE, which fires
 * `venue.on_payout_settled` and can advance the settlement header to 'paid' —
 * the ledger recording the venue as fully paid for money that had already been
 * pulled back, with nothing downstream ever re-reading the transfer.
 * `planReconcile` had the same blind spot from the other side: it compares
 * `amount` (unchanged by a reversal) and would ADOPT a reversed transfer as a
 * successful payment.
 *
 * Both now read `amount_reversed`. `reversed === true` is still honoured as a
 * belt for the full case, for a payload that omits the amount.
 *
 * WHAT THE EXECUTOR DOES WITH IT — and it is neither 'paid' nor 'reversed':
 *   · 'paid' is false. It asserts the venue received `amount_minor`, and it is
 *     not an inert label — `mark_payout_transfer_state` fires
 *     `venue.on_payout_settled` on 'paid'.
 *   · 'reversed' is only reachable THROUGH 'paid' (the state machine's one
 *     terminal-to-terminal edge), so taking it would write that lie first, and
 *     it additionally asserts the WHOLE transfer came back.
 *   · `kernel.payout` has ONE amount column, the obligation. There is nowhere
 *     to record "we moved 5000 and 1200 came back".
 * So the executor writes NO status transition and calls
 * `kernel.hold_payout_transfer_reversed`, which de-authorizes the payout back
 * to pending + held with the exact amounts in the audit and leaves the ruling
 * to a human. 'failed' is still never written.
 *
 * FULL REVERSAL IS BENIGN. Stripe may reverse a transfer on its own initiative
 * — for platforms created on or after 2025-01-01, when an async payment behind
 * the funds fails. "Already fully reversed" is an expected observation, not a
 * conflict and not a page.
 */
export interface TransferReversal {
  stripe_transfer_ref: string;
  /** The Transfer's own `amount`, as reported. Evidence for the audit only. */
  transfer_amount_minor: number | null;
  amount_reversed_minor: number;
  /**
   * Advisory. The DB verb re-derives full-versus-partial against the payout's
   * own `amount_minor`, so nothing the executor reports can turn a full
   * reversal into a partial one or the reverse.
   */
  fully_reversed: boolean;
}

/**
 * Read the reversal facts off a Stripe Transfer object.
 *
 * `unreadable` is a distinct outcome, never a silent zero: a payload whose
 * `amount_reversed` is present but not a finite non-negative number is one we
 * do not understand, and assuming "nothing came back" is exactly the failure
 * this function exists to remove. An ABSENT `amount_reversed` with `reversed`
 * absent or false is a clean transfer — the ordinary success shape.
 */
export function classifyTransferReversal(
  transfer: { id?: unknown; amount?: unknown; reversed?: unknown; amount_reversed?: unknown },
  obligationMinor: number,
): { state: 'none' } | { state: 'unreadable'; detail: string } | { state: 'reversed'; reversal: TransferReversal } {
  const id = typeof transfer?.id === 'string' ? transfer.id : '';
  const rawReversed = transfer?.amount_reversed;
  let reversedMinor = 0;
  if (rawReversed != null) {
    const n = Number(rawReversed);
    if (!Number.isFinite(n) || n < 0) {
      return { state: 'unreadable', detail: `amount_reversed=${String(rawReversed)} on ${id || '<no id>'}` };
    }
    reversedMinor = n;
  }
  const amountRaw = Number(transfer?.amount);
  const transferAmount = Number.isFinite(amountRaw) ? amountRaw : null;

  if (reversedMinor === 0 && transfer?.reversed !== true) return { state: 'none' };
  // `reversed === true` with no amount: fully reversed by definition. Fall back
  // to the transfer's own amount, then to the obligation, so the DB verb always
  // receives a positive number to record.
  if (reversedMinor === 0) reversedMinor = transferAmount ?? obligationMinor;

  return {
    state: 'reversed',
    reversal: {
      stripe_transfer_ref: id,
      transfer_amount_minor: transferAmount,
      amount_reversed_minor: reversedMinor,
      fully_reversed: transfer?.reversed === true || reversedMinor >= obligationMinor,
    },
  };
}

const NIL_UUID = '00000000-0000-0000-0000-000000000000';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Stripe connected-account ids. */
export const ACCT_RE = /^acct_[A-Za-z0-9]+$/;
/** Stripe Transfer ids. */
const TR_RE = /^tr_[A-Za-z0-9]+$/;

export function isUuid(v: unknown): v is string {
  return typeof v === 'string' && UUID_RE.test(v) && v !== NIL_UUID;
}

// ─────────────────────────────────────────────────────────────────────────────
// Stripe idempotency key
// ─────────────────────────────────────────────────────────────────────────────

/**
 * `payout_<payout_id>_<destination>_v1` — the key H3 §5 froze.
 *
 * • `payout_id` — minted by Postgres, immutable, and `amount_minor` is never
 *   mutated after the mint, so the request body is a function of the payout row.
 *   Any worker can reconstruct the key from audit data alone, with no shared
 *   state, so two attempts on one payout can never mint two Stripe Transfers
 *   inside Stripe's 24h key window.
 * • `destination` — REQUIRED in the key. `kernel.set_org_payout_destination`
 *   can re-point an organization, and reusing one key with different parameters
 *   is an `idempotency_error`, not a replay. Same reasoning and same shape as
 *   `buildPayoutIdempotencyKey` on the resale rail (`payout-logic.ts:23-25`).
 * • `_v1` (not `_src`) — deliberately DISJOINT from the resale rail's key
 *   space, and it records in the key itself which funding generation created
 *   any given Stripe Transfer. The resale rail funds with `source_transaction`;
 *   this rail does not (H3 §3). Two different request shapes must never be able
 *   to collide on one key.
 */
export function buildPayoutTransferIdempotencyKey(payoutId: string, destination: string): string {
  if (!isUuid(payoutId)) {
    throw new Error(`payout-execute: refusing to build an idempotency key from a non-uuid payout id: ${String(payoutId)}`);
  }
  if (!ACCT_RE.test(destination)) {
    throw new Error(`payout-execute: refusing to build an idempotency key from a malformed destination: ${String(destination)}`);
  }
  return `payout_${payoutId}_${destination}_v1`;
}

/** `payout_<payout_id>` — H3 §6: the recovery handle for a lost response. */
export function buildTransferGroup(payoutId: string): string {
  if (!isUuid(payoutId)) throw new Error(`payout-execute: non-uuid payout id: ${String(payoutId)}`);
  return `payout_${payoutId}`;
}

// ─────────────────────────────────────────────────────────────────────────────
// The request-side guard: the caller may NEVER name the money or the payee
// ─────────────────────────────────────────────────────────────────────────────

const FORBIDDEN_REQUEST_KEYS = [
  'amount',
  'amount_minor',
  'destination',
  'destination_ref',
  'connect_account',
  'stripe_connect_account_ref',
  'stripe_account_id',
  'org_id',
  'payee_org_id',
  'settlement_id',
  'source_transaction',
  'stripe_transfer_ref',
  'transfer_id',
  'currency',
  'idempotency_key',
] as const;

/**
 * Defence in depth for the properties that matter most. The executor resolves
 * the amount, the destination and the organization from the payout row inside
 * the database; a request that also tries to name one is a confused-deputy
 * attempt, so it is REFUSED rather than ignored — ignoring it would let a
 * future refactor start reading it.
 */
export function assertNoClientMoneyReference(
  body: Record<string, unknown> | null | undefined,
): { ok: true } | { ok: false; code: 'client_supplied_money_reference'; detail: string } {
  if (!body || typeof body !== 'object') return { ok: true };
  for (const k of FORBIDDEN_REQUEST_KEYS) {
    if (Object.prototype.hasOwnProperty.call(body, k) && body[k] != null) {
      return {
        ok: false,
        code: 'client_supplied_money_reference',
        detail: `the caller may not name the money or the payee: '${k}' is resolved from kernel.payout inside the database, never from the request`,
      };
    }
  }
  return { ok: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// The plan: may this payout reach the preflights at all?
// ─────────────────────────────────────────────────────────────────────────────

const refuse = (code: PayoutRefusalCode, detail: string, retryable = false): PayoutPlan =>
  ({ kind: 'refuse', code, detail, retryable });

/**
 * Adopt the database's verdict and add only the structural checks that protect
 * against a MALFORMED context (a bad join, a widened RPC, a hand-written row) —
 * never a second opinion about eligibility.
 *
 * `expected` is the caller's ASSERTION about what it believes it is paying. It
 * is never used to select anything; it exists so an operator who pastes the
 * wrong payout id gets a refusal instead of someone else's money.
 */
export function planPayoutTransfer(
  ctx: PayoutExecutionContext,
  opts: { execution_mode?: PayoutExecutionMode; expected?: { org_id?: string | null; settlement_id?: string | null } } = {},
): PayoutPlan {
  const expected = opts.expected ?? {};

  if (!isUuid(ctx?.payout_id)) return refuse('malformed_payout_id', `payout_id=${String(ctx?.payout_id)}`);

  // ── application-level idempotency, ahead of everything ────────────────────
  // A row that already carries a ref is finished with Stripe whatever else is
  // true; this is the DB-side idempotency stop and it OUTRANKS Stripe's 24h key
  // window (H3 §6).
  if (ctx.stripe_transfer_ref != null) {
    return { kind: 'noop_replay', reason: 'transfer_already_recorded', stripe_transfer_ref: ctx.stripe_transfer_ref };
  }
  if (ctx.status === 'paid') {
    return { kind: 'noop_replay', reason: 'already_paid', stripe_transfer_ref: ctx.stripe_transfer_ref };
  }

  // ── the caller's assertion, used only to refuse a mismatch ────────────────
  if (expected.org_id != null && expected.org_id !== ctx.payee_org_id) {
    return refuse(
      'context_binding_inconsistent',
      `caller asserted org ${expected.org_id}; payout ${ctx.payout_id} pays org ${String(ctx.payee_org_id)}`,
    );
  }
  if (expected.settlement_id != null && expected.settlement_id !== ctx.settlement_id) {
    return refuse(
      'context_binding_inconsistent',
      `caller asserted settlement ${expected.settlement_id}; payout ${ctx.payout_id} settles ${String(ctx.settlement_id)}`,
    );
  }

  // ── THE DATABASE'S VERDICT ────────────────────────────────────────────────
  // Not re-derived, not overridden, not softened. Two shapes of refusal:
  // de-authorizing (the payee is no longer the approved one → 10o) and
  // everything else (wait, and leave the row submitted).
  if (!ctx.execution_eligible) {
    const code = ctx.refusal_code ?? 'unknown';
    if ((DEAUTHORIZING_REFUSALS as readonly string[]).includes(code)) {
      return {
        kind: 'deauthorize',
        code: code as (typeof DEAUTHORIZING_REFUSALS)[number],
        detail: `pinned=${String(ctx.destination_ref)} current=${String(ctx.org_connect_ref_current)} org_status=${String(ctx.org_status)} transfers_active=${String(ctx.connect_transfers_active)}`,
      };
    }
    // Everything else is a WAIT, not a failure. `maturity_not_elapsed`,
    // `refund_in_flight` and `dispute_open` resolve on their own; `payout_held`
    // and `refund_exposure_stale` need a human. Neither is retryable-forever
    // noise, because the executor records a note either way.
    return refuse('db_refused', code, isTransientRefusal(code));
  }

  // ── structural checks on the context itself ───────────────────────────────
  // These cannot disagree with the DB — they catch a context that is malformed,
  // which is a different failure from one that is ineligible.
  if (ctx.cause !== 'settlement' || ctx.payee_kind !== 'organization' || !isUuid(ctx.payee_org_id ?? '')) {
    return refuse(
      'context_binding_inconsistent',
      `cause=${ctx.cause} payee_kind=${ctx.payee_kind} payee_org_id=${String(ctx.payee_org_id)}`,
    );
  }
  if (!isUuid(ctx.settlement_id)) {
    return refuse('context_binding_inconsistent', `settlement_id=${String(ctx.settlement_id)}`);
  }
  if (ctx.settlement_org_id !== ctx.payee_org_id) {
    return refuse(
      'context_binding_inconsistent',
      `settlement ${ctx.settlement_id} belongs to org ${String(ctx.settlement_org_id)}, payout pays ${String(ctx.payee_org_id)}`,
    );
  }
  if (!Number.isInteger(ctx.amount_minor) || ctx.amount_minor <= 0) {
    return refuse('amount_not_positive', `amount_minor=${String(ctx.amount_minor)}`);
  }
  // THE ANTI-TAMPER EQUALITY. The obligation is the closed header's net; the
  // payout must equal it. The DB asserts this too (`amount_ledger_mismatch`) —
  // asserting it again here costs nothing and means a widened or replaced RPC
  // cannot quietly let a different number through.
  if (ctx.settlement_net_minor !== ctx.amount_minor) {
    return refuse(
      'context_binding_inconsistent',
      `payout ${ctx.amount_minor} <> settlement net ${String(ctx.settlement_net_minor)}`,
    );
  }
  if ((ctx.currency ?? '').toUpperCase() !== 'USD') {
    return refuse('currency_unsupported', `currency=${String(ctx.currency)}`);
  }
  const destination = ctx.destination_ref ?? ctx.destination;
  if (typeof destination !== 'string' || !ACCT_RE.test(destination)) {
    return refuse('destination_malformed', `destination=${String(destination)}`);
  }
  // Belt and braces on the pin: the value sent is the PINNED one, and it must
  // still equal the organization's current ref. The DB refuses first
  // ('destination_changed'); this makes the property local and testable.
  if (ctx.org_connect_ref_current != null && ctx.org_connect_ref_current !== destination) {
    return {
      kind: 'deauthorize',
      code: 'destination_changed',
      detail: `pinned=${destination} current=${ctx.org_connect_ref_current}`,
    };
  }

  return {
    kind: 'preflight',
    payout_id: ctx.payout_id,
    destination,
    amount_minor: ctx.amount_minor,
    currency: (ctx.currency ?? 'USD').toLowerCase(),
    transfer_group: ctx.transfer_group || buildTransferGroup(ctx.payout_id),
    settlement_id: ctx.settlement_id,
    org_id: ctx.payee_org_id as string,
    execution_mode: opts.execution_mode ?? 'create',
  };
}

/**
 * Which DB refusals clear on their own (so a later tick should simply try
 * again) and which need a human. Both leave the row `submitted`; the difference
 * is only whether the worker should keep the row in its rotation.
 */
export function isTransientRefusal(code: string): boolean {
  return [
    'maturity_not_elapsed',
    'refund_in_flight',
    'dispute_open',
    'destination_cooldown',
    'settlement_not_closed',
  ].includes(code);
}

// ─────────────────────────────────────────────────────────────────────────────
// Preflights. NOTHING below spends an idempotency key.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Incident 2 of `_shared/payouts.ts:10-13`: a not-yet-onboarded destination
 * burned an idempotency key for 24h. Keys are only ever spent on requests that
 * CAN succeed, so the account is probed first — and the probe additionally
 * asserts that Stripe's own `id` is the account we intended, which is the last
 * defence against a re-pointed or substituted destination.
 */
export function evaluateDestination(
  probe: DestinationProbe,
  expectedDestination: string,
): { ok: true } | { ok: false; code: PayoutRefusalCode; detail: string; retryable: boolean } {
  if (!probe.ok) {
    // A missing account is a disconnected/deleted one; anything else is
    // transport and may be retried. Neither spends a key.
    const missing = probe.error_code === 'resource_missing' || probe.error_code === 'account_invalid';
    return {
      ok: false,
      code: missing ? 'destination_deleted' : 'destination_unreadable',
      detail: probe.error_message ?? probe.error_code ?? 'account probe failed',
      retryable: !missing,
    };
  }
  if (probe.deleted === true) {
    return { ok: false, code: 'destination_deleted', detail: `${expectedDestination} is deleted`, retryable: false };
  }
  if (probe.id != null && probe.id !== expectedDestination) {
    return {
      ok: false,
      code: 'destination_identity_mismatch',
      detail: `Stripe answered for ${probe.id}, we asked for ${expectedDestination}`,
      retryable: false,
    };
  }
  // The precedent: `_shared/payouts.ts:96` requires exactly this.
  if (probe.transfers_capability !== 'active') {
    return {
      ok: false,
      code: 'destination_transfers_inactive',
      detail: `capabilities.transfers=${String(probe.transfers_capability)}`,
      retryable: true,
    };
  }
  if (probe.disabled_reason != null && probe.disabled_reason !== '') {
    return {
      ok: false,
      code: 'destination_disabled',
      detail: `requirements.disabled_reason=${probe.disabled_reason}`,
      retryable: true,
    };
  }
  return { ok: true };
}

/**
 * H3 §3.5 — MANDATORY, and it runs BEFORE the key is spent.
 *
 * The settlement rail sets no `source_transaction`, so the transfer draws the
 * platform's AVAILABLE balance and Stripe "doesn't automatically retry failed
 * transfer requests". A shortfall must therefore never become a `/transfers`
 * call: that would burn the key for 24h on a request that cannot succeed, which
 * is incident 2 all over again on a different endpoint.
 */
export function evaluateBalance(
  probe: BalanceProbe,
  need: { amount_minor: number; currency: string },
): { ok: true; available_minor: number } | { ok: false; code: PayoutRefusalCode; detail: string; retryable: boolean } {
  if (!probe.ok) {
    return {
      ok: false,
      code: 'balance_unreadable',
      detail: probe.error_message ?? probe.error_code ?? 'balance probe failed',
      retryable: true,
    };
  }
  const cur = (need.currency ?? 'usd').toLowerCase();
  const entry = (probe.available ?? []).find((a) => (a.currency ?? '').toLowerCase() === cur);
  const available = Number.isFinite(entry?.amount) ? (entry as { amount: number }).amount : 0;
  if (available < need.amount_minor) {
    return {
      ok: false,
      code: 'balance_insufficient',
      // Operational, not terminal — the same class the resale rail already
      // treats as "retry later, do not page" (`payout-logic.ts`).
      detail: `available ${available} < required ${need.amount_minor} (${cur})`,
      retryable: true,
    };
  }
  return { ok: true, available_minor: available };
}

/**
 * H3 §6 — the >24h recovery path. Once Stripe has forgotten the idempotency
 * key, a bare POST would create a SECOND transfer of the same money. In
 * `reconcile` mode the executor must therefore read the transfer group FIRST
 * and adopt whatever it finds.
 *
 * `transfer_group` is set on every create precisely so this read exists; it is
 * the only durable handle back to a transfer whose response we lost.
 */
export function planReconcile(
  transfers: Array<{ id?: unknown; amount?: unknown; currency?: unknown; destination?: unknown; reversed?: unknown; amount_reversed?: unknown }>,
  plan: { amount_minor: number; currency: string; destination: string },
):
  | { kind: 'adopt'; stripe_transfer_ref: string }
  | { kind: 'create_allowed' }
  | { kind: 'reversed'; reversal: TransferReversal; detail: string }
  | { kind: 'refuse'; code: PayoutRefusalCode; detail: string } {
  const rows = Array.isArray(transfers) ? transfers : [];
  const matches = rows.filter((t) => typeof t.id === 'string' && TR_RE.test(t.id as string));
  if (matches.length === 0) return { kind: 'create_allowed' };
  if (matches.length > 1) {
    // Two transfers already share this payout's group. That is money we cannot
    // reconcile from here, and creating a third is the one thing that must not
    // happen. Refuse and escalate; the row stays `submitted`.
    return {
      kind: 'refuse',
      code: 'reconcile_ambiguous',
      detail: `${matches.length} transfers already carry transfer_group for this payout: ${matches.map((m) => String(m.id)).join(',')}`,
    };
  }
  const t = matches[0];
  const amount = Number(t.amount);
  const currency = String(t.currency ?? '').toLowerCase();
  const destination = typeof t.destination === 'string' ? t.destination : null;
  if (amount !== plan.amount_minor || currency !== plan.currency.toLowerCase()) {
    return {
      kind: 'refuse',
      code: 'reconcile_amount_mismatch',
      detail: `existing transfer ${String(t.id)} is ${amount} ${currency}; the obligation is ${plan.amount_minor} ${plan.currency}`,
    };
  }
  if (destination != null && destination !== plan.destination) {
    return {
      kind: 'refuse',
      code: 'reconcile_amount_mismatch',
      detail: `existing transfer ${String(t.id)} paid ${destination}, the pinned payee is ${plan.destination}`,
    };
  }
  // A reversal is invisible to every check above: `amount` is NOT reduced when
  // money comes back, and `reversed` stays false for a partial. Adopting such a
  // transfer would sync 'paid' at full face value for money that has already
  // been pulled back — the same defect this module carried at the sync site.
  // Creating a SECOND transfer would be worse still, so this is neither an
  // adopt nor a create: it is the reversal outcome, and the caller hands it to
  // `kernel.hold_payout_transfer_reversed`.
  const rev = classifyTransferReversal(t, plan.amount_minor);
  if (rev.state === 'unreadable') {
    return { kind: 'refuse', code: 'reconcile_ambiguous', detail: `unreadable reversal on ${String(t.id)}: ${rev.detail}` };
  }
  if (rev.state === 'reversed') {
    return {
      kind: 'reversed',
      reversal: rev.reversal,
      detail: `transfer ${String(t.id)} carries amount_reversed=${rev.reversal.amount_reversed_minor} of ${plan.amount_minor}; it is not a payment`,
    };
  }
  return { kind: 'adopt', stripe_transfer_ref: t.id as string };
}

/**
 * THE ONLY PLACE AN IDEMPOTENCY KEY IS PRODUCED. It requires both preflight
 * verdicts as arguments, so the ordering "preflight, then spend the key" is a
 * property of the types rather than of the call site's discipline.
 */
export function authorizeTransfer(
  plan: Extract<PayoutPlan, { kind: 'preflight' }>,
  probes: {
    destination: ReturnType<typeof evaluateDestination>;
    balance: ReturnType<typeof evaluateBalance>;
    reconcile?: ReturnType<typeof planReconcile>;
  },
): TransferAuthorization {
  if (!probes.destination.ok) {
    const d = probes.destination;
    return { kind: 'refuse', code: d.code, detail: d.detail, retryable: d.retryable };
  }
  if (!probes.balance.ok) {
    const b = probes.balance;
    return { kind: 'refuse', code: b.code, detail: b.detail, retryable: b.retryable };
  }
  if (plan.execution_mode === 'reconcile') {
    const r = probes.reconcile;
    if (r == null) {
      // A reconcile-mode attempt that never read the transfer group is exactly
      // the double-pay this mode exists to prevent. Fail closed.
      return {
        kind: 'refuse',
        code: 'reconcile_ambiguous',
        detail: 'execution_mode=reconcile requires a transfer_group read before a create is permitted',
        retryable: true,
      };
    }
    if (r.kind === 'refuse') return { kind: 'refuse', code: r.code, detail: r.detail, retryable: false };
    if (r.kind === 'reversed') {
      return { kind: 'reversed', reversal: r.reversal, detail: r.detail };
    }
    if (r.kind === 'adopt') {
      return { kind: 'adopt', stripe_transfer_ref: r.stripe_transfer_ref, detail: 'recovered via transfer_group' };
    }
  }

  // H3 §5 step 6. `amount` is sent explicitly and `source_transaction` is
  // ABSENT: on this rail the transfer draws the platform's available balance
  // (H3 §3), and there is no charge whose amount the net corresponds to.
  const body: Record<string, string> = {
    'amount': String(plan.amount_minor),
    'currency': plan.currency,
    'destination': plan.destination,
    'transfer_group': plan.transfer_group,
    'metadata[payout_id]': plan.payout_id,
    'metadata[settlement_id]': plan.settlement_id,
    'metadata[org_id]': plan.org_id,
    'metadata[source]': 'payout-execute',
  };
  return {
    kind: 'stripe_create',
    idempotency_key: buildPayoutTransferIdempotencyKey(plan.payout_id, plan.destination),
    body,
    amount_minor: plan.amount_minor,
    destination: plan.destination,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Stripe error classification
// ─────────────────────────────────────────────────────────────────────────────

export type TransferErrorClass =
  | 'network'
  | 'rate_limited'
  | 'api_error'
  | 'idempotency_in_use'
  | 'idempotency_conflict'
  | 'balance_insufficient'
  | 'destination_capability'
  | 'resource_missing'
  | 'invalid_request'
  | 'unknown';

export interface TransferErrorVerdict {
  class: TransferErrorClass;
  retryable: boolean;
  page: boolean;
  /**
   * ALWAYS false, and it is the type that says so. A create error means no
   * `tr_…` was returned, so nothing may be written through
   * `mark_payout_transfer_state` — and in particular NOT 'failed', which has no
   * exit and would destroy the venue's obligation. The row stays `submitted`
   * and the same key replays.
   */
  writesState: false;
}

export function classifyTransferError(
  input: { status?: number; error?: { type?: string; code?: string; message?: string } } | Error,
): TransferErrorVerdict {
  const base = { writesState: false as const };
  if (input instanceof Error) {
    // Thrown before any HTTP response existed: DNS, TLS, socket, abort/timeout.
    // Stripe MAY have created the transfer. We write NOTHING; the same key
    // replays and returns the SAME object (or, past 24h, the reconcile mode
    // finds it by transfer_group).
    return { ...base, class: 'network', retryable: true, page: false };
  }
  const status = input.status ?? 0;
  const code = input.error?.code ?? '';
  const type = input.error?.type ?? '';

  if (code === 'idempotency_error') {
    // Same key, different parameters — a CODE BUG or a mutated amount. This is
    // the anti-tamper guard tripping at Stripe. Never retry it blind.
    return { ...base, class: 'idempotency_conflict', retryable: false, page: true };
  }
  if (status === 409 || code === 'idempotency_key_in_use') {
    // A concurrent duplicate. Back off and re-read; NEVER escalate to a second
    // key (H3 §6) — a second key is a second transfer.
    return { ...base, class: 'idempotency_in_use', retryable: true, page: false };
  }
  if (code === 'balance_insufficient') {
    // Should be unreachable: the balance preflight refuses before the key is
    // spent. If it happens anyway the balance moved under us — operational.
    return { ...base, class: 'balance_insufficient', retryable: true, page: false };
  }
  if (code === 'account_invalid' || code === 'resource_missing') {
    return { ...base, class: 'resource_missing', retryable: false, page: true };
  }
  if (/capabilit/i.test(input.error?.message ?? '') || /capabilit/i.test(code)) {
    return { ...base, class: 'destination_capability', retryable: true, page: false };
  }
  if (status === 429 || code === 'rate_limit' || type === 'rate_limit_error') {
    return { ...base, class: 'rate_limited', retryable: true, page: false };
  }
  if (status >= 500 || type === 'api_error' || type === 'api_connection_error') {
    return { ...base, class: 'api_error', retryable: true, page: false };
  }
  if (type === 'invalid_request_error' || (status >= 400 && status < 500)) {
    return { ...base, class: 'invalid_request', retryable: false, page: true };
  }
  return { ...base, class: 'unknown', retryable: false, page: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// The callback plan: kernel.mark_payout_transfer_state
// ─────────────────────────────────────────────────────────────────────────────

/**
 * THE COMPLETE SET OF STATES THIS EXECUTOR MAY EVER WRITE. Exactly one member.
 * Exported so the test suite can assert the absence of 'failed' structurally
 * instead of by reading the code.
 */
export const PAYOUT_STATE_SYNC_TARGETS = ['paid'] as const;
export type PayoutStateSyncTarget = (typeof PAYOUT_STATE_SYNC_TARGETS)[number];

export interface PayoutStateSyncStep {
  /** 'paid' and nothing else. The type is the guarantee. */
  new_status: PayoutStateSyncTarget;
  stripe_transfer_ref: string;
  /**
   * ALWAYS null. `mark_payout_transfer_state` makes `failure_code` mandatory
   * only for 'failed', which this module never writes.
   */
  failure_code: null;
}

export type PayoutStateSyncPlan =
  | { kind: 'sync'; steps: PayoutStateSyncStep[] }
  /**
   * The money came back — wholly or in part. NO status transition is written;
   * the caller routes this to `kernel.hold_payout_transfer_reversed`. See
   * `TransferReversal` for why neither 'paid' nor 'reversed' is honest here.
   */
  | { kind: 'reversed'; reversal: TransferReversal; detail: string }
  | { kind: 'refuse'; code: 'malformed_stripe_transfer_ref' | 'transfer_reversal_unreadable'; detail: string };

/**
 * Turn the Stripe Transfer object into the `kernel.mark_payout_transfer_state`
 * call that makes it true in our ledger.
 *
 * A Transfer has no pending/failed lifecycle of its own the way a Refund does:
 * `POST /v1/transfers` either returns a `tr_…` (the money has been moved to the
 * connected account's balance) or errors. So there is exactly ONE step, and its
 * target is 'paid' — which also fires `venue.on_payout_settled` in the same
 * transaction and advances the settlement header closed→paid (085:1729,
 * 087:376).
 *
 * Two things can go wrong. A malformed id is a 2xx we cannot record: the row
 * stays `submitted` and a human is paged, because money moved and we cannot
 * prove it. A transfer whose money has come back is NOT that case — it is an
 * expected observation with its own DB verb (`reversed` below). NEITHER writes
 * 'failed'.
 *
 * `obligationMinor` is the payout's own `amount_minor`. It is used ONLY to
 * classify full-versus-partial for the executor's own logging; the DB verb
 * re-derives that verdict from the ledger and does not trust this number.
 */
export function planPayoutStateSync(
  transfer: { id?: unknown; amount?: unknown; reversed?: unknown; amount_reversed?: unknown },
  obligationMinor: number,
): PayoutStateSyncPlan {
  const id = transfer?.id;
  if (typeof id !== 'string' || !TR_RE.test(id)) {
    return { kind: 'refuse', code: 'malformed_stripe_transfer_ref', detail: `id=${String(id)}` };
  }
  // THE FIX. `reversed` alone is FULL reversal only — Stripe: "if the transfer
  // is only partially reversed, this attribute will still be false". Reading it
  // as the whole truth synced a partially reversed transfer to 'paid' at full
  // face value.
  const rev = classifyTransferReversal(transfer, obligationMinor);
  if (rev.state === 'unreadable') {
    return {
      kind: 'refuse',
      code: 'transfer_reversal_unreadable',
      detail: `${id}: ${rev.detail} — refusing to assume nothing came back`,
    };
  }
  if (rev.state === 'reversed') {
    return {
      kind: 'reversed',
      reversal: rev.reversal,
      detail: `${id} carries amount_reversed=${rev.reversal.amount_reversed_minor} of ${obligationMinor}; 'paid' would assert money the venue does not have`,
    };
  }
  return { kind: 'sync', steps: [{ new_status: 'paid', stripe_transfer_ref: id, failure_code: null }] };
}

// ─────────────────────────────────────────────────────────────────────────────
// mark_payout_transfer_state error classification
// ─────────────────────────────────────────────────────────────────────────────

export interface PayoutStateSyncVerdict {
  /**
   * `converged` — another worker already advanced this row past us. Because the
   *               Stripe key is deterministic per (payout, destination), whoever
   *               got there first holds the SAME `tr_…`. Not an error and NOT
   *               retryable: retrying it forever is how a healthy race becomes a
   *               hot loop against Stripe.
   * `held`      — a human applied a hold between our create and our callback.
   *               `mark_payout_transfer_state` refuses with BOTH columns
   *               untouched (085:1690), so nothing is half-written. Money moved
   *               and the ledger does not know: page, do not retry blind.
   * `conflict`  — two different refs on one payout row, a missing row, a
   *               malformed argument. Real incident.
   * `retry`     — transport/DB unavailability. The money already moved, so a
   *               later tick must replay and finish the callback.
   */
  kind: 'converged' | 'held' | 'conflict' | 'retry';
  page: boolean;
}

export function classifyPayoutStateSyncError(message: string): PayoutStateSyncVerdict {
  if (/payout_state_backwards/.test(message)) return { kind: 'converged', page: false };
  if (/payout_held/.test(message)) return { kind: 'held', page: true };
  if (/conflict_locked/.test(message)) return { kind: 'conflict', page: true };
  if (/not_found/.test(message)) return { kind: 'conflict', page: true };
  if (/invalid_input/.test(message)) return { kind: 'conflict', page: true };
  return { kind: 'retry', page: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// The claim batch
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The worker's work list, straight from `kernel.claim_payouts_for_execution`.
 *
 * The claim already applied every eligibility predicate, the lease and the
 * `create` / `reconcile` mode, so this function only guards against a malformed
 * row and bounds the batch. It deliberately does NOT re-filter on status: the
 * DB decides what is claimable, and a worker that re-decides is a worker that
 * can disagree.
 */
export function planPayoutBatch(rows: PayoutClaim[], opts: { limit?: number } = {}): PayoutClaim[] {
  const limit = Math.max(1, Math.min(opts.limit ?? 25, 100));
  const seen = new Set<string>();
  return (Array.isArray(rows) ? rows : [])
    .filter((r) => r && isUuid(r.payout_id))
    .filter((r) => r.execution_mode === 'create' || r.execution_mode === 'reconcile')
    .filter((r) => (seen.has(r.payout_id) ? false : (seen.add(r.payout_id), true)))
    .slice(0, limit);
}

/** Map a Postgres RPC error onto an HTTP status, per the edge spec's table. */
export function httpStatusForRpcError(message: string): number {
  if (/insufficient_privilege|sod_violation|step_up_required|step_up_unavailable/.test(message)) return 403;
  if (/not_found/.test(message)) return 404;
  if (/precondition_failed|conflict_locked|state_conflict|frozen|policy_violation/.test(message)) return 409;
  if (/invalid_input/.test(message)) return 400;
  return 500;
}
