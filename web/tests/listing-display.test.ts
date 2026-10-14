import { describe, expect, it } from "vitest";
import { clockState, eventWhen, fmtEventDay, homeSection, priceState, quantityLine } from "@/lib/listing-display";

const NOW = new Date("2026-10-13T16:00:00Z"); // Tue Oct 13, 12:00 PM in Miami (EDT)

function listing(over: Partial<Parameters<typeof priceState>[0]> = {}) {
  return {
    status: "active",
    auction_status: "active",
    ends_at: "2026-10-13T18:11:00Z",
    bid_count: 6,
    current_bid: 95,
    starting_bid: 80,
    winning_bid_amount: null,
    event_date: "2026-10-13",
    event_time: "21:30:00",
    quantity: 2,
    ticket_type: "GA",
    ...over,
  };
}

describe("priceState — which stored amount a row shows, and its label", () => {
  it("live auction with bids shows the current bid", () => {
    expect(priceState(listing(), NOW)).toEqual({ label: "Current bid", dollars: 95 });
  });
  it("live auction without bids is a starting bid", () => {
    expect(priceState(listing({ bid_count: 0, current_bid: 80 }), NOW)).toEqual({ label: "Starting bid", dollars: 80 });
  });
  it("sold uses the winning amount, falling back to the current bid", () => {
    expect(priceState(listing({ status: "sold", winning_bid_amount: 120 }), NOW)).toEqual({ label: "Sold for", dollars: 120 });
    expect(priceState(listing({ auction_status: "sold" }), NOW)).toEqual({ label: "Sold for", dollars: 95 });
  });
  it("ended with bids is the final bid; without bids it shows where it started", () => {
    expect(priceState(listing({ ends_at: "2026-10-13T15:00:00Z" }), NOW)).toEqual({ label: "Final bid", dollars: 95 });
    expect(priceState(listing({ auction_status: "ended", bid_count: 0 }), NOW)).toEqual({ label: "Started at", dollars: 80 });
  });
  it("a cancelled listing never reads as live", () => {
    expect(priceState(listing({ auction_status: "cancelled" }), NOW).label).toBe("Final bid");
  });
});

describe("clockState — native feed-row clock", () => {
  it("under an hour is urgent", () => {
    expect(clockState(listing({ ends_at: "2026-10-13T16:07:30Z" }), NOW)).toEqual({ text: "Ending in 7m", tone: "urgent" });
  });
  it("under a day counts down", () => {
    expect(clockState(listing(), NOW)).toEqual({ text: "2h 11m left", tone: "normal" });
  });
  it("later shows the end time in Miami time, not the server's UTC", () => {
    // 04:41 UTC on Thu Oct 15 is 12:41 AM Thursday in Miami
    expect(clockState(listing({ ends_at: "2026-10-15T04:41:00Z" }), NOW)).toEqual({ text: "Ends Thu, 12:41 AM", tone: "normal" });
  });
  it("closed and held states say so", () => {
    expect(clockState(listing({ status: "sold" }), NOW).text).toBe("Sold");
    expect(clockState(listing({ auction_status: "cancelled" }), NOW).text).toBe("Cancelled");
    expect(clockState(listing({ status: "reserved" }), NOW).text).toBe("On hold");
    expect(clockState(listing({ ends_at: "not a date" }), NOW).text).toBe("Ended");
  });
});

describe("homeSection — the native Home rule, with today in Miami", () => {
  const lateEvening = new Date("2026-10-13T03:30:00Z"); // Mon Oct 12, 11:30 PM in Miami; already Oct 13 in UTC
  it("uses the Miami calendar day", () => {
    expect(homeSection("2026-10-12", lateEvening)).toBe("Tonight");
    expect(homeSection("2026-10-13", lateEvening)).toBe("This week");
  });
  it("next 1–7 days is this week, beyond that is later", () => {
    expect(homeSection("2026-10-19", lateEvening)).toBe("This week");
    expect(homeSection("2026-10-20", lateEvening)).toBe("Later");
  });
  it("past or unreadable dates get no heading at all", () => {
    expect(homeSection("2026-10-11", lateEvening)).toBeNull();
    expect(homeSection("not-a-date", lateEvening)).toBeNull();
    expect(homeSection("2026-13-01", lateEvening)).toBeNull();
  });
});

describe("row text helpers", () => {
  it("formats the event day without a year or timezone shift", () => {
    expect(fmtEventDay("2026-10-24")).toBe("Sat, Oct 24");
    expect(fmtEventDay("garbage")).toBe("garbage");
    expect(eventWhen({ event_date: "2026-10-24", event_time: "19:30:00" })).toBe("Sat, Oct 24 · 7:30 PM");
  });
  it("names the ticket count and type", () => {
    expect(quantityLine({ quantity: 2, ticket_type: "GA" })).toBe("2 × GA");
    expect(quantityLine({ quantity: 6, ticket_type: "TABLE" })).toBe("6 × Table");
  });
});
