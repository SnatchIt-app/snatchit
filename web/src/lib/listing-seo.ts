import type { Metadata } from "next";
import { allInFromDollars, buyerTotalCents, dollarsToCents } from "@snatchit/core";
import type { WebListing } from "@/lib/listings";
import { coverImageUrl, deliveryLabel, fmtEventDate, listingCardStatus, neighborhoodLabel } from "@/lib/format";
import { effectiveBase, eventStartIso, listingTitle } from "@/lib/listing-display";
import { SITE_URL } from "@/lib/env";

/**
 * What the listing page tells crawlers and social cards: the page metadata and the Event JSON-LD.
 * Pure builders, so tests assert on the objects the page actually emits
 * (tests/listing-presentation.test.ts).
 */

type SeoListing = Pick<
  WebListing,
  | "id"
  | "event_name"
  | "venue"
  | "neighborhood"
  | "status"
  | "auction_status"
  | "ends_at"
  | "event_date"
  | "event_time"
  | "ticket_type"
  | "ticket_platform"
  | "cover_image_path"
  | "buy_now_enabled"
  | "buy_now_price"
  | "current_bid"
>;

/**
 * Title, description, canonical and Open Graph for /listing/[id]. No `twitter` block: Next fills
 * twitter:title, description and image from openGraph, and the layout's card type stays.
 */
export function listingMetadata(listing: SeoListing, now: Date = new Date()): Metadata {
  const status = listingCardStatus(listing, now);
  const active = status === "LIVE" || status === "ENDING SOON";
  const title = listingTitle(listing.event_name, listing.venue, fmtEventDate(listing.event_date));
  const description = `${listing.ticket_type} ticket · ${neighborhoodLabel(listing.neighborhood)} · ${
    listing.buy_now_enabled && listing.buy_now_price
      ? `Buy Now ${allInFromDollars(listing.buy_now_price)} all-in`
      : `bidding from ${allInFromDollars(listing.current_bid)} all-in`
  } on Snatch It, Miami's peer-to-peer ticket marketplace.`;

  return {
    title,
    description,
    alternates: { canonical: `/listing/${listing.id}` },
    robots: active ? undefined : { index: false, follow: true },
    openGraph: {
      title,
      description,
      // No declared size: covers are posters of any shape, and a fixed 1200×900 made social
      // cards crop portrait posters.
      images: [{ url: coverImageUrl(listing.cover_image_path) }],
    },
  };
}

/** schema.org Event with its Offer, for the listing page's JSON-LD. */
export function buildEventJsonLd(
  listing: SeoListing,
  opts: {
    /** The listing carries an owner proof waiver (proofWaiverNote is set). */
    proofWaived: boolean;
    sellerDisplayName?: string | null;
    /** The listing is open for purchase (LIVE or ENDING SOON). */
    available: boolean;
  },
) {
  const delivery = deliveryLabel(listing.ticket_platform);
  return {
    "@context": "https://schema.org",
    "@type": "Event",
    name: listing.event_name,
    startDate: eventStartIso(listing.event_date, listing.event_time),
    eventStatus: "https://schema.org/EventScheduled",
    eventAttendanceMode: "https://schema.org/OfflineEventAttendanceMode",
    location: {
      "@type": "Place",
      name: listing.venue,
      address: { "@type": "PostalAddress", addressLocality: "Miami", addressRegion: "FL" },
    },
    image: [coverImageUrl(listing.cover_image_path)],
    // A proof-waived listing is the platform owner's own inventory (156), not a peer resale.
    description: `${opts.proofWaived ? "Listed by Snatch It." : "Peer-to-peer resale listing on Snatch It."} ${listing.ticket_type} ticket delivered by ${delivery.charAt(0).toLowerCase()}${delivery.slice(1)} after purchase. Price includes all fees.`,
    offers: {
      "@type": "Offer",
      price: (buyerTotalCents(dollarsToCents(effectiveBase(listing))) / 100).toFixed(2),
      priceCurrency: "USD",
      availability: opts.available ? "https://schema.org/InStock" : "https://schema.org/SoldOut",
      url: `${SITE_URL}/listing/${listing.id}`,
      validThrough: listing.ends_at,
      ...(opts.proofWaived
        ? { offeredBy: { "@type": "Organization", name: "Snatch It" } }
        : opts.sellerDisplayName
          ? { offeredBy: { "@type": "Person", name: opts.sellerDisplayName } }
          : {}),
    },
  };
}
