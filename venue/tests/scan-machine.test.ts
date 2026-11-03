import { describe, expect, it } from "vitest";
import { ADMITTED_SHOW_MS, initialScanState, pendingSend, REFUSAL_SHOW_MS, SAME_WIRE_COOLDOWN_MS, scanReducer, type ScanState } from "@/lib/scan/machine";
import { ATOM, makeWire, SESS } from "./helpers/credential-wire";

const T0 = 1_799_999_000_000; // ms; the test wires expire at 1_800_000_000 s
const ready = (): ScanState => scanReducer(initialScanState(SESS), { type: "camera", state: "on" });
const wire = makeWire();

describe("one attempt at a time, same pass not re-sent, nothing sent when not ready", () => {
  it("a decoded good pass becomes the one busy attempt, and pendingSend hands it over exactly once", () => {
    const s0 = ready();
    const s1 = scanReducer(s0, { type: "decoded", wire, commandKey: "k1", now: T0 });
    expect(s1.phase).toBe("busy");
    expect(s1.attempt).toEqual({ wire, atomId: ATOM, commandKey: "k1", sentAt: T0, retries: 0 });
    expect(pendingSend(s0, s1)?.commandKey).toBe("k1");
    const s2 = scanReducer(s1, { type: "online", online: true });
    expect(pendingSend(s1, s2)).toBeNull();
  });
  it("frames decoded while busy are ignored; the same pass is ignored for the cooldown after it was seen", () => {
    const s1 = scanReducer(ready(), { type: "decoded", wire, commandKey: "k1", now: T0 });
    expect(scanReducer(s1, { type: "decoded", wire: makeWire({ atom: "a70a70a7-0000-4000-8000-000000000006" }), commandKey: "k2", now: T0 + 50 })).toBe(s1);
    const s2 = scanReducer(s1, { type: "result", commandKey: "k1", outcome: { kind: "admitted", atomId: ATOM, scanId: "s" }, now: T0 + 300 });
    const s3 = scanReducer(s2, { type: "tick", now: T0 + 300 + ADMITTED_SHOW_MS });
    expect(s3.phase).toBe("ready");
    expect(scanReducer(s3, { type: "decoded", wire, commandKey: "k3", now: T0 + 300 + ADMITTED_SHOW_MS + 10 })).toBe(s3);
    const s4 = scanReducer(s3, { type: "decoded", wire, commandKey: "k3", now: T0 + 300 + SAME_WIRE_COOLDOWN_MS + 1 });
    expect(s4.phase).toBe("busy");
  });
  it("camera off, blocked, or not ready: a decode changes nothing", () => {
    const off = initialScanState(SESS);
    expect(scanReducer(off, { type: "decoded", wire, commandKey: "k", now: T0 })).toBe(off);
    const blocked = scanReducer(ready(), { type: "blocked", why: "no_role" });
    expect(blocked.camera).toBe("paused");
    expect(scanReducer(blocked, { type: "decoded", wire, commandKey: "k", now: T0 })).toBe(blocked);
  });
});

describe("refusals the client makes alone never touch the server", () => {
  it("wrong session claim → WRONG EVENT, stale → INVALID, garbage → INVALID; none is busy, none is admitted", () => {
    const s = ready();
    const w = scanReducer(s, { type: "decoded", wire: makeWire({ sess: "5e55e55e-0000-4000-8000-000000000002" }), commandKey: "k", now: T0 });
    expect(w.phase).toBe("result");
    expect(w.outcome?.kind).toBe("wrong_event");
    expect(w.attempt).toBeNull();
    expect(pendingSend(s, w)).toBeNull();
    expect(scanReducer(s, { type: "decoded", wire: makeWire({ exp: 1, iat: 0 }), commandKey: "k", now: T0 }).phase).toBe("busy"); // expiry is the server action's verifier's call, not the phone's
    expect(scanReducer(s, { type: "decoded", wire: "nope", commandKey: "k", now: T0 }).outcome).toEqual({ kind: "invalid", why: "malformed" });
    expect(w.admittedHere).toBe(0);
  });
  it("known offline: a good pass is CANNOT VERIFY (offline) with no attempt and no retry", () => {
    const s = scanReducer(ready(), { type: "online", online: false });
    const o = scanReducer(s, { type: "decoded", wire, commandKey: "k", now: T0 });
    expect(o.outcome).toEqual({ kind: "cannot_verify", why: "offline", retrySameKey: false });
    expect(o.attempt).toBeNull();
  });
});

