import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  buildConfigRequestArgs,
  buildDecisionArgs,
  decisionOutcomeText,
  parseConfigValue,
  requestOutcomeText,
  toMoneyConfigList,
} from "../src/lib/money-config";

// Fake transports: record every call the server actions make. The real
// submitMoneyConfigRequest / submitMoneyConfigDecision code paths run unchanged.
const opsCalls: { fn: string; args: Record<string, unknown> }[] = [];
const kernelCalls: Record<string, unknown>[] = [];
let opsReply: unknown = { ok: true, data: { status: "parked", key: "refund.org_auto_execute_max_minor", version: 2, request_id: "7a000000-0000-4000-8000-000000000001" } };
let kernelReply: unknown = { ok: true, data: { status: "approved", request_id: "7a000000-0000-4000-8000-000000000001", applied_version: 3 } };

vi.mock("@/lib/ops", () => ({
  callOps: vi.fn(async (fn: string, args: Record<string, unknown> = {}) => {
    opsCalls.push({ fn, args });
    return opsReply;
  }),
  callKernelApproval: vi.fn(async (args: Record<string, unknown>) => {
    kernelCalls.push(args);
    return kernelReply;
  }),
}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

import { submitMoneyConfigDecision, submitMoneyConfigRequest } from "../src/lib/actions";

const CMD = "01234567-89ab-4cde-8f01-23456789abcd";
const REQ = "7a000000-0000-4000-8000-000000000001";

function form(fields: Record<string, string>): FormData {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) fd.set(k, v);
  return fd;
}

beforeEach(() => {
  opsCalls.length = 0;
  kernelCalls.length = 0;
  opsReply = { ok: true, data: { status: "parked", key: "refund.org_auto_execute_max_minor", version: 2, request_id: REQ } };
  kernelReply = { ok: true, data: { status: "approved", request_id: REQ, applied_version: 3 } };
});

describe("toMoneyConfigList", () => {
  it("keeps rows with a request_id, drops the rest, and reads the money keys", () => {
    const list = toMoneyConfigList({
      items: [
        { request_id: REQ, key: "payout.request_auto_max_minor", proposed_value: 7000, value_at_request: null, requested_by_me: false, can_decide: true, key_changed_since_request: false },
        { key: "no-id" },
        "garbage",
      ],
      money_keys: [{ key: "fee.buyer_service_bps", version: 1, value: null }, { version: 2 }],
      state: "pending",
    });
    expect(list.items).toHaveLength(1);
    expect(list.items[0]).toMatchObject({ request_id: REQ, key: "payout.request_auto_max_minor", proposed_value: 7000, value_at_request: null, can_decide: true });
    expect(list.money_keys).toEqual([{ key: "fee.buyer_service_bps", version: 1, value: null }]);
    expect(list.state).toBe("pending");
  });

  it("degrades to empty on an unrecognised payload", () => {
    expect(toMoneyConfigList(null)).toEqual({ items: [], money_keys: [], state: null });
  });
});

describe("parseConfigValue", () => {
  it("takes JSON so the type is explicit", () => {
    expect(parseConfigValue("2500")).toEqual({ ok: true, value: 2500 });
    expect(parseConfigValue(' "24 hours" ')).toEqual({ ok: true, value: "24 hours" });
    expect(parseConfigValue("true")).toEqual({ ok: true, value: true });
    expect(parseConfigValue("null")).toEqual({ ok: true, value: null });
  });
  it("refuses a bare word and an empty value instead of guessing", () => {
    expect(parseConfigValue("24 hours").ok).toBe(false);
    expect(parseConfigValue("   ").ok).toBe(false);
  });
});

describe("buildConfigRequestArgs", () => {
  const good = { key: "refund.org_auto_execute_max_minor", value: "9000", reason: "raise cap", commandKey: CMD };
  it("maps the form onto ops.request_platform_config's parameters", () => {
    expect(buildConfigRequestArgs(good)).toEqual({
      ok: true,
      args: { p_key: "refund.org_auto_execute_max_minor", p_value: 9000, p_reason_code: "raise cap", p_command_key: CMD },
    });
  });
  it("refuses a missing key, bad JSON, a missing reason and a missing form key", () => {
    expect(buildConfigRequestArgs({ ...good, key: "" }).ok).toBe(false);
    expect(buildConfigRequestArgs({ ...good, key: "DROP TABLE" }).ok).toBe(false);
    expect(buildConfigRequestArgs({ ...good, value: "nine thousand" }).ok).toBe(false);
    expect(buildConfigRequestArgs({ ...good, reason: "  " }).ok).toBe(false);
    expect(buildConfigRequestArgs({ ...good, reason: "x".repeat(2001) }).ok).toBe(false);
    expect(buildConfigRequestArgs({ ...good, commandKey: "not-a-uuid" }).ok).toBe(false);
  });
});

describe("buildDecisionArgs", () => {
  const good = { requestId: REQ, decision: "approve", reason: "second founder review", commandKey: CMD };
  it("maps onto kernel.approve_refund_request's parameters", () => {
    expect(buildDecisionArgs(good)).toEqual({
      ok: true,
      args: { p_request_id: REQ, p_decision: "approve", p_reason_code: "second founder review", p_command_key: CMD },
    });
    expect(buildDecisionArgs({ ...good, decision: " Deny " })).toMatchObject({ ok: true, args: { p_decision: "deny" } });
  });
  it("never defaults a decision", () => {
    for (const d of [undefined, null, "", "yes", "approved", "Approve!", 1]) {
      expect(buildDecisionArgs({ ...good, decision: d })).toEqual({ ok: false, invalid: "invalid decision" });
    }
  });
  it("refuses a missing request id or reason", () => {
    expect(buildDecisionArgs({ ...good, requestId: "abc" }).ok).toBe(false);
    expect(buildDecisionArgs({ ...good, reason: "" }).ok).toBe(false);
  });
});

describe("submitMoneyConfigRequest", () => {
  const fields = { idempotency_key: CMD, key: "refund.org_auto_execute_max_minor", value: "9000", reason: "raise cap" };
  it("calls ops.request_platform_config with exactly the form's terms and reports parked", async () => {
    const state = await submitMoneyConfigRequest({}, form(fields));
    expect(opsCalls).toEqual([
      { fn: "request_platform_config", args: { p_key: "refund.org_auto_execute_max_minor", p_value: 9000, p_reason_code: "raise cap", p_command_key: CMD } },
    ]);
    expect(state).toEqual({ submitted: true, status: "parked", requestId: REQ, appliedVersion: 2 });
  });
  it("does not call the database on invalid input", async () => {
    const state = await submitMoneyConfigRequest({}, form({ ...fields, value: "nine thousand" }));
    expect(opsCalls).toEqual([]);
    expect(state.invalid).toBeTruthy();
  });
  it("turns the duplicate-command-key violation into a reload hint", async () => {
    opsReply = { ok: false, kind: "error", code: "23505", message: "duplicate key value violates unique constraint" };
    const state = await submitMoneyConfigRequest({}, form(fields));
    expect(state.invalid).toMatch(/already submitted/);
    expect(state.failure).toBeUndefined();
  });
  it("passes a step-up refusal through as the mfa failure", async () => {
    opsReply = { ok: false, kind: "mfa" };
    expect(await submitMoneyConfigRequest({}, form(fields))).toEqual({ submitted: true, failure: { ok: false, kind: "mfa" } });
  });
});

describe("submitMoneyConfigDecision", () => {
  const fields = { idempotency_key: CMD, request_id: REQ, decision: "approve", reason: "looks right" };
  it("calls kernel.approve_refund_request with exactly the form's terms", async () => {
    const state = await submitMoneyConfigDecision({}, form(fields));
    expect(kernelCalls).toEqual([{ p_request_id: REQ, p_decision: "approve", p_reason_code: "looks right", p_command_key: CMD }]);
    expect(state).toEqual({ submitted: true, status: "approved", requestId: REQ, appliedVersion: 3 });
  });
  it("never reaches the database with an unrecognised decision", async () => {
    const state = await submitMoneyConfigDecision({}, form({ ...fields, decision: "yes" }));
    expect(kernelCalls).toEqual([]);
    expect(state).toEqual({ submitted: true, invalid: "invalid decision" });
  });
  it("surfaces the self-approval refusal as a failure, not an outcome", async () => {
    kernelReply = { ok: false, kind: "error", code: "P0001", message: "self_approval: the requester cannot decide their own request" };
    const state = await submitMoneyConfigDecision({}, form(fields));
    expect(state.status).toBeUndefined();
    expect(state.failure).toMatchObject({ kind: "error", message: expect.stringContaining("self_approval") });
  });
});

describe("outcome texts", () => {
  it("never calls a parked request applied", () => {
    expect(requestOutcomeText("parked")?.title).toMatch(/nothing has changed yet/);
    expect(requestOutcomeText("ok")?.title).toMatch(/Applied now/);
    expect(requestOutcomeText("weird")).toBeNull();
    expect(decisionOutcomeText("approved")?.title).toMatch(/Approved/);
    expect(decisionOutcomeText("denied")?.title).toMatch(/keeps its current value/);
  });
});
