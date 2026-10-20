import type { CaseEvent, JsonRecord } from "@/lib/types";

/**
 * Refund-resolution cases (migration 144) separate CLASSIFYING from CLOSING.
 *
 * Choosing A, B or C records what Stripe actually did; it never changes the
 * case status, and where the classification implies money still owed it raises
 * an OBLIGATION that has to be recorded settled before the case can be
 * resolved or dismissed. The database enforces that in
 * `ops.action_dispatch`'s `case_status` arm — this module only mirrors the
 * same reading of the event log so the console can SHOW an operator what is
 * outstanding, and say why a close would be refused, instead of letting them
 * discover it from a rejection.
 *
 * The mirror is deliberately one-directional: nothing here authorises
 * anything. If this and the database ever disagreed, the database still
 * refuses the close and `ConfirmForm` surfaces its message verbatim — the
 * worst case is a panel that is out of date, never a case closed over money
 * that is still owed.
 */

export const REFUND_CLASSIFICATIONS = [
  {
    value: "A",
    label: "A — a full refund was issued",
    hint: "Stripe shows the whole charge refunded. Nothing is owed unless the payout had already gone out.",
  },
  {
    value: "B",
    label: "B — a partial refund, and fulfilment continues",
    hint: "The buyer keeps the order. The seller is still owed the remainder: raises payout_owed.",
  },
  {
    value: "C",
    label: "C — a partial refund, and the order was cancelled",
    hint: "The order is off. The buyer is still owed the rest: raises remainder_refund_owed.",
  },
] as const;

export type RefundClassification = (typeof REFUND_CLASSIFICATIONS)[number]["value"];

export const OBLIGATION_KINDS = ["payout_owed", "remainder_refund_owed", "reversal_decision"] as const;
export type ObligationKind = (typeof OBLIGATION_KINDS)[number];

export const OBLIGATION_LABELS: Record<string, string> = {
  payout_owed: "Payout owed to the seller",
  remainder_refund_owed: "Remainder refund owed to the buyer",
  reversal_decision: "Reversal decision (the payout had already gone out)",
};

export type Obligation = {
  kind: string;
  settled: boolean;
  note: string | null;
  at: string | null;
  raisedBy: string | null;
};

export type RefundResolutionState = {
  /** The latest recorded classification, or null when nobody has classified yet. */
  classification: string | null;
  classifiedAt: string | null;
  classifiedReason: string | null;
  /** One entry per obligation kind: the latest record for that kind. */
  obligations: Obligation[];
  unsettled: Obligation[];
  /** True when `case_status` -> resolved/dismissed would be accepted. */
  canClose: boolean;
  /** Why a close would be refused right now, in the database's own words. */
  blockedReason: string | null;
};

function data(e: CaseEvent): JsonRecord {
  return e.data && typeof e.data === "object" && !Array.isArray(e.data) ? (e.data as JsonRecord) : {};
}

/** `settled` arrives as a JSON boolean from `to_jsonb`, but tolerate the text form. */
function isSettled(v: unknown): boolean {
  return v === true || v === "true";
}

function text(v: unknown): string | null {
  return typeof v === "string" && v.trim() !== "" ? v : null;
}

/**
 * Read the case's event log the way migration 144's close guard reads it:
 * the LAST `classified` event wins, and for obligations the last record per
 * `kind` wins. `events` is expected in the order `ops.case_detail` returns it
 * (oldest first).
 */
export function refundResolutionState(events: CaseEvent[]): RefundResolutionState {
  let classification: string | null = null;
  let classifiedAt: string | null = null;
  let classifiedReason: string | null = null;
  const byKind = new Map<string, Obligation>();

  for (const e of events) {
    const d = data(e);
    if (e.kind === "classified") {
      const value = text(d.classification);
      if (value) {
        classification = value;
        classifiedAt = e.at ?? null;
        classifiedReason = text(d.reason);
      }
    } else if (e.kind === "obligation_changed") {
      const kind = text(d.kind);
      if (kind) {
        byKind.set(kind, {
          kind,
          settled: isSettled(d.settled),
          note: text(d.note),
          at: e.at ?? null,
          raisedBy: text(d.raised_by),
        });
      }
    }
  }

  const obligations = [...byKind.values()].sort((a, b) => a.kind.localeCompare(b.kind));
  const unsettled = obligations.filter((o) => !o.settled);

  let blockedReason: string | null = null;
  if (classification === null) {
    blockedReason = "classify this case first (case_refund_classify: A, B or C)";
  } else if (unsettled.length > 0) {
    blockedReason = `unsettled obligation(s): ${unsettled.map((o) => o.kind).join(", ")} — record each with case_refund_obligation before closing`;
  }

  return {
    classification,
    classifiedAt,
    classifiedReason,
    obligations,
    unsettled,
    canClose: blockedReason === null,
    blockedReason,
  };
}