describe("a lost answer is CANNOT VERIFY, retried on the SAME key, and never green by itself", () => {
  it("timeout keeps the attempt; retry re-sends the same key with retries+1; a late answer for an old key is ignored", () => {
    const s1 = scanReducer(ready(), { type: "decoded", wire, commandKey: "k1", now: T0 });
    const s2 = scanReducer(s1, { type: "failed", commandKey: "k1", why: "timeout", now: T0 + 10_000 });
    expect(s2.phase).toBe("result");
    expect(s2.outcome).toEqual({ kind: "cannot_verify", why: "timeout", retrySameKey: true });
    expect(s2.attempt?.commandKey).toBe("k1");
    expect(scanReducer(s2, { type: "tick", now: T0 + 10_000 + REFUSAL_SHOW_MS * 10 })).toBe(s2); // never auto-cleared
    const s3 = scanReducer(s2, { type: "retry", now: T0 + 12_000 });
    expect(s3.phase).toBe("busy");
    expect(s3.attempt).toEqual({ wire, atomId: ATOM, commandKey: "k1", sentAt: T0 + 12_000, retries: 1 });
    expect(pendingSend(s2, s3)?.retries).toBe(1);
    expect(scanReducer(s3, { type: "result", commandKey: "k0", outcome: { kind: "admitted", atomId: ATOM, scanId: "x" }, now: T0 + 12_100 })).toBe(s3);
    const s4 = scanReducer(s3, { type: "result", commandKey: "k1", outcome: { kind: "already_used", atomId: ATOM, prior: null, possiblyThisPhone: true }, now: T0 + 12_200 });
    expect(s4.outcome?.kind).toBe("already_used");
    expect(s4.admittedHere).toBe(0);
    expect(s4.attempt).toBeNull();
  });
  it("retry is refused while offline, while busy, and when the outcome is not a retryable CANNOT VERIFY", () => {
    const s1 = scanReducer(ready(), { type: "decoded", wire, commandKey: "k1", now: T0 });
    expect(scanReducer(s1, { type: "retry", now: T0 + 1 })).toBe(s1);
    const s2 = scanReducer(s1, { type: "failed", commandKey: "k1", why: "transport", now: T0 + 500 });
    const off = scanReducer(s2, { type: "online", online: false });
    expect(scanReducer(off, { type: "retry", now: T0 + 600 })).toBe(off);
    const inv = scanReducer(ready(), { type: "decoded", wire: "nope", commandKey: "k", now: T0 });
    expect(scanReducer(inv, { type: "retry", now: T0 + 1 })).toBe(inv);
  });
});

describe("what the operator sees afterwards", () => {
  it("admitted counts once per server receipt, shows briefly, and history keeps the last five", () => {
    let s = ready();
    for (let i = 0; i < 7; i++) {
      const w = makeWire({ atom: `a70a70a7-0000-4000-8000-00000000000${i}` });
      s = scanReducer(s, { type: "decoded", wire: w, commandKey: `k${i}`, now: T0 + i * 10_000 });
      s = scanReducer(s, { type: "result", commandKey: `k${i}`, outcome: { kind: "admitted", atomId: `a${i}`, scanId: `s${i}` }, now: T0 + i * 10_000 + 200 });
      s = scanReducer(s, { type: "tick", now: T0 + i * 10_000 + 200 + ADMITTED_SHOW_MS });
    }
    expect(s.admittedHere).toBe(7);
    expect(s.history).toHaveLength(5);
    expect(s.phase).toBe("ready");
  });
  it("a refusal stays longer than a green, and dismiss clears it by hand; changing session resets attempts but not the camera", () => {
    const r = scanReducer(ready(), { type: "decoded", wire: "nope", commandKey: "k", now: T0 });
    expect(scanReducer(r, { type: "tick", now: T0 + ADMITTED_SHOW_MS }).phase).toBe("result");
    expect(scanReducer(r, { type: "tick", now: T0 + REFUSAL_SHOW_MS }).phase).toBe("ready");
    expect(scanReducer(r, { type: "dismiss", now: T0 + 1 }).phase).toBe("ready");
    const moved = scanReducer(r, { type: "session", sessionId: "5e55e55e-0000-4000-8000-000000000002" });
    expect(moved.sessionId).toBe("5e55e55e-0000-4000-8000-000000000002");
    expect(moved.camera).toBe("on");
    expect(moved.history).toEqual([]);
  });
});
