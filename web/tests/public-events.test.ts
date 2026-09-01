import { describe, expect, it } from "vitest";
import type { WebListing } from "../src/lib/listings";
import {
  clampLimit,
  inDateWindow,
  parseDateParam,
  parseSortParam,
  sortPublicEvents,
  toPublicEvent,
} from "../src/lib/public-events";

const NOW = new Date("2026-09-01T12:00:00Z");
const SITE = "https://snatchti.com";

function listing(over: Partial<WebListing> = {}): WebListing {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    seller_id: "22222222-2222-4222-8222-222222222222",
    event_name: "III Points Saturday",
    venue: "Mana Wynwood",
    neighborhood: "wynwood",
    category: "festivals",
    status: "active",
    auction_status: "active",
    event_date: "2026-09-12",
    event_time: "20:00:00",
    ticket_type: "GA",
    quantity: 2,
    starting_bid: 1,
    current_bid: 6,
    buy_now_enabled: true,
    buy_now_price: 300,
    cover_image_path: "22222222-2222-4222-8222-222222222222/covers/1780683748586.png",
    ends_at: "2026-09-10T00:00:00Z",
    bid_count: 3,
    ticket_platform: "dice",
    transfer_method: "mobile_transfer",
    winner_user_id: null,
    winning_bid_amount: null,
    created_at: "2026-08-30T00:00:00Z",
    ...over,
  } as WebListing;
}

describe("toPublicEvent", () => {
  it("never leaks non-display fields", () => {
    // The whole reason this endpoint exists instead of handing the marketing
    // site the anon key: anon can read ALL listings columns via PostgREST,
    // including seller_id, winner_user_id and proof paths. The projection is
    // the whitelist.
    const e = toPublicEvent(listing(), SITE, NOW) as unknown as Record<string, unknown>;
    // The seller uuid must not appear anywhere EXCEPT the imageUrl path (a
    // known, pinned caveat of today's storage layout — next test).
    const json = JSON.stringify({ ...e, imageUrl: "" });
    expect(json).not.toContain("22222222-2222-4222-8222");
    expect(e).not.toHaveProperty("seller_id");
    expect(e).not.toHaveProperty("winner_user_id");
    expect(e).not.toHaveProperty("transfer_method");
    expect(e).not.toHaveProperty("starting_bid");
    expect(e).not.toHaveProperty("proof_status");
  });

  it("known caveat: the image URL itself embeds the seller uuid", () => {
    // cover_image_path is {seller_uuid}/covers/{ts} by upload convention, and
    // the bucket is public — /browse exposes the identical URL today. Pinned
    // so a future storage restructure flips this test consciously.
    const e = toPublicEvent(listing(), SITE, NOW);
    expect(e.imageUrl).toContain("/auction-media/22222222-2222-4222-8222");
  });

  it("prices are all-in buyer prices in integer cents, matching product display", () => {
    const e = toPublicEvent(listing(), SITE, NOW);
    // $6 base -> $6.60 all-in; $300 base -> $330 all-in (10% buyer fee)
    expect(e.pricing.currentAllInCents).toBe(660);
    expect(e.pricing.currentAllInLabel).toMatch(/^\$6\.60/);
    expect(e.pricing.buyNow).toEqual(
      expect.objectContaining({ enabled: true, allInCents: 33000 }),
    );
  });

  it("buy_now disabled or null price collapses to enabled:false", () => {
    expect(toPublicEvent(listing({ buy_now_enabled: false }), SITE, NOW).pricing.buyNow).toEqual({ enabled: false });
    expect(toPublicEvent(listing({ buy_now_price: null }), SITE, NOW).pricing.buyNow).toEqual({ enabled: false });
  });

  it("canonical url is the real product route", () => {
    expect(toPublicEvent(listing(), SITE, NOW).url).toBe(
      "https://snatchti.com/listing/11111111-1111-4111-8111-111111111111",
    );
  });

  it("status maps LIVE/ENDING SOON onto the public vocabulary", () => {
    expect(toPublicEvent(listing(), SITE, NOW).status).toBe("live");
    expect(
      toPublicEvent(listing({ ends_at: "2026-09-01T20:00:00Z" }), SITE, NOW).status,
    ).toBe("ending_soon");
  });

  it("uses the app's own Miami-local formatters", () => {
    const e = toPublicEvent(listing(), SITE, NOW);
    expect(e.dateLabel).toBe("Sat, Sep 12, 2026");
    expect(e.timeLabel).toBe("8:00 PM");
  });
});

describe("inDateWindow", () => {
  it("is inclusive on both bounds and tolerant of open ends", () => {
    expect(inDateWindow("2026-09-12", "2026-09-12", "2026-09-12")).toBe(true);
    expect(inDateWindow("2026-09-11", "2026-09-12", undefined)).toBe(false);
    expect(inDateWindow("2026-09-13", undefined, "2026-09-12")).toBe(false);
    expect(inDateWindow("2026-09-13", undefined, undefined)).toBe(true);
  });
});

describe("sortPublicEvents", () => {
  const a = toPublicEvent(listing({ id: "aaaaaaaa-1111-4111-8111-111111111111", event_date: "2026-09-05", bid_count: 1, ends_at: "2026-09-04T00:00:00Z" }), SITE, NOW);
  const b = toPublicEvent(listing({ id: "bbbbbbbb-1111-4111-8111-111111111111", event_date: "2026-09-03", bid_count: 9, ends_at: "2026-09-06T00:00:00Z" }), SITE, NOW);

  it("soonest = soonest event first; ending = listing close first; most_bids = demand", () => {
    expect(sortPublicEvents([a, b], "soonest").map((e) => e.id[0])).toEqual(["b", "a"]);
    expect(sortPublicEvents([a, b], "ending").map((e) => e.id[0])).toEqual(["a", "b"]);
    expect(sortPublicEvents([a, b], "most_bids").map((e) => e.id[0])).toEqual(["b", "a"]);
  });

  it("is deterministic under ties (id tiebreak) and does not mutate input", () => {
    const t1 = toPublicEvent(listing({ id: "cccccccc-1111-4111-8111-111111111111" }), SITE, NOW);
    const t2 = toPublicEvent(listing({ id: "dddddddd-1111-4111-8111-111111111111" }), SITE, NOW);
    const input = [t2, t1];
    expect(sortPublicEvents(input, "soonest").map((e) => e.id[0])).toEqual(["c", "d"]);
    expect(input.map((e) => e.id[0])).toEqual(["d", "c"]);
  });
});

describe("param parsing", () => {
  it("clampLimit bounds to [1,50] and defaults junk", () => {
    expect(clampLimit(null)).toBe(12);
    expect(clampLimit("0")).toBe(1);
    expect(clampLimit("999")).toBe(50);
    expect(clampLimit("3.5")).toBe(12);
    expect(clampLimit("abc")).toBe(12);
  });

  it("parseDateParam accepts only literal YYYY-MM-DD", () => {
    expect(parseDateParam("2026-09-12")).toBe("2026-09-12");
    expect(parseDateParam("2026-9-12")).toBeUndefined();
    expect(parseDateParam("evil' or 1=1")).toBeUndefined();
    expect(parseDateParam(null)).toBeUndefined();
  });

  it("parseSortParam falls back to soonest", () => {
    expect(parseSortParam("most_bids")).toBe("most_bids");
    expect(parseSortParam("trending")).toBe("soonest");
    expect(parseSortParam(null)).toBe("soonest");
  });
});
