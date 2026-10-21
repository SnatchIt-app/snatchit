import { createElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { buyerTotalCents, dollarsToCents } from "@snatchit/core";

// Presentation accuracy for the platform owner's own (proof-waived) listings, from the live
// verification of the four published listings (2026-10-16). Everything here is asserted on what
// the code returns or renders: the metadata and JSON-LD builders, the listing page, the cards.

const db = vi.hoisted(() => ({ listing: null as unknown, seller: null as unknown }));

vi.mock("next/image", () => ({
  default: ({ src, alt }: { src: string; alt: string }) => createElement("img", { src, alt }),
}));
vi.mock("next/link", () => ({
  default: ({ href, children, ...rest }: { href: string; children?: ReactNode }) => createElement("a", { href, ...rest }, children),
}));
vi.mock("@/components/SaveButton", () => ({ SaveButton: () => null }));
vi.mock("@/components/ui/BackLink", () => ({ BackLink: () => null }));
vi.mock("@/components/listing/BuyNowButton", () => ({ BuyNowButton: () => null }));
vi.mock("@/components/listing/BidPanel", () => ({ BidPanel: () => null }));
vi.mock("@/lib/favorites", () => ({ isListingSaved: async () => false, getSavedListingIdSet: async () => new Set<string>() }));
vi.mock("@/lib/checkout", () => ({ getReservationState: async () => null, isUnpaidAuctionWinner: () => false }));
vi.mock("@/lib/auth/session", () => ({ getAuthedUser: async () => null }));
vi.mock("@/lib/listings", () => ({
  getListing: async () => db.listing,
  getRelatedListings: async () => [],
  getSellerSummary: async () => db.seller,
}));

import type { SellerSummary, WebListing } from "@/lib/listings";
import { SITE_URL } from "@/lib/env";
import { coverImageUrl } from "@/lib/format";
import { serializeJsonLd } from "@/lib/json-ld";
import { eventAtVenue, eventStartIso, listingTitle, showsFanBadge } from "@/lib/listing-display";
import { buildEventJsonLd, listingMetadata } from "@/lib/listing-seo";
import { ListingCard } from "@/components/ListingCard";
import { ListingFeature } from "@/components/listing/ListingFeature";
import ListingPage, { generateMetadata } from "@/app/listing/[id]/page";

const NOW = new Date("2026-10-21T16:00:00Z");

// Shaped like the live IDEMI listing: proof-waived, hybrid, auction ending Oct 27 11:47 PM ET.
const WAIVED: WebListing = {
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

// An ordinary fan listing: no waiver, auction only, venue not in the name.
const PEER: WebListing = {
  ...WAIVED,
  id: "9d2e4f60-7a8b-4c9d-8e0f-1a2b3c4d5e6f",
  event_name: "III Points Saturday",
  venue: "Mana Wynwood",
  neighborhood: "wynwood",
  event_date: "2026-11-14",
  event_time: "21:30:00",
  buy_now_enabled: false,
  buy_now_price: null,
  current_bid: 120,
  ticket_platform: "ticketmaster",
  proof_waived_at: null,
};

const SELLER: SellerSummary = {
  id: WAIVED.seller_id,
  display_name: "SNATCH IT APP ADMIN",
  is_verified_seller: true,
  created_at: "2026-05-15T23:13:47.876Z",
};

beforeAll(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
});
afterAll(() => {
  vi.useRealTimers();
});

/** The Event JSON-LD exactly as the page writes it, read back. */
function parseJsonLd(html: string): Record<string, unknown>[] {
  return [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => JSON.parse(m[1]));
}

async function renderListingPage(listing: WebListing, seller: SellerSummary | null): Promise<string> {
  db.listing = listing;
  db.seller = seller;
  return renderToStaticMarkup(await ListingPage({ params: Promise.resolve({ id: listing.id }) }));
}

describe("platform-owned listings aren't presented as a fan's resale", () => {
  it("no 'From a fan' on a proof-waived listing; peer listings keep it", () => {
    expect(showsFanBadge({ proof_waived_at: "2026-10-15T23:55:39Z" })).toBe(false);
    expect(showsFanBadge({ proof_waived_at: null })).toBe(true);
    expect(showsFanBadge({})).toBe(true);
  });

  it("the rendered listing page: no fan pill on a waived listing, the pill on a peer listing", async () => {
    expect(await renderListingPage(WAIVED, SELLER)).not.toContain("From a fan");
    expect(await renderListingPage(PEER, SELLER)).toContain("From a fan");
  });
});

describe("Event JSON-LD (buildEventJsonLd)", () => {
  const waived = buildEventJsonLd(WAIVED, { proofWaived: true, sellerDisplayName: SELLER.display_name, available: true });
  const peer = buildEventJsonLd(PEER, { proofWaived: false, sellerDisplayName: "Dana", available: true });

  it("survives the JSON round trip the page uses, and nothing in it can close the script tag", () => {
    expect(JSON.parse(serializeJsonLd(waived))).toEqual(waived);
    const hostile = buildEventJsonLd({ ...PEER, event_name: "Night </script><script>alert(1)</script>" }, { proofWaived: false, available: true });
    const text = serializeJsonLd(hostile);
    expect(text).not.toContain("<");
    expect(JSON.parse(text).name).toBe("Night </script><script>alert(1)</script>");
  });

  it("has the required Event fields", () => {
    const ld = JSON.parse(serializeJsonLd(waived));
    expect(ld["@context"]).toBe("https://schema.org");
    expect(ld["@type"]).toBe("Event");
    expect(ld.name).toBe(WAIVED.event_name);
    expect(ld.eventStatus).toBe("https://schema.org/EventScheduled");
    expect(ld.eventAttendanceMode).toBe("https://schema.org/OfflineEventAttendanceMode");
    expect(ld.location).toEqual({
      "@type": "Place",
      name: WAIVED.venue,
      address: { "@type": "PostalAddress", addressLocality: "Miami", addressRegion: "FL" },
    });
    expect(ld.image).toEqual([coverImageUrl(WAIVED.cover_image_path)]);
  });

  it("startDate carries Miami's offset for that date", () => {
    expect(waived.startDate).toBe("2026-10-31T22:00:00-04:00");
    expect(peer.startDate).toBe("2026-11-14T21:30:00-05:00");
  });

  it("has the required Offer fields: all-in price, currency, availability, url, validThrough", () => {
    const offer = JSON.parse(serializeJsonLd(waived)).offers;
    expect(offer["@type"]).toBe("Offer");
    expect(offer.price).toMatch(/^\d+\.\d{2}$/);
    expect(offer.priceCurrency).toBe("USD");
    expect(offer.availability).toBe("https://schema.org/InStock");
    expect(offer.url).toBe(`${SITE_URL}/listing/${WAIVED.id}`);
    expect(offer.validThrough).toBe(WAIVED.ends_at);
  });

  it("prices the offer all-in from Buy Now when there is one, otherwise from the current bid", () => {
    expect(waived.offers.price).toBe((buyerTotalCents(dollarsToCents(95)) / 100).toFixed(2));
    expect(peer.offers.price).toBe((buyerTotalCents(dollarsToCents(120)) / 100).toFixed(2));
  });

  it("a closed listing is SoldOut", () => {
    expect(buildEventJsonLd(PEER, { proofWaived: false, available: false }).offers.availability).toBe("https://schema.org/SoldOut");
  });

  it("a proof-waived listing is offered by Snatch It, whoever the seller account is", () => {
    expect(waived.offers).toHaveProperty("offeredBy", { "@type": "Organization", name: "Snatch It" });
    expect(waived.description).toBe("Listed by Snatch It. GA ticket delivered by official DICE transfer after purchase. Price includes all fees.");
  });

  it("a peer listing is offered by the seller by name, or by no one when there is no name", () => {
    expect(peer.offers).toHaveProperty("offeredBy", { "@type": "Person", name: "Dana" });
    expect(peer.description).toBe(
      "Peer-to-peer resale listing on Snatch It. GA ticket delivered by official Ticketmaster / Live Nation transfer after purchase. Price includes all fees.",
    );
    expect(buildEventJsonLd(PEER, { proofWaived: false, sellerDisplayName: null, available: true }).offers).not.toHaveProperty("offeredBy");
    expect(buildEventJsonLd(PEER, { proofWaived: false, sellerDisplayName: "", available: true }).offers).not.toHaveProperty("offeredBy");
  });

  it("the page writes exactly this object, once, on a live listing", async () => {
    expect(parseJsonLd(await renderListingPage(WAIVED, SELLER))).toEqual([waived]);
    expect(parseJsonLd(await renderListingPage(PEER, { ...SELLER, display_name: "Dana" }))).toEqual([peer]);
  });

  it("the page writes no Event JSON-LD once the listing has ended", async () => {
    expect(parseJsonLd(await renderListingPage({ ...PEER, auction_status: "ended" }, SELLER))).toEqual([]);
  });
});

describe("page metadata (listingMetadata)", () => {
  it("title, social title, description, canonical and cover image", () => {
    const md = listingMetadata(WAIVED, NOW);
    const title = "IDEMI: Halloween Night at Jolene Sound Room — Sat, Oct 31, 2026";
    expect(md.title).toBe(title);
    expect(md.description).toBe("GA ticket · Downtown Miami · Buy Now $104.50 all-in on Snatch It, Miami's peer-to-peer ticket marketplace.");
    expect(md.alternates).toEqual({ canonical: `/listing/${WAIVED.id}` });
    expect(md.robots).toBeUndefined();
    expect(md.openGraph).toEqual({ title, description: md.description, images: [{ url: coverImageUrl(WAIVED.cover_image_path) }] });
    // twitter:title/description/image come from openGraph (Next fills them in); the layout keeps the card type.
    expect(md).not.toHaveProperty("twitter");
  });

  it("og:image declares no fixed size (posters come in any shape)", () => {
    const images = listingMetadata(WAIVED, NOW).openGraph?.images as Record<string, unknown>[];
    expect(images).toHaveLength(1);
    expect(images[0]).not.toHaveProperty("width");
    expect(images[0]).not.toHaveProperty("height");
  });

  it("a pure auction says where bidding starts, all-in", () => {
    expect(listingMetadata(PEER, NOW).description).toBe(
      "GA ticket · Wynwood · bidding from $132 all-in on Snatch It, Miami's peer-to-peer ticket marketplace.",
    );
  });

  it("an ended listing is noindex, follow", () => {
    expect(listingMetadata({ ...PEER, auction_status: "ended" }, NOW).robots).toEqual({ index: false, follow: true });
  });

  it("generateMetadata returns the builder's object", async () => {
    db.listing = WAIVED;
    expect(await generateMetadata({ params: Promise.resolve({ id: WAIVED.id }) })).toEqual(listingMetadata(WAIVED, NOW));
  });
});

describe("structured-data start time carries Miami's offset", () => {
  it.each([
    ["2026-10-31", "22:00:00", "2026-10-31T22:00:00-04:00"], // IDEMI, still EDT
    ["2026-11-13", "22:00:00", "2026-11-13T22:00:00-05:00"], // after the switch, EST
    ["2026-11-13", "23:00:00", "2026-11-13T23:00:00-05:00"],
    ["2026-12-04", "16:00:00", "2026-12-04T16:00:00-05:00"],
    ["2026-07-04", "20:00", "2026-07-04T20:00:00-04:00"],
  ])("%s %s → %s", (d, t, want) => {
    expect(eventStartIso(d, t)).toBe(want);
  });

  it("unparseable input passes through rather than inventing an offset", () => {
    expect(eventStartIso("not-a-date", "22:00:00")).toBe("not-a-dateT22:00:00");
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
});

describe("poster alt text and card link labels don't repeat the venue", () => {
  const altOf = (html: string) => [...html.matchAll(/<img[^>]*alt="([^"]*)"/g)].map((m) => m[1]);
  const ariaOf = (html: string) => [...html.matchAll(/<a[^>]*aria-label="([^"]*)"/g)].map((m) => m[1]);
  const LIV: WebListing = { ...PEER, id: "liv", event_name: "Olivia Rodrigo Night", venue: "LIV" };

  it("listing card: poster alt and the card's link label", () => {
    const waived = renderToStaticMarkup(createElement(ListingCard, { listing: WAIVED }));
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
    expect(altOf(renderToStaticMarkup(createElement(ListingFeature, { listing: WAIVED, now: NOW })))).toEqual([
      "IDEMI: Halloween Night at Jolene Sound Room",
    ]);
    expect(altOf(renderToStaticMarkup(createElement(ListingFeature, { listing: LIV, now: NOW })))).toEqual(["Olivia Rodrigo Night at LIV"]);
  });

  it("listing page: poster alt", async () => {
    expect(altOf(await renderListingPage(WAIVED, SELLER))).toEqual(["IDEMI: Halloween Night at Jolene Sound Room"]);
    expect(altOf(await renderListingPage(LIV, SELLER))).toEqual(["Olivia Rodrigo Night at LIV"]);
  });
});
