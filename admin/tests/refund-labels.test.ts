import { describe, expect, it } from "vitest";
import { ACTION_STATE_LABELS, executorRefusalLabel, labelFor, refundStateLabel, REFUND_STATUS_LABELS } from "../src/lib/format";
import { refundStatusOf, toActionOutcome } from "../src/lib/types";

describe("refund state labels are honest", () => {
  it("processing + provider status is never called success", () => {
    expect(refundStateLabel("processing", "pending")).toBe("Processing — accepted by stripe, not yet succeeded");
    expect(refundStateLabel("processing", "requires_action")).toBe("Processing — requires action at stripe");
    expect(refundStateLabel("processing", null)).toBe("Processing — outcome not yet known");
    expect(refundStateLabel("processing", "weird_new")).toBe("Processing — provider status weird new");
    for (const rs of ["pending", "requires_action", null, "weird_new"]) {
      expect(refundStateLabel("processing", rs).toLowerCase()).not.toMatch(/^succeeded/);
    }
  });
  it("succeeded_at_provider and unknown carry the required wording", () => {
    expect(ACTION_STATE_LABELS.succeeded_at_provider).toBe("Succeeded at provider — awaiting local webhook");
    expect(ACTION_STATE_LABELS.unknown).toBe("Outcome unknown — needs reconciliation");
    expect(refundStateLabel("succeeded_at_provider", "succeeded")).toBe("Succeeded at provider — awaiting local webhook");
    expect(refundStateLabel("unknown", null)).toBe("Outcome unknown — needs reconciliation");
    expect(labelFor("action", "succeeded")).toBe("Succeeded");
  });
  it("provider status vocabulary", () => {
    expect(REFUND_STATUS_LABELS.pending).toMatch(/not yet succeeded/i);
    expect(REFUND_STATUS_LABELS.requires_action).toMatch(/requires action/i);
  });
  it("reads refund_status off an action result", () => {
    expect(refundStatusOf({ refund_status: "pending", stripe_refund_id: "re_1" })).toBe("pending");
    expect(refundStatusOf({ provider_status: "requires_action" })).toBe("requires_action");
    expect(refundStatusOf(null)).toBeNull();
    expect(refundStatusOf("pending")).toBeNull();
  });
  it("execute_action may answer processing for a refund hand-off", () => {
    expect(toActionOutcome({ status: "processing", action_id: "x", handoff: "ops-refund-execute" })).toMatchObject({ status: "processing", action_id: "x" });
    expect(toActionOutcome({ status: "rejected", reject_reason: "not_supported", message: "partial refunds are not supported" })).toMatchObject({ status: "rejected", reason: "not_supported" });
  });
});

describe("executor refusal reasons (409 {reason})", () => {
  it("maps the known ops.executor_claim reasons to operator text", () => {
    for (const r of ["disabled", "paused", "claim_busy", "approval_stale", "approval_missing", "terminal", "succeeded_at_provider", "not_executable"]) {
      expect(executorRefusalLabel(r)).not.toBe(r);
      expect(executorRefusalLabel(r).length).toBeGreaterThan(10);
    }
    expect(executorRefusalLabel("paused")).toMatch(/paused by a founder/);
    expect(executorRefusalLabel("claim_busy")).toMatch(/lease/);
  });
  it("never hides an unknown reason", () => {
    expect(executorRefusalLabel("brand_new_reason")).toBe("brand new reason");
    expect(executorRefusalLabel(null)).toBe("refused");
  });
});
