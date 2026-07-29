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
 * Listing card — editorial catalog treatment: the artwork carries the card,
 * no container box. Fixed 4:3 image (zero CLS), uppercase metadata, tabular
 * all-in price. The whole card is one anchor for a large tap target.
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
      <article>
        <div className="relative aspect-[4/3] overflow-hidden rounded-[6px] bg-white/[0.03]">
          <Image
            src={coverImageUrl(listing.cover_image_path)}
            alt={`${listing.event_name} at ${listing.venue}`}
            fill
            priority={priority}
            sizes="(min-width: 1280px) 280px, (min-width: 1024px) 30vw, (min-width: 640px) 45vw, 92vw"
            className="object-cover transition-[transform,filter] duration-300 ease-[var(--ease-swift)] group-hover:scale-[1.025] group-hover:brightness-[1.06] motion-reduce:transition-none motion-reduce:group-hover:scale-100"
          />
          <div className="absolute left-2.5 top-2.5 flex gap-1.5">
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

        <div className="pt-4">
          <p className="truncate text-[10.5px] font-semibold uppercase tracking-[0.14em] text-dim">
            {listing.venue} · {neighborhoodLabel(listing.neighborhood)} ·{" "}
            {fmtEventDate(listing.event_date)}
          </p>
          <h3 className="mt-1.5 truncate text-[16px] font-bold tracking-[-0.01em] text-ink transition-colors duration-150 group-hover:text-white motion-reduce:transition-none">
            {listing.event_name}
          </h3>
          <div className="mt-3 flex items-baseline justify-between gap-3">
            <PriceDisplay baseDollars={price} size="md" />
            {listing.buy_now_enabled ? (
              <span className="text-[10px] font-semibold uppercase tracking-[0.14em] text-success">
                Buy now
              </span>
            ) : (
              <span className="text-[10px] font-semibold uppercase tracking-[0.14em] text-dim">
                {listing.bid_count} bid{listing.bid_count === 1 ? "" : "s"}
              </span>
            )}
          </div>
        </div>
      </article>
    </Link>
  );
}
