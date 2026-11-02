/**
 * Ticket (primary) order money, as pure functions: the reconciliation read's
 * payload, the manual refund record's receipt, and every refusal in the
 * operator's words. No I/O, so each rule is a unit test.
 *
 * The server side is migration 189 (A), two `ops` functions, EXECUTE
 * `authenticated` only:
 *
 *   ops.primary_reconciliation(p_from date, p_to date) — STABLE. Primary orders
 *     by `kernel.payment_native.linked_at` (UTC calendar day; a NULL bound is
 *     open), each row carrying the payment, the order, the ticket counts and
 *     BOTH refund sides — what this system recorded and what Stripe reports —
 *     plus the attention codes where they disagree.
 *
 *   ops.record_primary_refund(p_order_id, p_amount_minor, p_reason_code,
 *     p_command_key) — VOLATILE. Asserts an operator role at aal2
 *     (platform_admin or platform_support) and the console's pause switch,
 *     then returns `kernel.refund_primary_order`'s own result unchanged.
 *
 * What that action does, and what it does NOT do: it voids the order's
 * voidable tickets so the door refuses them, and writes the refund row. IT
 * MOVES NO MONEY. Refunds stay manual by owner decision: a person refunds the
 * PaymentIntent in the Stripe Dashboard afterwards, and the webhook records
 * that side. Nothing in this module may say otherwise.
 */

type Rec = Record<string, unknown>;
const isRec = (v: unknown): v is Rec => !!v && typeof v === "object" && !Array.isArray(v);
const str = (v: unknown): string | null => (typeof v === "string" && v.length > 0 ? v : null);
const int = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) ? v : null);
const bool = (v: unknown): boolean | null => (v === true ? true : v === false ? false : null);

// ── the reconciliation read ────────────────────────────────────────────────

/** One primary order, with both refund sides as the server computed them. */
export type PrimaryRow = {
  paymentId: string | null;
  orderId: string | null;
  linkedAt: string | null;
  paymentStatus: string | null;
  paymentTotalMinor: number | null;
  stripeLivemode: boolean | null;
  orderStatus: string | null;
  orderTotalMinor: number | null;
  ticketsIssued: number | null;
  ticketsVoided: number | null;
  ticketsAdmitted: number | null;
  ticketsLive: number | null;
  /** What THIS system recorded (kernel.refund). */
  kernelRefundMinor: number | null;
  kernelRefundCount: number | null;
  /** What STRIPE reports (public.payment_refund_state). */
  stripeRefundSucceededMinor: number | null;
  stripeRefundOpenMinor: number | null;
  state: string | null;
  attention: string[];
};

export type PrimaryAttention = {
  code: string;
  severity: "critical" | "warning" | null;
  paymentId: string | null;
  orderId: string | null;
  message: string | null;
};

export type PrimaryReconciliation = {
  from: string | null;
  to: string | null;
  computedAt: string | null;
  currency: string | null;
  basis: string | null;
  count: number | null;
  attentionCount: number | null;
  criticalCount: number | null;
  rows: PrimaryRow[];
  attention: PrimaryAttention[];
};

function toRow(v: unknown): PrimaryRow | null {
  if (!isRec(v)) return null;
  return {
    paymentId: str(v.payment_id),
    orderId: str(v.order_id),
    linkedAt: str(v.linked_at),
    paymentStatus: str(v.payment_status),
    paymentTotalMinor: int(v.payment_total_minor),
    stripeLivemode: bool(v.stripe_livemode),
    orderStatus: str(v.order_status),
    orderTotalMinor: int(v.order_total_minor),
    ticketsIssued: int(v.tickets_issued),
    ticketsVoided: int(v.tickets_voided),
    ticketsAdmitted: int(v.tickets_admitted),
    ticketsLive: int(v.tickets_live),
    kernelRefundMinor: int(v.kernel_refund_minor),
    kernelRefundCount: int(v.kernel_refund_count),
    stripeRefundSucceededMinor: int(v.stripe_refund_succeeded_minor),
    stripeRefundOpenMinor: int(v.stripe_refund_open_minor),
    state: str(v.state),
    attention: Array.isArray(v.attention) ? v.attention.filter((x): x is string => typeof x === "string") : [],
  };
}

