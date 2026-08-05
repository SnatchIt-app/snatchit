import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";
import { formatCents } from "@snatchit/core";
import { getAuthedUser } from "@/lib/auth/session";
import { getMySales, payoutLabel } from "@/lib/sales";
import { coverImageUrl } from "@/lib/listings";
import { TransferStatusBadge } from "@/components/transfer/TransferStatusBadge";
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
      <div className="space-y-6">
        <h1 className="font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
          Your sales
        </h1>
        <EmptyState
          title="No sales yet"
          message="Once a ticket sells, it shows up here with its transfer and payout status."
          action={<LinkButton href="/account/listings">Your listings</LinkButton>}
        />
      </div>
    );
  }

  const paidOut = sales.filter((s) => s.payoutReleasedAt).reduce((sum, s) => sum + (s.netCents ?? 0), 0);

  return (
    <div className="space-y-6">
      <h1 className="font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
        Your sales
      </h1>

      <dl className="flex flex-wrap gap-8 border-y border-primary/15 py-5">
        <div>
          <dt className="text-[10px] font-medium uppercase tracking-[0.25em] text-white/40">Sales</dt>
          <dd className="mt-1.5 font-display text-[22px] font-bold text-ink">{sales.length}</dd>
        </div>
        <div>
          <dt className="text-[10px] font-medium uppercase tracking-[0.25em] text-white/40">Paid out</dt>
          <dd className="mt-1.5 font-display text-[22px] font-bold text-ink">{formatCents(paidOut)}</dd>
        </div>
      </dl>

      <ul className="space-y-3">
        {sales.map((s) => {
          const line = payoutLabel(s);
          const href = NEEDS_SEND.has(s.status) ? `/transfer/send/${s.id}` : `/listing/${s.listing_id}`;
          return (
            <li key={s.id} className="border border-primary/20 bg-card p-4">
              <Link href={href} className="flex gap-4">
                <span className="relative size-20 shrink-0 overflow-hidden border border-white/10">
                  {s.coverImagePath ? (
                    <Image src={coverImageUrl(s.coverImagePath)} alt="" fill sizes="80px" className="object-cover" />
                  ) : null}
                </span>
                <span className="min-w-0 flex-1">
                  <span className="flex flex-wrap items-center gap-2">
                    <TransferStatusBadge status={s.status} />
                    {s.netCents != null ? (
                      <span className="text-[12.5px] tabular-nums text-white/60">
                        {formatCents(s.netCents)} to you
                      </span>
                    ) : null}
                  </span>
                  <span className="mt-1.5 block truncate text-[15px] font-bold text-ink">{s.eventName}</span>
                  <span className="mt-0.5 block truncate text-[12.5px] text-white/50">
                    {s.venue}
                    {s.buyerName ? ` · sold to ${s.buyerName}` : ""}
                  </span>
                  <span className={`mt-1 block text-[12.5px] ${line.urgent ? "font-bold text-primary" : "text-white/45"}`}>
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
