import { describe, expect, it } from "vitest";
import {
  categoryLabel,
  fmtEndsIn,
  fmtEventDate,
  fmtEventTime,
  listingCardStatus,
  neighborhoodLabel,
  platformLabel,
} from "../src/lib/format";

describe("fmtEventDate", () => {
  it("formats date-only strings without timezone drift", () => {
    expect(fmtEventDate("2026-10-17")).toBe("Sat, Oct 17, 2026");
    expect(fmtEventDate("2026-08-29")).toBe("Sat, Aug 29, 2026");
    expect(fmtEventDate("2026-01-01")).toBe("Thu, Jan 1, 2026");
  });
  it("passes through malformed input", () => {
    expect(fmtEventDate("bad")).toBe("bad");
  });
});

describe("fmtEventTime", () => {
  it("formats 24h times to 12h", () => {
    expect(fmtEventTime("22:00:00")).toBe("10:00 PM");
    expect(fmtEventTime("02:00:00")).toBe("2:00 AM");
    expect(fmtEventTime("00:30:00")).toBe("12:30 AM");
    expect(fmtEventTime("12:00:00")).toBe("12:00 PM");
    expect(fmtEventTime("23:00:00")).toBe("11:00 PM");
  });
});

describe("fmtEndsIn", () => {
  const now = new Date("2026-07-27T12:00:00Z");
  it("renders coarse remaining time", () => {
    expect(fmtEndsIn("2026-08-23T20:09:02Z", now)).toBe("27d 8h");
    expect(fmtEndsIn("2026-07-27T15:12:00Z", now)).toBe("3h 12m");
    expect(fmtEndsIn("2026-07-27T12:12:00Z", now)).toBe("12m");
    expect(fmtEndsIn("2026-07-27T12:00:30Z", now)).toBe("1m");
  });
  it("returns Ended for past times", () => {
    expect(fmtEndsIn("2026-07-27T11:59:00Z", now)).toBe("Ended");
  });
});

describe("listingCardStatus", () => {
  const now = new Date("2026-07-27T12:00:00Z");
  const base = { status: "active", auction_status: "active", ends_at: "2026-08-23T20:09:02Z" };
  it("LIVE when active and >24h left", () => {
    expect(listingCardStatus(base, now)).toBe("LIVE");
  });
  it("ENDING SOON inside 24h", () => {
    expect(listingCardStatus({ ...base, ends_at: "2026-07-28T06:00:00Z" }, now)).toBe("ENDING SOON");
  });
  it("ENDED when past or auction ended", () => {
    expect(listingCardStatus({ ...base, ends_at: "2026-07-27T11:00:00Z" }, now)).toBe("ENDED");
    expect(listingCardStatus({ ...base, auction_status: "ended" }, now)).toBe("ENDED");
  });
  it("SOLD and RESERVED take precedence", () => {
    expect(listingCardStatus({ ...base, status: "sold" }, now)).toBe("SOLD");
    expect(listingCardStatus({ ...base, auction_status: "sold" }, now)).toBe("SOLD");
    expect(listingCardStatus({ ...base, status: "reserved" }, now)).toBe("RESERVED");
  });
});

describe("labels from shared @snatchit/core data", () => {
  it("maps known values", () => {
    expect(categoryLabel("clubs")).toBeTruthy();
    expect(neighborhoodLabel("wynwood")).toBe("Wynwood");
    expect(neighborhoodLabel("e11even")).toBe("E11EVEN");
    expect(platformLabel("posh")).toBeTruthy();
    expect(platformLabel("ticketmaster")).toBeTruthy();
  });
  it("falls back gracefully for unknown values", () => {
    expect(neighborhoodLabel("somewhere new")).toBe("Somewhere New");
    expect(platformLabel("unknown_platform")).toBe("Other platform");
  });
});
