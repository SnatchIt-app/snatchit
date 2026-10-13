import Image from "next/image";
import type { ReactNode } from "react";
import { coverImageUrl } from "@/lib/format";
import { BackLink } from "@/components/ui/BackLink";

/**
 * Top of the native "Your order" / "Send transfer" screens: the back chip and
 * screen title, then the order identity — small poster, status badge, the
 * other party, the event name and venue.
 */
export function TransferHeader({
  backHref,
  backLabel,
  screenTitle,
  badge,
  counterparty,
  eventName,
  venue,
  coverImagePath,
}: {
  backHref: string;
  backLabel: string;
  screenTitle: string;
  badge: ReactNode;
  counterparty: string | null;
  eventName: string;
  venue: string;
  coverImagePath: string;
}) {
  return (
    <>
      <div className="grid grid-cols-[44px_1fr_44px] items-center">
        <BackLink href={backHref} label={backLabel} />
        <p className="t-screen-title text-center text-ink">{screenTitle}</p>
        <span aria-hidden="true" />
      </div>
      <div className="mt-6 flex items-start gap-4">
        {coverImagePath ? (
          <span className="poster relative block h-[78px] w-[62px] shrink-0 overflow-hidden rounded-media">
            <Image src={coverImageUrl(coverImagePath)} alt="" fill sizes="62px" className="object-contain" />
          </span>
        ) : null}
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
            {badge}
            {counterparty ? <span className="t-body-sm text-muted">{counterparty}</span> : null}
          </div>
          <h1 className="t-name-order mt-1.5 text-ink">{eventName}</h1>
          <p className="t-body-sm mt-0.5 text-muted">{venue}</p>
        </div>
      </div>
    </>
  );
}
