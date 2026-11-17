import type { OpsFailure, OpsResult } from "@/lib/ops-errors";
import { isRecord, num, toActions, type OpsAction, type OrderDetail } from "@/lib/types";

/**
 * Action states that are not settled (the ops.action state CHECK, 115:248-250).
 * While one exists for a payment or transfer, a second request of the same
 * kind must not be parked from the order page: "unknown" and
 * "succeeded_at_provider" count too — a refund may already have happened at
 * Stripe.
 */
export const UNSETTLED_STATES = ["requested", "awaiting_approval", "processing", "succeeded_at_provider", "unknown"] as const;
const UNSETTLED = new Set<string>(UNSETTLED_STATES);

/** The two money verbs the order page can request, and the subject each one acts on. */
export const MONEY_ACTION_SUBJECT = { payout_release: "transfer", refund_execute: "payment" } as const;
export type MoneyActionType = keyof typeof MONEY_ACTION_SUBJECT;

/** The newest unsettled action of this type on this subject, from whatever rows the console read. */
export function unsettledAction(actions: OpsAction[], type: string, subjectId: string): OpsAction | null {
  const seen = new Set<string>();
  const open = actions.filter((a) => {
    if (a.action_type !== type || a.subject_id !== subjectId || !UNSETTLED.has(a.state ?? "")) return false;
    const k = a.id ?? `${a.requested_at}`;
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
  open.sort((x, y) => String(y.requested_at ?? "").localeCompare(String(x.requested_at ?? "")));
  return open[0] ?? null;
}

/**
 * ops.list_actions filters (116:1410) for "any unsettled <type> on this
 * subject". Arrays, because list_actions reads state/action_type with
 * ops.jsonb_text_array and ignores a non-array.
 */
export function pendingActionFilters(type: MoneyActionType, subjectId: string) {
  return { action_type: [type], subject_kind: MONEY_ACTION_SUBJECT[type], subject_id: subjectId, state: [...UNSETTLED_STATES] };
}

/** One row is enough to block; a few leave room without paging. */
export const PENDING_LOOKUP_LIMIT = 5;

/**
 * What the order page may show for one money verb:
 * - clear: list_actions answered an empty page and no row the page holds is
 *   unsettled → offer the form;
 * - pending: an unsettled action exists, or list_actions returned any row →
 *   "Already requested" with a link;
 * - unverified: list_actions failed or answered something unrecognisable →
 *   the form stays hidden (fail closed) and the page says why.
 */
export type PendingGuard =
  | { kind: "clear" }
  | { kind: "pending"; action: OpsAction }
  | { kind: "unverified"; failure: OpsFailure | null };

export type MoneyGuards = { release: PendingGuard | null; refund: PendingGuard | null };

type ListedPage = {
  /** The items that parse as action rows. */
  rows: OpsAction[];
  /** How many items the page carried, parseable or not. */
  itemCount: number;
  countHint: number | null;
};

/** A list_actions page, or null when the read failed or the payload is not a page. */
function listedPage(res: OpsResult<unknown>): ListedPage | null {
  if (!res.ok) return null;
  const v = res.data;
  if (!isRecord(v) || !Array.isArray(v.items)) return null;
  return { rows: toActions(v.items), itemCount: v.items.length, countHint: num(v.count_hint) };
}

/**
 * Pure decision. `known` are rows the page already holds (order_detail's
 * capped `actions`, and for refunds the uncapped `refund.refund_actions`);
 * `listed` is the list_actions answer.
 *
 * - An unsettled row of this type on this subject, from any source → pending.
 * - list_actions failed or answered something that is not a page → unverified.
 * - list_actions returned any row at all → pending. The server already
 *   filtered by type, subject and the unsettled states (116:1428-1433), so a
 *   row the exact-string match above misses (a subject_id in another case, a
 *   reshaped row) is still an unsettled duplicate.
 * - Items or count_hint > 0 but no usable row → unverified (nothing to link).
 * - Only an empty page clears.
 */
export function decidePendingGuard(input: { type: MoneyActionType; subjectId: string; known: OpsAction[]; listed: OpsResult<unknown> }): PendingGuard {
  const page = listedPage(input.listed);
  const pending = unsettledAction([...(page?.rows ?? []), ...input.known], input.type, input.subjectId);
  if (pending) return { kind: "pending", action: pending };
  if (page === null) return { kind: "unverified", failure: input.listed.ok ? null : input.listed };
  if (page.rows.length > 0) return { kind: "pending", action: page.rows[0] };
  if (page.itemCount > 0 || (page.countHint ?? 0) > 0) return { kind: "unverified", failure: null };
  return { kind: "clear" };
}

export type OpsRead = (fn: string, args: Record<string, unknown>) => Promise<OpsResult<unknown>>;

function safeRead(read: OpsRead, type: MoneyActionType, subjectId: string): Promise<OpsResult<unknown>> {
  return read("list_actions", { p_filters: pendingActionFilters(type, subjectId), p_cursor: null, p_limit: PENDING_LOOKUP_LIMIT }).catch(
    (e: unknown): OpsResult<unknown> => ({ ok: false, kind: "error", message: e instanceof Error ? e.message : "list_actions failed" }),
  );
}

/**
 * Money on an order is one subject: a payout release on the transfer and a
 * refund of the payment must not both be parked (check-then-act across two
 * tabs or two founders). list_actions filters by one action_type, so each
 * form's guard folds the other verb's answer in:
 * - either pending → pending, carrying the blocking action so the page can
 *   name it (the form's own type is preferred when both are pending);
 * - otherwise either unverified → unverified (a failed read on the other type
 *   hides this form too — fail closed);
 * - only both clear → clear.
 * `other` is null when that verb has no subject row (no transfer): nothing to
 * read, so it never blocks. `own` null means this form is not offered.
 */
export function combineMoneyGuards(own: PendingGuard | null, other: PendingGuard | null): PendingGuard | null {
  if (!own) return null;
  if (own.kind === "pending") return own;
  if (other?.kind === "pending") return other;
  if (own.kind === "unverified") return own;
  if (other?.kind === "unverified") return other;
  return own;
}

/** A subject row the page holds but cannot address (no id) can never be checked. */
const UNADDRESSABLE: PendingGuard = { kind: "unverified", failure: null };

/**
 * Reads list_actions for BOTH money types on this order whenever either money
 * form is about to be offered, decides each guard, and folds the other type
 * in (combineMoneyGuards). A form that will not be offered gets null; when no
 * money form is offered nothing is read.
 */
export async function loadMoneyGuards(read: OpsRead, d: OrderDetail, want: { release: boolean; refund: boolean }): Promise<MoneyGuards> {
  if (!want.release && !want.refund) return { release: null, refund: null };
  const transferId = d.transfer?.id;
  const paymentId = d.payment?.id;
  const [releaseRes, refundRes] = await Promise.all([
    transferId ? safeRead(read, "payout_release", transferId) : null,
    paymentId ? safeRead(read, "refund_execute", paymentId) : null,
  ]);
  // Per type, before the fold: null only when there is no row of that kind at all.
  const release: PendingGuard | null =
    releaseRes && transferId ? decidePendingGuard({ type: "payout_release", subjectId: transferId, known: d.actions, listed: releaseRes }) : d.transfer ? UNADDRESSABLE : null;
  const refund: PendingGuard | null =
    refundRes && paymentId
      ? decidePendingGuard({ type: "refund_execute", subjectId: paymentId, known: [...d.refund.refund_actions, ...d.actions], listed: refundRes })
      : d.payment
        ? UNADDRESSABLE
        : null;
  return {
    release: want.release ? combineMoneyGuards(release, refund) : null,
    refund: want.refund ? combineMoneyGuards(refund, release) : null,
  };
}
