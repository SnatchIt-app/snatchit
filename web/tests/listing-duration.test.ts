import { readFileSync } from "node:fs";
import path from "node:path";
import { beforeEach, describe, expect, it, vi } from "vitest";

// 72-hour auctions (owner via A, 2026-10-15): the database CHECK becomes {1,3,6,12,24,48,72}.
// /sell offers exactly that list, and createListing refuses anything else before computing
// ends_at from it — the action takes any payload, the form is not a boundary.

const h = vi.hoisted(() => ({ inserts: [] as Record<string, unknown>[] }));

vi.mock("server-only", () => ({}));
vi.mock("@/lib/payouts", () => ({ getPayoutStatus: async () => ({ status: "connected" }) }));
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: async () => ({
    from: () => ({
      insert(row: Record<string, unknown>) {
        h.inserts.push(row);
        return { select: () => ({ single: async () => ({ data: { id: "new-listing" }, error: null }) }) };
      },
    }),
  }),
}));

import { LISTING_DURATION_HOURS, durationLabel, isListingDuration } from "@/lib/listing-durations";
import { createListing } from "@/lib/create-listing";

const payload = (durationHours: unknown) =>
  ({
    eventName: "Show",
    venue: "Club",
    neighborhood: "wynwood",
    eventDate: "2026-11-01",
    eventTime: "22:00:00",
    ticketType: "GA",
    quantity: 1,
    transferMethod: "app",
    restrictions: null,
    startingBid: 20,
    buyNowEnabled: false,
    buyNowPrice: null,
    durationHours,
    ticketPlatform: "other",
    coverImagePath: "c",
    proofImagePath: "p",
    sellerCommitmentAccepted: true,
    category: "clubs",
  }) as unknown as Parameters<typeof createListing>[1];

beforeEach(() => {
  h.inserts = [];
});

describe("listing durations", () => {
  it("offers exactly the lengths the database accepts, 72 h included", () => {
    expect([...LISTING_DURATION_HOURS]).toEqual([1, 3, 6, 12, 24, 48, 72]);
    expect(durationLabel(72)).toBe("3d");
    expect(durationLabel(48)).toBe("2d");
    expect(durationLabel(6)).toBe("6h");
  });

  it("a 72 h listing is inserted with duration_hours 72 and ends 72 h from now", async () => {
    const before = Date.now();
    expect(await createListing("u", payload(72))).toEqual({ id: "new-listing" });
    expect(h.inserts).toHaveLength(1);
    expect(h.inserts[0].duration_hours).toBe(72);
    const ends = new Date(String(h.inserts[0].ends_at)).getTime();
    expect(ends - before).toBeGreaterThanOrEqual(72 * 3_600_000);
    expect(ends - Date.now()).toBeLessThanOrEqual(72 * 3_600_000);
  });

  it.each([96, 0, -24, 2, 24.5, "24", null, Number.NaN])("refuses %s before any insert", async (d) => {
    expect(isListingDuration(d)).toBe(false);
    expect(await createListing("u", payload(d))).toEqual({ error: "Choose how long the listing runs." });
    expect(h.inserts).toHaveLength(0);
  });

  it("the /sell form renders the shared list, not a copy of it", () => {
    const src = readFileSync(path.resolve(__dirname, "../src/components/sell/CreateListingForm.tsx"), "utf8");
    expect(src).toContain("LISTING_DURATION_HOURS.map(");
    expect(src).not.toMatch(/\[\s*1\s*,\s*3\s*,\s*6\s*,\s*12\s*,\s*24\s*,\s*48/);
  });
});
