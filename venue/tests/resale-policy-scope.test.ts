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
import { mapEvents, type PolicyRow, type VenueApprovalRow } from "@/lib/db/rows";

const V = "5a4d0b0e-0000-4000-8000-0000000000aa";
const W = "5a4d0b0e-0000-4000-8000-0000000000bb";
const E1 = "5a4d0b0e-0000-4000-8000-0000000000e1";
const E2 = "5a4d0b0e-0000-4000-8000-0000000000e2";
const O = "5a4d0b0e-0000-4000-8000-00000000000a";
const ev = (event_id: string, venue_id = V) => ({ event_id, venue_id, org_id: O, title: event_id, status: "on_sale" });
const pol = (p: Partial<PolicyRow> & Pick<PolicyRow, "policy_id" | "scope_kind" | "mode" | "version">): PolicyRow => ({ venue_id: null, event_id: null, ...p });
// venue_api.venues rows as the caller reads them (approval_status is a granted column of the view).
const approved: VenueApprovalRow[] = [
  { venue_id: V, approval_status: "approved" },
  { venue_id: W, approval_status: "approved" },
];

describe("mapEvents resolves the in-force policy the way the server does", () => {
  it("an event-scope policy wins over a venue-scope one, whatever the versions", () => {
    const [e] = mapEvents([ev(E1)], [], [pol({ policy_id: "pv", scope_kind: "venue", venue_id: V, mode: "buy_now", version: 9 }), pol({ policy_id: "pe", scope_kind: "event", event_id: E1, mode: "transfers_only", version: 1 })], approved);
    expect(e.resaleMode).toBe("transfers_only");
  });
  it("an event with no policy of its own gets its venue's policy (highest version)", () => {
    const [e] = mapEvents([ev(E2)], [], [pol({ policy_id: "pv1", scope_kind: "venue", venue_id: V, mode: "off", version: 1 }), pol({ policy_id: "pv2", scope_kind: "venue", venue_id: V, mode: "fixed_cap", version: 2 })], approved);
    expect(e.resaleMode).toBe("fixed_cap");
  });
  it("another venue's policy, or another event's, never applies", () => {
    const [e] = mapEvents([ev(E2)], [], [pol({ policy_id: "pw", scope_kind: "venue", venue_id: W, mode: "buy_now", version: 3 }), pol({ policy_id: "pe1", scope_kind: "event", event_id: E1, mode: "auction", version: 1 })], approved);
    expect(e.resaleMode).toBe("off");
  });
  it("an event-scope 'off' still overrides a permissive venue policy", () => {
    const [e] = mapEvents([ev(E1)], [], [pol({ policy_id: "pv", scope_kind: "venue", venue_id: V, mode: "buy_now", version: 4 }), pol({ policy_id: "pe", scope_kind: "event", event_id: E1, mode: "off", version: 1 })], approved);
    expect(e.resaleMode).toBe("off");
  });
});

// RLS (078 catalog_resale_policy_sel_public: `e.status <> 'draft'`) hides a draft's own event-scope policy
// from every client, while its venue's venue-wide row stays visible. The server (088, definer) still resolves
// the hidden event row first, so a draft resolved from what the caller can see could show a MORE permissive
// mode than the one that will apply. A draft without a visible event-scope row is therefore not readable.
describe("a draft event's resale mode is not resolved from the venue's policy alone", () => {
  const draft = (event_id: string) => ({ ...ev(event_id), status: "draft" });
  it("a draft that can see only its venue's policy reads as not_readable, never the venue's mode", () => {
    const [e] = mapEvents([draft(E1)], [], [pol({ policy_id: "pv", scope_kind: "venue", venue_id: V, mode: "buy_now", version: 1 })], approved);
    expect(e.resaleMode).toBe("not_readable");
  });
  it("a draft with no visible policy at all reads as not_readable, not 'off'", () => {
    const [e] = mapEvents([draft(E1)], [], [], approved);
    expect(e.resaleMode).toBe("not_readable");
  });
  it("a draft whose own event-scope row is visible shows that row (event scope always wins)", () => {
    const [e] = mapEvents([draft(E1)], [], [pol({ policy_id: "pv", scope_kind: "venue", venue_id: V, mode: "buy_now", version: 7 }), pol({ policy_id: "pe", scope_kind: "event", event_id: E1, mode: "transfers_only", version: 1 })], approved);
    expect(e.resaleMode).toBe("transfers_only");
  });
  it("another event's visible row does not make a draft readable", () => {
    const [e] = mapEvents([draft(E2)], [], [pol({ policy_id: "pe1", scope_kind: "event", event_id: E1, mode: "auction", version: 1 })], approved);
    expect(e.resaleMode).toBe("not_readable");
  });
  it("only the 'draft' status hides the row: announced and unknown statuses resolve as before", () => {
    const venueBuyNow = [pol({ policy_id: "pv", scope_kind: "venue", venue_id: V, mode: "buy_now", version: 1 })];
    expect(mapEvents([{ ...ev(E1), status: "announced" }], [], venueBuyNow, approved)[0].resaleMode).toBe("buy_now");
    expect(mapEvents([{ ...ev(E1), status: "weird" }], [], [], approved)[0].resaleMode).toBe("off");
  });
});

