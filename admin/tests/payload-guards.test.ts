import { describe, expect, it } from "vitest";
import { toJobHealth, toMoneyOverview, toOrderDetail, toOrderRow, toTimeline, toUserDetail, toSettings } from "../src/lib/types";

describe("payload guards are tolerant", () => {
  it("order_row keeps cents as numbers and parties as {id,display_name}", () => {
    const r = toOrderRow({ payment_id: "p", total: "8250", amount: 7500, buyer: { id: "b", display_name: "buyer_one" }, seller_funds_state: "held", open_cases: 2 });
    expect(r).toMatchObject({ payment_id: "p", total: 8250, amount: 7500, seller_funds_state: "held", open_cases: 2 });
    expect(r?.buyer).toEqual({ id: "b", display_name: "buyer_one" });
    expect(toOrderRow("nope")).toBeNull();
  });

  it("order_detail degrades when sections are missing", () => {
    const d = toOrderDetail({ payment: { id: "p", status: "succeeded", total: 100 }, transfer: null, evidence: { transfer_evidence_path: { bucket: "proof-docs", path: "a/b.jpg" }, x: { bucket: "proof-docs", path: null } } });
    expect(d?.payment?.status).toBe("succeeded");
    expect(d?.transfer).toBeNull();
    expect(d?.cases).toEqual([]);
    expect(d?.evidence.filter((e) => e.path)).toHaveLength(1);
    expect(d?.bank_payout.tracked).toBe(false);
  });

  it("timeline accepts {events} or a bare array", () => {
    expect(toTimeline({ events: [{ at: "2026-01-01T00:00:00Z", source: "payment", kind: "paid", label: "x", ref: null }], note: "n" }).events).toHaveLength(1);
    expect(toTimeline([{ at: "2026-01-01T00:00:00Z" }]).events[0].at).toBe("2026-01-01T00:00:00Z");
    expect(toTimeline(null).events).toEqual([]);
  });

  it("money_overview orders the six tiles and flags not-tracked", () => {
    const m = toMoneyOverview({
      from: "2026-08-07",
      to: "2026-09-06",
      metrics: {
        bank_payouts: { value_cents: null, basis: "not_tracked", definition: "nt" },
        gross_captured_volume: { value_cents: 100, count: 1, currency: "USD", basis: "paid_at", source: "public.payments", definition: "d" },
      },
    });
    expect(m?.metrics.map((x) => x.key)).toEqual(["gross_captured_volume", "bank_payouts"]);
    expect(m?.metrics[1].tracked).toBe(false);
    expect(m?.metrics[0].value_cents).toBe(100);
  });

  it("job_health surfaces cron availability and recent runs", () => {
    const h = toJobHealth({
      cron_jobs: { available: false, note: "no run details", items: [{ jobname: "x", schedule: "* * * * *", active: true }] },
      ops_jobs: [{ job_name: "paid_unsettled", enabled: true, consecutive_failures: 3, recent_runs: [{ status: "failed", error: "boom" }] }],
      webhook_backlog: { unprocessed: 1, failed: 0 },
      notify: { delivery: { failed: 2 }, outbox: {} },
      alerts: [],
    });
    expect(h?.cron.available).toBe(false);
    expect(h?.cron.items[0].jobname).toBe("x");
    expect(h?.ops_jobs[0].recent_runs[0].error).toBe("boom");
    expect(h?.notify.delivery).toEqual({ failed: 2 });
  });

  it("user_detail derives the block flag from seller_risk_scores", () => {
    const u = toUserDetail({ profile: { id: "u", display_name: "seller_three", email_masked: "s***@x" }, seller_risk_score: { is_listing_blocked: true }, restrictions: [] });
    expect(u?.is_listing_blocked).toBe(true);
    expect(u?.email_masked).toBe("s***@x");
    expect(toUserDetail({ profile: { id: "u" } })?.is_listing_blocked).toBe(false);
  });

  it("settings keep the raw jsonb value", () => {
    const s = toSettings([{ key: "refund_execute_enabled", value: false }, { key: "approval_ttl_hours", value: 72 }, { nokey: 1 }]);
    expect(s).toHaveLength(2);
    expect(s[0].value).toBe(false);
    expect(s[1].value).toBe(72);
  });
});
