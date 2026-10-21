/**
 * Resale policy in force for an event, as the dashboard shows it. The server's own rule
 * (088 market_native_rail: create_native_listing / buy_now) is
 *   where (scope_kind='event' and event_id = E) or (scope_kind='venue' and venue_id = V)
 *   order by (scope_kind = 'event') desc, version desc limit 1
 * so an event-scope policy wins over a venue-scope one, and a venue-wide policy applies to every
 * event at that venue that has none of its own. Before this the dashboard read event-scope rows
 * only, and a venue-wide policy was never shown.
 */
import { beforeEach, describe, expect, it, vi } from "vitest";
import { mapEvents, type PolicyRow } from "@/lib/db/rows";

const V = "5a4d0b0e-0000-4000-8000-0000000000aa";
const W = "5a4d0b0e-0000-4000-8000-0000000000bb";
const E1 = "5a4d0b0e-0000-4000-8000-0000000000e1";
const E2 = "5a4d0b0e-0000-4000-8000-0000000000e2";
const O = "5a4d0b0e-0000-4000-8000-00000000000a";
const ev = (event_id: string, venue_id = V) => ({ event_id, venue_id, org_id: O, title: event_id, status: "on_sale" });
const pol = (p: Partial<PolicyRow> & Pick<PolicyRow, "policy_id" | "scope_kind" | "mode" | "version">): PolicyRow => ({ venue_id: null, event_id: null, ...p });

describe("mapEvents resolves the in-force policy the way the server does", () => {
  it("an event-scope policy wins over a venue-scope one, whatever the versions", () => {
    const [e] = mapEvents([ev(E1)], [], [pol({ policy_id: "pv", scope_kind: "venue", venue_id: V, mode: "buy_now", version: 9 }), pol({ policy_id: "pe", scope_kind: "event", event_id: E1, mode: "transfers_only", version: 1 })]);
    expect(e.resaleMode).toBe("transfers_only");
  });
  it("an event with no policy of its own gets its venue's policy (highest version)", () => {
    const [e] = mapEvents([ev(E2)], [], [pol({ policy_id: "pv1", scope_kind: "venue", venue_id: V, mode: "off", version: 1 }), pol({ policy_id: "pv2", scope_kind: "venue", venue_id: V, mode: "fixed_cap", version: 2 })]);
    expect(e.resaleMode).toBe("fixed_cap");
  });
  it("another venue's policy, or another event's, never applies", () => {
    const [e] = mapEvents([ev(E2)], [], [pol({ policy_id: "pw", scope_kind: "venue", venue_id: W, mode: "buy_now", version: 3 }), pol({ policy_id: "pe1", scope_kind: "event", event_id: E1, mode: "auction", version: 1 })]);
    expect(e.resaleMode).toBe("off");
  });
  it("an event-scope 'off' still overrides a permissive venue policy", () => {
    const [e] = mapEvents([ev(E1)], [], [pol({ policy_id: "pv", scope_kind: "venue", venue_id: V, mode: "buy_now", version: 4 }), pol({ policy_id: "pe", scope_kind: "event", event_id: E1, mode: "off", version: 1 })]);
    expect(e.resaleMode).toBe("off");
  });
});

// ---------------------------------------------------------------------------
// The adapters must also READ the venue-scope rows. A tiny in-memory venue_api stands in for
// PostgREST: it applies select/eq/in/limit to fixed rows, so only what the adapter asks for comes back.
// ---------------------------------------------------------------------------
type Row = Record<string, unknown>;
const tables = vi.hoisted(() => ({ rows: {} as Record<string, Record<string, unknown>[]>, calls: [] as string[] }));
vi.mock("@/lib/supabase/server", () => {
  class SupabaseConfigError extends Error {}
  function query(table: string) {
    let out = [...(tables.rows[table] ?? [])];
    const desc: string[] = [table];
    const q = {
      select(cols: string) {
        desc.push(`select(${cols})`);
        return q;
      },
      eq(col: string, val: unknown) {
        desc.push(`eq(${col})`);
        out = out.filter((r) => r[col] === val);
        return q;
      },
      in(col: string, vals: unknown[]) {
        desc.push(`in(${col})`);
        out = out.filter((r) => vals.includes(r[col]));
        return q;
      },
      limit(n: number) {
        out = out.slice(0, n);
        return q;
      },
      then(resolve: (v: { data: Row[]; error: null; status: number }) => unknown) {
        tables.calls.push(desc.join("."));
        return Promise.resolve({ data: out, error: null, status: 200 }).then(resolve);
      },
    };
    return q;
  }
  return { SupabaseConfigError, createSupabaseServerClient: async () => ({ schema: () => ({ from: query }) }) };
});

describe("the event reads include the route venue's venue-wide policy", () => {
  beforeEach(() => {
    tables.calls = [];
    tables.rows = {
      events: [ev(E1), ev(E2), ev("5a4d0b0e-0000-4000-8000-0000000000e3", W)],
      event_sessions: [],
      resale_policies: [
        pol({ policy_id: "pe1", scope_kind: "event", event_id: E1, mode: "transfers_only", version: 1 }),
        pol({ policy_id: "pv1", scope_kind: "venue", venue_id: V, mode: "off", version: 1 }),
        pol({ policy_id: "pv2", scope_kind: "venue", venue_id: V, mode: "fixed_cap", version: 2 }),
        pol({ policy_id: "pw1", scope_kind: "venue", venue_id: W, mode: "buy_now", version: 5 }),
      ],
    };
  });
  it("dbListEvents: own policy for E1, the venue's for E2, never venue W's", async () => {
    const { dbListEvents } = await import("@/lib/db/adapters");
    const r = await dbListEvents(V);
    expect(r.ok).toBe(true);
    const byId = Object.fromEntries((r.ok ? r.data : []).map((e) => [e.eventId, e.resaleMode]));
    expect(byId).toEqual({ [E1]: "transfers_only", [E2]: "fixed_cap" });
  });
  it("dbGetEvent: an event without its own policy shows its venue's", async () => {
    const { dbGetEvent } = await import("@/lib/db/adapters");
    const r = await dbGetEvent(E2);
    expect(r.ok && r.data?.resaleMode).toBe("fixed_cap");
  });
  it("venue-scope rows are read for the event's venue only (eq venue_id + eq scope_kind)", async () => {
    const { dbGetEvent } = await import("@/lib/db/adapters");
    await dbGetEvent(E2);
    expect(tables.calls.filter((c) => c.startsWith("resale_policies"))).toContainEqual(expect.stringMatching(/eq\(scope_kind\).*eq\(venue_id\)|eq\(venue_id\).*eq\(scope_kind\)/));
  });
});
