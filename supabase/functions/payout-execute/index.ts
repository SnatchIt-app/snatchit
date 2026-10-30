// =============================================================================
// payout-execute — the server-side Stripe payout executor for venue settlements
// =============================================================================
// THE DEFECT THIS CLOSES
//   `kernel.close_settlement` mints a `cause='settlement'` payout,
//   `kernel.request_org_payout` advances it to `submitted` behind SoD-1,
//   money-role maturity, an aal2 step-up and dual control — and then NOTHING
//   calls Stripe. `kernel.mark_payout_transfer_state` (085:1668) has zero
//   callers repo-wide. The venue's money is computed, approved and never sent.
//   This function is that missing caller.
//
// THE SHAPE IS RULING H3 (docs/phase2/_impl/H3_transfer_cardinality.md)
//   ONE payout row → ONE Stripe Transfer → ONE `stripe_transfer_ref`, with NO
//   `source_transaction` (§3). The resale rail keeps `source_transaction` and
//   its `_src` key space; this rail is `_v1` and draws the platform's available
//   balance, which is why the balance preflight below is MANDATORY.
//
// THE RULE THAT OUTRANKS EVERYTHING: THIS FUNCTION NEVER WRITES 'failed'.
//   085's state machine has NO edge out of 'failed', `request_org_payout` never
//   sees a failed row, and `close_settlement` can never re-mint one. A failed
//   settlement payout destroys the venue's obligation permanently. Every
//   ordinary non-success therefore leaves the row `submitted` and writes
//   `kernel.record_payout_execution_note`. See executor.ts for the executed
//   proof of the absorbing state.
//
// THE DECISION IS THE DATABASE'S
//   `kernel.get_payout_execution_context` returns `execution_eligible` and a
//   `refusal_code`. This file does not re-derive eligibility, does not compute
//   money, and has no request field for an amount, a destination, an
//   organization or a settlement — `assertNoClientMoneyReference` refuses a
//   request that names one.
//
// ONE CLIENT, NOT TWO (unlike refund-execute)
//   Every RPC on this path is service_role-only and reads no `auth.uid()`:
//   claim_payouts_for_execution, get_payout_execution_context,
//   mark_payout_transfer_state, record_payout_execution_note,
//   hold_payout_destination_changed. There is no human arm to route, so there
//   is no caller client. `kernel.hold_payout` is deliberately NOT reachable
//   here: it is gated on `kernel.is_platform` (auth.uid(), NULL on a machine
//   session) AND is not granted to service_role at all.
//
// NOT DEPLOYED. Authoring this file creates no Stripe object and no payout.
// =============================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetchRaw } from '../_shared/stripe.ts';
import {
  assertNoClientMoneyReference,
  authorizeTransfer,
  buildPayoutTransferIdempotencyKey,
  classifyPayoutStateSyncError,
  classifyTransferError,
  evaluateBalance,
  evaluateDestination,
  httpStatusForRpcError,
  isUuid,
  planFailedReconcile,
  planPayoutBatch,
  planPayoutStateSync,
  planPayoutTransfer,
  planReconcile,
  type BalanceProbe,
  type TransferReversal,
  type DestinationProbe,
  type FailedPayoutClaim,
  type ObservedTransferRead,
  type PayoutClaim,
  type PayoutExecutionContext,
  type PayoutExecutionMode,
} from './executor.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const INTERNAL_CRON_SECRET = Deno.env.get('INTERNAL_CRON_SECRET') ?? '';

const CONTEXT_RPC = 'get_payout_execution_context';
const CLAIM_RPC = 'claim_payouts_for_execution';
const NOTE_RPC = 'record_payout_execution_note';
const DEAUTH_RPC = 'hold_payout_destination_changed';
const REVERSED_RPC = 'hold_payout_transfer_reversed';
const RECONCILE_CLAIM_RPC = 'claim_failed_payouts_for_reconcile';
const RECONCILE_RPC = 'reconcile_payout_transfer';

const ALLOWED_ORIGINS = ['https://snatchitapp.com', 'https://www.snatchitapp.com'];

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin') ?? '';
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };
}

const SECURITY_HEADERS: Record<string, string> = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'X-DNS-Prefetch-Control': 'off',
  'X-Download-Options': 'noopen',
  'X-Permitted-Cross-Domain-Policies': 'none',
  'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
};

const responseHeaders = (req: Request) => ({ ...getCorsHeaders(req), ...SECURITY_HEADERS });

function json(body: unknown, status: number, headers: Record<string, string>): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...headers, 'Content-Type': 'application/json' } });
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** service_role, kernel schema. The ONLY client this function has. */
function kernelServiceClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
    db: { schema: 'kernel' },
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// The audit note — the reason a stalled payout is visible rather than silent
// ─────────────────────────────────────────────────────────────────────────────

