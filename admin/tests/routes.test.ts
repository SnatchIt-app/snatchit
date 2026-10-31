import { describe, expect, it } from "vitest";
import { isUuid, metricHref, subjectHref, timelineRefHref } from "../src/lib/routes";

const U = "9a900000-0000-4000-8000-000000000005";

describe("subjectHref", () => {
  it("routes every uuid-addressed kind to its detail page", () => {
    expect(subjectHref("payment", U)).toBe(`/orders/${U}`);
    expect(subjectHref("order", U)).toBe(`/orders/${U}`);
    expect(subjectHref("transfer", U)).toBe(`/transfers/${U}`);
    expect(subjectHref("case", U)).toBe(`/cases/${U}`);
    expect(subjectHref("user", U)).toBe(`/users/${U}`);
    expect(subjectHref("seller", U)).toBe(`/users/${U}`);
    expect(subjectHref("listing", U)).toBe(`/marketplace/${U}`);
    expect(subjectHref("action", U)).toBe(`/actions/${U}`);
    expect(subjectHref("report", U)).toBe(`/reports#report-${U}`);
    expect(subjectHref("dispute", "dp_test_1")).toBe("/search?q=dp_test_1");
  });

  it("routes ref-addressed kinds by subject_ref and is case-insensitive", () => {
    expect(subjectHref("job", null, "daily_summary")).toBe("/system#job-daily_summary");
    expect(subjectHref("setting", null, "refund_execute_enabled")).toBe("/system#setting-refund_execute_enabled");
    expect(subjectHref("webhook_event", null, "evt_1")).toBe("/system#webhooks");
    expect(subjectHref("PAYMENT", U)).toBe(`/orders/${U}`);
  });

  it("returns null for unknown kinds or missing ids", () => {
    expect(subjectHref("payment", null)).toBeNull();
    expect(subjectHref("none", U)).toBeNull();
    expect(subjectHref(undefined, undefined)).toBeNull();
  });
});

describe("metricHref", () => {
  it("sends every Today tile somewhere useful", () => {
    expect(metricHref("open_cases")).toBe("/cases");
    expect(metricHref("refunds_pending")).toBe("/cases?case_type=refund_pending");
    expect(metricHref("reports_pending")).toBe("/reports?status=pending");
    expect(metricHref("approvals_pending")).toBe("/system#approvals");
    expect(metricHref("payout_review")).toContain("/money");
    expect(metricHref("something_new")).toBeNull();
  });
});

describe("timelineRefHref", () => {
  it("routes uuid refs by source", () => {
    expect(timelineRefHref("payment", "created", U)).toBe(`/orders/${U}`);
    expect(timelineRefHref("transfer", "created", U)).toBe(`/transfers/${U}`);
    expect(timelineRefHref("transfer", "dispute_resolved", U)).toBe(`/users/${U}`);
    expect(timelineRefHref("ops_action", "requested", U)).toBe(`/actions/${U}`);
    expect(timelineRefHref("ops_case", "detected", U)).toBe(`/cases/${U}`);
    expect(timelineRefHref("notification", "x", U)).toBeNull();
  });
  it("sends Stripe ids to search and leaves storage paths alone", () => {
    expect(timelineRefHref("payment", "paid", "pi_test_1")).toBe("/search?q=pi_test_1");
    expect(timelineRefHref("transfer", "seller_sent", "harness/evidence/t05.jpg")).toBeNull();
    expect(timelineRefHref("payment", "paid", null)).toBeNull();
  });
  it("isUuid", () => {
    expect(isUuid(U)).toBe(true);
    expect(isUuid("pi_x")).toBe(false);
  });
});
