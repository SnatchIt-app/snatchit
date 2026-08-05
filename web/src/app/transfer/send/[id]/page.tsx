import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getAuthedUser } from "@/lib/auth/session";
import { getTransferForSeller } from "@/lib/transfers";
import { countdownFrom } from "@/lib/transfer-format";
import { TransferStatusBadge } from "@/components/transfer/TransferStatusBadge";
import { SellerTransferPanel } from "@/components/transfer/SellerTransferPanel";
import { Container } from "@/components/ui/Container";

export const metadata: Metadata = {
  title: "Send tickets",
  robots: { index: false, follow: false },
};

export default async function SendTransferPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  const user = await getAuthedUser();
  if (!user) redirect(`/login?next=${encodeURIComponent(`/transfer/send/${id}`)}`);

  // Scoped to seller_id — the buyer cannot open this page.
  const transfer = await getTransferForSeller(user.id, id);
  if (!transfer) notFound();

  // pending -> the seller's 24h deadline; seller_sent -> the buyer's 72h
  // review window. Two different clocks, matching mobile.
  const countdown = countdownFrom(
    transfer.status === "pending"
      ? transfer.expires_at
      : transfer.status === "seller_sent"
        ? transfer.auto_release_at
        : null,
  );

  return (
    <Container className="max-w-[620px] py-10">
      <Link
        href="/account/listings"
        className="text-[10.5px] font-medium uppercase tracking-[0.3em] text-white/60 hover:text-primary"
      >
        ← Your listings
      </Link>

      <div className="mt-6 flex flex-wrap items-center gap-3">
        <TransferStatusBadge status={transfer.status} />
        {transfer.counterpartyName ? (
          <span className="text-[12.5px] text-white/50">for {transfer.counterpartyName}</span>
        ) : null}
      </div>
      <h1 className="mt-3 font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
        {transfer.eventName}
      </h1>
      <p className="mt-1 text-[13.5px] text-white/50">{transfer.venue}</p>

      <div className="mt-7">
        <SellerTransferPanel transfer={transfer} countdownLabel={countdown} />
      </div>
    </Container>
  );
}
