"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import type { TransferView } from "@/lib/transfers";
import { markTransferSentAction, uploadEvidenceAction } from "@/lib/transfers-actions";
import { PlatformInstructions } from "@/components/transfer/PlatformInstructions";
import { Button } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";

export function SellerTransferPanel({
  transfer,
  countdownLabel,
}: {
  transfer: TransferView;
  countdownLabel: string | null;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [evidencePath, setEvidencePath] = useState<string | null>(null);
  const [evidenceName, setEvidenceName] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [isPending, startTransition] = useTransition();

  const deliveryMissing = !transfer.delivery_email && !transfer.delivery_phone;

  function handlePick(file: File | undefined) {
    if (!file) return;
    setError(null);
    setEvidenceName(file.name);
    setUploading(true);
    startTransition(async () => {
      try {
        const res = await uploadEvidenceAction(file);
        if (res.error) {
          setEvidencePath(null);
          setError(res.error === "AUTH_REQUIRED" ? "Please sign in again." : res.error);
          return;
        }
        setEvidencePath(res.path ?? null);
      } catch {
        // Without this, a rejected upload (offline, oversized body, action
        // transport error) left `uploading` true forever, permanently
        // disabling "I've sent the tickets" — the seller would miss the 24h
        // deadline and the buyer would be auto-refunded.
        setEvidencePath(null);
        setError("That upload didn't go through. Check your connection and try again.");
      } finally {
        setUploading(false);
      }
    });
  }

  function handleSend() {
    setError(null);
    if (!evidencePath) return setError("Upload a screenshot of the transfer confirmation first.");
    startTransition(async () => {
      let result: { ok?: true; error?: string; warning?: string };
      try {
        result = await markTransferSentAction(transfer.id, evidencePath);
      } catch {
        setError("Something went wrong marking these sent. Check your connection and try again.");
        return;
      }
      if (result.error === "AUTH_REQUIRED") {
        router.push(`/login?next=${encodeURIComponent(`/transfer/send/${transfer.id}`)}`);
        return;
      }
      if (result.error) return setError(result.error);
      router.refresh();
    });
  }

  return (
    <div className="space-y-5">
      {error ? <Alert tone="error">{error}</Alert> : null}

      {transfer.status === "pending" ? (
        <>
          <Alert tone={countdownLabel ? "success" : "error"}>
            {countdownLabel
              ? `You have ${countdownLabel} to send these tickets. Miss it and the buyer is refunded automatically.`
              : "The transfer window has expired."}
          </Alert>

          {/* Buyer's delivery details — the only buyer PII shown, and only to
              this transfer's seller. */}
          <section className="border border-primary/20 bg-card p-5">
            <p className="eyebrow text-primary/80">Send the tickets to</p>
            {deliveryMissing ? (
              <p className="mt-3 text-[13.5px] leading-relaxed text-white/60">
                The buyer hasn&apos;t added their delivery details yet. You&apos;ll be able to send
                as soon as they do — we&apos;ve already nudged them.
              </p>
            ) : (
              <dl className="mt-3 space-y-2 text-[13.5px]">
                {transfer.delivery_email ? (
                  <div className="flex justify-between gap-4">
                    <dt className="text-muted">Email</dt>
                    <dd className="font-semibold text-ink">{transfer.delivery_email}</dd>
                  </div>
                ) : null}
                {transfer.delivery_phone ? (
                  <div className="flex justify-between gap-4">
                    <dt className="text-muted">Phone</dt>
                    <dd className="font-semibold text-ink">{transfer.delivery_phone}</dd>
                  </div>
                ) : null}
              </dl>
            )}
          </section>

          <PlatformInstructions
            platform={transfer.ticketPlatform}
            role="seller"
            buyerEmail={transfer.delivery_email}
            buyerPhone={transfer.delivery_phone}
          />

          <section className="border border-primary/20 bg-card p-5">
            <p className="eyebrow text-primary/80">Proof of transfer</p>
            <p className="mt-2 text-[13px] leading-relaxed text-white/60">
              Screenshot the confirmation from {transfer.ticketPlatform === "other" ? "the platform" : "the app"}.
              Required — it protects your payout if the buyer reports a problem.
            </p>
            <label className="mt-4 flex cursor-pointer items-center justify-center border border-dashed border-white/20 bg-white/[0.02] p-5 text-center transition-colors hover:border-primary/40">
              <span className="text-[12.5px] text-white/55">
                {evidencePath ? `✓ ${evidenceName}` : uploading ? "Uploading…" : "Choose a screenshot"}
              </span>
              <input
                type="file"
                accept="image/jpeg,image/png,image/webp,image/heic"
                className="hidden"
                onChange={(e) => handlePick(e.target.files?.[0])}
              />
            </label>
          </section>

          <Alert tone="error">
            Only mark this sent after you&apos;ve actually completed the transfer in the ticket
            platform. False confirmations put your payout and account at risk.
          </Alert>

          <Button
            variant="primary"
            size="lg"
            className="w-full"
            disabled={isPending || uploading || deliveryMissing || !evidencePath}
            onClick={handleSend}
          >
            {isPending ? "Marking sent…" : "I've sent the tickets"}
          </Button>
        </>
      ) : null}

      {transfer.status === "seller_sent" ? (
        <>
          <Alert tone="success">
            Tickets marked sent. Waiting for the buyer to confirm receipt.
          </Alert>
          <section className="border border-primary/20 bg-card p-5">
            <p className="eyebrow text-primary/80">Payout</p>
            <p className="mt-3 text-[13.5px] leading-relaxed text-white/70">
              {transfer.payout_review_status === "manual_review"
                ? "This payout is under manual review. Contact support@snatchitapp.com if you have questions."
                : transfer.payout_review_status === "held"
                  ? "Funds are held until shortly after the event as a standard protection."
                  : countdownLabel
                    ? `Buyer review window: ${countdownLabel}. Your payout releases once it clears — sooner if the buyer confirms.`
                    : "The buyer review window has passed. Your payout is being processed."}
            </p>
            <p className="mt-3 text-[12.5px] text-white/45">
              If the buyer reports an issue, your payout is held pending review.
            </p>
          </section>
        </>
      ) : null}

      {transfer.status === "buyer_confirmed" || transfer.status === "auto_released" ? (
        <Alert tone="success">
          {transfer.payout_released_at
            ? "Transfer complete and payout released."
            : "Transfer complete. Your payout is being processed — make sure payouts are set up in Settings."}
        </Alert>
      ) : null}

      {transfer.status === "disputed" ? (
        <Alert tone="error">
          The buyer reported a problem. Your payout is on hold while our team reviews it.
        </Alert>
      ) : null}

      {transfer.status === "expired" ? (
        <Alert tone="error">
          The 24-hour window passed without a transfer, so the buyer was refunded.
        </Alert>
      ) : null}
    </div>
  );
}
