import { describe, expect, it } from "vitest";
import { canRequest, canSuspend } from "@/lib/permissions";

// Migration 152: user_restrict is open to support for listing blocks, but ops.action_dispatch
// refuses kind "suspended" unless the operator is platform_admin or platform_risk.
describe("account suspension permission mirrors migration 152", () => {
  it("allows founders and risk operators only", () => {
    expect(canSuspend("platform_admin")).toBe(true);
    expect(canSuspend("platform_risk")).toBe(true);
    expect(canSuspend("platform_support")).toBe(false);
    expect(canSuspend(null)).toBe(false);
    expect(canSuspend(undefined)).toBe(false);
  });

  it("is narrower than user_restrict, which support keeps for listing blocks", () => {
    expect(canRequest("platform_support", "user_restrict")).toBe(true);
    expect(canSuspend("platform_support")).toBe(false);
  });
});
