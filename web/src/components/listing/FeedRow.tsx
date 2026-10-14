import Image from "next/image";
import Link from "next/link";
import type { WebListing } from "@/lib/listings";
import { coverImageUrl } from "@/lib/format";
import { clockState, eventWhen, priceState, quantityLine } from "@/lib/listing-display";
import { allInFromDollars } from "@snatchit/core";
import { PriceDisplay } from "@/components/ui/PriceDisplay";

const CLOCK_TONE = { urgent: "text-warning font-semibold", normal: "text-muted", muted: "text-muted" } as const;

/**
 * Native FeedRow: small poster (4:5, radius 8), the event name in Oswald, the
 * when/where line, then ticket count · bids · clock. The all-in price sits on
 * the right with "all-in" under it (the price label is announced to screen
 * readers; the native row shows only the caption). The whole row is one link.
 */
export function FeedRow({ listing, now }: { listing: WebListing; now?: Date }) {
  const price = priceState(listing, now);
  const clock = clockState(listing, now);
  const bids = `${listing.bid_count} bid${listing.bid_count === 1 ? "" : "s"}`;
  return (
    <Link
      href={`/listing/${listing.id}`}
      className="group -mx-3 flex items-start gap-4 rounded-panel px-3 py-3.5 transition-colors hover:bg-surface sm:gap-5"
    >
      <span className="poster relative block h-[78px] w-[62px] shrink-0 overflow-hidden rounded-media max-[299px]:hidden sm:h-[100px] sm:w-[80px]">
        <Image
          src={coverImageUrl(listing.cover_image_path)}
          alt=""
          fill
          sizes="80px"
          className="object-contain"
        />
      </span>
      <span className="flex min-w-0 flex-1 flex-wrap items-start gap-x-4 gap-y-1.5 sm:gap-x-6">
        <span className="min-w-0 flex-[1_1_8.5rem] [overflow-wrap:anywhere]">
          <span className="t-name-row line-clamp-2 text-ink group-hover:underline group-hover:decoration-2 group-hover:underline-offset-4">
            {listing.event_name}
          </span>
          <span className="t-body-sm mt-1 block text-muted">
            {eventWhen(listing)} · {listing.venue}
          </span>
          <span className="t-body-sm mt-0.5 block text-muted">
            {quantityLine(listing)} · {bids} · <span className={CLOCK_TONE[clock.tone]}>{clock.text}</span>
          </span>
        </span>
        <span className="ml-auto flex shrink-0 flex-col items-end text-right">
          <span className="sr-only">{price.label}: </span>
          <PriceDisplay baseDollars={price.dollars} size="sm" suffix={null} />
          <span className="t-body-sm text-muted">all-in</span>
          {listing.buy_now_enabled && listing.buy_now_price && price.label !== "Sold for" ? (
            <span className="t-body-sm mt-0.5 text-ink-2">
              Buy now <span className="t-price">{allInFromDollars(listing.buy_now_price)}</span>
            </span>
          ) : null}
        </span>
      </span>
    </Link>
  );
}
