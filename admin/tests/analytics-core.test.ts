import { describe, expect, it } from "vitest";
import {
  buckets,
  dayCount,
  delta,
  figuresFrom,
  formatUsdCompact,
  freshness,
  grainFor,
  isEmptySeries,
  niceTicks,
  previousPeriod,
  refundAmount,
  resolveRange,
  type SeriesPoint,
} from "@/lib/analytics-core";
import { toMoneyOverview } from "@/lib/types";

describe("periods and buckets (UTC, inclusive)", () => {
  it("counts days inclusively and rejects inverted or malformed ranges", () => {
    expect(dayCount("2026-09-01", "2026-09-30")).toBe(30);
    expect(dayCount("2026-09-10", "2026-09-10")).toBe(1);
    expect(dayCount("2026-09-10", "2026-09-01")).toBe(0);
    expect(dayCount("2026-02-30", "2026-03-01")).toBe(0);
  });

  it("uses daily buckets up to 31 days and Monday-start weekly buckets beyond, clipped to the range", () => {
    expect(grainFor("2026-09-01", "2026-10-01")).toBe("day");
    expect(grainFor("2026-08-01", "2026-09-30")).toBe("week");
    const d = buckets("2026-09-12", "2026-09-14");
    expect(d.map((b) => [b.from, b.to])).toEqual([["2026-09-12", "2026-09-12"], ["2026-09-13", "2026-09-13"], ["2026-09-14", "2026-09-14"]]);
    const w = buckets("2026-09-02", "2026-09-20", "week"); // Wed .. Sun
    expect(w.map((b) => [b.from, b.to])).toEqual([["2026-09-02", "2026-09-06"], ["2026-09-07", "2026-09-13"], ["2026-09-14", "2026-09-20"]]);
    // buckets tile the range exactly: no gaps, no overlap
    const days = w.reduce((n, b) => n + dayCount(b.from, b.to), 0);
    expect(days).toBe(dayCount("2026-09-02", "2026-09-20"));
  });

  it("previous period is the same length immediately before", () => {
    expect(previousPeriod("2026-09-01", "2026-09-30")).toEqual({ from: "2026-08-02", to: "2026-08-31" });
  });

  it("resolves presets and custom ranges, clamps the future, defaults to 30 days", () => {
    const now = new Date("2026-09-14T15:00:00Z");
    expect(resolveRange({}, now)).toEqual({ from: "2026-08-16", to: "2026-09-14", preset: "30d", days: 30 });
    expect(resolveRange({ range: "7d" }, now)).toMatchObject({ from: "2026-09-08", to: "2026-09-14", days: 7 });
    expect(resolveRange({ from: "2026-09-01", to: "2026-12-31" }, now)).toMatchObject({ from: "2026-09-01", to: "2026-09-14", preset: null });
    expect(resolveRange({ from: "2020-01-01", to: "2026-09-14" }, now).preset).toBe("30d"); // > 366 days falls back
  });
});

const ZERO = { capturedCents: 0, capturedCount: 0, feesCents: 0, feesCount: 0, refundCount: 0, refundUpperBoundCents: 0, refundKnownCents: null, refundCertainty: "uncertain" as const, releasedCents: 0, releasedCount: 0, pendingCents: 0, pendingCount: 0, bankPayoutsTracked: false };

describe("refund amount has three states and never adds a bound to a known amount", () => {
  it("unknown today: count headline, upper bound kept as 'at most'", () => {
    expect(refundAmount([{ ...ZERO, refundCount: 2, refundUpperBoundCents: 8800 }, { ...ZERO, refundCount: 1, refundUpperBoundCents: 4400 }])).toEqual({ state: "unknown", count: 3, atMostCents: 13200 });
  });
  it("known when every refunded period is exact", () => {
    expect(refundAmount([{ ...ZERO, refundCount: 1, refundKnownCents: 1000, refundCertainty: "exact", refundUpperBoundCents: 10000 }])).toEqual({ state: "known", count: 1, knownCents: 1000 });
  });
  it("mixed keeps the known sum and the bound separate", () => {
    expect(refundAmount([{ ...ZERO, refundCount: 1, refundKnownCents: 1000, refundCertainty: "exact" }, { ...ZERO, refundCount: 1, refundUpperBoundCents: 4400 }])).toEqual({ state: "mixed", count: 2, knownCents: 1000, atMostCents: 4400 });
  });
  it("none when there are no refunds", () => {
    expect(refundAmount([ZERO, ZERO])).toEqual({ state: "none", count: 0 });
  });
});

