import { describe, expect, it } from "vitest";
import { toActionOutcome, toCaseDetail, toListPage, toToday, toWhoami } from "../src/lib/types";

describe("contract guards", () => {
  it("narrows whoami and rejects unknown roles", () => {
    expect(toWhoami({ user_id: "u", role: "platform_admin", aal: "aal2", email_masked: "j***@x.com" })).toEqual({
      user_id: "u",
      role: "platform_admin",
      aal: "aal2",
      email_masked: "j***@x.com",
    });
    expect(toWhoami({ role: "superuser" })?.role).toBeNull();
    expect(toWhoami(null)).toBeNull();
  });

  it("accepts list pages as {items,next_cursor} or bare arrays", () => {
    expect(toListPage({ items: [{ id: "a" }], next_cursor: "c1" })).toEqual({ items: [{ id: "a" }], next_cursor: "c1" });
    expect(toListPage([{ id: "a" }, "junk"])).toEqual({ items: [{ id: "a" }], next_cursor: null });
    expect(toListPage("nope")).toEqual({ items: [], next_cursor: null });
  });

  it("maps the 3.4 statuses including rejected reasons", () => {
    expect(toActionOutcome({ status: "succeeded", action_id: "x" })).toMatchObject({ status: "succeeded", action_id: "x" });
    expect(toActionOutcome({ status: "rejected", reason: "stale_state" })).toMatchObject({ status: "rejected", reason: "stale_state" });
    expect(toActionOutcome({ status: "rejected", code: "disabled" })).toMatchObject({ reason: "disabled" });
    expect(toActionOutcome({ status: "awaiting_approval", id: "a" })).toMatchObject({ status: "awaiting_approval", action_id: "a" });
    expect(toActionOutcome({ status: "weird" })).toBeNull();
  });

  it("tolerates a case_detail with or without a nested case object", () => {
    const nested = toCaseDetail({ case: { id: "c", version: 3, status: "open" }, notes: [{ body: "hi" }], operators: [{ user_id: "o1" }] });
    expect(nested?.case?.version).toBe(3);
    expect(nested?.notes[0].body).toBe("hi");
    expect(nested?.operators[0].user_id).toBe("o1");
    const flat = toCaseDetail({ id: "c", version: 1, events: [{ at: "2026-01-01T00:00:00Z", kind: "created" }] });
    expect(flat?.case?.id).toBe("c");
    expect(flat?.events[0].kind).toBe("created");
  });

  it("normalises today() metrics from array or object form", () => {
    expect(toToday({ attention: [], metrics: [{ key: "open", label: "Open", value: 3, definition: "d" }], computed_at: "2026-09-06T00:00:00Z" })?.metrics).toEqual([
      { key: "open", label: "Open", value: 3, definition: "d", format: undefined },
    ]);
    expect(toToday({ metrics: { open: 3, gross_volume: { value: 100, format: "money" } } })?.metrics).toEqual([
      { key: "open", label: "open", value: 3 },
      { key: "gross_volume", label: "gross_volume", value: 100, definition: undefined, format: "money" },
    ]);
  });
});
