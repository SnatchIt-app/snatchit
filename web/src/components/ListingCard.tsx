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
import { Badge, Chip, LiveDot } from "@/components/ui/Badge";
import { PriceDisplay } from "@/components/ui/PriceDisplay";

/**
 * Listing card — a defined, clickable object: artwork on top, date-first
 * details below, all-in price anchored at the bottom. Fixed 4:3 image
 * (zero CLS); the whole card is one anchor for a large tap target.
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
    <Link href={`/listing/${listing.id}`} className="group block">
      <article className="overflow-hidden rounded-[12px] border border-white/[0.07] bg-card transition-[border-color,transform] duration-200 ease-[var(--ease-swift)] group-hover:-translate-y-1 group-hover:border-white/[0.18] motion-reduce:transition-none motion-reduce:group-hover:translate-y-0">
        <div className="relative aspect-[4/3] overflow-hidden bg-white/[0.03]">
          <Image
            src={coverImageUrl(listing.cover_image_path)}
            alt={`${listing.event_name} at ${listing.venue}`}
            fill
            priority={priority}
            sizes="(min-width: 1280px) 280px, (min-width: 1024px) 30vw, (min-width: 640px) 45vw, 92vw"
            className="object-cover transition-transform duration-[400ms] ease-[var(--ease-swift)] group-hover:scale-[1.05] motion-reduce:transition-none motion-reduce:group-hover:scale-100"
          />
          <div className="absolute left-3 top-3 flex gap-1.5">
            {status === "LIVE" ? (
              <Badge variant="live">
                <LiveDot /> Live
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
          <p className="text-[12.5px] font-bold text-white/55">
            {fmtEventDate(listing.event_date)}
          </p>
          <h3 className="mt-1 truncate text-[16.5px] font-extrabold tracking-[-0.01em] text-ink">
            {listing.event_name}
          </h3>
          <p className="mt-0.5 truncate text-[13px] font-medium text-muted">
            {listing.venue} · {neighborhoodLabel(listing.neighborhood)}
          </p>
          <div className="mt-3.5 flex items-center justify-between gap-3">
            <PriceDisplay baseDollars={price} size="md" />
            {listing.buy_now_enabled ? (
              <Chip tone="green">Buy Now</Chip>
            ) : (
              <Chip tone="neutral">
                {listing.bid_count} bid{listing.bid_count === 1 ? "" : "s"}
              </Chip>
            )}
          </div>
        </div>
      </article>
    </Link>
  );
}
