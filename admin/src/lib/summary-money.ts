import { formatMoney } from "@/lib/format";
import { isRecord, num, str, type JsonRecord } from "@/lib/types";

/**
 * Refund figures in the daily summary. The database (migration 120) reports
 * refund AMOUNTS as unknown — `payments` stores refund status only and Stripe
 * sends `charge.refunded` for partial refunds too — so a summary may carry:
 *   refunded_cents: null, refunded_count, refunded_upper_bound_cents,
 *   refunded_certainty: 'uncertain', refunded_note
 * Summaries stored before 120 carried a numeric `refunded_cents` (Σ total) and
 * no certainty key; `ops.latest_summary()` normalises those on read, but this
 * adapter never trusts a bare number either: a refunded amount is only ever
 * rendered as a labelled upper bound.
 */
export type RefundSummary = {
  /** Reliable count of payments whose status became refunded in the window; null when the summary predates 120. */
  count: number | null;
  /** Σ payments.total over refunded rows — an upper bound, never the refunded amount. */
  upperBoundCents: number | null;
  /** Always "uncertain" unless the DB ever states a known amount explicitly. */
  certainty: "uncertain" | "known";
  knownCents: number | null;
  note: string | null;
  legacy: boolean;
};

const DEFAULT_NOTE =
  "Refunded amount is not available locally: the payment record stores refund status only, and Stripe reports partial refunds with the same event. The figure shown is an upper bound (Σ payment totals over refunded rows).";

export function refundSummary(live: unknown): RefundSummary {
  const l: JsonRecord = isRecord(live) ? live : {};
  const certainty = str(l.refunded_certainty);
  const rawCents = num(l.refunded_cents);
  const upper = num(l.refunded_upper_bound_cents);
  const count = num(l.refunded_count);
  const legacy = l.legacy_normalized === true || (certainty === null && rawCents !== null);

  if (certainty === "known" && rawCents !== null) {
    return { count, upperBoundCents: upper, certainty: "known", knownCents: rawCents, note: str(l.refunded_note), legacy: false };
  }
  // Legacy: a numeric refunded_cents with no certainty key is Σ total, i.e. an
  // upper bound that must not be displayed as the refunded amount.
  const bound = upper !== null ? upper : rawCents;
  return {
    count,
    upperBoundCents: bound,
    certainty: "uncertain",
    knownCents: null,
    note: str(l.refunded_note) ?? DEFAULT_NOTE,
    legacy,
  };
}

/** Text the summary view shows for the refund row — never "$0" for an unknown amount. */
export function refundSummaryText(r: RefundSummary): { headline: string; detail: string | null } {
  if (r.certainty === "known" && r.knownCents !== null) {
    return { headline: formatMoney(r.knownCents), detail: r.count !== null ? `${r.count} payment${r.count === 1 ? "" : "s"}` : null };
  }
  const parts: string[] = [];
  if (r.count !== null) parts.push(`${r.count} payment${r.count === 1 ? "" : "s"} marked refunded`);
  else parts.push("count not recorded (legacy summary)");
  if (r.upperBoundCents !== null) parts.push(`upper bound ${formatMoney(r.upperBoundCents)}`);
  return { headline: "amount not available locally", detail: parts.join(" · ") };
}
