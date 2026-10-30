import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { CommandResult } from "@/lib/db/command-errors";
import { isUuid } from "@/lib/page";

/**
 * S1 — the venue_cmd server actions, DARK. F's client factory (lib/supabase/server) is mocked, so every
 * assertion is about what an action sends and what it says back: the schema, the RPC name, the 081
 * parameter names, the command key, and that an error of any shape never comes back as success.
 */
const mocks = vi.hoisted(() => ({ create: vi.fn(), schema: vi.fn(), rpc: vi.fn() }));

vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: mocks.create,
  SupabaseConfigError: class SupabaseConfigError extends Error {
    constructor(message: string) {
      super(message);
      this.name = "SupabaseConfigError";
    }
  },
}));

type Commands = typeof import("@/lib/db/commands");

/** DATA_SOURCE is fixed at import (lib/env.ts) and the gate is read per call, so each gate state reloads the module. */
async function load(opts: { source?: "database" | "fixtures"; gate?: string } = {}): Promise<Commands> {
  vi.unstubAllEnvs();
  vi.stubEnv("NEXT_PUBLIC_VENUE_DATA_SOURCE", opts.source ?? "database");
  vi.stubEnv("VENUE_COMMANDS_ENABLED", opts.gate); // undefined removes it — the default state everywhere today
  vi.resetModules();
  return import("@/lib/db/commands");
}

const E = "11111111-1111-4111-8111-111111111111";
const T = "22222222-2222-4222-8222-222222222222";
const B = "33333333-3333-4333-8333-333333333333";
const KEY = "4b2d0a4e-5f4e-4c0b-9a63-6c2d4a6f0e11";
const RECEIPT = { status: "ok", ticket_type_id: T };

type Call = { name: string; run: (m: Commands) => Promise<CommandResult<unknown>>; rpc: string; args: Record<string, unknown> };
/** One valid call per action, with the exact parameter names of 081:175 / 081:246 / 081:408 and the provisional 160 setters. */
const CALLS: Call[] = [
  {
    name: "createTicketTypeAction",
    run: (m) => m.createTicketTypeAction({ eventId: E, kind: "admission", name: "GA", priceMinor: 2500, visibility: "hidden", commandKey: KEY }),
    rpc: "create_ticket_type",
    args: { p_event_id: E, p_kind: "admission", p_name: "GA", p_price_minor: 2500, p_visibility: "hidden", p_command_key: KEY },
  },
  {
    name: "setTicketTypePriceAction",
    run: (m) => m.setTicketTypePriceAction({ ticketTypeId: T, priceMinor: 3000, reasonCode: "early_bird_over", commandKey: KEY }),
    rpc: "set_ticket_type_price",
    args: { p_ticket_type_id: T, p_price_minor: 3000, p_reason_code: "early_bird_over", p_command_key: KEY },
  },
  {
    name: "setTicketTypeVisibilityAction",
    run: (m) => m.setTicketTypeVisibilityAction({ ticketTypeId: T, visibility: "public", reasonCode: "tier_release", commandKey: KEY }),
    rpc: "set_ticket_type_visibility",
    args: { p_ticket_type_id: T, p_visibility: "public", p_reason_code: "tier_release", p_command_key: KEY },
  },
  {
    name: "setTicketTypeRankAction",
    run: (m) => m.setTicketTypeRankAction({ ticketTypeId: T, displayRank: 10, commandKey: KEY }),
    rpc: "set_ticket_type_rank",
    args: { p_ticket_type_id: T, p_display_rank: 10, p_command_key: KEY },
  },
  {
    name: "setBatchCapacityAction",
    run: (m) => m.setBatchCapacityAction({ batchId: B, newCapacity: 120, reasonCode: "room_reconfigured", commandKey: KEY }),
    rpc: "set_batch_capacity",
    args: { p_batch_id: B, p_new_capacity: 120, p_reason_code: "room_reconfigured", p_command_key: KEY },
  },
];