// RLS (078 catalog_resale_policy_sel_public: `v.approval_status = 'approved'`) also hides every venue-wide row of a
// venue that is not approved, from every client, its own staff included. 088 create_native_listing resolves that
// hidden row with no approval check, so an announced event at a pending venue with a venue-wide buy_now policy would
// read as "Off" while the server admits buy_now listings. Without a visible event-scope row of its own, an event at a
// venue that is not known to be approved is therefore not readable, exactly like a draft.
describe("an event at a venue that is not approved is not resolved from what RLS lets the caller see", () => {
  const pending = (status: string): VenueApprovalRow[] => [{ venue_id: V, approval_status: status }];
  const announced = (event_id: string) => ({ ...ev(event_id), status: "announced" });
  it.each(["pending", "draft", "archived"])("a %s venue's announced event with no visible row of its own reads as not_readable, not 'off'", (status) => {
    // What the caller sees: nothing (the venue-wide buy_now row is hidden by RLS).
    expect(mapEvents([announced(E1)], [], [], pending(status))[0].resaleMode).toBe("not_readable");
  });
  it("a visible event-scope row still decides it (the server takes event scope first)", () => {
    const [e] = mapEvents([announced(E1)], [], [pol({ policy_id: "pe", scope_kind: "event", event_id: E1, mode: "transfers_only", version: 1 })], pending("pending"));
    expect(e.resaleMode).toBe("transfers_only");
  });
  it("a venue row the caller cannot read counts as not approved (unknown, never 'off')", () => {
    expect(mapEvents([announced(E1)], [], [], [])[0].resaleMode).toBe("not_readable");
    expect(mapEvents([announced(E1)], [], [pol({ policy_id: "pv", scope_kind: "venue", venue_id: V, mode: "buy_now", version: 1 })], [])[0].resaleMode).toBe("not_readable");
  });
  it("another venue's approval does not make this venue's event readable", () => {
    expect(mapEvents([announced(E1)], [], [], [{ venue_id: W, approval_status: "approved" }])[0].resaleMode).toBe("not_readable");
  });
  it("an approved venue with no policy at all is genuinely off", () => {
    expect(mapEvents([announced(E1)], [], [], approved)[0].resaleMode).toBe("off");
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
      venues: [...approved],
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
  it("dbListEvents: a draft at the venue reads as not_readable even though the venue's policy is visible", async () => {
    tables.rows.events = [ev(E1), { ...ev(E2), status: "draft" }];
    const { dbListEvents } = await import("@/lib/db/adapters");
    const r = await dbListEvents(V);
    const byId = Object.fromEntries((r.ok ? r.data : []).map((e) => [e.eventId, e.resaleMode]));
    expect(byId).toEqual({ [E1]: "transfers_only", [E2]: "not_readable" });
  });
  it("venue-scope rows are read for the event's venue only (eq venue_id + eq scope_kind)", async () => {
    const { dbGetEvent } = await import("@/lib/db/adapters");
    await dbGetEvent(E2);
    expect(tables.calls.filter((c) => c.startsWith("resale_policies"))).toContainEqual(expect.stringMatching(/eq\(scope_kind\).*eq\(venue_id\)|eq\(venue_id\).*eq\(scope_kind\)/));
  });
  // A pending venue as its own manager sees it (the kit's C7 path): the venue row is readable (own-staff policy),
  // its venue-wide policy is not (RLS shows venue-scope rows of approved venues only), so it is left out here.
  const pendingVenue = () => {
    tables.rows.venues = [{ venue_id: V, approval_status: "pending" }];
    tables.rows.events = [{ ...ev(E1), status: "announced" }, { ...ev(E2), status: "announced" }];
    tables.rows.resale_policies = [pol({ policy_id: "pe1", scope_kind: "event", event_id: E1, mode: "transfers_only", version: 1 })];
  };
  it("dbListEvents at a pending venue: an event without a visible own row reads as not_readable, never 'off'", async () => {
    pendingVenue();
    const { dbListEvents } = await import("@/lib/db/adapters");
    const r = await dbListEvents(V);
    const byId = Object.fromEntries((r.ok ? r.data : []).map((e) => [e.eventId, e.resaleMode]));
    expect(byId).toEqual({ [E1]: "transfers_only", [E2]: "not_readable" });
  });
  it("dbGetEvent at a pending venue: the same rule", async () => {
    pendingVenue();
    const { dbGetEvent } = await import("@/lib/db/adapters");
    const r = await dbGetEvent(E2);
    expect(r.ok && r.data?.resaleMode).toBe("not_readable");
  });
  it("approval_status is read from venue_api.venues for the event's venue only", async () => {
    const { dbGetEvent } = await import("@/lib/db/adapters");
    await dbGetEvent(E2);
    expect(tables.calls).toContain("venues.select(venue_id,approval_status).eq(venue_id)");
  });
});
