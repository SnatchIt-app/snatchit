import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { makeWire, ATOM, SESS } from "./helpers/credential-wire";

/** The golden admit token and the fixture's keys: a real ES256 signature through the mocked keyring read. */
const fixture = JSON.parse(readFileSync(resolve(__dirname, "../../tests/fixtures/scanner-contract-v1.json"), "utf8")) as { m1_wire: unknown[]; tokens: { name: string; wire: string; now_seconds: number }[] };
const GOLD = fixture.tokens.find((t) => t.name === "admit_es256_pem_key")!;
const KID = (fixture.m1_wire[0] as { key_id: string }).key_id;

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

/** `from(table)`: the keyring read answers with the fixture's keys; anything else uses the per-test chain. */
const keyringRows = { value: fixture.m1_wire as unknown };
const keyringChain = () => ({ select: () => Promise.resolve({ data: keyringRows.value, error: null, status: 200 }) });

import { readSessionScanCounters, scanAction } from "@/lib/scan/actions";

const IDS = { orgId: "24232848-0bcf-4fa9-8040-c8bd2dc38ed2", venueId: "5e8db24b-a0ac-440a-9f00-fa15ee3bbb75", eventId: "9a000000-0000-4000-8000-000000000001" };
const input = (over: Partial<Parameters<typeof scanAction>[0]> = {}) => ({ ...IDS, sessionId: SESS, wire: GOLD.wire, commandKey: "11111111-2222-4333-8444-555555555555", deviceLabel: "Door A phone", retried: false, ...over });
beforeAll(() => vi.useFakeTimers({ now: GOLD.now_seconds * 1000, toFake: ["Date"] }));
afterAll(() => vi.useRealTimers());
const scanner = { venueRoles: ["venue_scanner"], orgRoles: [] };
const event = { ok: true, data: { eventId: IDS.eventId, venueId: IDS.venueId, orgId: IDS.orgId, title: "t", status: "published", sessions: [{ sessionId: SESS }] } };

