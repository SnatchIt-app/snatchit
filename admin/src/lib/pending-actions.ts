import type { OpsFailure, OpsResult } from "@/lib/ops-errors";
import { isRecord, toActions, type OpsAction, type OrderDetail } from "@/lib/types";

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
 * - clear: list_actions answered and nothing unsettled exists → offer the form;
 * - pending: an unsettled action exists → "Already requested" with a link;
 * - unverified: list_actions failed or answered something unrecognisable →
 *   the form stays hidden (fail closed) and the page says why.
 */
export type PendingGuard =
  | { kind: "clear" }
  | { kind: "pending"; action: OpsAction }
  | { kind: "unverified"; failure: OpsFailure | null };

export type MoneyGuards = { release: PendingGuard | null; refund: PendingGuard | null };

/** The items of a list_actions page, or null when the read failed or the payload is not a page. */
function listedRows(res: OpsResult<unknown>): OpsAction[] | null {
  if (!res.ok) return null;
  const v = res.data;
  if (!isRecord(v) || !Array.isArray(v.items)) return null;
  return toActions(v.items);
}

/**
 * Pure decision. `known` are rows the page already holds (order_detail's
 * capped `actions`, and for refunds the uncapped `refund.refund_actions`);
 * `listed` is the list_actions answer. Any unsettled row from any source
 * blocks; only a successful list_actions read with nothing unsettled clears.
 */
export function decidePendingGuard(input: { type: MoneyActionType; subjectId: string; known: OpsAction[]; listed: OpsResult<unknown> }): PendingGuard {
  const rows = listedRows(input.listed);
  const pending = unsettledAction([...(rows ?? []), ...input.known], input.type, input.subjectId);
  if (pending) return { kind: "pending", action: pending };
  if (rows === null) return { kind: "unverified", failure: input.listed.ok ? null : input.listed };
  return { kind: "clear" };
}

export type OpsRead = (fn: string, args: Record<string, unknown>) => Promise<OpsResult<unknown>>;

function safeRead(read: OpsRead, type: MoneyActionType, subjectId: string): Promise<OpsResult<unknown>> {
  return read("list_actions", { p_filters: pendingActionFilters(type, subjectId), p_cursor: null, p_limit: PENDING_LOOKUP_LIMIT }).catch(
    (e: unknown): OpsResult<unknown> => ({ ok: false, kind: "error", message: e instanceof Error ? e.message : "list_actions failed" }),
  );
}

/**
 * Reads list_actions for each money form the page is about to offer and
 * decides its guard. A form that will not be offered gets null (no read).
 */
export async function loadMoneyGuards(read: OpsRead, d: OrderDetail, want: { release: boolean; refund: boolean }): Promise<MoneyGuards> {
  const transferId = d.transfer?.id;
  const paymentId = d.payment?.id;
  const [releaseRes, refundRes] = await Promise.all([
    want.release && transferId ? safeRead(read, "payout_release", transferId) : null,
    want.refund && paymentId ? safeRead(read, "refund_execute", paymentId) : null,
  ]);
  return {
    release: releaseRes && transferId ? decidePendingGuard({ type: "payout_release", subjectId: transferId, known: d.actions, listed: releaseRes }) : null,
    refund:
      refundRes && paymentId
        ? decidePendingGuard({ type: "refund_execute", subjectId: paymentId, known: [...d.refund.refund_actions, ...d.actions], listed: refundRes })
        : null,
  };
}