describe("figures keep the database's definitions and never net measures", () => {
  const payload = {
    from: "2026-09-01",
    to: "2026-09-30",
    computed_at: "2026-09-14T15:00:00Z",
    metrics: {
      gross_captured_volume: { value_cents: 132000, count: 11, basis: "paid_at, UTC calendar day" },
      refunded_volume: { value_cents: null, upper_bound_cents: 4400, count: 1, certainty: "uncertain", basis: "refunded_at" },
      platform_fees_gross: { value_cents: 18640, count: 10, basis: "paid_at" },
      seller_funds_released: { value_cents: 22500, count: 1, basis: "payout_released_at" },
      seller_funds_pending: { value_cents: 26280, count: 4, basis: "now()" },
      bank_payouts: { value_cents: null, count: null, basis: "not_tracked" },
    },
  };
  const f = figuresFrom(toMoneyOverview(payload)!);

  it("reads each measure by key, refunds as count + upper bound only, bank payouts untracked", () => {
    expect(f).toMatchObject({ capturedCents: 132000, feesCents: 18640, refundCount: 1, refundUpperBoundCents: 4400, refundKnownCents: null, refundCertainty: "uncertain", releasedCents: 22500, pendingCents: 26280, bankPayoutsTracked: false });
    expect(Object.keys(f)).not.toContain("refundCents");
  });

  it("an all-zero series is empty; one refund makes it non-empty", () => {
    const zero = ZERO;
    const pts: SeriesPoint[] = [{ bucket: { from: "a", to: "a", label: "a" }, figures: zero }];
    expect(isEmptySeries(pts)).toBe(true);
    expect(isEmptySeries([{ ...pts[0], figures: { ...zero, refundCount: 1 } }])).toBe(false);
  });
});

describe("comparison, axes, formatting, freshness", () => {
  it("delta is honest about zero and unknown baselines", () => {
    expect(delta(150, 100)).toMatchObject({ kind: "up", text: "+50%" });
    expect(delta(50, 100)).toMatchObject({ kind: "down", text: "−50%" });
    expect(delta(5, 0)).toMatchObject({ kind: "new" });
    expect(delta(0, 0)).toMatchObject({ kind: "flat" });
    expect(delta(null, 10)).toMatchObject({ kind: "none" });
  });

  it("nice ticks start at zero, cover the max, and use round steps", () => {
    expect(niceTicks(132000)).toEqual([0, 50000, 100000, 150000]);
    expect(niceTicks(7)).toEqual([0, 2, 4, 6, 8]);
    expect(niceTicks(0)).toEqual([0, 1]);
    expect(niceTicks(1, 4, true)).toEqual([0, 1]); // counts: whole steps, no repeated "1" labels
    expect(niceTicks(7, 4, true)).toEqual([0, 2, 4, 6, 8]);
  });

  it("compact USD from cents", () => {
    expect(formatUsdCompact(95000)).toBe("$950");
    expect(formatUsdCompact(123456)).toBe("$1.2K");
    expect(formatUsdCompact(1500000000)).toBe("$15M");
  });

  it("freshness: missing timestamp is unknown, never fresh", () => {
    const now = new Date("2026-09-14T15:00:00Z");
    expect(freshness(null, now).state).toBe("unknown");
    expect(freshness("2026-09-14T14:55:00Z", now)).toEqual({ state: "fresh", ageMinutes: 5 });
    expect(freshness("2026-09-14T14:00:00Z", now)).toEqual({ state: "stale", ageMinutes: 60 });
  });
});
