import { afterEach, describe, expect, it, vi } from "vitest";

/**
 * The event/session/venue actions: the dark gate, what never reaches the
 * server, and the exact RPC name and argument names for what does.
 * DATA_SOURCE is fixed at import and the gate is read per call, so each state
 * reloads the module (D's pattern in tests/db-commands.test.ts).
 */
const rpc = vi.fn();

async function load(opts: { source?: string; gate?: string } = {}) {
  vi.resetModules();
  vi.stubEnv("NEXT_PUBLIC_VENUE_DATA_SOURCE", opts.source ?? "database");
  vi.stubEnv("VENUE_COMMANDS_ENABLED", opts.gate as string);
  vi.doMock("@/lib/supabase/server", () => ({
    SupabaseConfigError: class extends Error {},
    createSupabaseServerClient: async () => ({ schema: () => ({ rpc }) }),
  }));
  return import("@/lib/db/event-commands");
}

const VENUE = "5e8db24b-a0ac-440a-9f00-fa15ee3bbb75";
const EVENT = "9a000000-0000-4000-8000-000000000001";
const SESSION = "5e55e55e-0000-4000-8000-000000000001";
const KEY = "11111111-2222-4333-8444-555555555555";
const SESSION_PAYLOAD = { starts_at: "2026-11-30T19:00:00-05:00", session_label: "Doors" };
const ok = { data: { status: "ok", event_id: EVENT }, error: null, status: 200 };

afterEach(() => {
  vi.unstubAllEnvs();
  rpc.mockReset();
});

describe("the dark gate — the same two locks as the tier commands", () => {
  it("fixtures mode and a missing flag both answer unavailable, and nothing is sent", async () => {
    for (const opts of [{ source: "fixtures", gate: "true" }, { source: "database" }, { source: "database", gate: "TRUE" }]) {
      const m = await load(opts);
      const r = await m.publishEventAction({ eventId: EVENT, targetStatus: "announced", commandKey: KEY });
      expect(r.kind, JSON.stringify(opts)).toBe("unavailable");
    }
    expect(rpc).not.toHaveBeenCalled();
  });
});

describe("what the server is asked, verbatim", () => {
  it("each verb maps to its own RPC name and the server's own argument names", async () => {
    const m = await load({ gate: "true" });
    rpc.mockResolvedValue(ok);

    await m.createEventAction({ venueId: VENUE, title: " Pop-up ", firstSession: SESSION_PAYLOAD, commandKey: KEY });
    expect(rpc).toHaveBeenLastCalledWith("create_event", { p_venue_id: VENUE, p_title: "Pop-up", p_first_session: SESSION_PAYLOAD, p_command_key: KEY });

    await m.updateEventAction({ eventId: EVENT, patch: { title: "New" }, commandKey: KEY });
    expect(rpc).toHaveBeenLastCalledWith("update_event", { p_event_id: EVENT, p_patch: { title: "New" }, p_command_key: KEY });

    await m.createEventSessionAction({ eventId: EVENT, session: SESSION_PAYLOAD, commandKey: KEY });
    expect(rpc).toHaveBeenLastCalledWith("create_event_session", { p_event_id: EVENT, p_session: SESSION_PAYLOAD, p_command_key: KEY });

    await m.updateEventSessionAction({ sessionId: SESSION, patch: { doors_at: "2026-11-30T18:30:00-05:00" }, commandKey: KEY });
    expect(rpc).toHaveBeenLastCalledWith("update_event_session", { p_session_id: SESSION, p_patch: { doors_at: "2026-11-30T18:30:00-05:00" }, p_command_key: KEY });

    await m.publishEventAction({ eventId: EVENT, targetStatus: "on_sale", commandKey: KEY });
    expect(rpc).toHaveBeenLastCalledWith("publish_event", { p_event_id: EVENT, p_target_status: "on_sale", p_command_key: KEY });

    await m.cancelEventAction({ eventId: EVENT, reasonCode: " venue_lost ", commandKey: KEY });
    expect(rpc).toHaveBeenLastCalledWith("cancel_event", { p_event_id: EVENT, p_reason_code: "venue_lost", p_command_key: KEY });

    await m.updateVenueAction({ venueId: VENUE, patch: { address: "123 NW 2nd Ave" }, commandKey: KEY });
    expect(rpc).toHaveBeenLastCalledWith("update_venue", { p_venue_id: VENUE, p_patch: { address: "123 NW 2nd Ave" }, p_command_key: KEY });

    await m.setVenueTimezoneAction({ venueId: VENUE, timezone: " America/New_York ", reasonCode: " fix ", commandKey: KEY });
    expect(rpc).toHaveBeenLastCalledWith("set_venue_timezone", { p_venue_id: VENUE, p_timezone: "America/New_York", p_reason_code: "fix", p_command_key: KEY });

    await m.setSessionSalesCapacityAction({ sessionId: SESSION, capacity: 50, reasonCode: "pool", commandKey: KEY });
    expect(rpc).toHaveBeenLastCalledWith("set_session_sales_capacity", { p_session_id: SESSION, p_capacity: 50, p_reason_code: "pool", p_command_key: KEY });

    // null capacity means unlimited and is sent as null, not omitted
    await m.setSessionSalesCapacityAction({ sessionId: SESSION, capacity: null, reasonCode: "pool", commandKey: KEY });
    expect(rpc).toHaveBeenLastCalledWith("set_session_sales_capacity", { p_session_id: SESSION, p_capacity: null, p_reason_code: "pool", p_command_key: KEY });
  });
});

