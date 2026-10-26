import { describe, expect, it } from "vitest";
import { classifyToken, clock, outcomeDetail, outcomeFromRpc, outcomeFromRpcError, OUTCOME_TITLE, OUTCOME_TONE } from "@/lib/scan/outcome";
import { ATOM, makeWire, SESS } from "./helpers/credential-wire";

const NOW = 1_799_999_000;

describe("classifyToken — what the client may decide on its own (all refusals)", () => {
  it("a good pass for the selected session is ok with its atom", () => {
    const c = classifyToken(makeWire(), SESS, NOW);
    expect(c.kind).toBe("ok");
    if (c.kind === "ok") expect(c.claims.atomId).toBe(ATOM);
  });
  it("another session in the pass's own claim is WRONG EVENT (case-insensitive compare)", () => {
    const c = classifyToken(makeWire(), SESS.toUpperCase(), NOW);
    expect(c.kind).toBe("ok");
    const other = classifyToken(makeWire({ sess: "5e55e55e-0000-4000-8000-000000000002" }), SESS, NOW);
    expect(other).toEqual({ kind: "wrong_event", atomId: ATOM, tokenSessionId: "5e55e55e-0000-4000-8000-000000000002" });
  });
  it("a pass past its own exp is a stale pass; a non-decoding code is malformed; another credential type is wrong_type", () => {
    expect(classifyToken(makeWire({ exp: NOW - 1 }), SESS, NOW)).toEqual({ kind: "invalid", why: "stale_pass" });
    expect(classifyToken("hello", SESS, NOW)).toEqual({ kind: "invalid", why: "malformed" });
    expect(classifyToken(makeWire({ typ: "SNATCHIT-DOOR-MANIFEST-V1" }), SESS, NOW)).toEqual({ kind: "invalid", why: "wrong_type" });
  });
  it("nothing the client decides is ever admitted", () => {
    for (const w of [makeWire(), "x", makeWire({ exp: 0 })]) expect(classifyToken(w, SESS, NOW).kind).not.toBe("admitted");
  });
});

describe("outcomeFromRpc — the server's receipt is the only source of a green", () => {
  it("admitted / duplicate(+prior) / invalid map one to one", () => {
    expect(outcomeFromRpc({ status: "ok", scan_id: "s1", result: "admitted" }, ATOM, false)).toEqual({ kind: "admitted", atomId: ATOM, scanId: "s1" });
    expect(outcomeFromRpc({ status: "ok", scan_id: "s2", result: "duplicate", prior: { scan_id: "s1", occurred_at: "2026-11-30T03:05:00Z", actor_label: "ana", device_label: "Door A phone" } }, ATOM, false)).toEqual({
      kind: "already_used",
      atomId: ATOM,
      prior: { scanId: "s1", occurredAt: "2026-11-30T03:05:00Z", actorLabel: "ana", deviceLabel: "Door A phone" },
      possiblyThisPhone: false,
    });
    expect(outcomeFromRpc({ status: "ok", scan_id: "s3", result: "duplicate" }, ATOM, true)).toEqual({ kind: "already_used", atomId: ATOM, prior: null, possiblyThisPhone: true });
    expect(outcomeFromRpc({ status: "ok", scan_id: "s4", result: "invalid" }, ATOM, false)).toEqual({ kind: "invalid", why: "server" });
  });
  it("anything else is CANNOT VERIFY with a retry on the same key — never admitted", () => {
    for (const d of [null, "ok", {}, { status: "noop" }, { status: "ok", result: "frozen" }, { status: "ok", result: "ADMITTED" }]) {
      const o = outcomeFromRpc(d, ATOM, false);
      expect(o.kind).toBe("cannot_verify");
      if (o.kind === "cannot_verify") expect(o.retrySameKey).toBe(true);
    }
  });
});

