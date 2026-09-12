import { describe, expect, it } from "vitest";
import { ACTION_TYPE_LABELS, FUNDS_STATE_LABELS, labelFor, shortId, toDatetimeLocalUtc, formatRatio } from "../src/lib/format";
import { allowedRoles, canRequest, requiresApproval } from "../src/lib/permissions";

describe("labelFor", () => {
  it("maps known vocab values to human labels", () => {
    expect(labelFor("payment", "succeeded")).toBe("Captured");
    expect(labelFor("transfer", "seller_sent")).toBe("Seller marked sent");
    expect(labelFor("funds", "released_to_connected_account")).toMatch(/not a bank payout/);
    expect(labelFor("case", "in_progress")).toBe("In progress");
    expect(labelFor("action", "succeeded_at_provider")).toMatch(/provider/);
    expect(labelFor("approval", "stale")).toMatch(/terms changed/i);
    expect(labelFor("report", "actioned")).toBe("Actioned");
    expect(labelFor("action_type", "refund_execute")).toBe("Execute refund");
  });
  it("never hides an unknown value", () => {
    expect(labelFor("payment", "brand_new_state")).toBe("Brand New State");
    expect(labelFor("funds", null)).toBe("—");
    expect(labelFor("funds", "")).toBe("—");
  });
  it("covers every funds_state the SQL can return", () => {
    for (const k of [
      "not_applicable",
      "refunded",
      "reversed",
      "expired",
      "released_to_connected_account",
      "frozen_dispute",
      "awaiting_delivery",
      "manual_review",
      "held",
      "release_scheduled",
      "awaiting_confirmation",
    ]) {
      expect(FUNDS_STATE_LABELS[k]).toBeTruthy();
    }
  });
  it("covers every action type the engine accepts", () => {
    for (const t of [
      "case_create",
      "case_assign",
      "case_status",
      "case_priority",
      "case_due",
      "case_note",
      "dispute_resolve",
      "payout_release",
      "listing_relist",
      "report_resolve",
      "user_restrict",
      "user_unrestrict",
      "refund_execute",
      "job_retry",
      "setting_set",
    ]) {
      expect(ACTION_TYPE_LABELS[t]).toBeTruthy();
    }
  });
});

describe("small formatters", () => {
  it("shortId", () => {
    expect(shortId("9a900000-0000-4000-8000-000000000005")).toBe("9a900000");
    expect(shortId("pi_test_1")).toBe("pi_test_1");
    expect(shortId(null)).toBe("—");
  });
  it("toDatetimeLocalUtc renders UTC wall clock", () => {
    expect(toDatetimeLocalUtc("2026-09-06T18:45:12Z")).toBe("2026-09-06T18:45");
    expect(toDatetimeLocalUtc("nope")).toBe("");
  });
  it("formatRatio", () => {
    expect(formatRatio(0.5)).toBe("50.0%");
    expect(formatRatio("x")).toBe("—");
  });
});

describe("permissions mirror ops.action_allowed_roles", () => {
  it("money actions are founder-only", () => {
    expect(allowedRoles("payout_release")).toEqual(["platform_admin"]);
    expect(canRequest("platform_risk", "refund_execute")).toBe(false);
    expect(canRequest("platform_admin", "refund_execute")).toBe(true);
  });
  it("risk can resolve disputes and lift restrictions, support cannot", () => {
    expect(canRequest("platform_risk", "dispute_resolve")).toBe(true);
    expect(canRequest("platform_support", "dispute_resolve")).toBe(false);
    expect(canRequest("platform_support", "user_restrict")).toBe(true);
    expect(canRequest("platform_support", "user_unrestrict")).toBe(false);
  });
  it("case work is open to every operator; null role can do nothing", () => {
    expect(canRequest("platform_support", "case_note")).toBe(true);
    expect(canRequest(null, "case_note")).toBe(false);
  });
  it("approval gating", () => {
    expect(requiresApproval("payout_release")).toBe(true);
    expect(requiresApproval("refund_execute")).toBe(true);
    expect(requiresApproval("dispute_resolve")).toBe(false);
  });
});
