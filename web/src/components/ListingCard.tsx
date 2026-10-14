import Link from "next/link";
import type { WebListing } from "@/lib/listings";
import { listingCardStatus } from "@/lib/format";
import { clockState, eventWhen, priceState } from "@/lib/listing-display";
import { Badge } from "@/components/ui/Badge";
import { PriceDisplay } from "@/components/ui/PriceDisplay";
import { SaveButton } from "@/components/SaveButton";
import { Poster } from "@/components/listing/Poster";

/**
 * Poster card for grids (saved listings, "More nights like this"): the 4:5
 * poster with the save control over it, then name, when/where and the all-in
 * price. The card-wide link is a stretched anchor so the save button stays a
 * real sibling <button>, never a button nested inside a link.
 */
export function ListingCard({
  listing,
  priority = false,
  isSaved = false,
}: {
  listing: WebListing;
  priority?: boolean;
  isSaved?: boolean;
}) {
  const status = listingCardStatus(listing);
  const price = priceState(listing);
  const clock = clockState(listing);
  return (
    <article className="group relative">
      <div className="relative">
        <Poster
          path={listing.cover_image_path}
          alt={`${listing.event_name} at ${listing.venue}`}
          sizes="(min-width: 1200px) 270px, (min-width: 768px) 30vw, 50vw"
          priority={priority}
        />
        {status !== "LIVE" ? (
          <span className="pointer-events-none absolute left-2.5 top-2.5 z-10">
            <Badge onArt>{clock.text}</Badge>
          </span>
        ) : null}
        <span className="absolute right-2 top-2 z-20">
          <SaveButton listingId={listing.id} initialSaved={isSaved} />
        </span>
      </div>
      <div className="mt-3">
        <h3 className="t-name-row line-clamp-2 text-ink group-hover:underline group-hover:decoration-2 group-hover:underline-offset-4">
          {listing.event_name}
        </h3>
        <p className="t-body-sm mt-1 truncate text-muted">
          {eventWhen(listing)} · {listing.venue}
        </p>
        <p className="mt-2 flex flex-wrap items-baseline gap-x-1.5">
          <PriceDisplay baseDollars={price.dollars} size="sm" suffix={null} />
          <span className="t-body-sm text-muted">{price.label.toLowerCase()}, all-in</span>
        </p>
      </div>
      <Link href={`/listing/${listing.id}`} className="absolute inset-0 z-[5] rounded-panel" aria-label={`${listing.event_name} at ${listing.venue}`} />
    </article>
  );
}
