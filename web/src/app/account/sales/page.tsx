import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";
import { formatCents } from "@snatchit/core";
import { getAuthedUser } from "@/lib/auth/session";
import { getMySales, payoutLabel, saleRow } from "@/lib/sales";
import { coverImageUrl } from "@/lib/listings";
import { TransferStatusBadge } from "@/components/transfer/TransferStatusBadge";
import { AccountHeader } from "@/components/account/AccountHeader";
import { EmptyState } from "@/components/ui/EmptyState";
import { LinkButton } from "@/components/ui/Button";

export const metadata: Metadata = {
  title: "Your sales",
  robots: { index: false, follow: false },
};

/** Only an unsent sale needs the seller in the transfer flow. */
const NEEDS_SEND = new Set(["pending"]);

export default async function SalesPage() {
  const user = await getAuthedUser();
  if (!user) redirect("/login?next=%2Faccount%2Fsales");

  const sales = await getMySales(user.id);

  if (sales.length === 0) {
    return (
      <div>
        <AccountHeader title="Your sales" />
        <EmptyState
          icon="tag"
          title="No sales yet"
          message="Once a ticket sells, it shows up here with its transfer and payout status."
          action={<LinkButton href="/account/listings">Your listings</LinkButton>}
        />
      </div>
    );
  }

  const paidOut = sales.filter((s) => s.payoutReleasedAt).reduce((sum, s) => sum + (s.netCents ?? 0), 0);

  return (
    <div>
      <AccountHeader title="Your sales" />

      <dl className="flex flex-wrap gap-x-12 gap-y-4 border-t border-line py-5">
        <div>
          <dt className="t-micro text-muted">Sales</dt>
          <dd className="t-price mt-1 text-[26px] leading-tight text-ink">{sales.length}</dd>
        </div>
        <div>
          <dt className="t-micro text-muted">Paid out</dt>
          <dd className="t-price mt-1 text-[26px] leading-tight text-ink">{formatCents(paidOut)}</dd>
        </div>
      </dl>

      <ul className="border-t border-line">
        {sales.map((s) => {
          const line = payoutLabel(s);
          const href = NEEDS_SEND.has(s.status) ? `/transfer/send/${s.id}` : `/listing/${s.listing_id}`;
          return (
            <li key={s.id} className="border-b border-line">
              <Link
                href={href}
                className="group -mx-3 flex flex-wrap items-start gap-4 rounded-panel px-3 py-4 transition-colors hover:bg-surface sm:gap-5"
              >
                <span className="poster relative block h-[78px] w-[62px] shrink-0 overflow-hidden rounded-media sm:h-[100px] sm:w-[80px]">
                  {s.coverImagePath ? (
                    <Image src={coverImageUrl(s.coverImagePath)} alt="" fill sizes="80px" className="object-contain" />
                  ) : null}
                </span>
                {/* Beside the poster (under it when the row is too narrow, e.g. 200% zoom). Phones: the amount
                    sits under the text. Wider: a right-hand column that still wraps before it would be cut. */}
                <span className="flex min-w-0 grow basis-48 flex-wrap items-start gap-x-5 gap-y-2">
                  <span className="min-w-0 grow basis-40">
                    <TransferStatusBadge row={saleRow(s)} audience="seller" />
                    <span className="t-name-row mt-2 block break-words text-ink group-hover:underline group-hover:decoration-2 group-hover:underline-offset-4">
                      {s.eventName}
                    </span>
                    <span className="t-body-sm mt-0.5 block break-words text-muted">
                      {s.venue}
                      {s.buyerName ? ` · sold to ${s.buyerName}` : ""}
                    </span>
                    <span
                      className={`t-body-sm mt-1.5 block ${line.urgent ? "font-semibold text-brand-text" : "text-ink-2"}`}
                    >
                      {line.text}
                    </span>
                  </span>
                  {s.netCents != null ? (
                    <span className="t-body-sm w-full text-muted sm:ml-auto sm:w-auto sm:text-right">
                      <span className="t-price whitespace-nowrap text-[17px] text-ink">{formatCents(s.netCents)}</span> to you
                    </span>
                  ) : null}
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