describe("what never reaches the server", () => {
  it("bad ids, empty titles, a session with no start, a missing key, a bad publish target, a bad capacity, a reasonless cancel", async () => {
    const m = await load({ gate: "true" });
    rpc.mockResolvedValue(ok);
    const refusals = [
      await m.createEventAction({ venueId: "smp_ven_room", title: "x", firstSession: SESSION_PAYLOAD, commandKey: KEY }),
      await m.createEventAction({ venueId: VENUE, title: "  ", firstSession: SESSION_PAYLOAD, commandKey: KEY }),
      await m.createEventAction({ venueId: VENUE, title: "x", firstSession: { session_label: "no start" }, commandKey: KEY }),
      await m.createEventAction({ venueId: VENUE, title: "x", firstSession: SESSION_PAYLOAD, commandKey: "" }),
      await m.publishEventAction({ eventId: EVENT, targetStatus: "cancelled", commandKey: KEY }),
      await m.publishEventAction({ eventId: EVENT, targetStatus: "draft", commandKey: KEY }),
      await m.cancelEventAction({ eventId: EVENT, reasonCode: " ", commandKey: KEY }),
      await m.setSessionSalesCapacityAction({ sessionId: SESSION, capacity: 0, reasonCode: "r", commandKey: KEY }),
      await m.setSessionSalesCapacityAction({ sessionId: SESSION, capacity: 2.5, reasonCode: "r", commandKey: KEY }),
      await m.setSessionSalesCapacityAction({ sessionId: SESSION, capacity: 50, reasonCode: "", commandKey: KEY }),
      await m.updateEventAction({ eventId: EVENT, patch: {}, commandKey: KEY }),
      await m.updateEventAction({ eventId: EVENT, patch: { reason_code: "only a reason" }, commandKey: KEY }),
      await m.setVenueTimezoneAction({ venueId: VENUE, timezone: "", reasonCode: "r", commandKey: KEY }),
      await m.setVenueTimezoneAction({ venueId: VENUE, timezone: "America/New_York", reasonCode: "", commandKey: KEY }),
    ];
    for (const r of refusals) expect(r.kind).toBe("refused");
    expect(rpc).not.toHaveBeenCalled();
  });
  it("an org move is refused even if a caller builds it into the patch", async () => {
    const m = await load({ gate: "true" });
    rpc.mockResolvedValue(ok);
    const r = await m.updateVenueAction({ venueId: VENUE, patch: { name: "x", org_id: "24232848-0bcf-4fa9-8040-c8bd2dc38ed2" }, commandKey: KEY });
    expect(r.kind).toBe("refused");
    expect(rpc).not.toHaveBeenCalled();
  });
});

describe("what comes back", () => {
  it("a receipt is ok; a refusal is mapped; no receipt is not a success; a throw is a transport failure", async () => {
    const m = await load({ gate: "true" });
    rpc.mockResolvedValue(ok);
    expect((await m.publishEventAction({ eventId: EVENT, targetStatus: "live", commandKey: KEY })).kind).toBe("ok");

    rpc.mockResolvedValue({ data: null, error: { code: "P0001", message: "precondition_failed: empty_inventory" }, status: 400 });
    const refused = await m.publishEventAction({ eventId: EVENT, targetStatus: "on_sale", commandKey: KEY });
    expect(refused.kind).toBe("refused");

    rpc.mockResolvedValue({ data: null, error: { code: "42501", message: "insufficient_privilege" }, status: 403 });
    expect((await m.updateEventAction({ eventId: EVENT, patch: { title: "x" }, commandKey: KEY })).kind).toBe("refused");

    rpc.mockResolvedValue({ data: "surprise", error: null, status: 200 });
    const noReceipt = await m.updateEventAction({ eventId: EVENT, patch: { title: "x" }, commandKey: KEY });
    expect(noReceipt.kind).toBe("refused");
    if (noReceipt.kind === "refused") expect(noReceipt.message).toMatch(/didn't confirm|did not confirm/i);

    rpc.mockRejectedValue(new TypeError("fetch failed"));
    expect((await m.updateEventAction({ eventId: EVENT, patch: { title: "x" }, commandKey: KEY })).kind).toBe("refused");

    rpc.mockResolvedValue({ data: null, error: { code: "PGRST202", message: "Could not find the function" }, status: 404 });
    expect((await m.updateEventAction({ eventId: EVENT, patch: { title: "x" }, commandKey: KEY })).kind).toBe("unavailable");
  });
});
