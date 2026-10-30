import { describe, expect, it } from "vitest";
import {
  buildEventPatch,
  buildSalesCapacity,
  buildSessionPayload,
  buildVenuePatch,
  EVENT_PATCH_KEYS,
  NEIGHBORHOODS,
  nextPublishTarget,
  PUBLISH_TARGETS,
  refusalCopy,
  refusalToken,
  REFUSAL_COPY,
  SESSION_KEYS,
  transitionIsLegal,
  VENUE_PATCH_KEYS,
  type EventStatusName,
} from "@/lib/events/command-contract";

const NY = "America/New_York";

describe("session payloads carry instants, never wall clocks", () => {
  it("a first session: starts_at required, every time offset-qualified, label kept", () => {
    const r = buildSessionPayload({ label: " Doors ", startsLocal: "2026-11-30T19:00", endsLocal: "2026-12-01T02:00", doorsLocal: "2026-11-30T18:30" }, NY);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.value).toEqual({
      session_label: "Doors",
      starts_at: "2026-11-30T19:00:00-05:00",
      ends_at: "2026-12-01T02:00:00-05:00",
      doors_at: "2026-11-30T18:30:00-05:00",
    });
    // Only the server's own keys are ever present.
    for (const k of Object.keys(r.value)) expect(SESSION_KEYS).toContain(k as (typeof SESSION_KEYS)[number]);
  });
  it("no start time is refused by name, and a missing optional time is simply absent", () => {
    const none = buildSessionPayload({ startsLocal: "" }, NY);
    expect(none.ok).toBe(false);
    if (!none.ok) expect(none.problems[0]).toMatchObject({ field: "starts_at" });
    const minimal = buildSessionPayload({ startsLocal: "2026-11-30T19:00" }, NY);
    expect(minimal.ok && Object.keys(minimal.value)).toEqual(["starts_at"]);
  });
  it("the orderings the server enforces are caught on the field that is wrong", () => {
    const ends = buildSessionPayload({ startsLocal: "2026-11-30T19:00", endsLocal: "2026-11-30T19:00" }, NY);
    expect(ends.ok).toBe(false);
    if (!ends.ok) expect(ends.problems.map((p) => p.field)).toContain("ends_at");
    const doors = buildSessionPayload({ startsLocal: "2026-11-30T19:00", doorsLocal: "2026-11-30T20:00" }, NY);
    expect(doors.ok).toBe(false);
    if (!doors.ok) expect(doors.problems.map((p) => p.field)).toContain("doors_at");
  });
  it("a DST-impossible or doubled time is refused with the reason, and an unknown venue zone names itself", () => {
    const gone = buildSessionPayload({ startsLocal: "2026-03-08T02:30" }, NY);
    expect(gone.ok).toBe(false);
    if (!gone.ok) expect(gone.problems[0].message).toContain("does not exist");
    const twice = buildSessionPayload({ startsLocal: "2026-11-01T01:30" }, NY);
    expect(twice.ok).toBe(false);
    if (!twice.ok) expect(twice.problems[0].message).toContain("happens twice");
    const zone = buildSessionPayload({ startsLocal: "2026-11-30T19:00" }, "Mars/Olympus");
    expect(zone.ok).toBe(false);
    if (!zone.ok) expect(zone.problems[0].message).toContain("time zone");
  });
});

describe("event patches send only what changed, and only keys the server accepts", () => {
  it("a title change in draft needs no reason; after draft it does", () => {
    const draft = buildEventPatch({ title: "Pop-up" }, { status: "draft", currentTitle: "Untitled" });
    expect(draft.ok && draft.value).toEqual({ title: "Pop-up" });
    const live = buildEventPatch({ title: "Pop-up" }, { status: "on_sale", currentTitle: "Untitled" });
    expect(live.ok).toBe(false);
    if (!live.ok) expect(live.problems.map((p) => p.field)).toContain("reason_code");
    const withReason = buildEventPatch({ title: "Pop-up", reasonCode: "renamed_for_promo" }, { status: "on_sale", currentTitle: "Untitled" });
    expect(withReason.ok && withReason.value).toEqual({ title: "Pop-up", reason_code: "renamed_for_promo" });
  });
  it("an unchanged title is not sent, and a patch with nothing in it is refused rather than sent empty", () => {
    const same = buildEventPatch({ title: " Pop-up " }, { status: "draft", currentTitle: "Pop-up" });
    expect(same.ok).toBe(false);
    expect(buildEventPatch({}, { status: "draft" }).ok).toBe(false);
  });
  it("emptied text fields become null, tags are trimmed, and every key is an allowed one", () => {
    const r = buildEventPatch({ description: "  ", genreTags: [" house ", "", "techno"], category: "music" }, { status: "draft" });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.value).toEqual({ description: null, genre_tags: ["house", "techno"], category: "music" });
    for (const k of Object.keys(r.value)) expect(EVENT_PATCH_KEYS).toContain(k as (typeof EVENT_PATCH_KEYS)[number]);
  });
});

