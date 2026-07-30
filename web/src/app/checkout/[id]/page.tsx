import type { Metadata } from "next";
import Link from "next/link";
import { redirect, notFound } from "next/navigation";
import { getListing } from "@/lib/listings";
import { getReservationState, type ReservationState } from "@/lib/checkout";
import { getAuthedUser } from "@/lib/auth/session";
import { Container } from "@/components/ui/Container";
import { LinkButton } from "@/components/ui/Button";
import { CheckoutClient } from "@/components/checkout/CheckoutClient";

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

  if (!listing.buy_now_enabled || !listing.buy_now_price || !stillReservedForMe) {
    return (
      <Container className="py-16 text-center">
        <h1 className="font-display text-[22px] font-bold uppercase text-ink">
          {reservation?.status === "sold" ? "Already sold" : "Reservation expired"}
        </h1>
        <p className="mx-auto mt-3 max-w-[46ch] text-[13.5px] leading-relaxed text-white/60">
          {reservation?.status === "sold"
            ? "This listing has already been purchased."
            : "Your reservation has expired. Go back and tap Buy Now again."}
        </p>
        <LinkButton href={`/listing/${id}`} className="mt-6 inline-flex">
          Back to listing
        </LinkButton>
      </Container>
    );
  }

  return (
    <Container className="max-w-[560px] py-10">
      <nav aria-label="Breadcrumb" className="mb-6">
        <Link
          href={`/listing/${id}`}
          className="text-[10.5px] font-medium uppercase tracking-[0.3em] text-white/60 hover:text-primary"
        >
          ← Back to listing
        </Link>
      </nav>
      <h1 className="font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
        Checkout
      </h1>
      <CheckoutClient
        listingId={listing.id}
        eventName={listing.event_name}
        venue={listing.venue}
        buyNowPriceDollars={listing.buy_now_price}
      />
    </Container>
  );
}