function toAttention(v: unknown): PrimaryAttention | null {
  if (!isRec(v)) return null;
  const code = str(v.code);
  if (!code) return null;
  const sev = str(v.severity);
  return { code, severity: sev === "critical" || sev === "warning" ? sev : null, paymentId: str(v.payment_id), orderId: str(v.order_id), message: str(v.message) };
}

/** The whole payload, or null. A partial read is not rendered as a smaller truth. */
export function toPrimaryReconciliation(v: unknown): PrimaryReconciliation | null {
  if (!isRec(v)) return null;
  if (!Array.isArray(v.rows) || !Array.isArray(v.attention)) return null;
  return {
    from: str(v.from),
    to: str(v.to),
    computedAt: str(v.computed_at),
    currency: str(v.currency),
    basis: str(v.basis),
    count: int(v.count),
    attentionCount: int(v.attention_count),
    criticalCount: int(v.critical_count),
    rows: v.rows.map(toRow).filter((r): r is PrimaryRow => r !== null),
    attention: v.attention.map(toAttention).filter((a): a is PrimaryAttention => a !== null),
  };
}

/** Does this order still have tickets a door would admit? The question the critical code is about. */
export function doorWouldStillAdmit(row: PrimaryRow): boolean {
  return (row.ticketsLive ?? 0) > 0;
}

/** Do the two refund sides agree? Unknown on either side is not a disagreement. */
export function refundSidesAgree(row: PrimaryRow): boolean | null {
  const ours = row.kernelRefundMinor;
  const stripe = row.stripeRefundSucceededMinor;
  if (ours === null || stripe === null) return null;
  return ours === stripe;
}

// ── the manual refund record ───────────────────────────────────────────────

/** The console's idempotency key: the server's shape, and never the delegated `req:` form. */
const KEY_SHAPE = /^[A-Za-z0-9._:-]{8,80}$/;

export function isValidCommandKey(key: string): boolean {
  return KEY_SHAPE.test(key) && !key.startsWith("req:");
}

/**
 * A key for one refund record. `crypto.randomUUID()` already matches the
 * server's character class; the prefix makes the console's own actions legible
 * in the audit, and `req:` can never be produced.
 */
export function mintRefundKey(uuid: string): string {
  const key = `pr.${uuid}`;
  return key.slice(0, 80);
}

export type RefundRecordInput = { orderId: string; amountMinor: number; reasonCode: string; commandKey: string };
export type FieldProblem = { field: string; message: string };

/** What the dashboard refuses before sending, so a bad value is not a round trip. */
export function validateRefundInput(input: Partial<RefundRecordInput>, max?: number | null): FieldProblem[] {
  const problems: FieldProblem[] = [];
  if (!input.orderId || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input.orderId)) problems.push({ field: "orderId", message: "Missing or malformed order id." });
  const amt = input.amountMinor;
  if (typeof amt !== "number" || !Number.isInteger(amt) || amt < 1) problems.push({ field: "amountMinor", message: "Enter an amount in cents, at least 1." });
  else if (typeof max === "number" && amt > max) problems.push({ field: "amountMinor", message: `That is more than the order's total (${max} cents).` });
  if (!(input.reasonCode ?? "").trim()) problems.push({ field: "reasonCode", message: "A reason is required; it is recorded against your name." });
  if (!input.commandKey || !isValidCommandKey(input.commandKey)) problems.push({ field: "commandKey", message: "The console's key for this action is malformed." });
  return problems;
}

export type RefundOutcome =
  | { kind: "recorded"; full: boolean; refundId: string | null; voided: number | null; raw: Rec }
  | { kind: "replayed"; refundId: string | null; raw: Rec }
  | { kind: "refused"; reason: string; detail?: string };

