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
    <Container className="py-8 lg:py-12">
      {/* Breadcrumb */}
      <nav aria-label="Breadcrumb" className="mb-8">
        <ol className="flex flex-wrap items-center gap-2.5 text-[10.5px] font-semibold uppercase tracking-[0.14em] text-dim">
          <li>
            <Link
              href="/browse"
              className="inline-flex min-h-9 items-center transition-colors duration-150 hover:text-ink motion-reduce:transition-none"
            >
              Browse
            </Link>
          </li>
          <li aria-hidden="true" className="text-dim/50">/</li>
          <li>
            <Link
              href={`/browse?category=${encodeURIComponent(listing.category)}`}
              className="inline-flex min-h-9 items-center transition-colors duration-150 hover:text-ink motion-reduce:transition-none"
            >
              {categoryLabel(listing.category)}
            </Link>
          </li>
          <li aria-hidden="true" className="text-dim/50">/</li>
          <li aria-current="page" className="truncate text-muted">
            {listing.event_name}
          </li>
        </ol>
      </nav>

      <div className="grid gap-12 lg:grid-cols-[minmax(0,1.2fr)_400px] lg:gap-16">
        {/* ── Left column ── */}
        <div>
          <figure className="relative aspect-[4/3] overflow-hidden rounded-[8px] bg-white/[0.03]">
            <Image
              src={coverImageUrl(listing.cover_image_path)}
              alt={`${listing.event_name} at ${listing.venue}`}
              fill
              priority
              sizes="(min-width: 1024px) 58vw, 100vw"
              className="object-cover"
            />
            <div className="absolute left-3 top-3 flex gap-1.5">
              {status === "LIVE" ? (
                <Badge variant="live">
                  <LiveDot /> Live auction
                </Badge>
              ) : status === "ENDING SOON" ? (
                <Badge variant="soon">Ending soon</Badge>
              ) : (
                <Badge variant="sold">
                  {status === "SOLD" ? "Sold" : status === "RESERVED" ? "Reserved" : "Ended"}
                </Badge>
              )}
              {listing.buy_now_enabled ? <Badge variant="buyNow">Buy now</Badge> : null}
            </div>
          </figure>

          {/* Poster title block */}
          <div className="mt-9">
            <p className="u-label text-muted">
              <span className="text-primary">{categoryLabel(listing.category)}</span>
              {"  ·  "}
              {listing.venue}
              {"  ·  "}
              {neighborhoodLabel(listing.neighborhood)}
            </p>
            <h1 className="mt-4 max-w-[16ch] text-balance text-[clamp(2.1rem,5vw,3.4rem)] font-extrabold uppercase leading-[0.96] tracking-[-0.015em] text-ink">
              {listing.event_name}
            </h1>
            <p className="u-label mt-5 text-dim">
              {fmtEventDate(listing.event_date)} · {fmtEventTime(listing.event_time)}
            </p>
          </div>

          {/* Event facts — editorial spec table */}
          <dl className="mt-12 grid grid-cols-2 gap-x-8 gap-y-7 sm:grid-cols-4">
            <Fact label="Ticket type" value={listing.ticket_type} />
            <Fact label="Quantity" value={`${listing.quantity} ticket${listing.quantity === 1 ? "" : "s"}`} />
            <Fact label="Platform" value={platform} />
            <Fact label="Delivery" value={`Official ${platform} transfer`} />
          </dl>

          {/* Seller */}
          <section aria-label="Seller" className="rule-t mt-12 flex items-center gap-4 pt-7">
            <div
              aria-hidden="true"
              className="flex size-11 shrink-0 items-center justify-center rounded-full border border-white/12 bg-white/[0.04] text-[15px] font-bold text-muted"
            >
              {(seller?.display_name ?? "S").slice(0, 1).toUpperCase()}
            </div>
            <div className="min-w-0 flex-1">
              <p className="flex items-center gap-2.5 truncate text-[15px] font-bold tracking-[-0.01em] text-ink">
                {seller?.display_name ?? "Snatch It seller"}
                {seller?.is_verified_seller ? <Badge variant="buyNow">Verified</Badge> : null}
              </p>
              <p className="u-label mt-1.5 text-dim">
                {seller?.created_at
                  ? `Member since ${new Date(seller.created_at).toLocaleDateString("en-US", { month: "long", year: "numeric" })}`
                  : "Marketplace seller"}
              </p>
            </div>
            <p className="hidden max-w-[190px] text-right text-[11.5px] leading-relaxed text-dim sm:block">
              Seller is paid only after you confirm the transfer arrived.
            </p>
          </section>

          {/* Buyer protection */}
          <section
            aria-label="Buyer protection"
            className="mt-12 rounded-[8px] border border-white/10 p-7"
          >
            <h2 className="u-label flex items-center gap-2.5 text-ink">
              <ShieldMark />
              Snatch It Buyer Protection
            </h2>
            <ul className="mt-5 text-[13.5px] leading-relaxed text-muted">
              <li className="py-2.5">
                Payment processed by Stripe — your card details never touch Snatch It.
              </li>
              <li className="rule-t py-2.5">
                Your money is held by Snatch It until you confirm the ticket arrived.
              </li>
              <li className="rule-t pt-2.5">
                If the seller doesn&apos;t transfer within 24 hours, you&apos;re refunded in full —
                automatically.
              </li>
            </ul>
          </section>
        </div>

        {/* ── Purchase card (desktop sticky) ── */}
        <aside className="lg:sticky lg:top-28 lg:h-fit" aria-label="Purchase">
          <div className="rounded-[8px] border border-white/[0.08] border-t-2 border-t-primary bg-card">
            <div className="px-7 pb-7 pt-6">
              {isActive ? (
                <p className="flex items-baseline justify-between">
                  <span className="u-label text-dim">Auction ends in</span>
                  <Countdown endsAt={listing.ends_at} />
                </p>
              ) : (
                <p className="u-label text-muted">This listing has ended</p>
              )}

              <div className="rule-t mt-5 pt-6">
                {listing.buy_now_enabled && listing.buy_now_price ? (
                  <>
                    <p className="u-label text-dim">Buy Now · all-in</p>
                    <PriceDisplay
                      baseDollars={listing.buy_now_price}
                      size="lg"
                      suffix={null}
                      className="mt-3"
                    />
                    <dl className="mt-6 space-y-2 text-[12.5px]">
                      <div className="flex justify-between">
                        <dt className="text-muted">Current bid</dt>
                        <dd className="tabular-nums text-ink">
                          {allInFromDollars(listing.current_bid)} total
                        </dd>
                      </div>
                      <div className="flex justify-between">
                        <dt className="text-muted">Starting bid</dt>
                        <dd className="tabular-nums text-ink">
                          {allInFromDollars(listing.starting_bid)} total
                        </dd>
                      </div>
                      <div className="flex justify-between">
                        <dt className="text-muted">Bids placed</dt>
                        <dd className="tabular-nums text-ink">{listing.bid_count}</dd>
                      </div>
                    </dl>
                  </>
                ) : (
                  <>
                    <p className="u-label text-dim">Current bid · all-in</p>
                    <PriceDisplay
                      baseDollars={listing.current_bid}
                      size="lg"
                      suffix={null}
                      className="mt-3"
                    />
                    <p className="mt-4 text-[12.5px] text-muted">
                      {listing.bid_count} bid{listing.bid_count === 1 ? "" : "s"} · starting bid{" "}
                      {allInFromDollars(listing.starting_bid)}
                    </p>
                  </>
                )}
              </div>

              <div className="rule-t mt-6 pt-4">
                <PriceBreakdown baseDollars={base} />
              </div>

              <div className="mt-7 space-y-2.5">
                <Button
                  variant="secondary"
                  className="w-full cursor-not-allowed opacity-50"
                  disabled
                  aria-disabled="true"
                  title="Browser checkout is not available yet"
                >
                  Web checkout — coming soon
                </Button>
                <LinkButton href="https://snatchitapp.com" size="lg" className="w-full">
                  Get the iOS app to {listing.buy_now_enabled ? "buy" : "bid"}
                </LinkButton>
              </div>
            </div>

            <p className="rule-t px-7 py-4 text-center text-[11px] leading-relaxed text-dim">
              Bidding and Buy Now are live today in the Snatch It app. Browser checkout is on
              the way.
            </p>
          </div>
        </aside>
      </div>

      {/* ── Related ── */}
      {related.length > 0 ? (
        <section className="mt-24">
          <SectionHeader
            title="More nights like this"
            action={{ href: `/browse?category=${encodeURIComponent(listing.category)}`, label: "See all" }}
          />
          <div className="grid grid-cols-1 gap-x-5 gap-y-12 sm:grid-cols-2 lg:grid-cols-4">
            {related.map((l) => (
              <ListingCard key={l.id} listing={l} />
            ))}
          </div>
        </section>
      ) : null}

      {/* Mobile sticky CTA */}
      <div className="h-24 lg:hidden" aria-hidden="true" />
      <div className="fixed inset-x-0 bottom-0 z-40 border-t border-white/10 bg-card/95 backdrop-blur-md lg:hidden">
        <div className="mx-auto flex max-w-[1200px] items-center justify-between gap-4 px-5 py-3 pb-[max(env(safe-area-inset-bottom),0.75rem)]">
          <div>
            <p className="u-label text-dim">
              {listing.buy_now_enabled ? "Buy now · all-in" : "Current bid · all-in"}
            </p>
            <PriceDisplay baseDollars={base} size="md" suffix={null} className="mt-1" />
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
    <div className="rule-t pt-4">
      <dt className="u-label text-dim">{label}</dt>
      <dd className="mt-2 text-[14.5px] font-medium text-ink">{value}</dd>
    </div>
  );
}

function ShieldMark() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" fill="none" className="size-4 shrink-0 text-primary">
      <path
        d="M10 1.8 3.2 4.4v4.4c0 4.4 2.9 7.6 6.8 9.4 3.9-1.8 6.8-5 6.8-9.4V4.4L10 1.8Z"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
      <path
        d="m7 9.8 2.2 2.2L13.4 7.6"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
