import { describe, expect, it } from "vitest";
import { COMMAND_COPY, commandTransportFailure, invalidInput, mapCommandError, NOT_ENABLED_COPY, type CommandErrorCode, type CommandFailure } from "@/lib/db/command-errors";

/**
 * S1 — every refusal the venue_cmd wrappers can hand back (081:175/246/408 literals, the provisional
 * 160 setters, PostgREST's own codes) maps to plain copy. Nothing here can produce a success.
 */
const pg = (code: string | null, message: string) => ({ code, message, details: null, hint: null });

describe("SQLSTATE / PostgREST code → plain copy", () => {
  it.each<[string, string, CommandFailure["kind"], string]>([
    ["42501", "insufficient_privilege: authentication required", "refused", "not_allowed"],
    ["42501", "insufficient_privilege: venue_manager or org_owner/org_admin required", "refused", "not_allowed"],
    ["P0002", "not_found: event 1111", "refused", "not_found"],
    ["P0002", "not_found: ticket type 2222", "refused", "not_found"],
    ["P0002", "not_found: batch 3333", "refused", "not_found"],
    ["P0001", "precondition_failed: event_terminal", "refused", "event_terminal"],
    ["P0001", "precondition_failed: below_committed (new=5 < held+sold=12)", "refused", "below_committed"],
    ["P0001", "precondition_failed: shard_distribution_unsatisfiable", "refused", "shard_distribution"],
    ["P0001", "precondition_failed: duplicate_name", "refused", "duplicate_name"],
    ["P0001", "precondition_failed: command key required", "refused", "command_key_required"],
    ["P0001", "precondition_failed: reason_required", "refused", "reason_required"],
    ["P0001", "precondition_failed: bad_price", "refused", "invalid_input"],
    ["P0001", "precondition_failed: bad_capacity", "refused", "invalid_input"],
    ["P0001", "invalid_input: bad kind vip", "refused", "invalid_input"],
    ["P0001", "invalid_input: bad visibility secret", "refused", "invalid_input"],
    ["PGRST301", "JWT expired", "refused", "auth"],
    ["PGRST302", "Anonymous access is disabled", "refused", "auth"],
    ["PGRST106", "Invalid schema: venue_cmd", "unavailable", "not_exposed"],
    ["PGRST202", "Could not find the function venue_cmd.set_ticket_type_visibility(...) in the schema cache", "unavailable", "not_exposed"],
    ["3F000", "schema \"venue_cmd\" does not exist", "unavailable", "config"],
    ["42883", "function venue_cmd.get_inventory_counters(uuid) does not exist", "unavailable", "config"],
    ["XX000", "internal error", "refused", "unknown"],
    ["P0001", "precondition_failed: something_new_in_a_later_migration", "refused", "unknown"],
  ])("%s %s → %s/%s", (code, message, kind, label) => {
    const f = mapCommandError(pg(code, message));
    expect(f.kind).toBe(kind);
    if (f.kind === "refused") {
      expect(f.code).toBe(label);
      expect(f.message).toBe(COMMAND_COPY[label as CommandErrorCode]);
      expect(f.sqlstate).toBe(code);
    } else {
      expect(f.reason).toBe(label);
      expect(f.sqlstate).toBe(code);
    }
  });
  it("the dark state reads as 'not enabled', in those words", () => {
    expect(mapCommandError(pg("PGRST106", "Invalid schema: venue_cmd")).message).toBe(NOT_ENABLED_COPY);
    expect(NOT_ENABLED_COPY).toMatch(/Commands are not enabled for this project/);
  });
  it("a 401 without a code is an auth failure; a code-less network message is transport", () => {
    expect(mapCommandError(pg(null, "unauthorized"), 401)).toMatchObject({ kind: "refused", code: "auth" });
    expect(mapCommandError(pg(null, "TypeError: fetch failed"))).toMatchObject({ kind: "refused", code: "transport" });
    expect(mapCommandError(pg(null, "connect ECONNREFUSED 127.0.0.1:54321"))).toMatchObject({ kind: "refused", code: "transport" });
  });
  it("a missing error object is still a failure (unknown), never a success", () => {
    expect(mapCommandError(null)).toMatchObject({ kind: "refused", code: "unknown" });
    expect(mapCommandError(undefined)).toMatchObject({ kind: "refused", code: "unknown" });
    expect(mapCommandError({})).toMatchObject({ kind: "refused", code: "unknown" });
  });
});

describe("no path to success", () => {
  const inputs: Array<[Parameters<typeof mapCommandError>[0], number | undefined]> = [
    [pg("42501", "x"), undefined],
    [pg("P0002", "x"), 404],
    [pg("P0001", "precondition_failed: event_terminal"), 400],
    [pg("PGRST106", "x"), 406],
    [pg(null, ""), 200],
    [pg("00000", "successful_completion"), 200],
    [{ code: "ok", message: "ok" }, 200],
    [null, 200],
  ];
  it("every mapped input is refused or unavailable — including codes that look like success", () => {
    for (const [e, status] of inputs) {
      const f = mapCommandError(e, status) as { kind: string };
      expect(["refused", "unavailable"], JSON.stringify(e)).toContain(f.kind);
      expect(f).not.toHaveProperty("result");
    }
    expect(commandTransportFailure(new Error("ECONNRESET"))).toMatchObject({ kind: "refused", code: "transport" });
    expect(commandTransportFailure("not even an error")).toMatchObject({ kind: "refused", code: "transport" });
    expect(invalidInput("priceMinor", "Enter a whole number of cents, at least 1.")).toEqual({ kind: "refused", code: "invalid_input", field: "priceMinor", message: "Enter a whole number of cents, at least 1." });
  });
  it("copy is plain: no schema, function, SQLSTATE or PostgREST token reaches the operator", () => {
    const forbidden = /venue_cmd|venue\.|catalog\.|kernel\.|PGRST|SQLSTATE|\b[0-9A-Z]{5}\b|P000[12]|_failed|jsonb|rpc/;
    for (const [code, copy] of Object.entries(COMMAND_COPY)) {
      expect(copy, code).not.toMatch(forbidden);
      expect(copy.trim().length, code).toBeGreaterThan(10);
    }
    expect(NOT_ENABLED_COPY).not.toMatch(forbidden);
  });
  it("transport copy does not promise that nothing changed — the request may have landed, so it says to resend the same request", () => {
    expect(COMMAND_COPY.transport).toMatch(/Couldn.t reach the database/);
    expect(COMMAND_COPY.transport).not.toMatch(/nothing (was|has been) changed/i);
    expect(COMMAND_COPY.transport).toMatch(/same request|try again/i);
  });
  it("the unknown case keeps the raw code and message out of the copy but on the failure, for the log", () => {
    const f = mapCommandError(pg("XX000", "internal: shard 3 missing"));
    expect(f).toMatchObject({ kind: "refused", code: "unknown", sqlstate: "XX000", detail: "internal: shard 3 missing" });
    expect(f.message).not.toMatch(/XX000|shard 3/);
  });
});