describe("venue patches: descriptive fields only, never the organization", () => {
  it("name, neighbourhood from the nine values, address and capacity", () => {
    const r = buildVenuePatch({ name: " The Room ", neighborhood: "Wynwood", address: "123 NW 2nd Ave", capacityHint: "250", reasonCode: "profile_fill" });
    expect(r.ok && r.value).toEqual({ name: "The Room", neighborhood: "wynwood", address: "123 NW 2nd Ave", capacity_hint: 250, reason_code: "profile_fill" });
    for (const n of NEIGHBORHOODS) expect(buildVenuePatch({ neighborhood: n }).ok).toBe(true);
    const bad = buildVenuePatch({ neighborhood: "soho" });
    expect(bad.ok).toBe(false);
    if (!bad.ok) expect(bad.problems[0].field).toBe("neighborhood");
  });
  it("capacity must be a whole number or empty; empty clears it", () => {
    expect(buildVenuePatch({ capacityHint: "" }).ok && buildVenuePatch({ capacityHint: "" })).toMatchObject({ value: { capacity_hint: null } });
    for (const bad of ["0", "-5", "2.5", "many"]) expect(buildVenuePatch({ capacityHint: bad }).ok, bad).toBe(false);
  });
  it("org_id can never be built, whatever the caller passes", () => {
    const r = buildVenuePatch({ name: "x", ...({ orgId: "24232848-0bcf-4fa9-8040-c8bd2dc38ed2", org_id: "x" } as object) });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(Object.keys(r.value)).toEqual(["name"]);
    for (const k of Object.keys(r.value)) expect(VENUE_PATCH_KEYS).toContain(k as (typeof VENUE_PATCH_KEYS)[number]);
  });
});

describe("the publish ladder", () => {
  it("one step forward at a time, never backwards, never to cancelled", () => {
    const steps: [EventStatusName, string | null][] = [
      ["draft", "announced"],
      ["announced", "on_sale"],
      ["on_sale", "live"],
      ["live", "completed"],
      ["completed", null],
      ["cancelled", null],
    ];
    for (const [from, to] of steps) expect(nextPublishTarget(from), from).toBe(to);
    expect(transitionIsLegal("draft", "on_sale")).toBe(false);
    expect(transitionIsLegal("draft", "announced")).toBe(true);
    expect(transitionIsLegal("live", "completed")).toBe(true);
    expect(PUBLISH_TARGETS).not.toContain("cancelled" as never);
  });
});

describe("the sales pool", () => {
  it("a positive number or empty for unlimited, and a reason is required", () => {
    expect(buildSalesCapacity("50", "opening_pool")).toEqual({ ok: true, value: { capacity: 50, reasonCode: "opening_pool" } });
    expect(buildSalesCapacity("", "unlimited_run")).toEqual({ ok: true, value: { capacity: null, reasonCode: "unlimited_run" } });
    const noReason = buildSalesCapacity("50", " ");
    expect(noReason.ok).toBe(false);
    if (!noReason.ok) expect(noReason.problems.map((p) => p.field)).toContain("reason_code");
    for (const bad of ["0", "-1", "2.5", "lots"]) expect(buildSalesCapacity(bad, "r").ok, bad).toBe(false);
  });
});

describe("server refusals in the operator's words", () => {
  it("each token is recognised from the server's own message prefix", () => {
    const cases: [string, string][] = [
      ["precondition_failed: empty_inventory", "empty_inventory"],
      ["precondition_failed: connect_not_ready", "connect_not_ready"],
      ["precondition_failed: fee_policy_unset", "fee_policy_unset"],
      ["precondition_failed: org_not_saleable", "org_not_saleable"],
      ["precondition_failed: signing_not_ready", "signing_not_ready"],
      ["precondition_failed: illegal_transition (draft -> on_sale)", "illegal_transition"],
      ["precondition_failed: event_terminal", "event_terminal"],
      ["precondition_failed: session_terminal", "session_terminal"],
      ["precondition_failed: boundary_engaged", "boundary_engaged"],
      ["precondition_failed: move_exceeds_grace", "move_exceeds_grace"],
      ["precondition_failed: reason_required for a title change after draft", "reason_required"],
      ["precondition_failed: below_allocated (new=10 < allocated=40)", "below_allocated"],
      ["precondition_failed: above_venue_capacity (new=500 > capacity_hint=250)", "above_venue_capacity"],
      ["precondition_failed: session_capacity_exceeded (allocated=40 + new=20 > sales_capacity=50)", "session_capacity_exceeded"],
      ["invalid_input: unwritable_key age_policy", "unwritable_key"],
      ["invalid_input: unknown_timezone Mars/Olympus", "unknown_timezone"],
      ["precondition_failed: operatorship_transfer_frozen", "operatorship_transfer_frozen"],
      ["insufficient_privilege: venue_manager required", "insufficient_privilege"],
      ["not_found: session", "not_found"],
    ];
    for (const [message, token] of cases) {
      expect(refusalToken(message), message).toBe(token);
      expect(refusalCopy(message), message).toBe(REFUSAL_COPY[token]);
    }
  });
  it("an unknown refusal keeps the server's words instead of inventing a cause, and nothing claims a change happened", () => {
    expect(refusalCopy("something_new: with detail")).toContain("something_new: with detail");
    expect(refusalCopy(null)).toContain("Nothing changed");
    expect(refusalCopy("")).toContain("Nothing changed");
    for (const copy of Object.values(REFUSAL_COPY)) expect(copy.toLowerCase()).not.toMatch(/\bsaved\b|\bpublished\b|\bis now on sale\b/);
  });
  it("the five not-ready-to-sell reasons each say who can fix it", () => {
    expect(REFUSAL_COPY.empty_inventory).toContain("nothing to sell");
    expect(REFUSAL_COPY.org_not_saleable).toContain("payout setup");
    expect(REFUSAL_COPY.connect_not_ready).toContain("Stripe");
    expect(REFUSAL_COPY.signing_not_ready).toContain("platform");
    expect(REFUSAL_COPY.fee_policy_unset).toContain("Snatch It");
  });
});
