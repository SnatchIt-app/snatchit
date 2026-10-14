import type { Metadata } from "next";
import { redirect, notFound } from "next/navigation";
import { getListing } from "@/lib/listings";
import { getReservationState, isUnpaidAuctionWinner, type ReservationState } from "@/lib/checkout";
import { getAuthedUser } from "@/lib/auth/session";
import { Container } from "@/components/ui/Container";
import { LinkButton } from "@/components/ui/Button";
import { Icon } from "@/components/ui/Icon";
import { BackLink } from "@/components/ui/BackLink";
import { CheckoutClient } from "@/components/checkout/CheckoutClient";
import { eventWhen, quantityLine } from "@/lib/listing-display";

export const metadata: Metadata = {
  title: "Checkout",
  robots: { index: false, follow: false },
};

type Params = { id: string };

// Plain function, not a component — exempt from the render-purity rule that
// disallows Date.now()/new Date() directly in a component body (see
// listings.ts's getActiveListings for the same exemption pattern).
function isStillReservedFor(reservation: ReservationState | null, userId: string): boolean {
  const reservedUntil = reservation?.reservedUntil ? new Date(reservation.reservedUntil) : null;
  return (
    reservation?.status === "reserved" &&
    reservation.reservedBy === userId &&
    reservedUntil != null &&
    reservedUntil.getTime() > Date.now()
  );
}

export default async function CheckoutPage({ params }: { params: Promise<Params> }) {
  const { id } = await params;

  const user = await getAuthedUser();
  if (!user) redirect(`/login?next=${encodeURIComponent(`/checkout/${id}`)}`);

  const listing = await getListing(id);
  if (!listing) notFound();

  const reservation = await getReservationState(id);
  const stillReservedForMe = isStillReservedFor(reservation, user.id);

  // Two ways to legitimately be here. Buy Now still requires a live
  // reservation held by this user; an auction winner has no reservation at
  // all — the auction itself is what entitles them to pay.
  const canBuyNow = Boolean(listing.buy_now_enabled && listing.buy_now_price) && stillReservedForMe;
  const canPayForWin = isUnpaidAuctionWinner(listing, user.id);

  if (!canBuyNow && !canPayForWin) {
    const soldAlready = reservation?.status === "sold" || listing.auction_status === "sold";
    const auctionOver = listing.auction_status === "ended";
    return (
      <Container className="flex flex-col items-center py-16 text-center sm:py-24">
        <span className="mb-5 inline-flex size-14 items-center justify-center rounded-full bg-surface text-ink-2">
          <Icon name={soldAlready ? "ticket" : "clock"} size={26} />
        </span>
        <h1 className="t-name-state text-ink">
          {soldAlready ? "Already sold" : auctionOver ? "Auction ended" : "Reservation expired"}
        </h1>
        <p className="t-body mx-auto mt-2.5 max-w-[46ch] text-muted">
          {soldAlready
            ? "This listing has already been purchased."
            : auctionOver
              ? "This auction has ended and the winning bidder has been notified."
              : "Your reservation has expired. Go back and tap Buy Now again."}
        </p>
        <LinkButton href={`/listing/${id}`} size="lg" className="mt-7">
          Back to listing
        </LinkButton>
      </Container>
    );
  }

  // Buy Now wins a tie: a reservation this user is actively holding is the
  // more specific claim. Prices stay all-in downstream — CheckoutClient runs
  // this base through the shared fee math, exactly as create-payment-intent
  // does server-side.
  const mode = canBuyNow ? "buy_now" : "auction";
  const baseDollars = canBuyNow
    ? listing.buy_now_price!
    : (listing.winning_bid_amount ?? listing.current_bid);

  return (
    <Container size="medium" className="pb-12 pt-3 lg:pt-6">
      <div className="flex items-center gap-3">
        <BackLink href={`/listing/${id}`} label="Back to listing" />
        <span className="t-body-sm text-muted max-sm:hidden">Back to listing</span>
      </div>
      <h1 className="t-display-lg mt-5 text-ink">Checkout</h1>
      {mode === "auction" ? (
        <p className="t-body mt-2 max-w-[52ch] text-ink-2">You won this auction. Complete payment to claim your ticket.</p>
      ) : null}
      <CheckoutClient
        listingId={listing.id}
        mode={mode}
        eventName={listing.event_name}
        venue={listing.venue}
        baseDollars={baseDollars}
        posterPath={listing.cover_image_path}
        when={eventWhen(listing)}
        tickets={quantityLine(listing)}
      />
    </Container>
  );
}
