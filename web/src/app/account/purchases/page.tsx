import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getAuthedUser } from "@/lib/auth/session";
import { getMyPurchases, type TransferView } from "@/lib/transfers";
import { coverImageUrl } from "@/lib/listings";
import { TransferStatusBadge } from "@/components/transfer/TransferStatusBadge";
import { EmptyState } from "@/components/ui/EmptyState";
import { LinkButton } from "@/components/ui/Button";

export const metadata: Metadata = {
  title: "Your purchases",
  robots: { index: false, follow: false },
};

/** Mirrors mobile's bids.tsx labels, where transfer status wins. */
function actionLine(t: TransferView): { text: string; urgent: boolean } {
  switch (t.status) {
    case "pending":
      return !t.delivery_email && !t.delivery_phone
        ? { text: "Add your delivery info so the seller can send", urgent: true }
        : { text: "Waiting for the seller to send", urgent: false };
    case "seller_sent":
      return { text: "Seller sent — confirm you received them", urgent: true };
    case "disputed":
      return { text: "Disputed — support is reviewing", urgent: false };
    case "buyer_confirmed":
    case "auto_released":
      return { text: "Confirmed", urgent: false };
    case "expired":
      return { text: "Expired — refunded in full", urgent: false };
    default:
      return { text: "", urgent: false };
  }
}

const IN_FLIGHT = new Set(["pending", "seller_sent", "disputed"]);

export default async function PurchasesPage() {
  const user = await getAuthedUser();
  if (!user) redirect("/login?next=%2Faccount%2Fpurchases");

  const purchases = await getMyPurchases(user.id);

  if (purchases.length === 0) {
    return (
      <div className="space-y-6">
        <h1 className="font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
          Your purchases
        </h1>
        <EmptyState
          title="No purchases yet"
          message="Tickets you buy show up here, with their transfer status."
          action={<LinkButton href="/browse">Browse tickets</LinkButton>}
        />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <h1 className="font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
        Your purchases
      </h1>

      <ul className="space-y-3">
        {purchases.map((t) => {
          const line = actionLine(t);
          // Completed purchases go to the listing, in-flight ones to the
          // transfer — same routing rule as mobile.
          const href = IN_FLIGHT.has(t.status) ? `/transfer/receive/${t.id}` : `/listing/${t.listing_id}`;
          return (
            <li key={t.id} className="border border-primary/20 bg-card p-4">
              <Link href={href} className="flex gap-4">
                <span className="relative size-20 shrink-0 overflow-hidden border border-white/10">
                  {t.coverImagePath ? (
                    <Image src={coverImageUrl(t.coverImagePath)} alt="" fill sizes="80px" className="object-cover" />
                  ) : null}
                </span>
                <span className="min-w-0 flex-1">
                  <TransferStatusBadge status={t.status} />
                  <span className="mt-1.5 block truncate text-[15px] font-bold text-ink">{t.eventName}</span>
                  <span className="mt-0.5 block truncate text-[12.5px] text-white/50">{t.venue}</span>
                  <span
                    className={`mt-1 block text-[12.5px] ${line.urgent ? "font-bold text-primary" : "text-white/45"}`}
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
