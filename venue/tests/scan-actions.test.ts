import { beforeEach, describe, expect, it, vi } from "vitest";
import { makeWire, ATOM, SESS } from "./helpers/credential-wire";

const mocks = vi.hoisted(() => ({
  probeSession: vi.fn(),
  dbMyGrants: vi.fn(),
  dbGetEvent: vi.fn(),
  rpc: vi.fn(),
  from: vi.fn(),
  dataSource: { value: "database" as "database" | "fixtures" },
}));
vi.mock("@/lib/auth/session", () => ({ probeSession: mocks.probeSession }));
vi.mock("@/lib/db/adapters", () => ({ dbMyGrants: mocks.dbMyGrants, dbGetEvent: mocks.dbGetEvent }));
vi.mock("@/lib/env", () => ({
  get DATA_SOURCE() {
    return mocks.dataSource.value;
  },
}));
vi.mock("@/lib/supabase/server", () => ({
  SupabaseConfigError: class extends Error {},
  createSupabaseServerClient: async () => ({ schema: () => ({ rpc: mocks.rpc, from: mocks.from }) }),
}));

import { readSessionScanCounters, scanAction } from "@/lib/scan/actions";

const IDS = { orgId: "24232848-0bcf-4fa9-8040-c8bd2dc38ed2", venueId: "5e8db24b-a0ac-440a-9f00-fa15ee3bbb75", eventId: "9a000000-0000-4000-8000-000000000001" };
const input = (over: Partial<Parameters<typeof scanAction>[0]> = {}) => ({ ...IDS, sessionId: SESS, wire: makeWire({ exp: 4_000_000_000 }), commandKey: "11111111-2222-4333-8444-555555555555", deviceLabel: "Door A phone", retried: false, ...over });
const scanner = { venueRoles: ["venue_scanner"], orgRoles: [] };
const event = { ok: true, data: { eventId: IDS.eventId, venueId: IDS.venueId, orgId: IDS.orgId, title: "t", status: "published", sessions: [{ sessionId: SESS }] } };

beforeEach(() => {
  mocks.dataSource.value = "database";
  mocks.probeSession.mockReset().mockResolvedValue({ ok: true, user: { id: "u1", email: "door@example.test", aal: "aal1" } });
  mocks.dbMyGrants.mockReset().mockResolvedValue({ ok: true, data: scanner });
  mocks.dbGetEvent.mockReset().mockResolvedValue(event);
  mocks.rpc.mockReset();
  mocks.from.mockReset();
});

