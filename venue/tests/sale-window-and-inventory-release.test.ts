import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { CommandResult } from "@/lib/db/command-errors";
import { RELEASE_KINDS } from "@/lib/inventory";

/**
 * P2 gap closure: the two dashboard writes a new event needed and did not have.
 *
 * D found that the create wizard's "First inventory release" step only posted a preview marker
 * (`CreateEventWizard.tsx:90` — a `method="get"` form carrying `did=venue.create_inventory_batch`), and that
 * nothing set a sale window at all. A new event therefore could not get inventory, so `publish_event` refused
 * `empty_inventory`. Confirmed before writing this: the wizard has three GET preview forms and zero real
 * actions, and `grep -rni sale_window src` was empty.
 *
 * These assertions are about what the actions SEND — the schema, the RPC name, the server's own parameter
 * names, and the refusals that must never reach the database.
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

async function load(opts: { source?: "database" | "fixtures"; gate?: string } = {}): Promise<Commands> {
  vi.unstubAllEnvs();
  vi.stubEnv("NEXT_PUBLIC_VENUE_DATA_SOURCE", opts.source ?? "database");
  vi.stubEnv("VENUE_COMMANDS_ENABLED", opts.gate);
  vi.resetModules();
  return import("@/lib/db/commands");
}

const T = "2a7f3c21-9b4e-4d62-ae05-7c1b8fd3e064";
const S = "5d1ea86b-3f07-4c95-bb24-0e9fa7c6d381";
const KEY = "4b2d0a4e-5f4e-4c0b-9a63-6c2d4a6f0e11";
const START = "2026-11-01T20:00:00-04:00";
const END = "2026-11-02T20:00:00-04:00";
const RECEIPT = { status: "ok", ticket_type_id: T };

const window = (over: Record<string, unknown> = {}) => ({ ticketTypeId: T, saleStartsAt: START, saleEndsAt: END, reasonCode: "launch", commandKey: KEY, ...over }) as never;
const release = (over: Record<string, unknown> = {}) => ({ ticketTypeId: T, sessionId: S, releaseKind: "public_sale", capacity: 100, commandKey: KEY, ...over }) as never;

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

describe("both new actions obey the same two locks as every other write", () => {
  it("gate unset → unavailable, and the client is never created (negative control)", async () => {
    const m = await load({ source: "database", gate: undefined });
    expect(await m.setTicketTypeSaleWindowAction(window()), "sale window").toMatchObject({ kind: "unavailable", reason: "gate_unset" });
    expect(await m.createInventoryBatchAction(release()), "release").toMatchObject({ kind: "unavailable", reason: "gate_unset" });
    expect(mocks.create).not.toHaveBeenCalled();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it("fixtures mode → unavailable even with the gate set (negative control)", async () => {
    const m = await load({ source: "fixtures", gate: "true" });
    expect(await m.setTicketTypeSaleWindowAction(window())).toMatchObject({ kind: "unavailable", reason: "fixtures_mode" });
    expect(await m.createInventoryBatchAction(release())).toMatchObject({ kind: "unavailable", reason: "fixtures_mode" });
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
});

describe("set_ticket_type_sale_window — 162's parameter names, verbatim", () => {
  it("sends the server's own parameter names on venue_cmd", async () => {
    const m = await load({ gate: "true" });
    expect(await m.setTicketTypeSaleWindowAction(window())).toMatchObject({ kind: "ok" });
    expect(mocks.schema).toHaveBeenCalledWith("venue_cmd");
    expect(mocks.rpc).toHaveBeenCalledWith("set_ticket_type_sale_window", {
      p_ticket_type_id: T,
      p_sale_starts_at: START,
      p_sale_ends_at: END,
      p_reason_code: "launch",
      p_command_key: KEY,
    });
  });
  it("both ends null clears the window, and that is a legal call", async () => {
    const m = await load({ gate: "true" });
    expect(await m.setTicketTypeSaleWindowAction(window({ saleStartsAt: null, saleEndsAt: null }))).toMatchObject({ kind: "ok" });
    expect(mocks.rpc.mock.calls[0][1]).toMatchObject({ p_sale_starts_at: null, p_sale_ends_at: null });
  });
  it("one end null leaves that side open", async () => {
    const m = await load({ gate: "true" });
    expect(await m.setTicketTypeSaleWindowAction(window({ saleEndsAt: null }))).toMatchObject({ kind: "ok" });
    expect(mocks.rpc.mock.calls[0][1]).toMatchObject({ p_sale_starts_at: START, p_sale_ends_at: null });
  });

  it("REFUSES a naive timestamp with no offset — the server would read it as UTC and shift the organizer's time", async () => {
    const m = await load({ gate: "true" });
    const r = await m.setTicketTypeSaleWindowAction(window({ saleStartsAt: "2026-11-01T20:00:00" }));
    expect(r).toMatchObject({ kind: "refused" });
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it("refuses an end at or before the start — ends is exclusive, so equal is an empty window", async () => {
    const m = await load({ gate: "true" });
    for (const bad of [START, "2026-10-31T20:00:00-04:00"]) {
      mocks.rpc.mockClear();
      expect(await m.setTicketTypeSaleWindowAction(window({ saleEndsAt: bad })), bad).toMatchObject({ kind: "refused" });
      expect(mocks.rpc).not.toHaveBeenCalled();
    }
  });
  it("refuses a missing reason, a bad uuid and a missing key before any call", async () => {
    const m = await load({ gate: "true" });
    for (const bad of [window({ reasonCode: "" }), window({ ticketTypeId: "nope" }), window({ commandKey: "" })]) {
      mocks.rpc.mockClear();
      expect(await m.setTicketTypeSaleWindowAction(bad)).toMatchObject({ kind: "refused" });
      expect(mocks.rpc).not.toHaveBeenCalled();
    }
  });
});

describe("create_inventory_batch — 081's parameter names, and the shard rule", () => {
  it("sends the server's own parameter names, with p_shard_count exactly 0", async () => {
    const m = await load({ gate: "true" });
    expect(await m.createInventoryBatchAction(release())).toMatchObject({ kind: "ok" });
    expect(mocks.schema).toHaveBeenCalledWith("venue_cmd");
    expect(mocks.rpc).toHaveBeenCalledWith("create_inventory_batch", {
      p_ticket_type_id: T,
      p_session_id: S,
      p_release_kind: "public_sale",
      p_capacity: 100,
      p_shard_count: 0,
      p_command_key: KEY,
    });
  });
  it("never sends a shard count above 0, whatever the caller passes — the body raises sharding_deferred", async () => {
    const m = await load({ gate: "true" });
    // `shardCount` is not part of the input type; a caller who smuggles one must still get 0.
    await m.createInventoryBatchAction(release({ shardCount: 4 }));
    expect(mocks.rpc.mock.calls[0][1]).toMatchObject({ p_shard_count: 0 });
  });
  it("accepts every release kind the 081 check allows, and refuses one it does not", async () => {
    const m = await load({ gate: "true" });
    for (const kind of RELEASE_KINDS) {
      mocks.rpc.mockClear();
      expect(await m.createInventoryBatchAction(release({ releaseKind: kind })), kind).toMatchObject({ kind: "ok" });
      expect(mocks.rpc.mock.calls[0][1]).toMatchObject({ p_release_kind: kind });
    }
    mocks.rpc.mockClear();
    expect(await m.createInventoryBatchAction(release({ releaseKind: "flash_sale" }))).toMatchObject({ kind: "refused" });
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it("refuses a capacity of 0 or less, and a non-integer, before any call", async () => {
    const m = await load({ gate: "true" });
    for (const bad of [0, -1, 1.5]) {
      mocks.rpc.mockClear();
      expect(await m.createInventoryBatchAction(release({ capacity: bad })), String(bad)).toMatchObject({ kind: "refused" });
      expect(mocks.rpc).not.toHaveBeenCalled();
    }
  });
  it("refuses a bad session uuid and a missing key before any call", async () => {
    const m = await load({ gate: "true" });
    for (const bad of [release({ sessionId: "nope" }), release({ commandKey: "" })]) {
      mocks.rpc.mockClear();
      expect(await m.createInventoryBatchAction(bad)).toMatchObject({ kind: "refused" });
      expect(mocks.rpc).not.toHaveBeenCalled();
    }
  });
});

describe("a server refusal is never read as success", () => {
  it("an error of any shape comes back refused or unavailable, never ok", async () => {
    const m = await load({ gate: "true" });
    for (const err of [{ code: "42501", message: "insufficient_privilege" }, { message: "precondition_failed: sharding_deferred" }, { code: "PGRST202", message: "no function" }]) {
      mocks.rpc.mockClear();
      mocks.rpc.mockResolvedValue({ data: null, error: err, status: 400 });
      const a: CommandResult<unknown> = await m.createInventoryBatchAction(release());
      const b: CommandResult<unknown> = await m.setTicketTypeSaleWindowAction(window());
      expect(a.kind, JSON.stringify(err)).not.toBe("ok");
      expect(b.kind, JSON.stringify(err)).not.toBe("ok");
    }
  });
});
