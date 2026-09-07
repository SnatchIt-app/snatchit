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
  refunded: "Refunded",
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
  action_type: ACTION_TYPE_LABELS,
};

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