describe("scanAction — the gate", () => {
  it("fixtures mode never calls anything: CANNOT VERIFY (demo)", async () => {
    mocks.dataSource.value = "fixtures";
    expect(await scanAction(input())).toEqual({ kind: "outcome", outcome: { kind: "cannot_verify", why: "demo", retrySameKey: false } });
    expect(mocks.probeSession).not.toHaveBeenCalled();
  });
  it("signed out → blocked signed_out; a role that cannot scan → blocked no_role; a session not on the route event → blocked no_role; nothing is sent", async () => {
    mocks.probeSession.mockResolvedValue({ ok: true, user: null });
    expect(await scanAction(input())).toEqual({ kind: "blocked", why: "signed_out" });
    mocks.probeSession.mockResolvedValue({ ok: true, user: { id: "u1", email: null, aal: "aal1" } });
    mocks.dbMyGrants.mockResolvedValue({ ok: true, data: { venueRoles: ["venue_finance"], orgRoles: ["org_owner"] } });
    expect(await scanAction(input())).toEqual({ kind: "blocked", why: "no_role" });
    mocks.dbMyGrants.mockResolvedValue({ ok: true, data: scanner });
    expect(await scanAction(input({ sessionId: "5e55e55e-0000-4000-8000-000000000009" }))).toEqual({ kind: "blocked", why: "no_role" });
    mocks.dbGetEvent.mockResolvedValue({ ok: true, data: { ...event.data, venueId: "00000000-0000-4000-8000-000000000000" } });
    expect(await scanAction(input())).toEqual({ kind: "blocked", why: "no_role" });
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it("ids that are not uuids are refused before any read", async () => {
    expect(await scanAction(input({ eventId: "smp_evt_sat_music" }))).toEqual({ kind: "blocked", why: "no_role" });
    expect(mocks.probeSession).not.toHaveBeenCalled();
  });
});

describe("scanAction — the call", () => {
  it("a good pass is sent once with the atom from the token, the selected session, the phone's label and the command key; admitted comes back green", async () => {
    mocks.rpc.mockResolvedValue({ data: { status: "ok", scan_id: "s1", result: "admitted" }, error: null, status: 200 });
    const r = await scanAction(input());
    expect(r).toEqual({ kind: "outcome", outcome: { kind: "admitted", atomId: ATOM, scanId: "s1" } });
    expect(mocks.rpc).toHaveBeenCalledTimes(1);
    const [fn, args] = mocks.rpc.mock.calls[0];
    expect(fn).toBe("record_scan");
    expect(args.p_atom_id).toBe(ATOM);
    expect(args.p_session_id).toBe(SESS);
    expect(args.p_command_key).toBe("11111111-2222-4333-8444-555555555555");
    expect(args.p_scan_meta.device_label).toBe("Door A phone");
    expect(args.p_scan_meta).not.toHaveProperty("device_id");
    expect(typeof args.p_scan_meta.occurred_at).toBe("string");
  });
  it("client-side refusals never reach the server: wrong session claim, stale pass, garbage", async () => {
    expect(await scanAction(input({ wire: makeWire({ sess: "5e55e55e-0000-4000-8000-000000000002", exp: 4_000_000_000 }) }))).toEqual({ kind: "outcome", outcome: { kind: "wrong_event", atomId: ATOM, tokenSessionId: "5e55e55e-0000-4000-8000-000000000002" } });
    expect(await scanAction(input({ wire: makeWire({ exp: 1, iat: 0 }) }))).toEqual({ kind: "outcome", outcome: { kind: "invalid", why: "stale_pass" } });
    expect(await scanAction(input({ wire: "garbage" }))).toEqual({ kind: "outcome", outcome: { kind: "invalid", why: "malformed" } });
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it("a server 'invalid' is resolved through validate_ticket_online: scanned → ALREADY USED (this phone's retry flagged), anything else → INVALID", async () => {
    mocks.rpc.mockResolvedValueOnce({ data: { status: "ok", scan_id: "s2", result: "invalid" }, error: null, status: 200 }).mockResolvedValueOnce({ data: { status: "ok", ticket_state: "scanned", resale_state: "none", admissible: false }, error: null, status: 200 });
    expect(await scanAction(input({ retried: true }))).toEqual({ kind: "outcome", outcome: { kind: "already_used", atomId: ATOM, prior: null, possiblyThisPhone: true } });
    expect(mocks.rpc.mock.calls[1][0]).toBe("validate_ticket_online");
    mocks.rpc.mockReset();
    mocks.rpc.mockResolvedValueOnce({ data: { status: "ok", scan_id: "s3", result: "invalid" }, error: null, status: 200 }).mockResolvedValueOnce({ data: { status: "not_found" }, error: null, status: 200 });
    expect(await scanAction(input())).toEqual({ kind: "outcome", outcome: { kind: "invalid", why: "server" } });
    mocks.rpc.mockReset();
    mocks.rpc.mockResolvedValueOnce({ data: { status: "ok", scan_id: "s4", result: "invalid" }, error: null, status: 200 }).mockRejectedValueOnce(new Error("boom"));
    expect(await scanAction(input())).toEqual({ kind: "outcome", outcome: { kind: "invalid", why: "server" } });
  });
  it("duplicate with prior after 183 renders ALREADY USED with the prior; not exposed → not enabled; 42501 → blocked; a throw → CANNOT VERIFY (transport) with the same-key retry", async () => {
    mocks.rpc.mockResolvedValue({ data: { status: "ok", scan_id: "s5", result: "duplicate", prior: { scan_id: "s1", occurred_at: "2026-11-30T03:05:00Z", actor_label: "door@example.test", device_label: "Door A phone" } }, error: null, status: 200 });
    const dup = await scanAction(input());
    expect(dup.kind === "outcome" && dup.outcome.kind === "already_used" && dup.outcome.prior?.deviceLabel).toBe("Door A phone");
    mocks.rpc.mockResolvedValue({ data: null, error: { code: "PGRST106", message: "The schema must be one of the following: public, graphql_public" }, status: 406 });
    expect(await scanAction(input())).toEqual({ kind: "outcome", outcome: { kind: "cannot_verify", why: "not_enabled", retrySameKey: false } });
    mocks.rpc.mockResolvedValue({ data: null, error: { code: "42501", message: "insufficient_privilege" }, status: 403 });
    expect(await scanAction(input())).toEqual({ kind: "blocked", why: "no_role" });
    mocks.rpc.mockRejectedValue(new TypeError("fetch failed"));
    expect(await scanAction(input())).toEqual({ kind: "outcome", outcome: { kind: "cannot_verify", why: "transport", retrySameKey: true } });
  });
});

describe("readSessionScanCounters — measured or unavailable, never zero by default", () => {
  const chain = (result: unknown) => ({ select: () => ({ eq: () => ({ limit: () => Promise.resolve(result) }) }) });
  it("a row is numbers; no row is null; not exposed is unavailable; fixtures is unavailable", async () => {
    mocks.from.mockReturnValue(chain({ data: [{ session_id: SESS, admitted: 12, duplicate: 1, invalid: 2, last_admitted_at: "2026-11-30T04:00:00Z" }], error: null, status: 200 }));
    expect(await readSessionScanCounters({ ...IDS, sessionId: SESS })).toEqual({ ok: true, data: { sessionId: SESS, admitted: 12, duplicate: 1, invalid: 2, lastAdmittedAt: "2026-11-30T04:00:00Z" } });
    expect(mocks.from).toHaveBeenCalledWith("session_admissions");
    mocks.from.mockReturnValue(chain({ data: [], error: null, status: 200 }));
    expect(await readSessionScanCounters({ ...IDS, sessionId: SESS })).toEqual({ ok: true, data: null });
    mocks.from.mockReturnValue(chain({ data: null, error: { code: "PGRST106", message: "not exposed" }, status: 406 }));
    const ne = await readSessionScanCounters({ ...IDS, sessionId: SESS });
    expect(ne.ok).toBe(false);
    if (!ne.ok) expect(ne.kind).toBe("not_exposed");
    mocks.dataSource.value = "fixtures";
    const fx = await readSessionScanCounters({ ...IDS, sessionId: SESS });
    expect(fx.ok).toBe(false);
  });
  it("a count that is not a number is an error, not a zero", async () => {
    mocks.from.mockReturnValue(chain({ data: [{ session_id: SESS, admitted: "12", duplicate: 1, invalid: 2, last_admitted_at: null }], error: null, status: 200 }));
    const r = await readSessionScanCounters({ ...IDS, sessionId: SESS });
    expect(r.ok).toBe(false);
  });
});
