import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import {
  allInFromDollars,
  buyerTotalCents,
  dollarsToCents,
} from "@snatchit/core";
import {
  coverImageUrl,
  getListing,
  getRelatedListings,
  getSellerSummary,
  type WebListing,
} from "@/lib/listings";
import {
  categoryLabel,
  fmtEventDate,
  fmtEventTime,
  listingCardStatus,
  neighborhoodLabel,
  platformLabel,
} from "@/lib/format";
import { SITE_URL } from "@/lib/env";
import { Container } from "@/components/ui/Container";
import { Badge, LiveDot } from "@/components/ui/Badge";
import { Button, LinkButton } from "@/components/ui/Button";
import { PriceBreakdown, PriceDisplay } from "@/components/ui/PriceDisplay";
import { SectionHeader } from "@/components/ui/SectionHeader";
import { ListingCard } from "@/components/ListingCard";
import { Countdown } from "@/components/listing/Countdown";
import { JsonLd } from "@/components/site/JsonLd";

type Params = { id: string };

function effectiveBase(l: WebListing): number {
  return l.buy_now_enabled && l.buy_now_price ? l.buy_now_price : l.current_bid;
}

export async function generateMetadata({
  params,
}: {
  params: Promise<Params>;
}): Promise<Metadata> {
  const { id } = await params;
  const listing = await getListing(id).catch(() => null);
  // Deciding 404 here (before streaming starts) gives crawlers a real 404
  // status; the page body's notFound() alone would stream inside a 200.
  if (!listing) notFound();

  const status = listingCardStatus(listing);
  const active = status === "LIVE" || status === "ENDING SOON";
  const title = `${listing.event_name} at ${listing.venue} — ${fmtEventDate(listing.event_date)}`;
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
      images: [{ url: coverImageUrl(listing.cover_image_path), width: 1200, height: 900 }],
    },
  };
}

