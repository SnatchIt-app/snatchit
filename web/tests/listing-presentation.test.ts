import { readFileSync } from "node:fs";
import path from "node:path";
import { createElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/image", () => ({
  default: ({ src, alt }: { src: string; alt: string }) => createElement("img", { src, alt }),
}));
vi.mock("next/link", () => ({
  default: ({ href, children, ...rest }: { href: string; children?: ReactNode }) => createElement("a", { href, ...rest }, children),
}));
vi.mock("@/components/SaveButton", () => ({ SaveButton: () => null }));

import type { WebListing } from "@/lib/listings";
import { eventAtVenue, eventStartIso, listingTitle, showsFanBadge } from "@/lib/listing-display";
import { ListingCard } from "@/components/ListingCard";
import { ListingFeature } from "@/components/listing/ListingFeature";

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
    expect(eventAtVenue(name, venue)).toBe(name);
  });

  it("otherwise the venue is added as before", () => {
    expect(listingTitle("III Points Saturday", "Mana Wynwood", "Sat, Sep 12, 2026")).toBe("III Points Saturday at Mana Wynwood — Sat, Sep 12, 2026");
  });

  it("the venue must appear as whole words: LIV is not in 'Olivia' or 'Delivery … Live'", () => {
    expect(listingTitle("Olivia Rodrigo Night", "LIV", "Sat, Nov 7, 2026")).toBe("Olivia Rodrigo Night at LIV — Sat, Nov 7, 2026");
    expect(listingTitle("Delivery Boys Live", "LIV", "Sat, Nov 7, 2026")).toBe("Delivery Boys Live at LIV — Sat, Nov 7, 2026");
    expect(eventAtVenue("Olivia Rodrigo Night", "LIV")).toBe("Olivia Rodrigo Night at LIV");
    expect(eventAtVenue("Delivery Boys Live", "LIV")).toBe("Delivery Boys Live at LIV");
  });

  it("a whole-word venue in the name is found, ignoring case and surrounding punctuation", () => {
    expect(eventAtVenue("Kaskade at LIV", "LIV")).toBe("Kaskade at LIV");
    expect(eventAtVenue("Kaskade at liv", "LIV")).toBe("Kaskade at liv");
    expect(eventAtVenue("LIV Sundays: Kaskade", "LIV")).toBe("LIV Sundays: Kaskade");
    expect(eventAtVenue("Rooftop at Club M.I.A.", "Club M.I.A.")).toBe("Rooftop at Club M.I.A.");
    expect(eventAtVenue("Sunset at Óleo", "Óleo")).toBe("Sunset at Óleo");
    expect(eventAtVenue("Sunset at Óleos", "Óleo")).toBe("Sunset at Óleos at Óleo");
  });

  it("the venue is matched literally, never as a pattern", () => {
    // Unescaped, "." would match the "0" in "100".
    expect(eventAtVenue("Club 100 Anniversary", "Club 1.0")).toBe("Club 100 Anniversary at Club 1.0");
    expect(() => eventAtVenue("Night", "Bar) [x* +?")).not.toThrow();
    expect(eventAtVenue("Night at Bar) [x* +?", "Bar) [x* +?")).toBe("Night at Bar) [x* +?");
  });

  it("og:image no longer declares a fixed 1200×900 size", () => {
    const src = readFileSync(path.resolve(__dirname, "../src/app/listing/[id]/page.tsx"), "utf8");
    expect(src).not.toMatch(/width: 1200, height: 900/);
    expect(src).toContain("listingTitle(listing.event_name, listing.venue, fmtEventDate(listing.event_date))");
  });
});

const CARD: WebListing = {
  id: "0b6f3c55-6c1d-4d2e-9a43-5d1f2b7c9e01",
  seller_id: "4c1f0a8e-2b3d-4e5f-8a9b-0c1d2e3f4a5b",
  event_name: "IDEMI: Halloween Night at Jolene Sound Room",
  venue: "Jolene Sound Room (200 E Flagler St, Basement)",
  neighborhood: "downtown miami",
  category: "clubs",
  status: "active",
  auction_status: "active",
  event_date: "2026-10-31",
  event_time: "22:00:00",
  ticket_type: "GA",
  quantity: 1,
  starting_bid: 80,
  current_bid: 80,
  buy_now_enabled: true,
  buy_now_price: 95,
  cover_image_path: "4c1f0a8e-2b3d-4e5f-8a9b-0c1d2e3f4a5b/covers/idemi.jpg",
  ends_at: "2026-10-28T03:47:00.000Z",
  bid_count: 0,
  ticket_platform: "dice",
  transfer_method: "mobile_transfer",
  winner_user_id: null,
  winning_bid_amount: null,
  created_at: "2026-10-15T23:50:00.000Z",
  proof_waived_at: "2026-10-15T23:55:39.000Z",
};
const PEER: WebListing = { ...CARD, id: "peer", event_name: "III Points Saturday", venue: "Mana Wynwood", proof_waived_at: null };
const LIV: WebListing = { ...CARD, id: "liv", event_name: "Olivia Rodrigo Night", venue: "LIV", proof_waived_at: null };
const NOW = new Date("2026-10-21T16:00:00Z");

describe("poster alt text and card link labels don't repeat the venue", () => {
  const altOf = (html: string) => [...html.matchAll(/<img[^>]*alt="([^"]*)"/g)].map((m) => m[1]);
  const ariaOf = (html: string) => [...html.matchAll(/<a[^>]*aria-label="([^"]*)"/g)].map((m) => m[1]);

  it("listing card: poster alt and the card's link label", () => {
    const waived = renderToStaticMarkup(createElement(ListingCard, { listing: CARD }));
    expect(altOf(waived)).toEqual(["IDEMI: Halloween Night at Jolene Sound Room"]);
    expect(ariaOf(waived)).toEqual(["IDEMI: Halloween Night at Jolene Sound Room"]);
    const peer = renderToStaticMarkup(createElement(ListingCard, { listing: PEER }));
    expect(altOf(peer)).toEqual(["III Points Saturday at Mana Wynwood"]);
    expect(ariaOf(peer)).toEqual(["III Points Saturday at Mana Wynwood"]);
    const liv = renderToStaticMarkup(createElement(ListingCard, { listing: LIV }));
    expect(altOf(liv)).toEqual(["Olivia Rodrigo Night at LIV"]);
    expect(ariaOf(liv)).toEqual(["Olivia Rodrigo Night at LIV"]);
  });

  it("home feature: poster alt", () => {
    expect(altOf(renderToStaticMarkup(createElement(ListingFeature, { listing: CARD, now: NOW })))).toEqual([
      "IDEMI: Halloween Night at Jolene Sound Room",
    ]);
    expect(altOf(renderToStaticMarkup(createElement(ListingFeature, { listing: LIV, now: NOW })))).toEqual(["Olivia Rodrigo Night at LIV"]);
  });
});
