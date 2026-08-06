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
import { getSavedListingIdSet, isListingSaved } from "@/lib/favorites";
import { getAuthedUser } from "@/lib/auth/session";
import { SaveButton } from "@/components/SaveButton";
import { BuyNowButton } from "@/components/listing/BuyNowButton";
import { BidPanel } from "@/components/listing/BidPanel";
import {
  categoryLabel,
  fmtEventDate,
  fmtEventTime,
  listingCardStatus,
  neighborhoodLabel,
  platformLabel,
  deliveryLabel,
} from "@/lib/format";
import { SITE_URL } from "@/lib/env";
import { Container } from "@/components/ui/Container";
import { Badge, Chip, LiveDot } from "@/components/ui/Badge";
import { ArrowLink, Button, LinkButton } from "@/components/ui/Button";
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

  const [seller, related, saved, currentUser] = await Promise.all([
    getSellerSummary(listing.seller_id).catch(() => null),
    getRelatedListings(listing).catch(() => [] as WebListing[]),
    isListingSaved(listing.id),
    getAuthedUser(),
  ]);
  const relatedSavedIds = await getSavedListingIdSet(related.map((l) => l.id));

  const status = listingCardStatus(listing);
  const isActive = status === "LIVE" || status === "ENDING SOON";
  const base = effectiveBase(listing);
  const platform = platformLabel(listing.ticket_platform);
  const delivery = deliveryLabel(listing.ticket_platform);
  const isHybrid = listing.buy_now_enabled && !!listing.buy_now_price;
  const pureAuctionActive = isActive && !isHybrid;

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
    description: `Peer-to-peer resale listing on Snatch It. ${listing.ticket_type} ticket delivered by ${delivery.toLowerCase()} after purchase. Price includes all fees.`,
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
    <Container className="py-7 lg:py-10">
      {/* Breadcrumb — tracked uppercase micro with the site's slash motif */}
      <nav aria-label="Breadcrumb" className="mb-7">
        <ol className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[10.5px] font-medium uppercase tracking-[0.3em] text-white/60">
          <li>
            <Link
              href="/browse"
              className="inline-flex min-h-9 items-center transition-colors duration-200 hover:text-primary motion-reduce:transition-none"
            >
              ← Browse
            </Link>
          </li>
          <li aria-hidden="true" className="text-white/20">/</li>
          <li>
            <Link
              href={`/browse?category=${encodeURIComponent(listing.category)}`}
              className="inline-flex min-h-9 items-center transition-colors duration-200 hover:text-primary motion-reduce:transition-none"
            >
              {categoryLabel(listing.category)}
            </Link>
          </li>
          <li aria-hidden="true" className="text-white/20">/</li>
          <li aria-current="page" className="truncate text-white/40">
            {listing.event_name}
          </li>
        </ol>
      </nav>

      <div className="grid gap-10 lg:grid-cols-[minmax(0,1.18fr)_400px] lg:gap-12">
        {/* ── Left column ── */}
        <div>
          <figure className="relative aspect-[4/3] overflow-hidden border border-white/10 bg-white/[0.03]">
            <Image
              src={coverImageUrl(listing.cover_image_path)}
              alt={`${listing.event_name} at ${listing.venue}`}
              fill
              priority
              sizes="(min-width: 1024px) 58vw, 100vw"
              className="object-cover"
            />
            <div className="absolute left-3.5 top-3.5 flex gap-1.5">
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

          {/* Title block — meta eyebrow, Oswald statement, date line */}
          <div className="mt-9">
            <p className="flex flex-wrap items-center gap-x-3 gap-y-1.5 text-[11px] font-medium uppercase leading-none tracking-[0.3em]">
              <span className="text-primary/80">{categoryLabel(listing.category)}</span>
              <span aria-hidden="true" className="text-white/20">/</span>
              <span className="text-white/45">
                {listing.venue} · {neighborhoodLabel(listing.neighborhood)}
              </span>
            </p>
            <h1 className="mt-4 max-w-[24ch] text-balance font-display text-[clamp(2.3rem,5vw,3.6rem)] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
              {listing.event_name}
            </h1>
            <div className="mt-4 flex flex-wrap items-center justify-between gap-4">
              <p className="text-[15px] font-semibold text-white/85">
                {fmtEventDate(listing.event_date)} · {fmtEventTime(listing.event_time)}
              </p>
              <SaveButton listingId={listing.id} initialSaved={saved} variant="labeled" />
            </div>
          </div>

          {/* Event facts — hairline definition rows, no box */}
          <dl className="mt-9 grid grid-cols-2 gap-x-6 gap-y-6 border-y border-primary/15 py-6 sm:grid-cols-4">
            <Fact label="Ticket type" value={listing.ticket_type} />
            <Fact label="Quantity" value={`${listing.quantity} ticket${listing.quantity === 1 ? "" : "s"}`} />
            <Fact label="Platform" value={platform} />
            <Fact label="Delivery" value={delivery} />
          </dl>

          {/* Seller */}
          <section
            aria-label="Seller"
            className="flex items-center gap-4 border-b border-primary/15 py-6"
          >
            <div
              aria-hidden="true"
              className="flex size-11 shrink-0 items-center justify-center bg-white/[0.07] font-display text-[17px] font-bold text-white/70"
            >
              {(seller?.display_name ?? "S").slice(0, 1).toUpperCase()}
            </div>
            <div className="min-w-0 flex-1">
              <p className="flex items-center gap-3 truncate text-[15px] font-bold text-ink">
                {seller?.display_name ?? "Snatch It seller"}
                {seller?.is_verified_seller ? <Chip tone="red">Verified</Chip> : null}
              </p>
              <p className="mt-1 text-[13px] text-muted">
                {seller?.created_at
                  ? `Member since ${new Date(seller.created_at).toLocaleDateString("en-US", { month: "long", year: "numeric" })}`
                  : "Marketplace seller"}
              </p>
            </div>
            <p className="hidden max-w-[200px] text-right text-[12px] leading-relaxed text-dim sm:block">
              Seller is paid only after you confirm the transfer arrived.
            </p>
          </section>

          {/* Buyer protection — the marketing site's guarantee grammar */}
          <section aria-label="Buyer protection" className="border-b border-primary/15 py-8">
            <p className="eyebrow text-primary/80">Buyer Guarantee</p>
            <h2 className="mt-4 font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink sm:text-[28px]">
              You&apos;re covered.
            </h2>
            <ul className="mt-5 space-y-3 text-[14px] leading-relaxed text-white/70">
              <li className="flex gap-3">
                <span aria-hidden="true" className="font-bold text-primary">·</span>
                Payment is processed by Stripe. Your card details never touch Snatch It.
              </li>
              <li className="flex gap-3">
                <span aria-hidden="true" className="font-bold text-primary">·</span>
                Your money is held by Snatch It until you confirm the ticket arrived.
              </li>
              <li className="flex gap-3">
                <span aria-hidden="true" className="font-bold text-primary">·</span>
                If the seller doesn&apos;t transfer within 24 hours, you&apos;re refunded in
                full, automatically.
              </li>
              <li className="flex gap-3">
                <span aria-hidden="true" className="font-bold text-primary">·</span>
                Report a problem before confirming and the seller&apos;s payout freezes while
                we review.
              </li>
            </ul>
            <ArrowLink href="https://snatchitapp.com/buyer-guarantee" className="mt-4">
              Read the full guarantee →
            </ArrowLink>
          </section>
        </div>

        {/* ── Purchase panel (desktop sticky) ── */}
        <aside className="lg:sticky lg:top-28 lg:h-fit" aria-label="Purchase">
          <div className="border border-primary/20 bg-card p-6">
            {isActive ? (
              <p className="flex items-center justify-between border-b border-primary/15 pb-4">
                <span className="inline-flex items-center gap-2.5 text-[10.5px] font-bold uppercase tracking-[0.25em] text-primary">
                  <LiveDot /> Ends in
                </span>
                <Countdown endsAt={listing.ends_at} />
              </p>
            ) : (
              <p className="border-b border-primary/15 pb-4 text-[10.5px] font-bold uppercase tracking-[0.25em] text-white/50">
                This listing has ended
              </p>
            )}

            <div className="mt-5">
              {listing.buy_now_enabled && listing.buy_now_price ? (
                <>
                  <p className="text-[10.5px] font-medium uppercase tracking-[0.25em] text-white/45">
                    Buy Now · all-in
                  </p>
                  <PriceDisplay
                    baseDollars={listing.buy_now_price}
                    size="lg"
                    suffix={null}
                    className="mt-2.5"
                  />
                  <dl className="mt-5 space-y-2 text-[13.5px]">
                    <div className="flex justify-between">
                      <dt className="text-muted">Current bid</dt>
                      <dd className="tabular-nums font-semibold text-white/85">
                        {allInFromDollars(listing.current_bid)} total
                      </dd>
                    </div>
                    <div className="flex justify-between">
                      <dt className="text-muted">Starting bid</dt>
                      <dd className="tabular-nums font-semibold text-white/85">
                        {allInFromDollars(listing.starting_bid)} total
                      </dd>
                    </div>
                    <div className="flex justify-between">
                      <dt className="text-muted">Bids placed</dt>
                      <dd className="tabular-nums font-semibold text-white/85">{listing.bid_count}</dd>
                    </div>
                  </dl>
                </>
              ) : !isActive ? (
                <>
                  <p className="text-[10.5px] font-medium uppercase tracking-[0.25em] text-white/45">
                    Current bid · all-in
                  </p>
                  <PriceDisplay
                    baseDollars={listing.current_bid}
                    size="lg"
                    suffix={null}
                    className="mt-2.5"
                  />
                  <p className="mt-3 text-[13.5px] text-muted">
                    {listing.bid_count} bid{listing.bid_count === 1 ? "" : "s"} · starting bid{" "}
                    {allInFromDollars(listing.starting_bid)}
                  </p>
                </>
              ) : null}
            </div>

            {!pureAuctionActive ? (
              <div className="mt-5 border-t border-primary/15 pt-4">
                <PriceBreakdown baseDollars={base} />
              </div>
            ) : null}

            {isActive ? (
              /* scroll-mt clears the sticky header when the mobile bar's
                 #buy anchor jumps here. */
              <div id="buy" className="mt-6 space-y-4 scroll-mt-24">
                {isHybrid ? <BuyNowButton listingId={listing.id} /> : null}
                <BidPanel
                  listingId={listing.id}
                  sellerId={listing.seller_id}
                  currentUserId={currentUser?.id ?? null}
                  initialCurrentBid={listing.current_bid}
                  initialBidCount={listing.bid_count}
                  initialAuctionStatus={listing.auction_status}
                  initialEndsAt={listing.ends_at}
                  compact={isHybrid}
                />
              </div>
            ) : (
              <div className="mt-6 space-y-2.5">
                <Button variant="secondary" className="w-full" disabled>
                  This listing has ended
                </Button>
              </div>
            )}
          </div>
        </aside>
      </div>

      {/* ── Related ── */}
      {related.length > 0 ? (
        <section className="mt-20">
          <SectionHeader
            title="More nights like this"
            action={{ href: `/browse?category=${encodeURIComponent(listing.category)}`, label: "See all" }}
          />
          <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
            {related.map((l) => (
              <ListingCard key={l.id} listing={l} isSaved={relatedSavedIds.has(l.id)} />
            ))}
          </div>
        </section>
      ) : null}

      {/* Mobile sticky CTA — solid black bar with red hairline, per the site */}
      <div className="h-24 lg:hidden" aria-hidden="true" />
      <div className="fixed inset-x-0 bottom-0 z-40 border-t border-primary/30 bg-black lg:hidden">
        <div className="mx-auto flex max-w-[1200px] items-center justify-between gap-4 px-5 py-3 pb-[max(env(safe-area-inset-bottom),0.75rem)]">
          <div>
            <p className="text-[9.5px] font-medium uppercase tracking-[0.25em] text-white/45">
              {listing.buy_now_enabled ? "Buy Now · all-in" : "Current bid · all-in"}
            </p>
            <PriceDisplay baseDollars={base} size="md" suffix={null} className="mt-1" />
          </div>
          {/* This used to be "Get the app" -> snatchitapp.com. On phones it is
              the most prominent control on the page, at the exact purchase
              moment, and it sent the buyer OFF-SITE while the real Buy Now /
              bid controls sat further down. Now it jumps to them. When the
              listing is over there is nothing to jump to, so it links onward
              to browse instead of dead-ending. */}
          {isActive ? (
            <LinkButton href="#buy" className="shrink-0">
              {listing.buy_now_enabled ? "Buy now" : "Place bid"}
            </LinkButton>
          ) : (
            <LinkButton href="/browse" variant="secondary" className="shrink-0">
              Browse tickets
            </LinkButton>
          )}
        </div>
      </div>

      {isActive ? <JsonLd data={eventJsonLd} /> : null}
    </Container>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-[10px] font-medium uppercase tracking-[0.25em] text-white/40">{label}</dt>
      <dd className="mt-2 text-[14.5px] font-bold text-ink">{value}</dd>
    </div>
  );
}
