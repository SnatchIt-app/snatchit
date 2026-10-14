import Link from "next/link";
import type { WebListing } from "@/lib/listings";
import { clockState, eventWhen, priceState, quantityLine } from "@/lib/listing-display";
import { PriceDisplay } from "@/components/ui/PriceDisplay";
import { Poster } from "@/components/listing/Poster";

/**
 * Native HomeFeature: the first live listing as a full 4:5 poster with no
 * overlay, then the name, two meta lines and the price with its caption.
 * Desktop places the details beside the poster instead of under it.
 */
export function ListingFeature({ listing, now }: { listing: WebListing; now?: Date }) {
  const price = priceState(listing, now);
  const clock = clockState(listing, now);
  return (
    <Link href={`/listing/${listing.id}`} className="group grid gap-5 md:grid-cols-[minmax(0,5fr)_minmax(0,6fr)] md:items-center md:gap-10">
      <Poster
        path={listing.cover_image_path}
        alt={`${listing.event_name} at ${listing.venue}`}
        sizes="(min-width: 1200px) 520px, (min-width: 768px) 45vw, 100vw"
        priority
        rounded="rounded-none sm:rounded-card"
        className="-mx-5 w-[calc(100%+40px)] sm:mx-0 sm:w-full"
      />
      <div className="min-w-0">
        <div className="flex flex-wrap items-start justify-between gap-x-6 gap-y-3 md:block">
          <div className="min-w-0 flex-1">
            <h3 className="t-name-feature text-ink group-hover:underline group-hover:decoration-2 group-hover:underline-offset-[6px]">
              {listing.event_name}
            </h3>
            <p className="t-body mt-2 text-muted">
              {eventWhen(listing)} · {listing.venue}
            </p>
            <p className="t-body text-muted">
              {quantityLine(listing)} · {listing.bid_count} bid{listing.bid_count === 1 ? "" : "s"} ·{" "}
              <span className={clock.tone === "urgent" ? "font-semibold text-warning" : ""}>{clock.text}</span>
            </p>
          </div>
          <div className="flex flex-col items-end text-right md:mt-6 md:items-start md:text-left">
            <PriceDisplay baseDollars={price.dollars} size="lg" suffix={null} />
            <span className="t-body text-muted">{price.label.toLowerCase()}, all-in</span>
          </div>
        </div>
        <span className="mt-6 hidden min-h-11 items-center gap-1 text-[15px] font-semibold text-ink md:inline-flex">
          View listing
          <span aria-hidden="true" className="transition-transform group-hover:translate-x-0.5">
            →
          </span>
        </span>
      </div>
    </Link>
  );
}
