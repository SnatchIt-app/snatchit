import { describe, expect, it } from "vitest";
import { mapOpsError } from "../src/lib/ops-errors";

describe("mapOpsError", () => {
  it("maps 42501 and insufficient_privilege to denied", () => {
    expect(mapOpsError("today", { code: "42501", message: "permission denied for function today" })).toEqual({ ok: false, kind: "denied" });
    expect(mapOpsError("today", { code: "P0001", message: "insufficient_privilege: not an operator" })).toEqual({ ok: false, kind: "denied" });
  });

  it("maps step-up messages to mfa", () => {
    expect(mapOpsError("execute_action", { code: "P0001", message: "step_up_required" })).toEqual({ ok: false, kind: "mfa" });
    expect(mapOpsError("execute_action", { code: "P0001", message: "STEP_UP_UNAVAILABLE for this session" })).toEqual({ ok: false, kind: "mfa" });
  });

  it("flags a missing function/schema as unavailable with a friendly message", () => {
    const r = mapOpsError("list_orders", { code: "PGRST202", message: "Could not find the function ops.list_orders(p_filters) in the schema cache" });
    expect(r).toMatchObject({ ok: false, kind: "error", unavailable: true, message: "RPC ops.list_orders not available yet" });
    expect(mapOpsError("today", { code: "PGRST106", message: "The schema must be one of the following: public, kernel" })).toMatchObject({ unavailable: true });
    expect(mapOpsError("today", { code: "42883", message: "function ops.today() does not exist" })).toMatchObject({ unavailable: true });
  });

  it("keeps other errors generic with the server message and code", () => {
    expect(mapOpsError("today", { code: "22P02", message: "invalid input syntax for type uuid" })).toEqual({
      ok: false,
      kind: "error",
      code: "22P02",
      message: "invalid input syntax for type uuid",
    });
    expect(mapOpsError("today", null)).toEqual({ ok: false, kind: "error", message: "Request failed" });
  });
});
