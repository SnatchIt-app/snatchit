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
 * Listing card in the brand system: square #0a0a0a surface with a red
 * hairline, artwork on top, journal-style meta line (red date / neighborhood),
 * Oswald title that turns red on hover — the site's click affordance.
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
      <article className="overflow-hidden border border-primary/15 bg-card transition-colors duration-200 group-hover:border-primary/50 motion-reduce:transition-none">
        <div className="relative aspect-[4/3] overflow-hidden bg-white/[0.03]">
          <Image
            src={coverImageUrl(listing.cover_image_path)}
            alt={`${listing.event_name} at ${listing.venue}`}
            fill
            priority={priority}
            sizes="(min-width: 1280px) 280px, (min-width: 1024px) 30vw, (min-width: 640px) 45vw, 92vw"
            className="object-cover transition-transform duration-[400ms] ease-[var(--ease-swift)] group-hover:scale-[1.04] motion-reduce:transition-none motion-reduce:group-hover:scale-100"
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
          <p className="flex min-w-0 items-center gap-2 text-[10px] font-medium uppercase leading-none tracking-[0.2em]">
            <time className="shrink-0 whitespace-nowrap text-primary/80" dateTime={listing.event_date}>
              {fmtEventDate(listing.event_date)}
            </time>
            <span aria-hidden="true" className="shrink-0 text-white/20">/</span>
            <span className="truncate text-white/45">{neighborhoodLabel(listing.neighborhood)}</span>
          </p>
          <h3 className="mt-2.5 truncate font-display text-[20px] font-bold uppercase leading-[1.05] tracking-tight text-ink transition-colors duration-200 group-hover:text-primary motion-reduce:transition-none">
            {listing.event_name}
          </h3>
          <p className="mt-1 truncate text-[13px] text-white/55">{listing.venue}</p>
          <div className="mt-3.5 flex items-baseline justify-between gap-3 border-t border-primary/10 pt-3">
            <PriceDisplay baseDollars={price} size="md" suffix="all-in" />
            {listing.buy_now_enabled ? (
              <span className="text-[10px] font-bold uppercase leading-none tracking-[0.22em] text-primary">
                Buy Now
              </span>
            ) : (
              <span className="text-[10px] font-medium uppercase leading-none tracking-[0.22em] text-white/45">
                {listing.bid_count} bid{listing.bid_count === 1 ? "" : "s"}
              </span>
            )}
          </div>
        </div>
      </article>
    </Link>
  );
}
