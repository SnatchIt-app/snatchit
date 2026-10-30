import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { dbInventoryCounters, rollUpCounters, type CounterRow } from "@/lib/db/counters";
import { availability } from "@/lib/inventory";

/**
 * S1 — venue_cmd.get_inventory_counters (the read E-29 intended for staff) and the per-session, per-tier
 * roll-up. The one property that matters most: a failed read is a ReadFailure, never a row of zeros.
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

const E = "11111111-1111-4111-8111-111111111111";
const S1 = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1";
const S2 = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2";
const GA = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1";
const VIP = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2";

const row = (batch: string, tt: string, s: string, release: string, capacity: number, held: number, sold: number): CounterRow => ({
  batch_id: batch,
  ticket_type_id: tt,
  event_session_id: s,
  release_kind: release,
  capacity,
  held,
  sold,
  remaining: capacity - held - sold,
});

/** Session 1: GA has three releases (public sold out, promoter hold all held, door open); VIP all held. Session 2: GA available. */
const ROWS: CounterRow[] = [
  row("b1", GA, S1, "public_sale", 300, 0, 300),
  row("b2", GA, S1, "promoter_hold", 40, 40, 0),
  row("b3", GA, S1, "door", 30, 0, 10),
  row("b4", VIP, S1, "public_sale", 20, 20, 0),
  row("b5", GA, S2, "public_sale", 100, 5, 60),
  row("b6", VIP, S2, "public_sale", 10, 0, 10),
];

beforeEach(() => {
  mocks.create.mockReset();
  mocks.schema.mockReset();
  mocks.rpc.mockReset();
  mocks.schema.mockReturnValue({ rpc: mocks.rpc });
  mocks.create.mockResolvedValue({ schema: mocks.schema });
});
afterEach(() => {
  vi.unstubAllEnvs();
});

describe("dbInventoryCounters — the read", () => {
  it("calls venue_cmd.get_inventory_counters(p_event_id) and hands the rows back unchanged", async () => {
    mocks.rpc.mockResolvedValue({ data: ROWS, error: null, status: 200 });
    const r = await dbInventoryCounters(E);
    expect(mocks.schema).toHaveBeenCalledWith("venue_cmd");
    expect(mocks.rpc).toHaveBeenCalledTimes(1);
    expect(mocks.rpc).toHaveBeenCalledWith("get_inventory_counters", { p_event_id: E });
    expect(r).toEqual({ ok: true, data: ROWS });
  });
  it("an empty event (no batches) is ok with zero rows — rows, not zeros", async () => {
    mocks.rpc.mockResolvedValue({ data: [], error: null, status: 200 });
    expect(await dbInventoryCounters(E)).toEqual({ ok: true, data: [] });
  });
  it.each([
    ["P0002", "not_found: event 1111", "error"], // unknown AND unauthorized events answer alike (160 (d)); never zero
    ["42501", "permission denied for schema venue_cmd", "permission"],
    ["PGRST106", "Invalid schema: venue_cmd", "not_exposed"], // the dark state today
    ["PGRST301", "JWT expired", "auth"],
    ["42883", "function venue_cmd.get_inventory_counters(uuid) does not exist", "config"],
    ["XX000", "boom", "error"],
  ])("a returned error %s → ReadFailure %s with no data at all", async (code, message, kind) => {
    mocks.rpc.mockResolvedValue({ data: null, error: { code, message, details: null, hint: null }, status: 400 });
    const r = await dbInventoryCounters(E);
    expect(r).toMatchObject({ ok: false, kind, code, read: "venue_cmd.get_inventory_counters" });
    expect(r).not.toHaveProperty("data");
  });
  it("a missing-object failure names the venue_cmd transport migration, not F's read-views one", async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { code: "42883", message: "function venue_cmd.get_inventory_counters(uuid) does not exist" }, status: 404 });
    const r = await dbInventoryCounters(E);
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.kind).toBe("config");
      expect(r.message).toMatch(/venue_cmd/);
      expect(r.message).not.toMatch(/venue_api_read_views/);
    }
  });
  it("a thrown transport error → ReadFailure transport, never zeros", async () => {
    mocks.rpc.mockRejectedValue(new TypeError("fetch failed"));
    const r = await dbInventoryCounters(E);
    expect(r).toMatchObject({ ok: false, kind: "transport", read: "venue_cmd.get_inventory_counters" });
    expect(r).not.toHaveProperty("data");
  });
  it("a client that cannot be built (config) → ReadFailure config; the RPC is never called", async () => {
    const { SupabaseConfigError } = await import("@/lib/supabase/server");
    mocks.create.mockRejectedValue(new SupabaseConfigError("not set"));
    expect(await dbInventoryCounters(E)).toMatchObject({ ok: false, kind: "config" });
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it("rows in an unexpected shape are a failure, not coerced to zero counters", async () => {
    for (const data of [null, "rows", { capacity: 1 }, [{ batch_id: "b", capacity: "100" }], [{ ...ROWS[0], held: null }], [{ ...ROWS[0], sold: undefined }]]) {
      mocks.rpc.mockResolvedValue({ data, error: null, status: 200 });
      const r = await dbInventoryCounters(E);
      expect(r, JSON.stringify(data)).toMatchObject({ ok: false, kind: "error" });
      expect(r).not.toHaveProperty("data");
    }
  });
  it("refuses a non-uuid event id without touching the client", async () => {
    expect(await dbInventoryCounters("smp_evt_1")).toMatchObject({ ok: false, kind: "error" });
    expect(await dbInventoryCounters("")).toMatchObject({ ok: false, kind: "error" });
    expect(mocks.create).not.toHaveBeenCalled();
  });
});

describe("rollUpCounters — per (session, tier), with the F3 chip states", () => {
  const up = rollUpCounters(ROWS);
  const find = (s: string, tt: string) => up.find((x) => x.sessionId === s && x.ticketTypeId === tt);
  it("sums the four counters across a tier's releases within one session and never across sessions", () => {
    expect(find(S1, GA)).toMatchObject({ capacity: 370, held: 40, sold: 310, remaining: 20, state: "available", countersKnown: true });
    expect(find(S2, GA)).toMatchObject({ capacity: 100, held: 5, sold: 60, remaining: 35, state: "available", countersKnown: true });
    expect(up).toHaveLength(4);
  });
  it("sold out (remaining 0, nothing held) and all held (remaining 0, something held) are distinct states", () => {
    expect(find(S2, VIP)).toMatchObject({ capacity: 10, held: 0, sold: 10, remaining: 0, state: "sold_out" });
    expect(find(S1, VIP)).toMatchObject({ capacity: 20, held: 20, sold: 0, remaining: 0, state: "all_held" });
    // Mixed: everything consumed, part of it by holds → all held (releasing the holds puts tickets back on sale).
    expect(rollUpCounters([row("x", GA, S1, "public_sale", 50, 10, 40)])[0]).toMatchObject({ remaining: 0, state: "all_held" });
  });
  it("uses lib/inventory.ts availability() for the state, so the chip logic has one home", () => {
    for (const t of up) expect(t.state).toBe(availability({ capacity: t.capacity, held: t.held, sold: t.sold }));
  });
  it("keeps first-seen order of (session, tier) and marks every roll-up as counters known", () => {
    expect(up.map((t) => [t.sessionId, t.ticketTypeId])).toEqual([
      [S1, GA],
      [S1, VIP],
      [S2, GA],
      [S2, VIP],
    ]);
    expect(up.every((t) => t.countersKnown === true)).toBe(true);
    expect(rollUpCounters([])).toEqual([]);
  });
});
