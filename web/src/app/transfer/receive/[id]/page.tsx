import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { getAuthedUser } from "@/lib/auth/session";
import { getEvidenceUrl, getTransferForBuyer } from "@/lib/transfers";
import { countdownFrom } from "@/lib/transfer-format";
import { TransferStatusBadge } from "@/components/transfer/TransferStatusBadge";
import { BuyerTransferPanel } from "@/components/transfer/BuyerTransferPanel";
import { Container } from "@/components/ui/Container";
import { TransferHeader } from "@/components/transfer/TransferHeader";

export const metadata: Metadata = {
  title: "Your transfer",
  robots: { index: false, follow: false },
};

export default async function ReceiveTransferPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  const user = await getAuthedUser();
  if (!user) redirect(`/login?next=${encodeURIComponent(`/transfer/receive/${id}`)}`);

  // Scoped to buyer_id — another user's transfer is simply not found.
  const transfer = await getTransferForBuyer(user.id, id);
  if (!transfer) notFound();

  // Proof is only meaningful once the seller has sent, and proof-docs is
  // private — this is a short-lived signed URL, not a public path.
  const evidenceUrl =
    transfer.status === "seller_sent" && transfer.transfer_evidence_path
      ? await getEvidenceUrl(transfer.transfer_evidence_path)
      : null;

  const countdown = countdownFrom(transfer.status === "pending" ? transfer.expires_at : null);

  return (
    <Container size="narrow" className="pb-12 pt-3 lg:pt-6">
      <TransferHeader
        backHref="/account/purchases"
        backLabel="Your purchases"
        screenTitle="Your order"
        badge={<TransferStatusBadge row={transfer} audience="buyer" />}
        counterparty={transfer.counterpartyName ? `from ${transfer.counterpartyName}` : null}
        eventName={transfer.eventName}
        venue={transfer.venue}
        coverImagePath={transfer.coverImagePath}
      />

      <div className="mt-7">
        <BuyerTransferPanel transfer={transfer} evidenceUrl={evidenceUrl} countdownLabel={countdown} />
      </div>
    </Container>
  );
}