/**
 * `kernel.refund_primary_order`'s own receipt, returned unchanged by 189. A
 * status this console does not recognise is NOT read as success.
 */
export function toRefundOutcome(v: unknown): RefundOutcome {
  if (!isRec(v)) return { kind: "refused", reason: "no_receipt", detail: typeof v === "string" ? v : undefined };
  const status = str(v.status);
  const refundId = str(v.refund_id) ?? str(v.id);
  const voided = int(v.voided_atoms) ?? int(v.voided) ?? null;
  if (status === "ok") return { kind: "recorded", full: v.full === true || v.partial === false, refundId, voided, raw: v };
  if (status === "idempotency_replay" || status === "noop_replay" || status === "replay") return { kind: "replayed", refundId, raw: v };
  // An unrecognised status is NOT success, and the operator must be told not to
  // refund in Stripe on the strength of it. The reason is the token so the copy
  // resolves; the server's own word is kept in `detail`.
  return { kind: "refused", reason: "unknown_status", detail: status ?? undefined };
}

/**
 * Every refusal these two verbs raise, in the operator's words. The key is the
 * server's own token; an unknown refusal keeps the server's sentence rather
 * than inventing a cause.
 */
export const REFUND_REFUSAL_COPY: Record<string, string> = {
  step_up_required: "Confirm it is you with your authenticator, then try again.",
  step_up_unavailable: "This session cannot be stepped up. Sign in again and confirm with your authenticator.",
  insufficient_privilege: "Your role cannot record a refund.",
  actions_disabled: "Console actions are paused. Nothing was recorded.",
  invalid_input: "One of the values was refused. Nothing was recorded.",
  not_found: "That order is not something this account can see, or it is not there.",
  over_refund: "That would refund more than the order was paid. Nothing was recorded.",
  not_refundable: "This order is not in a state that can be refunded (only a paid or partially refunded order can be).",
  support_cap: "This amount is above what your role may refund on its own. A platform admin has to record it.",
  atom_not_voidable: "A ticket on this order cannot be voided — it is listed for resale, transferred or frozen. Resolve that first; nothing was recorded.",
  already_refunded: "This order is already fully refunded. Nothing was recorded.",
  no_native_payment: "This order has no linked payment, so there is nothing to refund against.",
  no_receipt: "The server did not confirm the refund. Reload before trying again; do not refund in Stripe until this says recorded.",
  unknown_status: "The server answered with a status this console does not recognise. Treat the refund as NOT recorded and reload.",
};

/** The server's message → a token above. `invalid_input: command key must be …` → `invalid_input`. */
export function refundRefusalToken(message: string | null | undefined): string | null {
  const m = (message ?? "").trim().toLowerCase();
  if (!m) return null;
  for (const token of Object.keys(REFUND_REFUSAL_COPY)) if (m.includes(token)) return token;
  // the kernel's own phrasings that do not carry the token verbatim
  if (/refund.*exceed|exceeds.*paid|over-?refund/.test(m)) return "over_refund";
  if (/listed|transferred|frozen|conflict_locked/.test(m)) return "atom_not_voidable";
  if (/aal2|step.?up/.test(m)) return "step_up_required";
  return null;
}

export function refundRefusalCopy(message: string | null | undefined): string {
  const token = refundRefusalToken(message);
  if (token) return REFUND_REFUSAL_COPY[token];
  const m = (message ?? "").trim();
  return m ? `The server refused this: ${m}` : "The server refused this. Nothing was recorded.";
}

/** The sentence the console shows beside the button, every time. Money is not moved here. */
export const MANUAL_REFUND_NOTE =
  "Recording a refund voids this order's tickets so the door refuses them, and writes the refund against your name. It does not move money: refund the PaymentIntent in the Stripe Dashboard afterwards, and this page will show both sides once the webhook records it.";
