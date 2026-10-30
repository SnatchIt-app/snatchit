import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  createEvent: vi.fn(),
  updateEvent: vi.fn(),
  createSession: vi.fn(),
  updateSession: vi.fn(),
  publish: vi.fn(),
  cancel: vi.fn(),
  updateVenue: vi.fn(),
  setTz: vi.fn(),
  setCapacity: vi.fn(),
  revalidatePath: vi.fn(),
}));
vi.mock("@/lib/db/event-commands", () => ({
  createEventAction: mocks.createEvent,
  updateEventAction: mocks.updateEvent,
  createEventSessionAction: mocks.createSession,
  updateEventSessionAction: mocks.updateSession,
  publishEventAction: mocks.publish,
  cancelEventAction: mocks.cancel,
  updateVenueAction: mocks.updateVenue,
  setVenueTimezoneAction: mocks.setTz,
  setSessionSalesCapacityAction: mocks.setCapacity,
  mintCommandKey: async () => "minted",
}));
vi.mock("next/cache", () => ({ revalidatePath: mocks.revalidatePath }));

import { cancelEventForm, createEventForm, createSessionForm, publishEventForm, setSessionCapacityForm, setVenueTimezoneForm, updateEventForm, updateSessionForm, updateVenueForm } from "@/lib/events/forms";

const ORG = "24232848-0bcf-4fa9-8040-c8bd2dc38ed2";
const VENUE = "5e8db24b-a0ac-440a-9f00-fa15ee3bbb75";
const EVENT = "9a000000-0000-4000-8000-000000000001";
const SESSION = "5e55e55e-0000-4000-8000-000000000001";
const NY = "America/New_York";
const ok = { kind: "ok", result: { status: "ok" } } as const;

const fd = (o: Record<string, string>) => {
  const f = new FormData();
  for (const [k, v] of Object.entries({ orgId: ORG, venueId: VENUE, eventId: EVENT, commandKey: "k-1", timeZone: NY, ...o })) f.append(k, v);
  return f;
};

beforeEach(() => {
  for (const m of Object.values(mocks)) m.mockReset();
  for (const m of [mocks.createEvent, mocks.updateEvent, mocks.createSession, mocks.updateSession, mocks.publish, mocks.cancel, mocks.updateVenue, mocks.setTz, mocks.setCapacity]) m.mockResolvedValue(ok);
});

describe("the operator's wall clock becomes an instant before it is sent", () => {
  it("create event: the first session carries offset-qualified times built from the venue's zone", async () => {
    const s = await createEventForm({ result: null }, fd({ title: " Snatch It pop-up ", session_label: "Doors", starts_local: "2026-11-30T19:00", doors_local: "2026-11-30T18:30" }));
    expect(s.result?.kind).toBe("ok");
    expect(mocks.createEvent).toHaveBeenCalledWith({
      venueId: VENUE,
      title: "Snatch It pop-up",
      firstSession: { session_label: "Doors", starts_at: "2026-11-30T19:00:00-05:00", doors_at: "2026-11-30T18:30:00-05:00" },
      commandKey: "k-1",
    });
    expect(mocks.revalidatePath).toHaveBeenCalledWith(`/o/${ORG}/v/${VENUE}/events`);
  });
  it("a DST-impossible time never reaches the server, and names the field", async () => {
    const s = await createEventForm({ result: null }, fd({ title: "x", starts_local: "2026-03-08T02:30" }));
    expect(s.problems?.map((p) => p.field)).toContain("starts_at");
    expect(mocks.createEvent).not.toHaveBeenCalled();
  });
  it("sessions: create and update send only the session keys, with the same conversion", async () => {
    await createSessionForm({ result: null }, fd({ starts_local: "2026-07-04T21:00" }));
    expect(mocks.createSession).toHaveBeenCalledWith({ eventId: EVENT, session: { starts_at: "2026-07-04T21:00:00-04:00" }, commandKey: "k-1" });
    await updateSessionForm({ result: null }, fd({ sessionId: SESSION, starts_local: "2026-11-30T20:00", ends_local: "2026-12-01T02:00", reason_code: "moved_later" }));
    expect(mocks.updateSession).toHaveBeenCalledWith({
      sessionId: SESSION,
      patch: { starts_at: "2026-11-30T20:00:00-05:00", ends_at: "2026-12-01T02:00:00-05:00", reason_code: "moved_later" },
      commandKey: "k-1",
    });
  });
});

describe("event details", () => {
  it("only changed keys are sent, and a post-draft title change without a reason is refused here", async () => {
    await updateEventForm({ result: null }, fd({ title: "New name", current_title: "Old", status: "draft" }));
    expect(mocks.updateEvent).toHaveBeenCalledWith({ eventId: EVENT, patch: { title: "New name" }, commandKey: "k-1" });
    mocks.updateEvent.mockClear();
    const s = await updateEventForm({ result: null }, fd({ title: "New name", current_title: "Old", status: "on_sale" }));
    expect(s.problems?.map((p) => p.field)).toContain("reason_code");
    expect(mocks.updateEvent).not.toHaveBeenCalled();
  });
  it("genre tags arrive as a comma list and leave as a trimmed array", async () => {
    await updateEventForm({ result: null }, fd({ genre_tags: " house , techno , ", status: "draft" }));
    expect(mocks.updateEvent).toHaveBeenCalledWith({ eventId: EVENT, patch: { genre_tags: ["house", "techno"] }, commandKey: "k-1" });
  });
});

