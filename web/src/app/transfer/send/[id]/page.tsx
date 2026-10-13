import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { getAuthedUser } from "@/lib/auth/session";
import { getTransferForSeller } from "@/lib/transfers";
import { countdownFrom } from "@/lib/transfer-format";
import { TransferStatusBadge } from "@/components/transfer/TransferStatusBadge";
import { SellerTransferPanel } from "@/components/transfer/SellerTransferPanel";
import { Container } from "@/components/ui/Container";
import { TransferHeader } from "@/components/transfer/TransferHeader";

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
    <Container size="narrow" className="pb-12 pt-3 lg:pt-6">
      <TransferHeader
        backHref="/account/listings"
        backLabel="Your listings"
        screenTitle="Send transfer"
        badge={<TransferStatusBadge row={transfer} audience="seller" />}
        counterparty={transfer.counterpartyName ? `for ${transfer.counterpartyName}` : null}
        eventName={transfer.eventName}
        venue={transfer.venue}
        coverImagePath={transfer.coverImagePath}
      />

      <div className="mt-7">
        <SellerTransferPanel transfer={transfer} countdownLabel={countdown} />
      </div>
    </Container>
  );
}
