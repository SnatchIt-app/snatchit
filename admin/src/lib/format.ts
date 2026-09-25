/**
 * Pure formatters — unit-tested. Money is integer cents, USD only (the
 * platform is single-currency); the currency code is always printed so a
 * number is never mistaken for a count.
 */
const usd = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

export function formatMoney(cents: unknown): string {
  if (typeof cents === "string" && cents.trim() !== "" && /^-?\d+$/.test(cents.trim())) {
    cents = Number(cents);
  }
  if (typeof cents !== "number" || !Number.isFinite(cents) || !Number.isInteger(cents)) return "—";
  return `${usd.format(cents / 100)} USD`;
}

export function parseDate(v: unknown): Date | null {
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v;
  if (typeof v !== "string" && typeof v !== "number") return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
}

const pad = (n: number) => String(n).padStart(2, "0");

/** "2026-09-06 18:45 UTC" — explicit basis, no locale ambiguity. */
export function formatUtc(v: unknown, withSeconds = false): string {
  const d = parseDate(v);
  if (!d) return "—";
  const base = `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
  return `${withSeconds ? `${base}:${pad(d.getUTCSeconds())}` : base} UTC`;
}

/** Coarse relative time: "just now" · "4m ago" · "in 3h" · "2d ago". */
export function formatRelative(v: unknown, now: Date = new Date()): string {
  const d = parseDate(v);
  if (!d) return "—";
  const diffMs = d.getTime() - now.getTime();
  const abs = Math.abs(diffMs);
  const future = diffMs > 0;
  const s = Math.round(abs / 1000);
  if (s < 45) return future ? "in <1m" : "just now";
  const m = Math.round(s / 60);
  const unit = m < 60 ? `${m}m` : m < 60 * 24 ? `${Math.round(m / 60)}h` : `${Math.round(m / (60 * 24))}d`;
  return future ? `in ${unit}` : `${unit} ago`;
}

export function humanize(key: string): string {
  return key
    .replace(/_/g, " ")
    .replace(/\b([a-z])/g, (c) => c.toUpperCase())
    .replace(/\bId\b/g, "ID")
    .replace(/\bAt\b/g, "at");
}

// ---------------------------------------------------------------------------
// Status vocabularies — human labels, never colour-only. Unknown values fall
// back to the humanized raw value so nothing is ever hidden.
// ---------------------------------------------------------------------------

export const PAYMENT_STATUS_LABELS: Record<string, string> = {
  pending: "Pending (not captured)",
  processing: "Processing",
  succeeded: "Captured",
  failed: "Failed",
  refunded: "Refund recorded (not confirmed settled)",
  canceled: "Canceled",
  cancelled: "Cancelled",
};

export const TRANSFER_STATUS_LABELS: Record<string, string> = {
  pending: "Awaiting seller delivery",
  seller_sent: "Seller marked sent",
  buyer_confirmed: "Buyer confirmed",
  auto_released: "Auto-released",
  disputed: "Disputed",
  expired: "Expired (seller did not send)",
  reversed: "Reversed",
};

/** ops.funds_state() vocabulary — where the seller's share of a captured payment sits. */
export const FUNDS_STATE_LABELS: Record<string, string> = {
  not_applicable: "Not applicable (no captured payment / no obligation)",
  refunded: "Refunded to buyer",
  reversed: "Reversed",
  expired: "Expired — refund path",
  released_to_connected_account: "Released to connected account (not a bank payout)",
  frozen_dispute: "Frozen — dispute open",
  refund_pending: "Refund owed to buyer — not yet executed",
  awaiting_delivery: "Awaiting seller delivery",
  manual_review: "Manual payout review",
  held: "Held (risk hold)",
  release_scheduled: "Release scheduled — Stripe Transfer pending",
  awaiting_confirmation: "Awaiting buyer confirmation / auto-release",
};

export const PAYOUT_REVIEW_LABELS: Record<string, string> = {
  manual_review: "Manual review",
  held: "Held",
  auto_release: "Auto release",
};

export const CASE_STATUS_LABELS: Record<string, string> = {
  open: "Open",
  in_progress: "In progress",
  waiting: "Waiting",
  resolved: "Resolved",
  dismissed: "Dismissed",
};

export const ACTION_STATE_LABELS: Record<string, string> = {
  requested: "Requested",
  awaiting_approval: "Awaiting approval",
  processing: "Processing",
  succeeded: "Succeeded",
  succeeded_at_provider: "Succeeded at provider — awaiting local webhook",
  failed: "Failed",
  unknown: "Outcome unknown — needs reconciliation",
  rejected: "Rejected",
};

/** Stripe refund.status as mirrored in ops.action.result.refund_status (refund_execute). */
export const REFUND_STATUS_LABELS: Record<string, string> = {
  pending: "Accepted by Stripe, not yet succeeded",
  requires_action: "Requires action at Stripe",
  succeeded: "Succeeded at Stripe",
  failed: "Failed at Stripe",
  canceled: "Canceled at Stripe",
};

/**
 * Honest one-line label for a refund_execute action: the action state, and
 * for `processing` the provider's own status (pending / requires_action is
 * NOT success). Never says "succeeded" unless the state does.
 */
export function refundStateLabel(state: unknown, refundStatus: unknown): string {
  const s = state === null || state === undefined ? "" : String(state);
  const rs = refundStatus === null || refundStatus === undefined ? "" : String(refundStatus);
  if (s === "processing") {
    if (rs && REFUND_STATUS_LABELS[rs]) return `Processing — ${REFUND_STATUS_LABELS[rs].toLowerCase()}`;
    if (rs) return `Processing — provider status ${humanize(rs).toLowerCase()}`;
    return "Processing — outcome not yet known";
  }
  return labelFor("action", s);
}

/** ops.executor_claim() refusal reasons surfaced by ops-refund-execute as HTTP 409 {reason}. */
export const EXECUTOR_REFUSAL_LABELS: Record<string, string> = {
  disabled: "refund execution is disabled (ops.setting refund_execute_enabled = false)",
  paused: "console actions are paused by a founder (ops.setting actions_enabled = false)",
  claim_busy: "another executor run holds the lease — wait for it to finish, then retry",
  approval_missing: "no approved second-founder decision exists for this action",
  approval_stale: "the approval no longer matches the action's terms — a fresh approval is needed",
  terminal: "the action is already in a terminal state — nothing to resume",
  succeeded_at_provider: "Stripe already succeeded — the local record completes when the webhook lands",
  not_executable: "the action is not in a resumable state",
  not_found: "no such action",
  wrong_type: "not a refund_execute action",
  payment_missing: "the payment row no longer exists",
  already_refunded_locally: "the payment is already refunded locally",
  payment_not_refundable: "the payment is not in a refundable state",
};

export function executorRefusalLabel(reason: unknown): string {
  if (reason === null || reason === undefined || reason === "") return "refused";
  const r = String(reason);
  return EXECUTOR_REFUSAL_LABELS[r] ?? humanize(r).toLowerCase();
}

export const APPROVAL_STATE_LABELS: Record<string, string> = {
  pending: "Pending",
  approved: "Approved",
  denied: "Denied",
  expired: "Expired",
  stale: "Stale (terms changed)",
  cancelled: "Cancelled",
};

export const REPORT_STATUS_LABELS: Record<string, string> = {
  pending: "Pending",
  reviewing: "Reviewing",
  actioned: "Actioned",
  dismissed: "Dismissed",
};

export const DISPUTE_OUTCOME_LABELS: Record<string, string> = {
  seller_win: "Seller wins (payout path unfrozen)",
  buyer_win: "Buyer wins (refund required — not executed here)",
  partial_refund: "Partial refund (refund required — not executed here)",
};

/**
 * `transfers.dispute_resolution` — the OPERATOR'S decision, never a money fact.
 *
 * `resolved_seller_paid` is a standing misnomer: 065 writes the decision and clears
 * `disputed_at`; the payout happens later and only if `claim_payout_attempt` admits it
 * (a live `payout_hold_until` or `manual_review` refuses it, migration 148), the sweep
 * may not have run, the Stripe transfer can fail, and `flag_payout_reversal_required`
 * can owe it back afterwards. Payout evidence is `payout_released_at` with `reversed`
 * taking precedence (A's ratified ruling 2) — never this column.
 */
export const DISPUTE_RESOLUTION_LABELS: Record<string, string> = {
  resolved_seller_paid: "Resolved — seller (decision; payout not implied)",
  resolved_buyer_refunded: "Resolved — buyer (refund required)",
  resolved_partial_refund: "Resolved — partial refund (refund required)",
};

export const ACTION_TYPE_LABELS: Record<string, string> = {
  case_create: "Create case",
  case_assign: "Assign case",
  case_status: "Set case status",
  case_priority: "Set case priority",
  case_due: "Set case due",
  case_note: "Add case note",
  dispute_resolve: "Resolve dispute",
  payout_release: "Release held payout",
  listing_relist: "Relist listing",
  report_resolve: "Resolve report",
  user_restrict: "Block listing creation",
  user_unrestrict: "Unblock listing creation",
  refund_execute: "Execute refund",
  job_retry: "Run job now",
  setting_set: "Change setting",
};

export type Vocab =
  | "payment"
  | "transfer"
  | "funds"
  | "payout_review"
  | "case"
  | "action"
  | "approval"
  | "report"
  | "dispute_outcome"
  | "dispute_resolution"
  | "action_type";

const VOCABS: Record<Vocab, Record<string, string>> = {
  payment: PAYMENT_STATUS_LABELS,
  transfer: TRANSFER_STATUS_LABELS,
  funds: FUNDS_STATE_LABELS,
  payout_review: PAYOUT_REVIEW_LABELS,
  case: CASE_STATUS_LABELS,
  action: ACTION_STATE_LABELS,
  approval: APPROVAL_STATE_LABELS,
  report: REPORT_STATUS_LABELS,
  dispute_outcome: DISPUTE_OUTCOME_LABELS,
  dispute_resolution: DISPUTE_RESOLUTION_LABELS,
  action_type: ACTION_TYPE_LABELS,
};

/**
 * Row-aware transfer state. `TRANSFER_STATUS_LABELS` maps a bare status and therefore
 * CANNOT tell a buyer's confirmation from an operator's seller-win decision: 065 sets
 * status `buyer_confirmed` while leaving `buyer_confirmed_at` NULL. The only record that
 * the buyer confirmed receipt is that timestamp, written by `confirm_transfer_received`
 * (0550:204, and 002:228-229 before it — both eras set status and timestamp together).
 * Use this wherever the label is a claim about what happened; the bare map stays correct
 * for a filter control, which selects on the status column itself.
 */
export function transferStateLabel(row: {
  status?: string | null;
  buyer_confirmed_at?: string | null;
  dispute_resolution?: string | null;
}): string {
  const status = row.status ?? "";
  if (status !== "buyer_confirmed") return labelFor("transfer", status);
  if (row.buyer_confirmed_at) return "Buyer confirmed";
  if (row.dispute_resolution === "resolved_seller_paid") return "Resolved — seller (no buyer confirmation)";
  return "Confirmed status, no confirmation record";
}

/**
 * Payout state for a transfer row. Ratified ruling 2: `payout_released_at` is the
 * evidence — every writer sets it with `stripe_transfer_id` and only after Stripe
 * accepted the transfer — and `reversed` takes precedence over it, so a reversed
 * transfer must never read as released. Never the word "received": what is observed is
 * a transfer to the seller's connected account, not money reaching their bank.
 *
 * `status = 'reversed'` is written by `mark_transfer_reversed` (0561:114-127) from Stripe's
 * own `transfer.reversed` event, so the reversal has ALREADY happened — nothing is owed
 * back. Money owed back is `payout_attempts.state = 'reversal_required'`, a different fact
 * from a different writer. The reversed amount is not stored and a reversal can be partial,
 * so no amount is implied here (wording table §2d).
 */
export function payoutStateLabel(row: {
  status?: string | null;
  payout_released_at?: string | null;
  payout_review_status?: string | null;
}): string {
  if (row.status === "reversed") return "Reversed (a reversal was recorded; amount not stored)";
  if (row.payout_released_at) return "Released to connected account";
  if (row.payout_review_status === "manual_review") return "Not released — manual review";
  if (row.payout_review_status === "held") return "Not released — held";
  return "Not released";
}

/**
 * Provenance of `payout_decisions.buyer_confirmed`, per WRITER. The flag means different
 * things depending on who wrote it and when, so the console annotates rather than rewrites.
 *
 * Fixed by 149 + v38 — these derived the flag from `transfers.status`, so a seller-win row
 * recorded a confirmation that never happened:
 *   - `edge:confirm-and-release` (a1/a2) — fixed when **v38 deployed**, not when the
 *     migration applied. The platform recorded the switchover at 2026-09-24T20:31:20.378Z
 *     (D's own W2 read); A's deploy step completed at 20:31:30Z. The later value is used on
 *     purpose: a v37 invocation already in flight could still write after the switchover, and
 *     over-annotating a few seconds of good rows only asks an operator to look twice, while
 *     under-annotating lets a false record pass as trustworthy.
 *   - `edge:stripe-webhook` (a4) and the `record_payout_attempt_result` reversal_required row
 *     (a3) — fixed when migration 149 applied, 2026-09-24T20:31:03Z.
 *
 * NOT affected, and not annotated: `cron:enforce-transfer-expiry`'s risk-tiering rows and
 * `admin:<uuid>` releases (039:304 / 0551:94, which leave the column's `false` default). Both
 * run only on `seller_sent` rows, where `false` is simply accurate.
 *
 * Never fixed, and annotated with NO time boundary: `edge:enforce-transfer-expiry`
 * (F-PD-EXPIRY-1, A's finding 2026-09-25). `recordManualReviewOnce` writes a literal `false`
 * while serving the Phase 2b sweep, whose rows are `buyer_confirmed` / `auto_released` — so a
 * manual-review decision on a genuinely confirmed row records "not confirmed". A owns the
 * source fix; until it lands every row from this writer is unreliable on this column.
 */
/**
 * `confirm-and-release` v38 became current at the platform's own switchover; A's deploy step
 * completed 10 s later. Neither instant bounds the risk on its own: a v37 invocation that
 * started just before the switchover may still be running, and a Supabase edge function's
 * wall-clock limit on a paid plan is 400 s (supabase.com/docs/guides/functions/limits; the
 * project is Pro per the 2026-09-22 preflight). So there are three regions, not two, and the
 * middle one is reported as uncertain rather than guessed either way.
 */
export const CONFIRM_AND_RELEASE_SWITCHOVER_AT = "2026-09-24T20:31:20.378Z";
export const CONFIRM_AND_RELEASE_DRAIN_END_AT = "2026-09-24T20:38:00.378Z"; // switchover + 400 s

/**
 * Migration 149 applied here. A SQL function replacement is transactional, so the SQL writers
 * flip atomically and need no drain window; the only residual is a transaction whose `now()`
 * predates the commit that installed the new body, which is negligible.
 */
export const SQL_WRITER_FIX_AT = "2026-09-24T20:31:03Z";

export type DecisionProvenance =
  | "reliable"
  | "status_derived"
  | "maybe_status_derived"
  | "never_reads_confirmation";

/**
 * What a stored `buyer_confirmed` flag is worth, from the row itself.
 *
 * ORDER MATTERS, and not in the order the writers were discovered:
 *
 * 1. `edge:enforce-transfer-expiry` first. `recordManualReviewOnce` writes a literal `false`
 *    and TWO of its evidence objects carry `attempt_id` (index.ts:976-977 and :984), so the
 *    a3 test below would otherwise capture those rows and hand them a boundary — silently
 *    un-annotating the one writer that is wrong at every time (F-PD-EXPIRY-1).
 * 2. Then a3, by the row's own evidence rather than its actor. `record_payout_attempt_result`
 *    writes `v_a.actor` — the ATTEMPT's actor — so an a3 row reads `cron:enforce-transfer-expiry`
 *    or `edge:confirm-and-release` depending on who claimed it (payouts.ts:363;
 *    confirm-and-release:407, enforce-transfer-expiry:929), never `edge:stripe-webhook`.
 *    Classifying it by actor would let a pre-fix a3 row from the cron pass as reliable.
 *    Its own signature is `decision = 'manual_review'` with `evidence.attempt_id`
 *    (20260924120000:139-141), and it is a SQL writer, so it takes the migration boundary.
 * 3. Then the remaining actor-keyed writers.
 *
 * An affected writer with an unreadable timestamp is treated as status-derived: the safe
 * direction is to ask the operator to look.
 */
export function decisionProvenance(
  actor: string | null | undefined,
  decidedAt: string | null | undefined,
  row?: { decision?: unknown; evidence?: unknown },
): DecisionProvenance {
  const a = actor ?? "";
  if (a === "edge:enforce-transfer-expiry") return "never_reads_confirmation";

  const at = decidedAt ? Date.parse(decidedAt) : NaN;
  const isA3 =
    row?.decision === "manual_review" &&
    typeof row?.evidence === "object" && row.evidence !== null &&
    "attempt_id" in (row.evidence as Record<string, unknown>);

  if (isA3) {
    if (!Number.isFinite(at)) return "status_derived";
    return at < Date.parse(SQL_WRITER_FIX_AT) ? "status_derived" : "reliable";
  }

  if (a === "edge:stripe-webhook") {
    if (!Number.isFinite(at)) return "status_derived";
    return at < Date.parse(SQL_WRITER_FIX_AT) ? "status_derived" : "reliable";
  }

  if (a === "edge:confirm-and-release") {
    if (!Number.isFinite(at)) return "status_derived";
    if (at < Date.parse(CONFIRM_AND_RELEASE_SWITCHOVER_AT)) return "status_derived";
    if (at < Date.parse(CONFIRM_AND_RELEASE_DRAIN_END_AT)) return "maybe_status_derived";
    return "reliable";
  }

  return "reliable";
}

/** The operator-facing caveat for a flag, or null when the flag stands on its own. */
export function decisionProvenanceNote(
  actor: string | null | undefined,
  decidedAt: string | null | undefined,
  row?: { decision?: unknown; evidence?: unknown },
): string | null {
  switch (decisionProvenance(actor, decidedAt, row)) {
    case "status_derived":
      return "recorded before the 2026-09-24 fix (derived from status, not the confirmation record)";
    case "maybe_status_derived":
      return "recorded while the fixed function was rolling out — may have been written by the pre-fix version";
    case "never_reads_confirmation":
      return "this writer does not read the confirmation record (always recorded false)";
    default:
      return null;
  }
}

/** Human label for a status value; falls back to the humanized raw value; "—" for empty. */
export function labelFor(vocab: Vocab, value: unknown): string {
  if (value === null || value === undefined || value === "") return "—";
  const s = String(value);
  return VOCABS[vocab][s] ?? humanize(s);
}

/** Short id for dense tables: first 8 hex chars of a uuid, else the value itself. */
export function shortId(v: unknown): string {
  if (typeof v !== "string" || v === "") return "—";
  return /^[0-9a-f-]{36}$/i.test(v) ? v.slice(0, 8) : v;
}

/** ISO/timestamptz → value for <input type="datetime-local"> (UTC wall clock). */
export function toDatetimeLocalUtc(v: unknown): string {
  const d = parseDate(v);
  if (!d) return "";
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}T${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
}

/** Percentage from a 0..1 ratio, one decimal. */
export function formatRatio(v: unknown): string {
  if (typeof v !== "number" || !Number.isFinite(v)) return "—";
  return `${(v * 100).toFixed(1)}%`;
}
