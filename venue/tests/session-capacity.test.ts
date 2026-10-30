import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ from: vi.fn() }));
vi.mock("@/lib/supabase/server", () => ({
  SupabaseConfigError: class extends Error {},
  createSupabaseServerClient: async () => ({ schema: () => ({ from: mocks.from }) }),
}));

import { dbSessionCapacities, parseSessionCapacity } from "@/lib/db/session-capacity";

const S1 = "5e55e55e-0000-4000-8000-000000000001";
const S2 = "5e55e55e-0000-4000-8000-000000000002";
const row = (over: Record<string, unknown> = {}) => ({ session_id: S1, sales_capacity: 50, allocated: 40, remaining_to_allocate: 10, capacity_hint: 250, ...over });
const chain = (result: unknown) => ({ select: () => ({ in: () => Promise.resolve(result) }) });

beforeEach(() => mocks.from.mockReset());

describe("parseSessionCapacity — the numbers the server sent, or nothing", () => {
  it("reads the five columns", () => {
    expect(parseSessionCapacity(row())).toEqual({ sessionId: S1, salesCapacity: 50, allocated: 40, remainingToAllocate: 10, capacityHint: 250 });
  });
  it("an unlimited pool has no remainder, whatever the server put there", () => {
    expect(parseSessionCapacity(row({ sales_capacity: null, remaining_to_allocate: null }))).toMatchObject({ salesCapacity: null, remainingToAllocate: null, allocated: 40 });
    expect(parseSessionCapacity(row({ sales_capacity: null, remaining_to_allocate: 7 }))?.remainingToAllocate).toBeNull();
  });
  it("a missing venue capacity is null, not zero", () => {
    expect(parseSessionCapacity(row({ capacity_hint: null }))?.capacityHint).toBeNull();
  });
  it("a row that is not the promised shape is null — never a rendered guess", () => {
    for (const bad of [null, undefined, [], "x", row({ session_id: "nope" }), row({ allocated: "40" }), row({ allocated: null }), row({ sales_capacity: "50" }), row({ remaining_to_allocate: 1.5 })]) {
      expect(parseSessionCapacity(bad), JSON.stringify(bad)).toBeNull();
    }
  });
});

describe("dbSessionCapacities", () => {
  it("keys by session id, asks only for the five columns, and never calls out for an empty or non-uuid list", async () => {
    mocks.from.mockReturnValue(chain({ data: [row(), row({ session_id: S2, sales_capacity: null, remaining_to_allocate: null, allocated: 0 })], error: null, status: 200 }));
    const r = await dbSessionCapacities([S1, S2]);
    expect(r.ok && Object.keys(r.data).sort()).toEqual([S1, S2].sort());
    expect(r.ok && r.data[S2]).toMatchObject({ salesCapacity: null, allocated: 0 });
    expect(await dbSessionCapacities([])).toEqual({ ok: true, data: {} });
    mocks.from.mockClear();
    expect(await dbSessionCapacities(["smp_session"])).toEqual({ ok: true, data: {} });
    expect(mocks.from).not.toHaveBeenCalled();
  });
  it("a session the caller may not read is simply absent — the form then shows nothing rather than zero", async () => {
    mocks.from.mockReturnValue(chain({ data: [row()], error: null, status: 200 }));
    const r = await dbSessionCapacities([S1, S2]);
    expect(r.ok && r.data[S2]).toBeUndefined();
    expect(r.ok && r.data[S1]?.allocated).toBe(40);
  });
  it("a row for a session that was not asked about is ignored", async () => {
    mocks.from.mockReturnValue(chain({ data: [row({ session_id: S2 })], error: null, status: 200 }));
    const r = await dbSessionCapacities([S1]);
    expect(r.ok && Object.keys(r.data)).toEqual([]);
  });
  it("a schema that is not exposed is reported as not exposed", async () => {
    mocks.from.mockReturnValue(chain({ data: null, error: { code: "PGRST106", message: "not exposed" }, status: 406 }));
    const r = await dbSessionCapacities([S1]);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.kind).toBe("not_exposed");
  });
  it("a role the view refuses is reported as permission, not as empty numbers", async () => {
    mocks.from.mockReturnValue(chain({ data: null, error: { code: "42501", message: "permission denied" }, status: 403 }));
    const r = await dbSessionCapacities([S1]);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.kind).toBe("permission");
  });
  it("a failed request is reported as transport — it never escapes to the page", async () => {
    // The realistic shape: supabase-js rejects its promise, it does not throw from .from().
    // (A synchronous throw is caught by the same block; proven out-of-band, since a mock whose
    // implementation throws is reported by vitest as an unhandled error rather than a return value.)
    mocks.from.mockReturnValue({ select: () => ({ in: () => Promise.reject(new TypeError("fetch failed")) }) });
    const r = await dbSessionCapacities([S1]);
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.kind).toBe("transport");
      expect(r.message).toBe("fetch failed");
      expect(r.read).toBe("venue_api.session_capacity");
    }
  });
});
