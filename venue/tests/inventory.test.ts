import { describe, expect, it } from "vitest";
import { BATCHES, HOLDS, PREVIEW_NOW, TICKET_TYPES } from "@/fixtures/venue";
import { availability, capacityFloor, doorHoldback, inventoryWarnings, remaining, sessionTotals } from "@/lib/inventory";

describe("capacity truth (spec §2.5, §8.4, §8.8)", () => {
  it("remaining = capacity − held − sold, never negative", () => {
    expect(remaining({ capacity: 300, held: 6, sold: 282 })).toBe(12);
    expect(remaining({ capacity: 10, held: 8, sold: 5 })).toBe(0);
  });
  it("capacity floor is held + sold", () => {
    expect(capacityFloor({ held: 40, sold: 200 })).toBe(240);
  });
  it("sold out and all held are distinct states", () => {
    expect(availability({ capacity: 100, held: 0, sold: 100 })).toBe("sold_out");
    expect(availability({ capacity: 40, held: 40, sold: 0 })).toBe("all_held");
    expect(availability({ capacity: 40, held: 30, sold: 5 })).toBe("available");
  });
});

describe("inventory warnings (spec §6.1 zone 6)", () => {
  const w = inventoryWarnings(BATCHES, TICKET_TYPES, HOLDS, { liveSessionIds: new Set(["smp_ses_sat_0912"]), now: PREVIEW_NOW });
  const kinds = (batchId: string) => w.filter((x) => x.batchId === batchId).map((x) => x.kind).sort();
  it("names the ticket type and release on every row", () => {
    for (const x of w) {
      expect(x.ticketTypeName).not.toBe("Unknown type");
      expect(x.release.length).toBeGreaterThan(0);
    }
  });
  it("flags GA public as low (12 left, threshold 20) with holds expiring", () => {
    expect(kinds("smp_b_ga_pub")).toEqual(["holds_expiring", "low"]);
  });
  it("flags the promoter hold as all held, never sold out", () => {
    expect(kinds("smp_b_ga_promo")).toContain("all_held");
    expect(kinds("smp_b_ga_promo")).not.toContain("sold_out");
  });
  it("flags early bird as sold out", () => {
    expect(kinds("smp_b_early_pub")).toEqual(["sold_out"]);
  });
  it("flags untouched door stock only while the session is live", () => {
    expect(kinds("smp_b_door")).toEqual(["door_untouched"]);
    const notLive = inventoryWarnings(BATCHES, TICKET_TYPES, HOLDS, { liveSessionIds: new Set(), now: PREVIEW_NOW });
    expect(notLive.filter((x) => x.batchId === "smp_b_door").map((x) => x.kind)).not.toContain("door_untouched");
  });
  it("does not count expired holds as expiring", () => {
    const expiring = w.find((x) => x.batchId === "smp_b_ga_pub" && x.kind === "holds_expiring");
    expect(expiring?.detail).toMatch(/^2 holds \(6 tickets\)/);
  });
});

describe("per-session roll-ups (spec §7.6, §8.5)", () => {
  it("rolls GA across its releases for tonight", () => {
    const t = sessionTotals(BATCHES, "smp_tt_ga", "smp_ses_sat_0912");
    expect(t).toEqual({ capacity: 370, held: 46, sold: 304, remaining: 20 });
  });
  it("states the door hold-back as N of total", () => {
    expect(doorHoldback(BATCHES, "smp_ses_sat_0912")).toEqual({ door: 40, total: 520 });
  });
});