describe("outcomeFromRpcError — dark, no role, signed out, not admitting", () => {
  it("not exposed / wrapper absent / flag off → not enabled (no retry); 42501 → blocked no_role; 401 → signed out", () => {
    expect(outcomeFromRpcError({ code: "PGRST106", message: "The schema must be one of the following" })).toEqual({ kind: "outcome", outcome: { kind: "cannot_verify", why: "not_enabled", retrySameKey: false } });
    expect(outcomeFromRpcError({ code: "PGRST202", message: "Could not find the function" })).toEqual({ kind: "outcome", outcome: { kind: "cannot_verify", why: "not_enabled", retrySameKey: false } });
    expect(outcomeFromRpcError({ code: "P0001", message: "precondition_failed: feature_disabled — native scanning is dark" })).toEqual({ kind: "outcome", outcome: { kind: "cannot_verify", why: "not_enabled", retrySameKey: false } });
    expect(outcomeFromRpcError({ code: "42501", message: "insufficient_privilege" })).toEqual({ kind: "blocked", why: "no_role" });
    expect(outcomeFromRpcError({ code: "PGRST301", message: "JWT expired" })).toEqual({ kind: "blocked", why: "signed_out" });
    expect(outcomeFromRpcError(null, 401)).toEqual({ kind: "blocked", why: "signed_out" });
  });
  it("session_not_admitting and rate limits are CANNOT VERIFY; unknown errors keep the same-key retry", () => {
    const na = outcomeFromRpcError({ code: "P0001", message: "precondition_failed: session_not_admitting (status=closed)" });
    expect(na.kind === "outcome" && na.outcome.kind === "cannot_verify" && na.outcome.why).toBe("session_not_admitting");
    expect(outcomeFromRpcError(null, 429)).toEqual({ kind: "outcome", outcome: { kind: "cannot_verify", why: "rate_limited", retrySameKey: true } });
    const other = outcomeFromRpcError({ code: "57014", message: "canceling statement due to statement timeout" });
    expect(other).toEqual({ kind: "outcome", outcome: { kind: "cannot_verify", why: "server_error", retrySameKey: true, detail: "canceling statement due to statement timeout" } });
  });
});

describe("copy — five words, one tone each, the prior rendered as a clock", () => {
  it("titles and tones", () => {
    expect(Object.values(OUTCOME_TITLE)).toEqual(["ADMITTED", "ALREADY USED", "WRONG EVENT", "INVALID", "CANNOT VERIFY"]);
    expect(OUTCOME_TONE.admitted).toBe("success");
    expect(OUTCOME_TONE.already_used).toBe("warning");
    expect(OUTCOME_TONE.cannot_verify).toBe("neutral");
  });
  it("'Already admitted at HH:MM (Door A phone)' in the venue's zone, and the retry caveat only when it may be this phone", () => {
    expect(clock("2026-11-30T03:05:00Z", "America/New_York")).toBe("22:05");
    const prior = { scanId: "s1", occurredAt: "2026-11-30T03:05:00Z", actorLabel: null, deviceLabel: "Door A phone" };
    expect(outcomeDetail({ kind: "already_used", atomId: ATOM, prior, possiblyThisPhone: false }, "America/New_York")).toBe("Already admitted at 22:05 (Door A phone).");
    expect(outcomeDetail({ kind: "already_used", atomId: ATOM, prior: null, possiblyThisPhone: true }, null)).toContain("this phone's previous attempt");
    expect(outcomeDetail({ kind: "cannot_verify", why: "timeout", retrySameKey: true }, null)).toContain("may or may not");
    expect(outcomeDetail({ kind: "cannot_verify", why: "demo", retrySameKey: false }, null)).toContain("Demo");
  });
  it("no detail line claims a timeout or an error was admitted", () => {
    for (const why of ["offline", "timeout", "transport", "not_enabled", "session_not_admitting", "rate_limited", "server_error", "demo"] as const) {
      expect(outcomeDetail({ kind: "cannot_verify", why, retrySameKey: false }, null).toLowerCase()).not.toMatch(/\badmitted\b|\blet them in\b/);
    }
  });
});
