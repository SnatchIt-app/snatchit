import type { Metadata } from "next";
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
import { getReservationState, isUnpaidAuctionWinner } from "@/lib/checkout";
import { getAuthedUser } from "@/lib/auth/session";
import { SaveButton } from "@/components/SaveButton";
import { BuyNowButton } from "@/components/listing/BuyNowButton";
import { BidPanel } from "@/components/listing/BidPanel";
import {
  categoryLabel,
  fmtEventDate,
  listingCardStatus,
  neighborhoodLabel,
  platformLabel,
  deliveryLabel,
} from "@/lib/format";
import { eventWhen, proofWaiverNote, quantityLine, sellerVerifiedLabel } from "@/lib/listing-display";
import { SITE_URL } from "@/lib/env";
import { Container } from "@/components/ui/Container";
import { Badge, LiveDot } from "@/components/ui/Badge";
import { ArrowLink, Button, ButtonLabel, LinkButton } from "@/components/ui/Button";
import { Icon } from "@/components/ui/Icon";
import { BackLink } from "@/components/ui/BackLink";
import { PriceBreakdown, PriceDisplay } from "@/components/ui/PriceDisplay";
import { SectionHeader } from "@/components/ui/SectionHeader";
import { ListingCard } from "@/components/ListingCard";
import { Countdown } from "@/components/listing/Countdown";
import { Poster } from "@/components/listing/Poster";
import { JsonLd } from "@/components/site/JsonLd";
import { PAYOUT_SHORT, REFUND_SHORT, REPORT_FREEZES_PAYOUT } from "@/lib/policy-wording";

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
  const proofNote = proofWaiverNote(listing);
  const sellerBadge = sellerVerifiedLabel(seller?.is_verified_seller, proofNote !== null);

  const status = listingCardStatus(listing);
  const isActive = status === "LIVE" || status === "ENDING SOON";
  const base = effectiveBase(listing);
  const platform = platformLabel(listing.ticket_platform);
  const delivery = deliveryLabel(listing.ticket_platform);
  const isHybrid = listing.buy_now_enabled && !!listing.buy_now_price;
  const pureAuctionActive = isActive && !isHybrid;
  const iWon = isUnpaidAuctionWinner(listing, currentUser?.id);
  // The winner owes their winning bid — never the Buy Now price a hybrid
  // listing still carries, which effectiveBase would otherwise surface.
  const priceBase = iWon ? (listing.winning_bid_amount ?? listing.current_bid) : base;
  const isOwner = currentUser?.id === listing.seller_id;

  // A reserved listing is on hold during someone's Buy Now checkout, not over.
  // Only the holder can tell it is theirs (checkout reads the same row).
  const onHold = status === "RESERVED";
  const heldByMe =
    onHold && currentUser ? (await getReservationState(listing.id).catch(() => null))?.reservedBy === currentUser.id : false;

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
      availability: isActive ? "https://schema.org/InStock" : "https://schema.org/SoldOut",
      url: `${SITE_URL}/listing/${listing.id}`,
      ...(seller?.display_name ? { offeredBy: { "@type": "Person", name: seller.display_name } } : {}),
    },
  };

  const headline = iWon
    ? { label: "Your winning bid", dollars: priceBase }
    : isHybrid && isActive
      ? { label: "Buy Now", dollars: listing.buy_now_price! }
      : { label: listing.bid_count > 0 ? (isActive ? "Current bid" : "Final bid") : "Starting bid", dollars: listing.current_bid };

  return (
    <div className="pb-6 lg:pb-10">
      <Container className="flex items-center justify-between gap-3 py-3 lg:py-5">
        <div className="flex min-w-0 items-center gap-3">
          <BackLink href="/browse" label="Back to listings" />
          <nav aria-label="Breadcrumb" className="min-w-0 max-sm:hidden">
            <ol className="flex items-center gap-2 text-[14px] text-muted">
              <li>
                <Link href="/browse" className="hover:text-ink hover:underline underline-offset-4">
                  Browse
                </Link>
              </li>
              <li aria-hidden="true">/</li>
              <li>
                <Link
                  href={`/browse?category=${encodeURIComponent(listing.category)}`}
                  className="hover:text-ink hover:underline underline-offset-4"
                >
                  {categoryLabel(listing.category)}
                </Link>
              </li>
              <li aria-hidden="true">/</li>
              <li aria-current="page" className="truncate text-ink-2">
                {listing.event_name}
              </li>
            </ol>
          </nav>
        </div>
        <SaveButton listingId={listing.id} initialSaved={saved} variant="labeled" />
      </Container>

      <Container>
        <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_420px] lg:gap-x-14 lg:gap-y-10">
          <div className="lg:col-start-1 lg:row-start-1">
            <Poster
              path={listing.cover_image_path}
              alt={`${listing.event_name} at ${listing.venue}`}
              sizes="(min-width: 1280px) 600px, (min-width: 1024px) 55vw, 100vw"
              priority
              rounded="rounded-none sm:rounded-card"
              className="-mx-5 w-[calc(100%+40px)] sm:mx-0 sm:w-full lg:max-w-[600px]"
            />
          </div>

          {/* Identity + purchase: under the poster on phones (native order), the right column on desktop. */}
          <aside className="min-w-0 lg:col-start-2 lg:row-span-2 lg:row-start-1" aria-label="Purchase">
            <div className="flex flex-wrap items-center gap-2">
              <Badge>From a fan</Badge>
              {status === "LIVE" ? (
                <Badge tone="brand">
                  <LiveDot /> Live auction
                </Badge>
              ) : status === "ENDING SOON" ? (
                <Badge tone="warning">Ending soon</Badge>
              ) : status === "SOLD" ? (
                <Badge>Sold</Badge>
              ) : status === "RESERVED" ? (
                <Badge tone="warning">On hold</Badge>
              ) : (
                <Badge>Ended</Badge>
              )}
              {listing.buy_now_enabled && isActive ? <Badge tone="brand">Buy now</Badge> : null}
            </div>
            <p className="t-body mt-3 text-muted">
              {eventWhen(listing)} · {listing.venue}
            </p>
            <h1 className="t-name-detail mt-1.5 text-balance text-ink">{listing.event_name}</h1>

            <div className="mt-6 rounded-card bg-surface p-5 sm:p-6">
              <div className="flex flex-wrap items-start justify-between gap-x-4 gap-y-3">
                <div className="min-w-0">
                  <p className="t-label text-muted">{headline.label}</p>
                  <PriceDisplay baseDollars={headline.dollars} size="lg" suffix={null} className="mt-1" />
                  <p className="t-body-sm mt-1 text-muted">
                    all-in · {listing.bid_count} bid{listing.bid_count === 1 ? "" : "s"}
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-[17px] font-semibold text-ink">{quantityLine(listing)}</p>
                  {listing.quantity > 1 ? <p className="t-body-sm text-muted">sold together</p> : null}
                </div>
              </div>

              <div className="mt-4 flex items-center justify-between gap-3 border-t border-line pt-4">
                {isActive ? (
                  <>
                    <span className="inline-flex items-center gap-2 text-[14px] font-semibold text-ink-2">
                      <Icon name="clock" size={18} /> Ends in
                    </span>
                    <Countdown endsAt={listing.ends_at} />
                  </>
                ) : onHold ? (
                  <span className="text-[14px] font-semibold text-warning">
                    {heldByMe ? "Held for you" : "Held for another buyer"}
                  </span>
                ) : (
                  <span className="text-[14px] font-semibold text-muted">This listing has ended</span>
                )}
              </div>

              {isHybrid && isActive ? (
                <dl className="mt-3 text-[14px]">
                  <div className="flex flex-wrap justify-between gap-x-4 py-1.5">
                    <dt className="text-muted">Current bid</dt>
                    <dd className="t-price text-ink">{allInFromDollars(listing.current_bid)} total</dd>
                  </div>
                  <div className="flex flex-wrap justify-between gap-x-4 py-1.5">
                    <dt className="text-muted">Starting bid</dt>
                    <dd className="t-price text-ink">{allInFromDollars(listing.starting_bid)} total</dd>
                  </div>
                </dl>
              ) : null}

              {!pureAuctionActive && !onHold ? (
                <div className="mt-4">
                  <p className="t-micro text-muted">{iWon ? "What you pay" : isHybrid && isActive ? "If you buy now" : "Price breakdown"}</p>
                  <div className="mt-1">
                    <PriceBreakdown baseDollars={priceBase} />
                  </div>
                </div>
              ) : null}

              {isActive ? (
                /* scroll-mt clears the sticky header when the phone bar's #buy anchor jumps here. */
                <div id="buy" className="mt-5 scroll-mt-24 space-y-4">
                  {isHybrid && !isOwner ? <BuyNowButton listingId={listing.id} /> : null}
                  <BidPanel
                    listingId={listing.id}
                    sellerId={listing.seller_id}
                    currentUserId={currentUser?.id ?? null}
                    initialCurrentBid={listing.current_bid}
                    initialBidCount={listing.bid_count}
                    initialAuctionStatus={listing.auction_status}
                    initialEndsAt={listing.ends_at}
                    buyNowPrice={listing.buy_now_enabled ? listing.buy_now_price : null}
                    compact={isHybrid}
                  />
                </div>
              ) : iWon ? (
                /* The auction is over but this buyer still owes money — the one
                   case where an ended listing is actionable. */
                <div id="buy" className="mt-5 scroll-mt-24 space-y-2.5">
                  <LinkButton href={`/checkout/${listing.id}`} size="lg" className="w-full">
                    You won — complete payment
                  </LinkButton>
                  <p className="t-body-sm text-center text-muted">Pay {allInFromDollars(priceBase)} to claim your ticket.</p>
                </div>
              ) : onHold && heldByMe ? (
                <div id="buy" className="mt-5 scroll-mt-24">
                  <LinkButton href={`/checkout/${listing.id}`} size="lg" className="w-full">
                    Finish checkout
                  </LinkButton>
                </div>
              ) : onHold ? (
                <div className="mt-5">
                  <Button size="lg" variant="secondary" className="w-full" disabled>
                    <ButtonLabel label="On hold" sub="Another buyer is in checkout." />
                  </Button>
                </div>
              ) : (
                <div className="mt-5">
                  <Button variant="secondary" size="lg" className="w-full" disabled>
                    This listing has ended
                  </Button>
                </div>
              )}
            </div>
          </aside>

          <div className="min-w-0 lg:col-start-1 lg:row-start-2">
            <dl className="border-t border-line">
              <Fact label="Ticket type" value={listing.ticket_type} />
              <Fact label="Quantity" value={`${listing.quantity} ticket${listing.quantity === 1 ? "" : "s"}`} />
              <Fact label="Platform" value={platform} />
              <Fact label="Delivery" value={delivery} />
              <Fact label="Neighborhood" value={neighborhoodLabel(listing.neighborhood)} />
              <Fact label="Category" value={categoryLabel(listing.category)} />
            </dl>

            {/* Seller */}
            <section aria-label="Seller" className="mt-8 flex items-center gap-4 rounded-panel bg-surface p-4 sm:p-5">
              <div
                aria-hidden="true"
                className="flex size-12 shrink-0 items-center justify-center rounded-full bg-brand-soft font-display text-[20px] font-bold text-brand-text"
              >
                {(seller?.display_name ?? "S").slice(0, 1).toUpperCase()}
              </div>
              <div className="min-w-0 flex-1">
                <p className="flex flex-wrap items-center gap-x-2.5 gap-y-1 text-[16px] font-semibold text-ink">
                  <span className="truncate">{seller?.display_name ?? "Snatch It seller"}</span>
                  {sellerBadge ? <Badge tone="success">{sellerBadge}</Badge> : null}
                </p>
                <p className="t-body-sm mt-0.5 text-muted">
                  {seller?.created_at
                    ? `Member since ${new Date(seller.created_at).toLocaleDateString("en-US", { month: "long", year: "numeric" })}`
                    : "Marketplace seller"}
                </p>
                {proofNote ? (
                  <p className="t-body-sm mt-1.5 flex items-center gap-1.5 text-ink-2">
                    <Icon name="info" size={15} className="shrink-0 text-muted" />
                    {proofNote}
                  </p>
                ) : null}
              </div>
            </section>

            {/* Buyer protection */}
            <section aria-label="Buyer protection" className="mt-8">
              <div className="flex items-center gap-2.5">
                <Icon name="shield" size={22} className="text-success" />
                <p className="t-micro text-muted">Buyer Guarantee</p>
              </div>
              <h2 className="t-name-state mt-2 text-ink">You&apos;re covered.</h2>
              <ul className="mt-4 border-t border-line">
                {[
                  "Payment is processed by Stripe. Your card details never touch Snatch It.",
                  PAYOUT_SHORT,
                  REFUND_SHORT,
                  REPORT_FREEZES_PAYOUT,
                ].map((line) => (
                  <li key={line} className="t-body flex gap-3 border-b border-line py-3 text-ink-2">
                    <Icon name="check" size={18} strokeWidth={2.2} className="mt-0.5 text-ink" />
                    {line}
                  </li>
                ))}
              </ul>
              <div className="mt-2 flex flex-wrap gap-x-6">
                <ArrowLink href="https://snatchitapp.com/buyer-guarantee">Read the full guarantee</ArrowLink>
                <ArrowLink href="https://snatchitapp.com/terms">Fees, payouts and refunds</ArrowLink>
              </div>
            </section>
          </div>
        </div>

        {/* ── Related ── */}
        {related.length > 0 ? (
          <section className="mt-16 lg:mt-20">
            <SectionHeader
              title="More nights like this"
              action={{ href: `/browse?category=${encodeURIComponent(listing.category)}`, label: "See all" }}
              className="mb-5"
            />
            <div className="grid grid-cols-2 gap-x-4 gap-y-8 sm:gap-x-6 lg:grid-cols-4">
              {related.map((l) => (
                <ListingCard key={l.id} listing={l} isSaved={relatedSavedIds.has(l.id)} />
              ))}
            </div>
          </section>
        ) : null}
      </Container>

      {/* Phone action bar (native stacked footer): the purchase controls live in the
          panel above; these jump to them, or go onward when there is nothing to do. */}
      <div className="h-28 lg:hidden" aria-hidden="true" />
      <div className="fixed inset-x-0 bottom-0 z-40 border-t border-line-strong bg-elevated lg:hidden">
        <div className="mx-auto flex max-w-[1200px] items-center gap-4 px-5 pb-[max(env(safe-area-inset-bottom),12px)] pt-3">
          <div className="min-w-0 flex-1">
            <p className="t-body-sm text-muted">
              {iWon ? "You pay" : headline.label}, all-in
            </p>
            <PriceDisplay baseDollars={iWon ? priceBase : headline.dollars} size="md" suffix={null} />
          </div>
          {isActive ? (
            <LinkButton href="#buy" size="lg" className="shrink-0">
              {isOwner ? "Your listing" : isHybrid ? "Buy now" : "Place bid"}
            </LinkButton>
          ) : iWon ? (
            <LinkButton href={`/checkout/${listing.id}`} size="lg" className="shrink-0">
              Complete payment
            </LinkButton>
          ) : onHold && heldByMe ? (
            <LinkButton href={`/checkout/${listing.id}`} size="lg" className="shrink-0">
              Finish checkout
            </LinkButton>
          ) : (
            <LinkButton href="/browse" variant="secondary" size="lg" className="shrink-0">
              Browse tickets
            </LinkButton>
          )}
        </div>
      </div>

      {isActive ? <JsonLd data={eventJsonLd} /> : null}
    </div>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-0.5 border-b border-line py-3">
      <dt className="t-body text-ink-2">{label}</dt>
      <dd className="t-body text-right font-medium text-ink">{value}</dd>
    </div>
  );
}
