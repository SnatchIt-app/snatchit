import Image from "next/image";
import Link from "next/link";
import type { WebListing } from "@/lib/listings";
import { coverImageUrl } from "@/lib/listings";
import {
  fmtEndsIn,
  fmtEventDate,
  listingCardStatus,
  neighborhoodLabel,
} from "@/lib/format";
import { Badge, LiveDot } from "@/components/ui/Badge";
import { PriceDisplay } from "@/components/ui/PriceDisplay";

/**
 * Listing card. Fixed 4:3 image aspect (zero CLS), all-in price, status badge.
 * The whole card is one anchor for a large tap target.
 */
export function ListingCard({
  listing,
  priority = false,
}: {
  listing: WebListing;
  priority?: boolean;
}) {
  const status = listingCardStatus(listing);
  const price = listing.buy_now_enabled && listing.buy_now_price ? listing.buy_now_price : listing.current_bid;

  return (
    <Link
      href={`/listing/${listing.id}`}
      className="group block overflow-hidden rounded-card border border-line bg-card transition-colors hover:border-line-strong motion-reduce:transition-none"
    >
      <article>
        <div className="relative aspect-[4/3] overflow-hidden bg-field">
          <Image
            src={coverImageUrl(listing.cover_image_path)}
            alt={`${listing.event_name} at ${listing.venue}`}
            fill
            priority={priority}
            sizes="(min-width: 1280px) 280px, (min-width: 1024px) 30vw, (min-width: 640px) 45vw, 92vw"
            className="object-cover transition-transform duration-300 group-hover:scale-[1.03] motion-reduce:transition-none motion-reduce:group-hover:scale-100"
          />
          <div className="absolute left-3 top-3 flex gap-2">
            {status === "LIVE" ? (
              <Badge variant="live">
                <LiveDot /> Live auction
              </Badge>
            ) : status === "ENDING SOON" ? (
              <Badge variant="soon">Ends in {fmtEndsIn(listing.ends_at)}</Badge>
            ) : status === "SOLD" ? (
              <Badge variant="sold">Sold</Badge>
            ) : status === "RESERVED" ? (
              <Badge variant="soon">Reserved</Badge>
            ) : (
              <Badge variant="sold">Ended</Badge>
            )}
          </div>
        </div>

        <div className="p-4">
          <h3 className="truncate text-[15px] font-semibold text-ink">{listing.event_name}</h3>
          <p className="mt-0.5 truncate text-[13px] text-muted">
            {listing.venue} · {neighborhoodLabel(listing.neighborhood)} ·{" "}
            {fmtEventDate(listing.event_date)}
          </p>
          <div className="mt-3 flex items-center justify-between gap-2">
            <PriceDisplay baseDollars={price} size="md" />
            {listing.buy_now_enabled ? (
              <Badge variant="buyNow">Buy now</Badge>
            ) : (
              <Badge variant="neutral">
                {listing.bid_count} bid{listing.bid_count === 1 ? "" : "s"}
              </Badge>
            )}
          </div>
        </div>
      </article>
    </Link>
  );
}
