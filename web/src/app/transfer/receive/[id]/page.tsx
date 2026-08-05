import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getAuthedUser } from "@/lib/auth/session";
import { getEvidenceUrl, getTransferForBuyer } from "@/lib/transfers";
import { countdownFrom } from "@/lib/transfer-format";
import { TransferStatusBadge } from "@/components/transfer/TransferStatusBadge";
import { BuyerTransferPanel } from "@/components/transfer/BuyerTransferPanel";
import { Container } from "@/components/ui/Container";

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
    <Container className="max-w-[620px] py-10">
      <Link
        href="/account/purchases"
        className="text-[10.5px] font-medium uppercase tracking-[0.3em] text-white/60 hover:text-primary"
      >
        ← Your purchases
      </Link>

      <div className="mt-6 flex flex-wrap items-center gap-3">
        <TransferStatusBadge status={transfer.status} />
        {transfer.counterpartyName ? (
          <span className="text-[12.5px] text-white/50">from {transfer.counterpartyName}</span>
        ) : null}
      </div>
      <h1 className="mt-3 font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
        {transfer.eventName}
      </h1>
      <p className="mt-1 text-[13.5px] text-white/50">{transfer.venue}</p>

      <div className="mt-7">
        <BuyerTransferPanel transfer={transfer} evidenceUrl={evidenceUrl} countdownLabel={countdown} />
      </div>
    </Container>
  );
}