beforeEach(() => {
  mocks.create.mockReset();
  mocks.schema.mockReset();
  mocks.rpc.mockReset();
  mocks.schema.mockReturnValue({ rpc: mocks.rpc });
  mocks.create.mockResolvedValue({ schema: mocks.schema });
  mocks.rpc.mockResolvedValue({ data: RECEIPT, error: null, status: 200 });
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetModules();
});

describe("the write gate — dark by default", () => {
  it("VENUE_COMMANDS_ENABLED unset → every action is unavailable and the client is never created", async () => {
    const m = await load({ source: "database", gate: undefined });
    for (const c of CALLS) {
      const r = await c.run(m);
      expect(r, c.name).toMatchObject({ kind: "unavailable", reason: "gate_unset" });
    }
    expect(mocks.create).not.toHaveBeenCalled();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it("fixtures mode → unavailable even with the gate set; the client is never created", async () => {
    const m = await load({ source: "fixtures", gate: "true" });
    for (const c of CALLS) expect(await c.run(m), c.name).toMatchObject({ kind: "unavailable", reason: "fixtures_mode" });
    expect(mocks.create).not.toHaveBeenCalled();
  });
  it("only the exact string 'true' opens the gate", async () => {
    for (const v of ["TRUE", "1", "yes", " true", "on"]) {
      const m = await load({ source: "database", gate: v });
      expect(await CALLS[0].run(m), JSON.stringify(v)).toMatchObject({ kind: "unavailable", reason: "gate_unset" });
    }
    expect(mocks.create).not.toHaveBeenCalled();
  });
  it("database mode + gate 'true' → the command goes out and the receipt comes back as ok", async () => {
    const m = await load({ source: "database", gate: "true" });
    expect(await CALLS[0].run(m)).toEqual({ kind: "ok", result: RECEIPT });
    expect(mocks.create).toHaveBeenCalledTimes(1);
  });
});

describe("the RPC contract — venue_cmd SECURITY INVOKER wrappers (provisional 161) over the 081 / 160 signatures", () => {
  it.each(CALLS)("$name → venue_cmd.$rpc with exactly the server's parameter names", async (c) => {
    const m = await load({ gate: "true" });
    const r = await c.run(m);
    expect(mocks.schema).toHaveBeenCalledWith("venue_cmd");
    expect(mocks.rpc).toHaveBeenCalledTimes(1);
    expect(mocks.rpc).toHaveBeenCalledWith(c.rpc, c.args);
    // toEqual on the recorded args: no extra or renamed parameter can slip past.
    expect(mocks.rpc.mock.calls[0][1]).toEqual(c.args);
    expect(r).toEqual({ kind: "ok", result: RECEIPT });
  });
  it("the command key is minted once per render and re-sent unchanged on a retry", async () => {
    const m = await load({ gate: "true" });
    const k1 = await m.mintCommandKey();
    const k2 = await m.mintCommandKey();
    expect(k1).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    expect(k2).not.toBe(k1);
    const input = { ticketTypeId: T, priceMinor: 3000, reasonCode: "early_bird_over", commandKey: k1 };
    // First attempt fails in transport; the retry carries the SAME key so the server can replay it as a no-op.
    mocks.rpc.mockRejectedValueOnce(new TypeError("fetch failed"));
    const first = await m.setTicketTypePriceAction(input);
    const second = await m.setTicketTypePriceAction(input);
    expect(first).toMatchObject({ kind: "refused", code: "transport" });
    expect(second).toMatchObject({ kind: "ok" });
    const sent = mocks.rpc.mock.calls.map((call) => (call[1] as { p_command_key: string }).p_command_key);
    expect(sent).toEqual([k1, k1]);
  });
});

describe("input validation — before any call, with the client untouched", () => {
  type Bad = { name: string; field: string; run: (m: Commands) => Promise<CommandResult<unknown>> };
  const as = <T>(v: unknown) => v as T;
  const BAD: Bad[] = [
    { name: "create: empty event id", field: "eventId", run: (m) => m.createTicketTypeAction({ eventId: "", kind: "admission", name: "GA", priceMinor: 2500, visibility: "hidden", commandKey: KEY }) },
    { name: "create: non-uuid event id", field: "eventId", run: (m) => m.createTicketTypeAction({ eventId: "smp_evt_1", kind: "admission", name: "GA", priceMinor: 2500, visibility: "hidden", commandKey: KEY }) },
    { name: "create: bad kind", field: "kind", run: (m) => m.createTicketTypeAction({ eventId: E, kind: as("vip"), name: "GA", priceMinor: 2500, visibility: "hidden", commandKey: KEY }) },
    { name: "create: blank name", field: "name", run: (m) => m.createTicketTypeAction({ eventId: E, kind: "admission", name: "   ", priceMinor: 2500, visibility: "hidden", commandKey: KEY }) },
    { name: "create: zero cents", field: "priceMinor", run: (m) => m.createTicketTypeAction({ eventId: E, kind: "admission", name: "GA", priceMinor: 0, visibility: "hidden", commandKey: KEY }) },
    { name: "create: negative cents", field: "priceMinor", run: (m) => m.createTicketTypeAction({ eventId: E, kind: "admission", name: "GA", priceMinor: -100, visibility: "hidden", commandKey: KEY }) },
    { name: "create: fractional cents", field: "priceMinor", run: (m) => m.createTicketTypeAction({ eventId: E, kind: "admission", name: "GA", priceMinor: 25.5, visibility: "hidden", commandKey: KEY }) },
    { name: "create: NaN cents", field: "priceMinor", run: (m) => m.createTicketTypeAction({ eventId: E, kind: "admission", name: "GA", priceMinor: Number.NaN, visibility: "hidden", commandKey: KEY }) },
    { name: "create: cents as a string", field: "priceMinor", run: (m) => m.createTicketTypeAction({ eventId: E, kind: "admission", name: "GA", priceMinor: as("2500"), visibility: "hidden", commandKey: KEY }) },
    { name: "create: bad visibility", field: "visibility", run: (m) => m.createTicketTypeAction({ eventId: E, kind: "admission", name: "GA", priceMinor: 2500, visibility: as("secret"), commandKey: KEY }) },
    { name: "create: empty command key", field: "commandKey", run: (m) => m.createTicketTypeAction({ eventId: E, kind: "admission", name: "GA", priceMinor: 2500, visibility: "hidden", commandKey: "" }) },
    { name: "create: blank command key", field: "commandKey", run: (m) => m.createTicketTypeAction({ eventId: E, kind: "admission", name: "GA", priceMinor: 2500, visibility: "hidden", commandKey: "   " }) },
    { name: "price: non-uuid ticket type", field: "ticketTypeId", run: (m) => m.setTicketTypePriceAction({ ticketTypeId: "tt-1", priceMinor: 3000, reasonCode: "r", commandKey: KEY }) },
    { name: "price: zero cents", field: "priceMinor", run: (m) => m.setTicketTypePriceAction({ ticketTypeId: T, priceMinor: 0, reasonCode: "r", commandKey: KEY }) },
    { name: "price: blank reason", field: "reasonCode", run: (m) => m.setTicketTypePriceAction({ ticketTypeId: T, priceMinor: 3000, reasonCode: " ", commandKey: KEY }) },
    { name: "price: empty command key", field: "commandKey", run: (m) => m.setTicketTypePriceAction({ ticketTypeId: T, priceMinor: 3000, reasonCode: "r", commandKey: "" }) },
    { name: "visibility: bad value", field: "visibility", run: (m) => m.setTicketTypeVisibilityAction({ ticketTypeId: T, visibility: as("door"), reasonCode: "r", commandKey: KEY }) },
    { name: "visibility: blank reason", field: "reasonCode", run: (m) => m.setTicketTypeVisibilityAction({ ticketTypeId: T, visibility: "public", reasonCode: "", commandKey: KEY }) },
    { name: "visibility: non-uuid ticket type", field: "ticketTypeId", run: (m) => m.setTicketTypeVisibilityAction({ ticketTypeId: "x", visibility: "public", reasonCode: "r", commandKey: KEY }) },
    { name: "rank: negative", field: "displayRank", run: (m) => m.setTicketTypeRankAction({ ticketTypeId: T, displayRank: -1, commandKey: KEY }) },
    { name: "rank: above 999", field: "displayRank", run: (m) => m.setTicketTypeRankAction({ ticketTypeId: T, displayRank: 1000, commandKey: KEY }) },
    { name: "rank: fractional", field: "displayRank", run: (m) => m.setTicketTypeRankAction({ ticketTypeId: T, displayRank: 2.5, commandKey: KEY }) },
    { name: "rank: as a string", field: "displayRank", run: (m) => m.setTicketTypeRankAction({ ticketTypeId: T, displayRank: as("5"), commandKey: KEY }) },
    { name: "rank: empty command key", field: "commandKey", run: (m) => m.setTicketTypeRankAction({ ticketTypeId: T, displayRank: 5, commandKey: "" }) },
    { name: "capacity: zero", field: "newCapacity", run: (m) => m.setBatchCapacityAction({ batchId: B, newCapacity: 0, reasonCode: "r", commandKey: KEY }) },
    { name: "capacity: fractional", field: "newCapacity", run: (m) => m.setBatchCapacityAction({ batchId: B, newCapacity: 10.5, reasonCode: "r", commandKey: KEY }) },
    { name: "capacity: non-uuid batch", field: "batchId", run: (m) => m.setBatchCapacityAction({ batchId: "b1", newCapacity: 10, reasonCode: "r", commandKey: KEY }) },
    { name: "capacity: blank reason", field: "reasonCode", run: (m) => m.setBatchCapacityAction({ batchId: B, newCapacity: 10, reasonCode: "", commandKey: KEY }) },
  ];
  it.each(BAD)("$name → refused invalid_input on $field, nothing sent", async (b) => {
    const m = await load({ gate: "true" });
    expect(await b.run(m)).toMatchObject({ kind: "refused", code: "invalid_input", field: b.field });
    expect(mocks.create).not.toHaveBeenCalled();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it("accepts the boundary values: 1 cent, capacity 1, rank 0 and 999, an upper-case uuid", async () => {
    const m = await load({ gate: "true" });
    expect(await m.createTicketTypeAction({ eventId: E.toUpperCase(), kind: "table", name: "Booth", priceMinor: 1, visibility: "door_only", commandKey: KEY })).toMatchObject({ kind: "ok" });
    expect(await m.setBatchCapacityAction({ batchId: B, newCapacity: 1, reasonCode: "r", commandKey: KEY })).toMatchObject({ kind: "ok" });
    expect(await m.setTicketTypeRankAction({ ticketTypeId: T, displayRank: 0, commandKey: KEY })).toMatchObject({ kind: "ok" });
    expect(await m.setTicketTypeRankAction({ ticketTypeId: T, displayRank: 999, commandKey: KEY })).toMatchObject({ kind: "ok" });
    expect(mocks.rpc).toHaveBeenCalledTimes(4);
  });
  it("the id rule is lib/page.ts isUuid (one definition), so the route's and the actions' idea of an id cannot drift", async () => {
    const m = await load({ gate: "true" });
    for (const id of [E, E.toUpperCase(), "11111111-1111-4111-8111-11111111111", "smp_evt_1", "", "11111111-1111-4111-8111-11111111111g"]) {
      const r = await m.setTicketTypeRankAction({ ticketTypeId: id, displayRank: 1, commandKey: KEY });
      expect(r.kind === "ok", id).toBe(isUuid(id));
    }
  });
});

describe("an error of any shape never becomes success", () => {
  const err = (code: string, message: string) => ({ data: null, error: { code, message, details: null, hint: null }, status: 400 });
  it("a PostgREST error returned next to receipt-shaped data is still a refusal", async () => {
    const m = await load({ gate: "true" });
    mocks.rpc.mockResolvedValue({ data: { status: "ok" }, error: { code: "P0001", message: "precondition_failed: event_terminal" }, status: 400 });
    expect(await CALLS[2].run(m)).toMatchObject({ kind: "refused", code: "event_terminal" });
  });
  it.each([
    ["42501", "insufficient_privilege: venue_manager or org_owner/org_admin required", "refused", "not_allowed"],
    ["P0002", "not_found: ticket type 2222", "refused", "not_found"],
    ["P0001", "precondition_failed: event_terminal", "refused", "event_terminal"],
    ["P0001", "precondition_failed: below_committed (new=5 < held+sold=12)", "refused", "below_committed"],
    ["P0001", "precondition_failed: duplicate_name", "refused", "duplicate_name"],
    ["P0001", "precondition_failed: command key required", "refused", "command_key_required"],
    ["P0001", "precondition_failed: reason_required", "refused", "reason_required"],
    ["P0001", "invalid_input: bad visibility secret", "refused", "invalid_input"],
    ["P0001", "precondition_failed: bad_price", "refused", "invalid_input"],
    ["P0001", "precondition_failed: shard_distribution_unsatisfiable", "refused", "shard_distribution"],
    ["PGRST301", "JWT expired", "refused", "auth"],
    ["PGRST106", "Invalid schema: venue_cmd", "unavailable", "not_exposed"],
    ["PGRST202", "Could not find the function venue_cmd.set_ticket_type_rank", "unavailable", "not_exposed"],
    ["42883", "function venue_cmd.set_ticket_type_rank(uuid, smallint, text) does not exist", "unavailable", "config"],
    ["XX000", "something nobody mapped", "refused", "unknown"],
  ])("%s %s → %s/%s", async (code, message, kind, label) => {
    const m = await load({ gate: "true" });
    mocks.rpc.mockResolvedValue(err(code, message));
    const r = await CALLS[3].run(m);
    expect(r.kind).toBe(kind);
    expect(r).toMatchObject(kind === "refused" ? { code: label, sqlstate: code } : { reason: label });
    expect(r).not.toHaveProperty("result");
  });
  it("the unknown case keeps the server's code and message for the log and says so in plain words", async () => {
    const m = await load({ gate: "true" });
    mocks.rpc.mockResolvedValue(err("XX000", "something nobody mapped"));
    const r = await CALLS[0].run(m);
    expect(r).toMatchObject({ kind: "refused", code: "unknown", sqlstate: "XX000", detail: "something nobody mapped" });
    expect((r as { message: string }).message).not.toMatch(/XX000|venue_cmd|venue\./);
  });
  it("a thrown transport error → refused transport (the same request is safe to resend)", async () => {
    const m = await load({ gate: "true" });
    mocks.rpc.mockRejectedValue(new TypeError("fetch failed"));
    const r = await CALLS[4].run(m);
    expect(r).toMatchObject({ kind: "refused", code: "transport" });
    expect((r as { message: string }).message).toMatch(/Couldn.t reach the database/);
  });
  it("no receipt and no error is not a success", async () => {
    const m = await load({ gate: "true" });
    mocks.rpc.mockResolvedValue({ data: null, error: null, status: 200 });
    expect(await CALLS[1].run(m)).toMatchObject({ kind: "refused", code: "unknown" });
    mocks.rpc.mockResolvedValue({ data: "ok", error: null, status: 200 });
    expect(await CALLS[1].run(m)).toMatchObject({ kind: "refused", code: "unknown" });
    mocks.rpc.mockResolvedValue({ data: { ticket_type_id: T }, error: null, status: 200 });
    expect(await CALLS[1].run(m)).toMatchObject({ kind: "refused", code: "unknown" });
  });
  it("a client factory failure (missing or privileged key) → unavailable config, never ok", async () => {
    const m = await load({ gate: "true" });
    const { SupabaseConfigError } = await import("@/lib/supabase/server");
    mocks.create.mockRejectedValue(new SupabaseConfigError("NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY are not set"));
    expect(await CALLS[0].run(m)).toMatchObject({ kind: "unavailable", reason: "config" });
    mocks.create.mockRejectedValue(new Error("cookies() outside a request scope"));
    expect(await CALLS[0].run(m)).toMatchObject({ kind: "unavailable", reason: "config" });
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
});