export default async function ListingPage({ params }: { params: Promise<Params> }) {
  const { id } = await params;
  const listing = await getListing(id);
  if (!listing) notFound();

  const [seller, related] = await Promise.all([
    getSellerSummary(listing.seller_id).catch(() => null),
    getRelatedListings(listing).catch(() => [] as WebListing[]),
  ]);

  const status = listingCardStatus(listing);
  const isActive = status === "LIVE" || status === "ENDING SOON";
  const base = effectiveBase(listing);
  const platform = platformLabel(listing.ticket_platform);

  const eventJsonLd = {
    "@context": "https://schema.org",
    "@type": "Event",
    name: listing.event_name,
    startDate: `${listing.event_date}T${listing.event_time}`,
    eventStatus: "https://schema.org/EventScheduled",
    eventAttendanceMode: "https://schema.org/OfflineEventAttendanceMode",
    location: {
      "@type": "Place",
      name: listing.venue,
      address: { "@type": "PostalAddress", addressLocality: "Miami", addressRegion: "FL" },
    },
    image: [coverImageUrl(listing.cover_image_path)],
    description: `Peer-to-peer resale listing on Snatch It. ${listing.ticket_type} ticket transferred via ${platform} after purchase. Price includes all fees.`,
    offers: {
      "@type": "Offer",
      price: (buyerTotalCents(dollarsToCents(base)) / 100).toFixed(2),
      priceCurrency: "USD",
      availability: isActive
        ? "https://schema.org/InStock"
        : "https://schema.org/SoldOut",
      url: `${SITE_URL}/listing/${listing.id}`,
      ...(seller?.display_name
        ? { offeredBy: { "@type": "Person", name: seller.display_name } }
        : {}),
    },
  };

  return (
    <Container className="py-6 lg:py-10">
      {/* Breadcrumb */}
      <nav aria-label="Breadcrumb" className="mb-5 text-[13px] text-muted">
        <ol className="flex flex-wrap items-center gap-1.5">
          <li>
            <Link href="/browse" className="inline-flex min-h-9 items-center hover:text-ink">
              Browse
            </Link>
          </li>
          <li aria-hidden="true">/</li>
          <li>
            <Link
              href={`/browse?category=${encodeURIComponent(listing.category)}`}
              className="inline-flex min-h-9 items-center hover:text-ink"
            >
              {categoryLabel(listing.category)}
            </Link>
          </li>
          <li aria-hidden="true">/</li>
          <li aria-current="page" className="truncate text-dim">
            {listing.event_name}
          </li>
        </ol>
      </nav>

      <div className="grid gap-10 lg:grid-cols-[minmax(0,1fr)_400px]">
        {/* ── Left column ── */}
        <div className="space-y-8">
          <figure className="relative aspect-[4/3] overflow-hidden rounded-card border border-line bg-field">
            <Image
              src={coverImageUrl(listing.cover_image_path)}
              alt={`${listing.event_name} at ${listing.venue}`}
              fill
              priority
              sizes="(min-width: 1024px) 58vw, 100vw"
              className="object-cover"
            />
          </figure>

          <div>
            <div className="flex flex-wrap items-center gap-2.5">
              {status === "LIVE" ? (
                <Badge variant="live">
                  <LiveDot /> Live auction
                </Badge>
              ) : status === "ENDING SOON" ? (
                <Badge variant="soon">Ending soon</Badge>
              ) : (
                <Badge variant="sold">{status === "SOLD" ? "Sold" : status === "RESERVED" ? "Reserved" : "Ended"}</Badge>
              )}
              {listing.buy_now_enabled ? <Badge variant="buyNow">Buy now available</Badge> : null}
            </div>
            <h1 className="mt-3 text-2xl font-bold tracking-tight text-ink sm:text-3xl">
              {listing.event_name}
            </h1>
            <p className="mt-2 text-[15px] text-muted">
              {listing.venue} · {neighborhoodLabel(listing.neighborhood)} ·{" "}
              {fmtEventDate(listing.event_date)} · {fmtEventTime(listing.event_time)}
            </p>
          </div>

          {/* Event facts */}
          <dl className="grid grid-cols-2 gap-x-8 gap-y-5 rounded-card border border-line bg-card p-6 sm:grid-cols-4">
            <Fact label="Ticket type" value={listing.ticket_type} />
            <Fact label="Quantity" value={`${listing.quantity} ticket${listing.quantity === 1 ? "" : "s"}`} />
            <Fact label="Platform" value={platform} />
            <Fact label="Delivery" value={`Official ${platform} transfer`} />
          </dl>

          {/* Seller */}
          <section aria-label="Seller" className="flex items-center gap-4 rounded-card border border-line bg-card p-5">
            <div
              aria-hidden="true"
              className="flex size-12 shrink-0 items-center justify-center rounded-full bg-field text-lg font-bold text-muted"
            >
              {(seller?.display_name ?? "S").slice(0, 1).toUpperCase()}
            </div>
            <div className="min-w-0 flex-1">
              <p className="truncate text-[15px] font-semibold text-ink">
                {seller?.display_name ?? "Snatch It seller"}
                {seller?.is_verified_seller ? (
                  <span className="ml-2 align-middle">
                    <Badge variant="buyNow">Verified</Badge>
                  </span>
                ) : null}
              </p>
              <p className="mt-0.5 text-[13px] text-muted">
                {seller?.created_at
                  ? `Member since ${new Date(seller.created_at).toLocaleDateString("en-US", { month: "long", year: "numeric" })}`
                  : "Marketplace seller"}
              </p>
            </div>
            <p className="hidden max-w-[200px] text-right text-[12px] leading-snug text-dim sm:block">
              Seller is paid only after you confirm the transfer arrived.
            </p>
          </section>

          {/* Buyer protection */}
          <section aria-label="Buyer protection" className="rounded-card border border-line bg-card p-6">
            <h2 className="text-base font-bold text-ink">Snatch It Buyer Protection</h2>
            <ul className="mt-4 space-y-3 text-sm text-muted">
              <li className="flex gap-2.5">
                <Dot /> Payment processed by Stripe — your card details never touch Snatch It.
              </li>
              <li className="flex gap-2.5">
                <Dot /> Your money is held by Snatch It until you confirm the ticket arrived.
              </li>
              <li className="flex gap-2.5">
                <Dot /> If the seller doesn&apos;t transfer within 24 hours, you&apos;re refunded in full —
                automatically.
              </li>
            </ul>
          </section>
        </div>

        {/* ── Purchase card (desktop sticky) ── */}
        <aside className="lg:sticky lg:top-24 lg:h-fit" aria-label="Purchase">
          <div className="rounded-card border border-line bg-card p-6">
            {isActive ? (
              <p className="flex items-center justify-between text-sm text-muted">
                <span>Auction ends in</span>
                <Countdown endsAt={listing.ends_at} />
              </p>
            ) : (
              <p className="text-sm font-semibold text-muted">This listing has ended.</p>
            )}

            <div className="mt-4 border-t border-line pt-4">
              {listing.buy_now_enabled && listing.buy_now_price ? (
                <>
                  <p className="text-[13px] font-medium text-muted">Buy Now price (all-in)</p>
                  <PriceDisplay baseDollars={listing.buy_now_price} size="lg" className="mt-1" />
                  <dl className="mt-4 space-y-1.5 text-[13px]">
                    <div className="flex justify-between">
                      <dt className="text-muted">Current bid</dt>
                      <dd className="text-ink">{allInFromDollars(listing.current_bid)} total</dd>
                    </div>
                    <div className="flex justify-between">
                      <dt className="text-muted">Starting bid</dt>
                      <dd className="text-ink">{allInFromDollars(listing.starting_bid)} total</dd>
                    </div>
                    <div className="flex justify-between">
                      <dt className="text-muted">Bids placed</dt>
                      <dd className="text-ink">{listing.bid_count}</dd>
                    </div>
                  </dl>
                </>
              ) : (
                <>
                  <p className="text-[13px] font-medium text-muted">Current bid (all-in)</p>
                  <PriceDisplay baseDollars={listing.current_bid} size="lg" className="mt-1" />
                  <p className="mt-2 text-[13px] text-muted">
                    {listing.bid_count} bid{listing.bid_count === 1 ? "" : "s"} · starting bid{" "}
                    {allInFromDollars(listing.starting_bid)}
                  </p>
                </>
              )}
            </div>

            <div className="mt-5 border-t border-line pt-5">
              <PriceBreakdown baseDollars={base} />
            </div>

            <div className="mt-6 space-y-2.5">
              <Button
                variant="secondary"
                className="w-full cursor-not-allowed opacity-60"
                disabled
                aria-disabled="true"
                title="Browser checkout is not available yet"
              >
                Web checkout — coming soon
              </Button>
              <LinkButton href="https://snatchitapp.com" size="lg" className="w-full">
                Get the iOS app to {listing.buy_now_enabled ? "buy" : "bid"}
              </LinkButton>
              <p className="pt-1 text-center text-[12px] leading-snug text-dim">
                Bidding and Buy Now are live today in the Snatch It app. Browser checkout is on
                the way.
              </p>
            </div>
          </div>
        </aside>
      </div>

      {/* ── Related ── */}
      {related.length > 0 ? (
        <section className="mt-16">
          <SectionHeader
            title="More nights like this"
            action={{ href: `/browse?category=${encodeURIComponent(listing.category)}`, label: "See all" }}
          />
          <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
            {related.map((l) => (
              <ListingCard key={l.id} listing={l} />
            ))}
          </div>
        </section>
      ) : null}

      {/* Mobile sticky CTA */}
      <div className="h-24 lg:hidden" aria-hidden="true" />
      <div className="fixed inset-x-0 bottom-0 z-40 border-t border-line bg-card/95 backdrop-blur-md lg:hidden">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-3 pb-[max(env(safe-area-inset-bottom),0.75rem)]">
          <div>
            <p className="text-[11px] font-medium uppercase tracking-wide text-muted">
              {listing.buy_now_enabled ? "Buy Now · all-in" : "Current bid · all-in"}
            </p>
            <PriceDisplay baseDollars={base} size="md" suffix={null} />
          </div>
          <LinkButton href="https://snatchitapp.com" className="shrink-0">
            Get the app
          </LinkButton>
        </div>
      </div>

      {isActive ? <JsonLd data={eventJsonLd} /> : null}
    </Container>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-[11px] font-semibold uppercase tracking-[0.1em] text-dim">{label}</dt>
      <dd className="mt-1 text-[15px] font-medium text-ink">{value}</dd>
    </div>
  );
}

function Dot() {
  return (
    <svg aria-hidden="true" viewBox="0 0 16 16" fill="none" className="mt-0.5 size-4 shrink-0 text-success">
      <path d="m3 8.5 3.2 3L13 4.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
