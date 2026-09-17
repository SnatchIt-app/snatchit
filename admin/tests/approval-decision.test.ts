import { beforeEach, describe, expect, it, vi } from "vitest";
import { parseApprovalDecision, APPROVAL_DECISIONS } from "../src/lib/types";

// Fake ops transport: records every (fn, args) the adapter sends. The real
// submitActionForm / approveAction / executeAction code paths run unchanged.
const calls: { fn: string; args: Record<string, unknown> }[] = [];
let reply: unknown = { status: "succeeded", action_id: "00000000-0000-4000-8000-000000000001" };

vi.mock("@/lib/ops", () => ({
  callOps: vi.fn(async (fn: string, args: Record<string, unknown> = {}) => {
    calls.push({ fn, args });
    return { ok: true, data: reply };
  }),
}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

import { submitActionForm } from "../src/lib/actions";

const ACTION_ID = "9a900000-0000-4000-8000-000000000005";
const KEY = "01234567-89ab-4cde-8f01-23456789abcd";

function approvalForm(decision: unknown, reason = "second founder review"): FormData {
  const fd = new FormData();
  fd.set("idempotency_key", KEY);
  fd.set("action_type", "approval_decide");
  fd.set("subject_kind", "action");
  fd.set("subject_id", ACTION_ID);
  fd.set("params", JSON.stringify({ action_id: ACTION_ID, decision }));
  fd.set("expected", "{}");
  fd.set("reason_required", "1");
  fd.set("reason", reason);
  return fd;
}

describe("parseApprovalDecision", () => {
  it("accepts exactly the two values ops.approve_action() accepts", () => {
    expect(APPROVAL_DECISIONS).toEqual(["approve", "deny"]);
    expect(parseApprovalDecision("approve")).toBe("approve");
    expect(parseApprovalDecision("deny")).toBe("deny");
    expect(parseApprovalDecision(" Deny ")).toBe("deny");
  });
  it("returns null for anything else — never defaults to approve", () => {
    for (const v of ["reject", "rejected", "approved", "yes", "", " ", null, undefined, 1, true, {}, [], "approve;deny"]) {
      expect(parseApprovalDecision(v)).toBeNull();
    }
  });
});

describe("submitActionForm → ops.approve_action mapping", () => {
  beforeEach(() => {
    calls.length = 0;
    reply = { status: "succeeded", action_id: ACTION_ID };
  });

  it("Deny sends p_decision = 'deny' verbatim", async () => {
    const state = await submitActionForm({}, approvalForm("deny", "terms look wrong"));
    expect(calls).toHaveLength(1);
    expect(calls[0].fn).toBe("approve_action");
    expect(calls[0].args).toEqual({ p_action_id: ACTION_ID, p_decision: "deny", p_reason: "terms look wrong" });
    expect(state.outcome?.status).toBe("succeeded");
    expect(state.failure).toBeUndefined();
  });

  it("Approve sends p_decision = 'approve' verbatim", async () => {
    await submitActionForm({}, approvalForm("approve"));
    expect(calls).toHaveLength(1);
    expect(calls[0].args.p_decision).toBe("approve");
    expect(calls[0].fn).toBe("approve_action");
  });

  it("the legacy 'reject' value is refused client-side and NOTHING is sent (must not become approve)", async () => {
    const state = await submitActionForm({}, approvalForm("reject"));
    expect(calls).toHaveLength(0);
    expect(state.failure).toEqual({ ok: false, kind: "error", message: "invalid decision" });
    expect(state.outcome).toBeUndefined();
  });

  it("a missing / malformed decision is refused, not defaulted", async () => {
    for (const bad of [undefined, null, "", "APPROVED!", 42]) {
      calls.length = 0;
      const state = await submitActionForm({}, approvalForm(bad));
      expect(calls).toHaveLength(0);
      expect(state.failure).toMatchObject({ kind: "error", message: "invalid decision" });
    }
  });

  it("approval_decide never goes through execute_action", async () => {
    await submitActionForm({}, approvalForm("deny"));
    expect(calls.map((c) => c.fn)).toEqual(["approve_action"]);
    expect(calls[0].args).not.toHaveProperty("p_idempotency_key");
  });

  it("still requires a reason before contacting the database", async () => {
    const state = await submitActionForm({}, approvalForm("deny", ""));
    expect(calls).toHaveLength(0);
    expect(state.invalid).toMatch(/reason/i);
  });

  it("surfaces the paused failure kind from the transport untouched", async () => {
    const { callOps } = await import("@/lib/ops");
    (callOps as unknown as ReturnType<typeof vi.fn>).mockImplementationOnce(async () => ({ ok: false, kind: "paused", message: "precondition_failed: console_actions_paused" }));
    const state = await submitActionForm({}, approvalForm("deny"));
    expect(state.failure).toMatchObject({ kind: "paused" });
  });
});