async function note(
  service: SupabaseClient,
  payoutId: string,
  reasonCode: string,
  detail: Record<string, unknown>,
  commandKey: string,
): Promise<void> {
  try {
    const { error } = await service.rpc(NOTE_RPC, {
      p_payout_id: payoutId,
      p_reason_code: reasonCode.slice(0, 120),
      p_detail: detail,
      p_command_key: commandKey,
    });
    if (error) console.warn('[payout-execute] execution note failed:', error.message);
  } catch (err) {
    console.warn('[payout-execute] execution note threw:', String(err));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A transfer whose money came back
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Route a reversal — full or partial — to `kernel.hold_payout_transfer_reversed`.
 *
 * NO STATUS TRANSITION IS WRITTEN, from either of the two sites that can
 * observe a reversal (the reconcile read, and the sync after a create). 'paid'
 * would assert money the venue does not have and would fire
 * `venue.on_payout_settled`; 'reversed' is only reachable through 'paid'; and
 * `kernel.payout` has one amount column, so a partial has nowhere to live. The
 * DB verb de-authorizes the row to pending + held with the amounts in the
 * audit, and a human rules. 'failed' is never written here either.
 *
 * A FULL reversal is BENIGN, not an error: Stripe may reverse on its own
 * initiative (platforms created on or after 2025-01-01, when an async payment
 * behind the funds fails). It is logged, not paged. A PARTIAL reversal is the
 * unrepresentable case and IS paged, because a human has to decide what the
 * venue is still owed.
 */
async function holdReversedTransfer(
  service: SupabaseClient,
  payoutId: string,
  reversal: TransferReversal,
  obligationMinor: number,
  detail: string,
  commandKey: string,
  origin: 'reconcile' | 'post_create',
): Promise<PayoutOutcome> {
  const { data, error } = await service.rpc(REVERSED_RPC, {
    p_payout_id: payoutId,
    p_stripe_transfer_ref: reversal.stripe_transfer_ref,
    p_transfer_amount_minor: reversal.transfer_amount_minor,
    p_amount_reversed_minor: reversal.amount_reversed_minor,
    p_detail: { origin, detail, obligation_minor: obligationMinor },
    p_command_key: commandKey,
  });
  if (error) {
    await note(service, payoutId, 'transfer_reversed_hold_failed', {
      stripe_transfer_ref: reversal.stripe_transfer_ref,
      amount_reversed_minor: reversal.amount_reversed_minor,
      error: error.message,
    }, commandKey);
    await captureException('payout-execute:reversal-hold', new Error(`hold_payout_transfer_reversed: ${error.message}`), {
      payout_id: payoutId,
    });
    return { payout_id: payoutId, outcome: 'refused', code: 'transfer_reversed_hold_failed', detail: error.message, retryable: true, http: 500 };
  }
  const fault = (data as { fault?: string })?.fault ?? (reversal.fully_reversed ? 'transfer_reversed' : 'transfer_partially_reversed');
  if (fault !== 'transfer_reversed') {
    // The unrepresentable case. A human must decide what is still owed.
    await captureException('payout-execute:partial-reversal', new Error(`${fault}: ${detail}`), { payout_id: payoutId });
  }
  return {
    payout_id: payoutId,
    outcome: 'transfer_reversed',
    code: fault,
    detail,
    stripe_transfer_ref: reversal.stripe_transfer_ref,
    retryable: false,
    http: 200,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Stripe probes. NEITHER spends an idempotency key.
// ─────────────────────────────────────────────────────────────────────────────

async function probeDestination(destination: string): Promise<DestinationProbe> {
  try {
    const res = await stripeFetchRaw(`/accounts/${destination}`);
    const a = (res.data ?? {}) as Record<string, unknown>;
    const caps = (a.capabilities ?? {}) as Record<string, string>;
    const req = (a.requirements ?? {}) as Record<string, unknown>;
    const err = (res.data as { error?: { code?: string; message?: string } })?.error;
    return {
      ok: res.ok,
      id: (a.id as string) ?? null,
      deleted: (a.deleted as boolean) ?? null,
      transfers_capability: caps.transfers ?? null,
      payouts_enabled: (a.payouts_enabled as boolean) ?? null,
      charges_enabled: (a.charges_enabled as boolean) ?? null,
      details_submitted: (a.details_submitted as boolean) ?? null,
      disabled_reason: (req.disabled_reason as string) ?? null,
      error_code: err?.code ?? (res.ok ? null : `http_${res.status}`),
      error_message: err?.message ?? null,
    };
  } catch (e) {
    return { ok: false, error_code: 'transport', error_message: String(e) };
  }
}

async function probeBalance(): Promise<BalanceProbe> {
  try {
    const res = await stripeFetchRaw('/balance');
    const b = (res.data ?? {}) as Record<string, unknown>;
    const err = (res.data as { error?: { code?: string; message?: string } })?.error;
    const available = Array.isArray(b.available)
      ? (b.available as Array<Record<string, unknown>>).map((x) => ({
          currency: String(x.currency ?? ''),
          amount: Number(x.amount ?? 0),
        }))
      : [];
    return {
      ok: res.ok,
      available,
      error_code: err?.code ?? (res.ok ? null : `http_${res.status}`),
      error_message: err?.message ?? null,
    };
  } catch (e) {
    return { ok: false, available: [], error_code: 'transport', error_message: String(e) };
  }
}

async function probeTransferGroup(group: string): Promise<{ ok: boolean; rows: Array<Record<string, unknown>>; detail?: string }> {
  try {
    const res = await stripeFetchRaw(`/transfers?transfer_group=${encodeURIComponent(group)}&limit=100`);
    if (!res.ok) return { ok: false, rows: [], detail: `HTTP ${res.status}` };
    const d = (res.data ?? {}) as Record<string, unknown>;
    return { ok: true, rows: Array.isArray(d.data) ? (d.data as Array<Record<string, unknown>>) : [] };
  } catch (e) {
    return { ok: false, rows: [], detail: String(e) };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KE §4.2 / DESIGN_096 §2.3 — the ref-bearing FAILED payout reconcile pass
//
// `claim_payouts_for_execution` only ever selects `status='submitted'`, so a
// `failed` row that DOES carry a `stripe_transfer_ref` — money that moved at
// Stripe but was never recorded because the callback died — is invisible to
// `executeOne` above. This is a SECOND, independent phase with its own claim
// (`claim_failed_payouts_for_reconcile`) and its own single-writer DB verb
// (`reconcile_payout_transfer`, 096 R-7). It NEVER writes 'failed', NEVER
// creates a Stripe transfer, and NEVER calls `mark_payout_transfer_state`
// directly — the verb is the sole writer of the failed→paid edge.
// ─────────────────────────────────────────────────────────────────────────────

type TransferRead =
  | { kind: 'found'; data: Record<string, unknown> }
  | { kind: 'not_found' }
  | { kind: 'error'; detail: string };

/** `GET /v1/transfers/{ref}` — a 404 is a legitimate observation, not an error. */
async function readTransfer(ref: string): Promise<TransferRead> {
  try {
    const res = await stripeFetchRaw(`/transfers/${encodeURIComponent(ref)}`);
    if (res.status === 404) return { kind: 'not_found' };
    if (!res.ok) return { kind: 'error', detail: `HTTP ${res.status}` };
    return { kind: 'found', data: (res.data ?? {}) as Record<string, unknown> };
  } catch (e) {
    return { kind: 'error', detail: String(e) };
  }
}

/**
 * `GET /v1/transfers/{id}/reversals`, paged. Stripe's `reversals` sub-list on
 * the Transfer object itself may be short (`has_more`); the EDGE pages here so
 * `planFailedReconcile`'s Σ is never short of `amount_reversed` (096:932-934).
 * A hard 20-page cap (2000 reversals) guards against a runaway loop; no real
 * payout will ever carry that many.
 */
async function readAllReversals(
  transferId: string,
): Promise<{ ok: true; reversals: Array<{ id: unknown; amount: unknown }> } | { ok: false; detail: string }> {
  const out: Array<{ id: unknown; amount: unknown }> = [];
  let startingAfter: string | undefined;
  for (let page = 0; page < 20; page++) {
    const qs = new URLSearchParams({ limit: '100' });
    if (startingAfter) qs.set('starting_after', startingAfter);
    let res: { ok: boolean; status: number; data: unknown };
    try {
      res = await stripeFetchRaw(`/transfers/${encodeURIComponent(transferId)}/reversals?${qs.toString()}`);
    } catch (e) {
      return { ok: false, detail: String(e) };
    }
    if (!res.ok) return { ok: false, detail: `HTTP ${res.status}` };
    const d = (res.data ?? {}) as Record<string, unknown>;
    const rows = Array.isArray(d.data) ? (d.data as Array<Record<string, unknown>>) : [];
    for (const r of rows) out.push({ id: r.id, amount: r.amount });
    if (d.has_more !== true) break;
    const last = rows[rows.length - 1];
    if (!last || typeof last.id !== 'string') break;
    startingAfter = last.id;
  }
  return { ok: true, reversals: out };
}

interface ReconcileOutcome {
  payout_id: string;
  status: string;
  refusal_code?: string | null;
  payout_status?: string | null;
}

/**
 * Reconcile ONE ref-bearing failed payout: read Stripe, plan (pure), call the
 * sole-writer verb, log. No status is written from this function — the RPC is
 * the only writer, and it writes 'paid' (never 'failed', never a re-create).
 */
async function reconcileOneFailedPayout(service: SupabaseClient, claim: FailedPayoutClaim): Promise<ReconcileOutcome> {
  const transferRead = await readTransfer(claim.stripe_transfer_ref);
  if (transferRead.kind === 'error') {
    // Transport hiccup, not an observation. Stays `failed`; the lease expires
    // and a later tick reclaims it. No verb call — nothing to compare yet.
    await note(service, claim.payout_id, 'reconcile_transfer_read_failed', {
      stripe_transfer_ref: claim.stripe_transfer_ref,
      detail: transferRead.detail,
    }, claim.command_key);
    return { payout_id: claim.payout_id, status: 'read_failed' };
  }

  let reversals: Array<{ id: unknown; amount: unknown }> = [];
  if (transferRead.kind === 'found') {
    const revRead = await readAllReversals(claim.stripe_transfer_ref);
    if (!revRead.ok) {
      await note(service, claim.payout_id, 'reconcile_reversals_read_failed', {
        stripe_transfer_ref: claim.stripe_transfer_ref,
        detail: revRead.detail,
      }, claim.command_key);
      return { payout_id: claim.payout_id, status: 'read_failed' };
    }
    reversals = revRead.reversals;
  }

  const group = await probeTransferGroup(claim.transfer_group);
  if (!group.ok) {
    await note(service, claim.payout_id, 'reconcile_group_read_failed', {
      transfer_group: claim.transfer_group,
      detail: group.detail ?? null,
    }, claim.command_key);
    return { payout_id: claim.payout_id, status: 'read_failed' };
  }

  const observedTransfer: ObservedTransferRead =
    transferRead.kind === 'found'
      ? {
          found: true,
          id: typeof transferRead.data.id === 'string' ? transferRead.data.id : null,
          amount: Number.isFinite(transferRead.data.amount as number) ? (transferRead.data.amount as number) : null,
          currency: typeof transferRead.data.currency === 'string' ? transferRead.data.currency : null,
          destination: typeof transferRead.data.destination === 'string' ? transferRead.data.destination : null,
          transfer_group: typeof transferRead.data.transfer_group === 'string' ? transferRead.data.transfer_group : null,
          reversed: transferRead.data.reversed === true,
          amount_reversed: Number.isFinite(transferRead.data.amount_reversed as number)
            ? (transferRead.data.amount_reversed as number)
            : null,
        }
      : { found: false };

  const plan = planFailedReconcile(observedTransfer, reversals, group.rows, claim);

  const { data, error } = await service.rpc(RECONCILE_RPC, {
    p_payout_id: claim.payout_id,
    p_stripe_transfer_ref: claim.stripe_transfer_ref,
    p_observed: plan.observed,
    p_command_key: claim.command_key,
  });

  if (error) {
    await note(service, claim.payout_id, 'reconcile_rpc_failed', { error: error.message, plan_outcome: plan.outcome }, claim.command_key);
    await captureException('payout-execute:reconcile', new Error(`${RECONCILE_RPC}: ${error.message}`), { payout_id: claim.payout_id });
    return { payout_id: claim.payout_id, status: 'rpc_failed' };
  }

  const result = (data ?? {}) as { status?: string; refusal_code?: string; payout_status?: string };
  await note(service, claim.payout_id, `reconcile_${result.status ?? 'unknown'}`, {
    result,
    plan_outcome: plan.outcome,
    plan_refusal_code: plan.refusalCode,
  }, claim.command_key);

  if (result.status === 'refused') {
    // transfer_unresolvable / *_mismatch / reconcile_ambiguous / reversals_* —
    // the row stays `failed`. This IS the page (096:926-929: a terminal row
    // cannot be held, so the audit + alert together are the "operator hold").
    await captureException(
      'payout-execute:reconcile-refused',
      new Error(`${result.refusal_code ?? 'unknown'}: payout ${claim.payout_id} stays failed`),
      { payout_id: claim.payout_id, refusal_code: result.refusal_code ?? '' },
    );
  }
  console.log('[payout-execute] reconcile:', {
    payout_id: claim.payout_id,
    status: result.status,
    payout_status: result.payout_status,
  });
  return { payout_id: claim.payout_id, status: result.status ?? 'unknown', refusal_code: result.refusal_code, payout_status: result.payout_status };
}

async function runReconcilePass(
  service: SupabaseClient,
  limit: number,
  leaseSeconds: number,
): Promise<{ claimed: number; results: ReconcileOutcome[] }> {
  const { data, error } = await service.rpc(RECONCILE_CLAIM_RPC, { p_limit: limit, p_lease_seconds: leaseSeconds });
  if (error) {
    const missing = error.code === 'PGRST202' || /could not find the function|does not exist/i.test(error.message);
    console.warn('[payout-execute] reconcile claim failed:', missing ? `${RECONCILE_CLAIM_RPC} not deployed` : error.message);
    return { claimed: 0, results: [] };
  }
  const rows = ((data as { payouts?: FailedPayoutClaim[] } | null)?.payouts ?? []).filter(
    (r) => r && isUuid(r.payout_id) && typeof r.stripe_transfer_ref === 'string',
  );
  const results: ReconcileOutcome[] = [];
  for (const c of rows) {
    try {
      results.push(await reconcileOneFailedPayout(service, c));
    } catch (err) {
      await captureException('payout-execute:reconcile-batch', err, { payout_id: c.payout_id });
      results.push({ payout_id: c.payout_id, status: 'unhandled_error' });
    }
  }
  console.log('[payout-execute] reconcile pass complete:', { claimed: rows.length });
  return { claimed: rows.length, results };
}

// ─────────────────────────────────────────────────────────────────────────────
// Execute ONE payout. The whole money path lives here.
// ─────────────────────────────────────────────────────────────────────────────

export type PayoutOutcome = {
  payout_id: string;
  outcome:
    | 'paid'
    | 'noop_replay'
    | 'refused'
    | 'deauthorized'
    | 'stripe_error'
    | 'state_sync_deferred'
    /** A Transfer exists and its money came back. No status transition written. */
    | 'transfer_reversed';
  stripe_transfer_ref?: string | null;
  code?: string;
  detail?: string;
  retryable?: boolean;
  http?: number;
};

async function executeOne(
  service: SupabaseClient,
  payoutId: string,
  commandKey: string,
  mode: PayoutExecutionMode,
  expected: { org_id?: string | null; settlement_id?: string | null },
): Promise<PayoutOutcome> {
  if (!isUuid(payoutId)) {
    return { payout_id: payoutId, outcome: 'refused', code: 'malformed_payout_id', detail: payoutId, http: 400 };
  }

  // ── 1. the context, which is also the verdict ─────────────────────────────
  const { data, error } = await service.rpc(CONTEXT_RPC, { p_payout_id: payoutId });
  if (error) {
    const missing = error.code === 'PGRST202' || /could not find the function|does not exist/i.test(error.message);
    return {
      payout_id: payoutId,
      outcome: 'refused',
      code: missing ? 'context_rpc_missing' : 'context_read_failed',
      detail: missing
        ? `kernel.${CONTEXT_RPC}(uuid) is not deployed. service_role holds USAGE on kernel but NO table grants (085:2093-2096), so the executor cannot resolve payout_id → obligation → destination without it. See docs/phase2/_impl/H8_payout_executor.md.`
        : error.message,
      http: missing ? 501 : httpStatusForRpcError(error.message),
    };
  }
  if (!data || typeof data !== 'object') {
    return { payout_id: payoutId, outcome: 'refused', code: 'payout_not_found', detail: payoutId, http: 404 };
  }
  const ctx = data as PayoutExecutionContext;

  // ── 2. the plan ───────────────────────────────────────────────────────────
  const plan = planPayoutTransfer(ctx, { execution_mode: mode, expected });

  if (plan.kind === 'noop_replay') {
    return { payout_id: payoutId, outcome: 'noop_replay', code: plan.reason, stripe_transfer_ref: plan.stripe_transfer_ref, http: 200 };
  }

  if (plan.kind === 'deauthorize') {
    // THE PAYEE IS NO LONGER THE APPROVED ONE. Do not pay either address, and do
    // NOT write 'failed'. The DB verb re-derives the fault itself and returns
    // the payout to pending+held, where a human must release it and the org
    // must re-request behind the full control set.
    const { data: held, error: hErr } = await service.rpc(DEAUTH_RPC, {
      p_payout_id: payoutId,
      p_observed_ref: ctx.org_connect_ref_current ?? '',
      p_command_key: commandKey,
    });
    if (hErr) {
      await note(service, payoutId, `deauthorize_failed:${plan.code}`, { error: hErr.message, detail: plan.detail }, commandKey);
      await captureException('payout-execute:deauthorize', new Error(`${plan.code}: ${hErr.message}`), { payout_id: payoutId });
      return { payout_id: payoutId, outcome: 'refused', code: 'deauthorize_failed', detail: hErr.message, retryable: true, http: 500 };
    }
    await captureException('payout-execute:destination-changed', new Error(`${plan.code}: ${plan.detail}`), { payout_id: payoutId });
    return {
      payout_id: payoutId,
      outcome: 'deauthorized',
      code: (held as { fault?: string })?.fault ?? plan.code,
      detail: plan.detail,
      http: 409,
    };
  }

  if (plan.kind === 'refuse') {
    await note(service, payoutId, plan.code === 'db_refused' ? `db_refused:${plan.detail}` : plan.code, {
      refusal_code: ctx.refusal_code,
      detail: plan.detail,
      retryable: plan.retryable,
    }, commandKey);
    if (!plan.retryable && plan.code !== 'db_refused') {
      await captureException('payout-execute:refusal', new Error(`${plan.code}: ${plan.detail}`), {
        payout_id: payoutId,
        settlement_id: ctx.settlement_id,
      });
    }
    return { payout_id: payoutId, outcome: 'refused', code: plan.code, detail: plan.detail, retryable: plan.retryable, http: 409 };
  }

  // ── 3+4. THE PREFLIGHTS. No idempotency key exists yet, by construction. ──
  const destProbe = await probeDestination(plan.destination);
  const destVerdict = evaluateDestination(destProbe, plan.destination);
  const balProbe = destVerdict.ok ? await probeBalance() : { ok: false, available: [], error_code: 'skipped' } as BalanceProbe;
  const balVerdict = destVerdict.ok
    ? evaluateBalance(balProbe, { amount_minor: plan.amount_minor, currency: plan.currency })
    : evaluateBalance({ ok: false, available: [], error_code: 'skipped' }, { amount_minor: plan.amount_minor, currency: plan.currency });

  // ── 5. reconcile mode: read the transfer group BEFORE any create ──────────
  let reconcile: ReturnType<typeof planReconcile> | undefined;
  if (plan.execution_mode === 'reconcile' && destVerdict.ok && balVerdict.ok) {
    const tg = await probeTransferGroup(plan.transfer_group);
    if (!tg.ok) {
      await note(service, payoutId, 'reconcile_read_failed', { transfer_group: plan.transfer_group, detail: tg.detail ?? null }, commandKey);
      return { payout_id: payoutId, outcome: 'refused', code: 'reconcile_read_failed', detail: tg.detail ?? '', retryable: true, http: 503 };
    }
    reconcile = planReconcile(tg.rows, plan);
  }

  const auth = authorizeTransfer(plan, { destination: destVerdict, balance: balVerdict, reconcile });

  if (auth.kind === 'reversed') {
    // The transfer group already holds a transfer for this payout and its money
    // has come back. Adopting it would sync 'paid' for money the venue does not
    // have; creating a second one would pay twice. Neither. Hold, and let a
    // human rule.
    await note(service, payoutId, 'reconcile_transfer_reversed', {
      stripe_transfer_ref: auth.reversal.stripe_transfer_ref,
      amount_reversed_minor: auth.reversal.amount_reversed_minor,
      obligation_minor: plan.amount_minor,
      detail: auth.detail,
    }, commandKey);
    return await holdReversedTransfer(service, payoutId, auth.reversal, plan.amount_minor, auth.detail, commandKey, 'reconcile');
  }

  if (auth.kind === 'refuse') {
    await note(service, payoutId, auth.code, {
      destination_state: destProbe,
      balance_available: balProbe.available,
      required_minor: plan.amount_minor,
      detail: auth.detail,
    }, commandKey);
    if (!auth.retryable) {
      await captureException('payout-execute:preflight', new Error(`${auth.code}: ${auth.detail}`), { payout_id: payoutId });
    }
    // THE ROW STAYS `submitted`. Not one of these writes 'failed'.
    return { payout_id: payoutId, outcome: 'refused', code: auth.code, detail: auth.detail, retryable: auth.retryable, http: auth.retryable ? 503 : 409 };
  }

  // ── 6. the transfer (or the adoption of one we already made) ─────────────
  let transferObj: { id?: string; amount?: number; reversed?: boolean; amount_reversed?: number };
  if (auth.kind === 'adopt') {
    // planReconcile has already proved this transfer carries amount_reversed = 0
    // (a reversed one takes the branch above and never reaches here), so the
    // zero is asserted rather than assumed.
    transferObj = { id: auth.stripe_transfer_ref, amount: plan.amount_minor, reversed: false, amount_reversed: 0 };
    await note(service, payoutId, 'reconciled_from_transfer_group', { stripe_transfer_ref: auth.stripe_transfer_ref }, commandKey);
  } else {
    let res: { ok: boolean; status: number; data: unknown };
    try {
      res = await stripeFetchRaw('/transfers', { method: 'POST', idempotencyKey: auth.idempotency_key, body: auth.body });
    } catch (err) {
      // No HTTP response: DNS/TLS/socket/abort. Stripe MAY have created the
      // transfer. We write NOTHING — the row stays `submitted` and a later tick
      // replays the SAME key (or, past 24h, finds it by transfer_group).
      const verdict = classifyTransferError(err instanceof Error ? err : new Error(String(err)));
      await note(service, payoutId, `stripe_${verdict.class}`, { idempotency_key: auth.idempotency_key, detail: String(err) }, commandKey);
      return { payout_id: payoutId, outcome: 'stripe_error', code: verdict.class, detail: String(err), retryable: verdict.retryable, http: 502 };
    }
    if (!res.ok) {
      const stripeErr = (res.data as { error?: { type?: string; code?: string; message?: string } })?.error;
      const verdict = classifyTransferError({ status: res.status, error: stripeErr });
      await note(service, payoutId, `stripe_${verdict.class}`, {
        idempotency_key: auth.idempotency_key,
        stripe_code: stripeErr?.code ?? null,
        status: res.status,
      }, commandKey);
      if (verdict.page) {
        await captureException('payout-execute:stripe', new Error(`${verdict.class}: ${stripeErr?.message ?? res.status}`), {
          payout_id: payoutId,
          stripe_code: stripeErr?.code ?? '',
        });
      }
      // verdict.writesState is ALWAYS false — see executor.ts.
      return {
        payout_id: payoutId,
        outcome: 'stripe_error',
        code: verdict.class,
        detail: stripeErr?.message ?? `HTTP ${res.status}`,
        retryable: verdict.retryable,
        http: verdict.retryable ? 503 : 409,
      };
    }
    transferObj = res.data as { id?: string; amount?: number; reversed?: boolean; amount_reversed?: number };
  }

  // ── 7. the callback. From here on money HAS moved. ───────────────────────
  const syncPlan = planPayoutStateSync(transferObj, plan.amount_minor);
  if (syncPlan.kind === 'reversed') {
    // Stripe returned a transfer whose money has already come back — fully (it
    // may reverse on its own initiative when an async payment behind the funds
    // fails) or partially. Writing 'paid' here was the defect: `reversed` is
    // false for a partial, so a partially reversed transfer was recorded as a
    // full payment. No status transition; hold and page if partial.
    await note(service, payoutId, 'transfer_reversed_on_arrival', {
      stripe_transfer_ref: syncPlan.reversal.stripe_transfer_ref,
      transfer_amount_minor: syncPlan.reversal.transfer_amount_minor,
      amount_reversed_minor: syncPlan.reversal.amount_reversed_minor,
      obligation_minor: plan.amount_minor,
    }, commandKey);
    return await holdReversedTransfer(service, payoutId, syncPlan.reversal, plan.amount_minor, syncPlan.detail, commandKey, 'post_create');
  }
  if (syncPlan.kind === 'refuse') {
    await note(service, payoutId, syncPlan.code, { detail: syncPlan.detail }, commandKey);
    await captureException('payout-execute:unrecordable-transfer', new Error(`${syncPlan.code}: ${syncPlan.detail}`), { payout_id: payoutId });
    return { payout_id: payoutId, outcome: 'state_sync_deferred', code: syncPlan.code, detail: syncPlan.detail, retryable: true, http: 500 };
  }

  for (const step of syncPlan.steps) {
    const { error: sErr } = await service.rpc('mark_payout_transfer_state', {
      p_payout_id: payoutId,
      p_new_status: step.new_status,          // 'paid'. The only value this module can produce.
      p_stripe_transfer_ref: step.stripe_transfer_ref,
      p_failure_code: step.failure_code,      // always null
      p_command_key: commandKey,
    });
    if (sErr) {
      // MONEY MOVED, DB WRITE FAILED — the dangerous case. Do not retry inline
      // and do not compensate. The row stays where it is; a later tick replays
      // the SAME Stripe key, gets the SAME `tr_…` back and re-runs this
      // callback. `mark_payout_transfer_state` returns noop_replay on an
      // identical terminal (085:1694-1697), so convergence is guaranteed and a
      // double transfer is impossible.
      const verdict = classifyPayoutStateSyncError(sErr.message);
      await note(service, payoutId, `state_sync_${verdict.kind}`, {
        stripe_transfer_ref: step.stripe_transfer_ref,
        error: sErr.message,
      }, commandKey);
      if (verdict.page) {
        await captureException('payout-execute:state-sync', new Error(`mark_payout_transfer_state(paid): ${sErr.message}`), {
          payout_id: payoutId,
          stripe_transfer_ref: step.stripe_transfer_ref,
        });
      }
      if (verdict.kind === 'converged') {
        return { payout_id: payoutId, outcome: 'noop_replay', code: 'converged_elsewhere', stripe_transfer_ref: step.stripe_transfer_ref, retryable: false, http: 200 };
      }
      return {
        payout_id: payoutId,
        outcome: 'state_sync_deferred',
        code: verdict.kind === 'held' ? 'state_sync_payout_held' : verdict.kind === 'conflict' ? 'state_sync_conflict' : 'mark_payout_transfer_state_failed',
        detail: sErr.message,
        stripe_transfer_ref: step.stripe_transfer_ref,
        retryable: verdict.kind === 'retry',
        http: 500,
      };
    }
  }

  console.log('[payout-execute] payout complete:', {
    payout_id: payoutId,
    stripe_transfer_ref: transferObj.id,
    amount_minor: plan.amount_minor,
    settlement_id: plan.settlement_id,
  });
  return { payout_id: payoutId, outcome: 'paid', stripe_transfer_ref: transferObj.id ?? null, http: 200 };
}

// ─────────────────────────────────────────────────────────────────────────────
// Handler — machine-only. There is no human arm.
// ─────────────────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  const headers = responseHeaders(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405, headers);

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice('Bearer '.length) : '';

  let body: Record<string, unknown> = {};
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    body = {};
  }

  // The wrong-payee / wrong-amount guard, applied to the REQUEST first.
  const clean = assertNoClientMoneyReference(body);
  if (!clean.ok) {
    console.warn('[payout-execute] rejected request naming the money:', clean.detail);
    return json({ error: clean.code, detail: clean.detail }, 400, headers);
  }

  // Machine credential only. Both accepted forms are constant-time compared.
  const cronOk = INTERNAL_CRON_SECRET.length > 0 && constantTimeEqual(token, INTERNAL_CRON_SECRET);
  const svcOk = SUPABASE_SERVICE_ROLE_KEY.length > 0 && constantTimeEqual(token, SUPABASE_SERVICE_ROLE_KEY);
  if (!cronOk && !svcOk) return json({ error: 'Unauthorized' }, 401, headers);

  const service = kernelServiceClient();

  try {
    const limit = Number.isInteger(body.limit) ? Math.max(1, Math.min(body.limit as number, 100)) : 25;
    const leaseSeconds = Number.isInteger(body.lease_seconds) ? (body.lease_seconds as number) : 900;

    // ── THE CLAIM. The worker cannot name a subject; the DB hands out work. ──
    const { data, error } = await service.rpc(CLAIM_RPC, { p_limit: limit, p_lease_seconds: leaseSeconds });
    if (error) {
      const missing = error.code === 'PGRST202' || /could not find the function|does not exist/i.test(error.message);
      return json({
        error: missing ? 'claim_rpc_missing' : 'claim_failed',
        detail: missing
          ? `kernel.${CLAIM_RPC}(integer,integer) is not deployed — see docs/phase2/_impl/H8_payout_executor.md`
          : error.message,
      }, missing ? 501 : 500, headers);
    }

    const claims = planPayoutBatch(((data as { payouts?: PayoutClaim[] } | null)?.payouts ?? []), { limit });
    const results: PayoutOutcome[] = [];
    // One failure NEVER blocks the batch (the enforce-transfer-expiry rule).
    for (const c of claims) {
      try {
        // The command key is the DB's, never the worker's: two workers on one
        // payout cannot land under two audit identities.
        results.push(await executeOne(service, c.payout_id, c.command_key, c.execution_mode, {}));
      } catch (err) {
        await captureException('payout-execute:batch', err, { payout_id: c.payout_id });
        results.push({ payout_id: c.payout_id, outcome: 'stripe_error', code: 'unhandled', detail: String(err), retryable: true });
      }
    }
    const counts = results.reduce<Record<string, number>>((acc, r) => {
      acc[r.outcome] = (acc[r.outcome] ?? 0) + 1;
      return acc;
    }, {});
    console.log('[payout-execute] run complete:', { claimed: claims.length, counts });

    // ── SECOND PHASE: the ref-bearing FAILED payout reconcile pass (KE §4.2).
    // Independent of the batch above; one failure here never blocks a reply.
    let reconciled: { claimed: number; results: ReconcileOutcome[] } = { claimed: 0, results: [] };
    try {
      reconciled = await runReconcilePass(service, limit, leaseSeconds);
    } catch (err) {
      await captureException('payout-execute:reconcile-phase', err);
    }

    return json({ status: 'ok', attempted: claims.length, counts, results, reconciled }, 200, headers);
  } catch (err) {
    await captureException('payout-execute', err);
    return json({ error: 'Internal server error' }, 500, headers);
  }
});

// Exported for a future Deno-side integration test; the vitest protocol suite
// targets ./executor.ts because this module's https imports are unloadable there.
export { buildPayoutTransferIdempotencyKey, executeOne };