describe("publish and cancel", () => {
  it("publish passes the target through; anything outside the four is refused before sending", async () => {
    await publishEventForm({ result: null }, fd({ target_status: "on_sale" }));
    expect(mocks.publish).toHaveBeenCalledWith({ eventId: EVENT, targetStatus: "on_sale", commandKey: "k-1" });
    for (const bad of ["cancelled", "draft", ""]) {
      mocks.publish.mockClear();
      const s = await publishEventForm({ result: null }, fd({ target_status: bad }));
      expect(s.problems?.[0].field, bad).toBe("target_status");
      expect(mocks.publish).not.toHaveBeenCalled();
    }
  });
  it("the server's not-ready reason is rendered in the operator's words", async () => {
    mocks.publish.mockResolvedValue({ kind: "refused", code: "unknown", message: "refused", detail: "precondition_failed: connect_not_ready" });
    const s = await publishEventForm({ result: null }, fd({ target_status: "on_sale" }));
    expect(s.refusal).toContain("Stripe has not confirmed");
    expect(mocks.revalidatePath).not.toHaveBeenCalled();
  });
  it("cancelling needs a reason AND a typed confirmation", async () => {
    const noReason = await cancelEventForm({ result: null }, fd({ confirm: "cancel" }));
    expect(noReason.problems?.[0].field).toBe("reason_code");
    const noConfirm = await cancelEventForm({ result: null }, fd({ reason_code: "venue_lost" }));
    expect(noConfirm.problems?.[0].field).toBe("confirm");
    expect(mocks.cancel).not.toHaveBeenCalled();
    await cancelEventForm({ result: null }, fd({ reason_code: "venue_lost", confirm: "CANCEL" }));
    expect(mocks.cancel).toHaveBeenCalledWith({ eventId: EVENT, reasonCode: "venue_lost", commandKey: "k-1" });
  });
});

describe("venue details, time zone and the sales pool", () => {
  it("the venue patch carries descriptive fields only", async () => {
    await updateVenueForm({ result: null }, fd({ name: "The Room", neighborhood: "wynwood", address: "123 NW 2nd Ave", capacity_hint: "250", reason_code: "profile_fill" }));
    expect(mocks.updateVenue).toHaveBeenCalledWith({
      venueId: VENUE,
      patch: { name: "The Room", neighborhood: "wynwood", address: "123 NW 2nd Ave", capacity_hint: 250, reason_code: "profile_fill" },
      commandKey: "k-1",
    });
  });
  it("the time zone needs a reason, and the pool takes a number or empty for unlimited", async () => {
    const noReason = await setVenueTimezoneForm({ result: null }, fd({ timezone: NY }));
    expect(noReason.problems?.map((p) => p.field)).toContain("reason_code");
    await setVenueTimezoneForm({ result: null }, fd({ timezone: NY, reason_code: "fix" }));
    expect(mocks.setTz).toHaveBeenCalledWith({ venueId: VENUE, timezone: NY, reasonCode: "fix", commandKey: "k-1" });
    await setSessionCapacityForm({ result: null }, fd({ sessionId: SESSION, capacity: "50", reason_code: "pool" }));
    expect(mocks.setCapacity).toHaveBeenCalledWith({ sessionId: SESSION, capacity: 50, reasonCode: "pool", commandKey: "k-1" });
    await setSessionCapacityForm({ result: null }, fd({ sessionId: SESSION, capacity: "", reason_code: "unlimited" }));
    expect(mocks.setCapacity).toHaveBeenLastCalledWith({ sessionId: SESSION, capacity: null, reasonCode: "unlimited", commandKey: "k-1" });
  });
  it("the pool's two boundary refusals are rendered by their own reason", async () => {
    mocks.setCapacity.mockResolvedValue({ kind: "refused", code: "unknown", message: "refused", detail: "precondition_failed: below_allocated (new=10 < allocated=40)" });
    const below = await setSessionCapacityForm({ result: null }, fd({ sessionId: SESSION, capacity: "10", reason_code: "r" }));
    expect(below.refusal).toContain("already allocated");
    mocks.setCapacity.mockResolvedValue({ kind: "refused", code: "unknown", message: "refused", detail: "precondition_failed: above_venue_capacity (new=500 > capacity_hint=250)" });
    const above = await setSessionCapacityForm({ result: null }, fd({ sessionId: SESSION, capacity: "500", reason_code: "r" }));
    expect(above.refusal).toContain("venue's capacity");
  });
});

describe("nothing is revalidated unless the server gave a receipt", () => {
  it("an unavailable or refused answer leaves the pages alone, and non-uuid ids never build a path", async () => {
    mocks.publish.mockResolvedValue({ kind: "unavailable", reason: "gate_unset", message: "not enabled" });
    await publishEventForm({ result: null }, fd({ target_status: "live" }));
    expect(mocks.revalidatePath).not.toHaveBeenCalled();
    mocks.publish.mockResolvedValue(ok);
    const f = fd({ target_status: "live" });
    f.set("orgId", "../../admin");
    await publishEventForm({ result: null }, f);
    expect(mocks.revalidatePath).not.toHaveBeenCalled();
  });
});