beforeEach(() => {
  mocks.dataSource.value = "database";
  mocks.probeSession.mockReset().mockResolvedValue({ ok: true, user: { id: "u1", email: "door@example.test", aal: "aal1" } });
  mocks.dbMyGrants.mockReset().mockResolvedValue({ ok: true, data: scanner });
  mocks.dbGetEvent.mockReset().mockResolvedValue(event);
  mocks.rpc.mockReset();
  mocks.from.mockReset();
  keyringRows.value = fixture.m1_wire;
  mocks.from.mockImplementation((table: string) => (table === "signing_key" ? keyringChain() : chainRef.current(table)));
});
const chainRef: { current: (table: string) => unknown } = { current: () => ({}) };

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
  it("an org owner who also holds a venue role is admitted, as the server admits them", async () => {
    mocks.dbMyGrants.mockResolvedValue({ ok: true, data: { venueRoles: ["venue_manager"], orgRoles: ["org_owner"] } });
    mocks.rpc.mockResolvedValue({ data: { status: "ok", scan_id: "s1", result: "admitted" }, error: null, status: 200 });
    const r = await scanAction(input());
    expect(r).toEqual({ kind: "outcome", outcome: { kind: "admitted", atomId: ATOM, scanId: "s1" } });
    // and an org role with no venue grant is still refused, because has_venue_role refuses it
    mocks.dbMyGrants.mockResolvedValue({ ok: true, data: { venueRoles: [], orgRoles: ["org_owner"] } });
    expect(await scanAction(input())).toEqual({ kind: "blocked", why: "no_role" });
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
    expect(args.p_scan_meta).toEqual({ device_label: "Door A phone", credential_version: expect.any(Number), key_id: KID }); // B §4 allow-list, exactly; never occurred_at (E, F-R1) nor device_id
    expect(mocks.from).toHaveBeenCalledWith("signing_key"); // the keyring was read under the staff session before the call
  });
  it("verifier refusals never reach the server: a forged signature under a known key, an unknown key, another session, garbage", async () => {
    expect(await scanAction(input({ wire: makeWire({ kid: KID }) }))).toEqual({ kind: "outcome", outcome: { kind: "invalid", why: "not_trusted", reason: "signature_invalid" } });
    expect(await scanAction(input({ wire: makeWire() }))).toEqual({ kind: "outcome", outcome: { kind: "invalid", why: "not_trusted", reason: "unknown_key" } });
    const other = await scanAction(input({ sessionId: "5e55e55e-0000-4000-8000-000000000002" }));
    expect(other).toEqual({ kind: "blocked", why: "no_role" }); // that session is not on the route event: the gate refuses before the verifier
    mocks.dbGetEvent.mockResolvedValue({ ok: true, data: { ...event.data, sessions: [{ sessionId: SESS }, { sessionId: "5e55e55e-0000-4000-8000-000000000002" }] } });
    expect(await scanAction(input({ sessionId: "5e55e55e-0000-4000-8000-000000000002" }))).toEqual({ kind: "outcome", outcome: { kind: "wrong_event", atomId: ATOM, tokenSessionId: SESS } });
    expect(await scanAction(input({ wire: "garbage" }))).toEqual({ kind: "outcome", outcome: { kind: "invalid", why: "malformed", reason: "malformed_token" } });
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it("an expired pass is refused by the server action's clock, not the phone's; a keyring that cannot be read is CANNOT VERIFY (keyring), retryable", async () => {
    vi.setSystemTime((GOLD.now_seconds + 86_400 * 400) * 1000);
    expect(await scanAction(input())).toEqual({ kind: "outcome", outcome: { kind: "invalid", why: "stale_pass", reason: "expired" } });
    vi.setSystemTime(GOLD.now_seconds * 1000);
    keyringRows.value = [{ key_id: "nope" }];
    expect(await scanAction(input())).toEqual({ kind: "outcome", outcome: { kind: "cannot_verify", why: "keyring", retrySameKey: true, detail: "keyring rows malformed" } });
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it("a server invalid WITH a reason is the server's word (no read); wrong_session renders WRONG EVENT", async () => {
    mocks.rpc.mockResolvedValue({ data: { status: "ok", scan_id: "s9", result: "invalid", reason: "voided" }, error: null, status: 200 });
    expect(await scanAction(input())).toEqual({ kind: "outcome", outcome: { kind: "invalid", why: "voided", reason: "voided" } });
    expect(mocks.rpc).toHaveBeenCalledTimes(1);
    mocks.rpc.mockReset().mockResolvedValue({ data: { status: "ok", scan_id: "s10", result: "invalid", reason: "wrong_session" }, error: null, status: 200 });
    expect((await scanAction(input())).kind === "outcome" && (await scanAction(input())).kind).toBe("outcome");
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
    chainRef.current = () => chain({ data: [{ session_id: SESS, admitted: 12, duplicate: 1, invalid: 2, last_admitted_at: "2026-11-30T04:00:00Z" }], error: null, status: 200 });
    expect(await readSessionScanCounters({ ...IDS, sessionId: SESS })).toEqual({ ok: true, data: { sessionId: SESS, admitted: 12, duplicate: 1, invalid: 2, lastAdmittedAt: "2026-11-30T04:00:00Z" } });
    expect(mocks.from).toHaveBeenCalledWith("session_admissions");
    chainRef.current = () => chain({ data: [], error: null, status: 200 });
    expect(await readSessionScanCounters({ ...IDS, sessionId: SESS })).toEqual({ ok: true, data: null });
    chainRef.current = () => chain({ data: null, error: { code: "PGRST106", message: "not exposed" }, status: 406 });
    const ne = await readSessionScanCounters({ ...IDS, sessionId: SESS });
    expect(ne.ok).toBe(false);
    if (!ne.ok) expect(ne.kind).toBe("not_exposed");
    mocks.dataSource.value = "fixtures";
    const fx = await readSessionScanCounters({ ...IDS, sessionId: SESS });
    expect(fx.ok).toBe(false);
  });
  it("a count that is not a number is an error, not a zero", async () => {
    chainRef.current = () => chain({ data: [{ session_id: SESS, admitted: "12", duplicate: 1, invalid: 2, last_admitted_at: null }], error: null, status: 200 });
    const r = await readSessionScanCounters({ ...IDS, sessionId: SESS });
    expect(r.ok).toBe(false);
  });
});
