import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getAuthedUser } from "@/lib/auth/session";
import { getMyPurchases } from "@/lib/transfers";
import { coverImageUrl } from "@/lib/listings";
import { buyerPurchaseLine } from "@/lib/transfer-wording";
import { TransferStatusBadge } from "@/components/transfer/TransferStatusBadge";
import { AccountHeader } from "@/components/account/AccountHeader";
import { EmptyState } from "@/components/ui/EmptyState";
import { LinkButton } from "@/components/ui/Button";

export const metadata: Metadata = {
  title: "Your purchases",
  robots: { index: false, follow: false },
};

const IN_FLIGHT = new Set(["pending", "seller_sent", "disputed"]);

export default async function PurchasesPage() {
  const user = await getAuthedUser();
  if (!user) redirect("/login?next=%2Faccount%2Fpurchases");

  const purchases = await getMyPurchases(user.id);

  if (purchases.length === 0) {
    return (
      <div>
        <AccountHeader title="Your purchases" back={null} />
        <EmptyState
          icon="receipt"
          title="No purchases yet"
          message="Tickets you buy show up here, with their transfer status."
          action={<LinkButton href="/browse">Browse tickets</LinkButton>}
        />
      </div>
    );
  }

  return (
    <div>
      <AccountHeader title="Your purchases" back={null} />

      <ul className="border-t border-line">
        {purchases.map((t) => {
          const line = buyerPurchaseLine(t);
          // Completed purchases go to the listing, in-flight ones to the
          // transfer — same routing rule as mobile.
          const href = IN_FLIGHT.has(t.status) ? `/transfer/receive/${t.id}` : `/listing/${t.listing_id}`;
          return (
            <li key={t.id} className="border-b border-line">
              <Link
                href={href}
                className="group -mx-3 flex flex-wrap items-start gap-4 rounded-panel px-3 py-4 transition-colors hover:bg-surface sm:gap-5"
              >
                <span className="poster relative block h-[78px] w-[62px] shrink-0 overflow-hidden rounded-media sm:h-[100px] sm:w-[80px]">
                  {t.coverImagePath ? (
                    <Image src={coverImageUrl(t.coverImagePath)} alt="" fill sizes="80px" className="object-contain" />
                  ) : null}
                </span>
                {/* Beside the poster; under it when the row is too narrow (200% zoom) to fit the badge. */}
                <span className="min-w-0 grow basis-48">
                  <TransferStatusBadge row={t} audience="buyer" />
                  <span className="t-name-row mt-2 block break-words text-ink group-hover:underline group-hover:decoration-2 group-hover:underline-offset-4">
                    {t.eventName}
                  </span>
                  <span className="t-body-sm mt-0.5 block break-words text-muted">{t.venue}</span>
                  <span
                    className={`t-body-sm mt-1.5 block ${line.urgent ? "font-semibold text-brand-text" : "text-ink-2"}`}
                  >
                    {line.text}
                  </span>
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
