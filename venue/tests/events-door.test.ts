import { describe, expect, it } from "vitest";
import { DEVICES, EVENTS, PREVIEW_NOW } from "@/fixtures/venue";
import { editMode, nextStatus, publishBlocker } from "@/lib/events";
import { REJECT_COPY, effectiveFreeze, manifestAge, manifestState, normaliseReason } from "@/lib/door";
import { readPreviewContext, withPreview } from "@/lib/preview";
import { usd, venueTime } from "@/lib/format";

describe("event lifecycle (spec §7.4)", () => {
  it("offers only the next forward transition and never a reverse one", () => {
    expect(nextStatus("draft")).toBe("announced");
    expect(nextStatus("announced")).toBe("on_sale");
    expect(nextStatus("on_sale")).toBe("live");
    expect(nextStatus("live")).toBe("completed");
    expect(nextStatus("completed")).toBeNull();
    expect(nextStatus("cancelled")).toBeNull();
  });
  it("names what is missing before on_sale instead of a dead button", () => {
    expect(publishBlocker([], [])).toMatch(/Add a ticket type/);
    const t = { ticketTypeId: "t", eventId: "e", name: "GA", kind: "admission" as const, priceMinor: 100, visibility: "public" as const };
    expect(publishBlocker([t], [])).toMatch(/inventory release/);
    expect(publishBlocker([t], [{ batchId: "b", ticketTypeId: "t", sessionId: "s", releaseKind: "public_sale", capacity: 1, held: 0, sold: 0, lowThreshold: 0 }])).toBeNull();
  });
  it("edits are free while draft, confirmed while selling, locked after", () => {
    expect(editMode("draft")).toBe("free");
    expect(editMode("on_sale")).toBe("confirmed");
    expect(editMode("completed")).toBe("locked");
  });
});

describe("door (spec §12)", () => {
  it("maps the six reject reasons to operator copy and folds already_scanned into duplicate", () => {
    expect(Object.keys(REJECT_COPY)).toHaveLength(6);
    expect(REJECT_COPY.refund_hold).toMatch(/refund is being reviewed/);
    expect(normaliseReason("already_scanned")).toBe("duplicate");
    expect(normaliseReason("duplicate")).toBe("duplicate");
    expect(normaliseReason("nonsense")).toBe("unknown");
  });
  it("freeze is monotone: closing an episode keeps transfers closed", () => {
    const s = EVENTS[0].sessions[0];
    expect(manifestState(s, true)).toBe("open");
    expect(manifestState(s, false)).toBe("closed_after_open");
    expect(manifestState({ doorOpenAt: null }, false)).toBe("closed");
  });
  it("states which input produced the effective freeze", () => {
    const s = EVENTS[0].sessions[0];
    expect(effectiveFreeze(s)).toEqual({ at: s.doorOpenAt, source: "manifest_open" });
    expect(effectiveFreeze({ doorOpenAt: null, doorsAt: "2026-09-13T01:00:00Z", startsAt: "2026-09-13T02:00:00Z" })).toEqual({ at: "2026-09-13T01:00:00.000Z", source: "doors_time_backstop" });
  });
  it("renders manifest staleness as a duration with a threshold, not a version", () => {
    expect(manifestAge(DEVICES[0], PREVIEW_NOW)).toEqual({ minutes: 2, stale: false });
    expect(manifestAge(DEVICES[1], PREVIEW_NOW)).toEqual({ minutes: 19, stale: true });
  });
});

describe("preview context and formatting", () => {
  it("defaults to venue_manager / live and ignores junk", () => {
    expect(readPreviewContext({ role: "hacker", state: "boom" })).toMatchObject({ role: "venue_manager", state: "live", source: "fixtures", countersAvailable: true });
    expect(readPreviewContext({ role: "venue_scanner", state: "denied" })).toMatchObject({ role: "venue_scanner", state: "denied" });
  });
  it("carries role and state through links only when non-default", () => {
    expect(withPreview("/x", { role: "venue_manager", state: "live" })).toBe("/x");
    expect(withPreview("/x", { role: "org_finance", state: "error" })).toBe("/x?role=org_finance&state=error");
  });
  it("formats minor units as USD and times in the venue zone with the zone named", () => {
    expect(usd(300000)).toBe("$3,000.00");
    expect(usd(5)).toBe("$0.05");
    expect(venueTime("2026-09-13T02:00:00Z", "America/New_York")).toMatch(/Sat, Sep 12, 10:00 PM E[DS]T/);
  });
});
