import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { eventStartIso, listingTitle, showsFanBadge } from "@/lib/listing-display";

// Presentation accuracy for the platform owner's own (proof-waived) listings, from the live
// verification of the four published listings (2026-10-16).

describe("platform-owned listings aren't presented as a fan's resale", () => {
  it("no 'From a fan' on a proof-waived listing; peer listings keep it", () => {
    expect(showsFanBadge({ proof_waived_at: "2026-10-15T23:55:39Z" })).toBe(false);
    expect(showsFanBadge({ proof_waived_at: null })).toBe(true);
    expect(showsFanBadge({})).toBe(true);
  });

  it("the listing page wires it: badge, structured-data seller and description", () => {
    const src = readFileSync(path.resolve(__dirname, "../src/app/listing/[id]/page.tsx"), "utf8");
    expect(src).toContain("{showsFanBadge(listing) ? <Badge>From a fan</Badge> : null}");
    expect(src).not.toMatch(/<Badge>From a fan<\/Badge>\n/);
    expect(src).toContain('offeredBy: { "@type": "Organization", name: "Snatch It" }');
    expect(src).toContain('"Listed by Snatch It."');
    expect(src).toContain("validThrough: listing.ends_at");
  });
});

describe("structured-data start time carries Miami's offset", () => {
  it.each([
    ["2026-10-31", "22:00:00", "2026-10-31T22:00:00-04:00"], // IDEMI — still EDT
    ["2026-11-13", "22:00:00", "2026-11-13T22:00:00-05:00"], // after the switch — EST
    ["2026-11-13", "23:00:00", "2026-11-13T23:00:00-05:00"],
    ["2026-12-04", "16:00:00", "2026-12-04T16:00:00-05:00"],
    ["2026-07-04", "20:00", "2026-07-04T20:00:00-04:00"],
  ])("%s %s → %s", (d, t, want) => {
    expect(eventStartIso(d, t)).toBe(want);
  });

  it("unparseable input passes through rather than inventing an offset", () => {
    expect(eventStartIso("not-a-date", "22:00:00")).toBe("not-a-dateT22:00:00");
  });

  it("the page uses it for startDate", () => {
    const src = readFileSync(path.resolve(__dirname, "../src/app/listing/[id]/page.tsx"), "utf8");
    expect(src).toContain("startDate: eventStartIso(listing.event_date, listing.event_time)");
  });
});

describe("titles don't repeat the venue", () => {
  it("event name already naming the venue → no 'at <venue>' suffix", () => {
    expect(listingTitle("IDEMI — Halloween Night at Jolene Sound Room", "Jolene Sound Room (200 E Flagler St, Basement)", "Sat, Oct 31, 2026")).toBe(
      "IDEMI — Halloween Night at Jolene Sound Room — Sat, Oct 31, 2026",
    );
    expect(listingTitle("ANOTR — Watson Island Park", "Watson Island Park", "Fri, Dec 4, 2026")).toBe("ANOTR — Watson Island Park — Fri, Dec 4, 2026");
  });

  it.each([
    // The four live titles after the owner-approved retitle (A, 2026-10-16), with their stored venues.
    ["IDEMI: Halloween Night at Jolene Sound Room", "Jolene Sound Room (200 E Flagler St, Basement)", "Sat, Oct 31, 2026"],
    ["Adiel & Yu Su with JOVIGIBS at Jolene Sound Room", "Jolene Sound Room (200 E Flagler St, Basement)", "Fri, Nov 13, 2026"],
    ["James Hype + HILLS at Club Space", "Club Space (Terrace)", "Fri, Nov 13, 2026"],
    ["ANOTR at Watson Island Park", "Watson Island Park", "Fri, Dec 4, 2026"],
  ])("live title %s: venue not repeated", (name, venue, date) => {
    expect(listingTitle(name, venue, date)).toBe(`${name} — ${date}`);
  });

  it("otherwise the venue is added as before", () => {
    expect(listingTitle("III Points Saturday", "Mana Wynwood", "Sat, Sep 12, 2026")).toBe("III Points Saturday at Mana Wynwood — Sat, Sep 12, 2026");
  });

  it("og:image no longer declares a fixed 1200×900 size", () => {
    const src = readFileSync(path.resolve(__dirname, "../src/app/listing/[id]/page.tsx"), "utf8");
    expect(src).not.toMatch(/width: 1200, height: 900/);
    expect(src).toContain("listingTitle(listing.event_name, listing.venue, fmtEventDate(listing.event_date))");
  });
});
