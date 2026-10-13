import { describe, expect, it } from "vitest";
import { metricDisplay, NOT_AVAILABLE_LOCALLY } from "../src/lib/metrics";
import { toMoneyOverview } from "../src/lib/types";

const refunded = {
  value_cents: null,
  upper_bound_cents: 123400,
  count: 3,
  currency: "USD",
  from: "2026-08-07",
  to: "2026-09-06",
  definition: "Count of payments with status = refunded.",
  note: "upper_bound_cents = Σ payments.total over refunded rows; the true refunded amount may be lower.",
  certainty: "uncertain" as const,
  source: "public.payments",
  basis: "refunded_at, UTC calendar day",
};

describe("metricDisplay", () => {
  it("renders a null value as 'not available locally' with the note; the bound is secondary only", () => {
    const d = metricDisplay({ ...refunded, tracked: true });
    expect(d.headline).toBe(NOT_AVAILABLE_LOCALLY);
    expect(d.unavailable).toBe(true);
    expect(d.note).toBe(refunded.note);
    expect(d.secondary).toBe("3 rows · upper bound $1,234.00 USD · 2026-08-07 → 2026-09-06");
    expect(d.headline).not.toMatch(/\$/);
  });
  it("renders a known value as the headline", () => {
    const d = metricDisplay({ ...refunded, value_cents: 5000, upper_bound_cents: null, note: null, certainty: "exact" as const, tracked: true });
    expect(d).toEqual({ headline: "$50.00 USD", unavailable: false, secondary: "3 rows · 2026-08-07 → 2026-09-06", note: null });
  });
  it("keeps the not-tracked style", () => {
    const d = metricDisplay({ ...refunded, value_cents: null, count: null, basis: "not_tracked", tracked: false, definition: "Bank payouts are not tracked." });
    expect(d).toEqual({ headline: "not tracked", unavailable: true, secondary: "Bank payouts are not tracked.", note: refunded.note });
  });
  it("point-in-time metrics say so", () => {
    const d = metricDisplay({ ...refunded, value_cents: 1, upper_bound_cents: null, from: null, to: null, basis: "now()", note: null, tracked: true });
    expect(d.secondary).toBe("3 rows · point in time (now)");
  });
});

describe("toMoneyOverview carries the uncertainty fields", () => {
  it("parses refunded_volume with value_cents null + upper bound + note", () => {
    const o = toMoneyOverview({ from: "a", to: "b", metrics: { refunded_volume: refunded, gross_captured_volume: { value_cents: 10, count: 1, basis: "paid_at" } } });
    const r = o?.metrics.find((m) => m.key === "refunded_volume");
    expect(r).toMatchObject({ value_cents: null, upper_bound_cents: 123400, count: 3, certainty: "uncertain", note: refunded.note, tracked: true });
    const g = o?.metrics.find((m) => m.key === "gross_captured_volume");
    expect(g).toMatchObject({ value_cents: 10, upper_bound_cents: null, certainty: null, note: null });
    expect(o?.metrics.map((m) => m.key)).toEqual(["gross_captured_volume", "refunded_volume"]);
  });
});
