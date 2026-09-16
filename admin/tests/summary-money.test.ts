import { describe, expect, it } from "vitest";
import { refundSummary, refundSummaryText } from "@/lib/summary-money";

describe("daily summary refund semantics (migration 120)", () => {
  it("post-120 shape: null amount, count and upper bound, never $0 or the total as the headline", () => {
    const r = refundSummary({ refunded_cents: null, refunded_count: 1, refunded_upper_bound_cents: 10000, refunded_certainty: "uncertain" });
    expect(r.certainty).toBe("uncertain");
    expect(r.knownCents).toBeNull();
    const t = refundSummaryText(r);
    expect(t.headline).toBe("amount not available locally");
    expect(t.detail).toContain("1 payment marked refunded");
    expect(t.detail).toContain("upper bound $100.00");
    expect(t.headline).not.toMatch(/\$/);
  });

  it("a $100 payment refunded after an external $10 partial refund is never shown as $100 refunded", () => {
    const t = refundSummaryText(refundSummary({ refunded_cents: null, refunded_count: 1, refunded_upper_bound_cents: 10000, refunded_certainty: "uncertain" }));
    expect(`${t.headline} ${t.detail}`).not.toMatch(/^\$100\.00/);
    expect(t.headline).not.toContain("$100.00");
  });

  it("legacy stored summary (numeric refunded_cents, no certainty) is treated as an upper bound, flagged legacy, count unknown", () => {
    const r = refundSummary({ refunded_cents: 10000, captured_cents: 20000 });
    expect(r.legacy).toBe(true);
    expect(r.certainty).toBe("uncertain");
    expect(r.knownCents).toBeNull();
    expect(r.upperBoundCents).toBe(10000);
    const t = refundSummaryText(r);
    expect(t.headline).toBe("amount not available locally");
    expect(t.detail).toContain("count not recorded (legacy summary)");
    expect(t.detail).toContain("upper bound $100.00");
  });

  it("legacy summary normalised by the database keeps the legacy flag and bound", () => {
    const r = refundSummary({ refunded_cents: null, refunded_upper_bound_cents: 4400, refunded_count: null, refunded_certainty: "uncertain", legacy_normalized: true });
    expect(r.legacy).toBe(true);
    expect(refundSummaryText(r).detail).toContain("upper bound $44.00");
  });

  it("empty window: zero count, zero upper bound, still no amount claimed", () => {
    const t = refundSummaryText(refundSummary({ refunded_cents: null, refunded_count: 0, refunded_upper_bound_cents: 0, refunded_certainty: "uncertain" }));
    expect(t.headline).toBe("amount not available locally");
    expect(t.detail).toContain("0 payments marked refunded"); expect(t.detail).toContain("upper bound $0.00");
  });

  it("missing block entirely → uncertain with no numbers, no $0", () => {
    const t = refundSummaryText(refundSummary(undefined));
    expect(t.headline).toBe("amount not available locally");
    expect(t.detail).toBe("count not recorded (legacy summary)");
  });

  it("only an explicitly 'known' certainty may render a money headline", () => {
    const t = refundSummaryText(refundSummary({ refunded_cents: 1234, refunded_count: 2, refunded_certainty: "known" }));
    expect(t.headline).toBe("$12.34 USD");
    expect(t.detail).toBe("2 payments");
  });
});
