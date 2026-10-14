"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import type { TransferView } from "@/lib/transfers";
import { markTransferSentAction, uploadEvidenceAction } from "@/lib/transfers-actions";
import { PlatformInstructions } from "@/components/transfer/PlatformInstructions";
import { sellerPayoutParagraph, sellerStateAlert } from "@/lib/transfer-wording";
import { Button } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";
import { Icon } from "@/components/ui/Icon";
import { SELLER_MISSED_DEADLINE } from "@/lib/policy-wording";

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
  const stateAlert = sellerStateAlert(transfer);
  const payoutParagraph = sellerPayoutParagraph(transfer);

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
          <Alert tone={countdownLabel ? "warning" : "error"}>
            {countdownLabel
              ? `You have ${countdownLabel} to send these tickets. ${SELLER_MISSED_DEADLINE}`
              : "The transfer window has expired."}
          </Alert>

          {/* Buyer's delivery details — the only buyer PII shown, and only to
              this transfer's seller. */}
          <section className="rounded-panel bg-surface p-5">
            <h2 className="t-title text-ink">Send the tickets to</h2>
            {deliveryMissing ? (
              <p className="t-body mt-2 text-muted">
                The buyer hasn&apos;t added their delivery details yet. You&apos;ll be able to send
                as soon as they do — we&apos;ve already nudged them.
              </p>
            ) : (
              <dl className="mt-2 text-[15px]">
                {transfer.delivery_email ? (
                  <div className="flex flex-wrap justify-between gap-x-4 border-b border-line py-2.5 last:border-b-0">
                    <dt className="text-ink-2">Email</dt>
                    <dd className="break-all font-semibold text-ink">{transfer.delivery_email}</dd>
                  </div>
                ) : null}
                {transfer.delivery_phone ? (
                  <div className="flex flex-wrap justify-between gap-x-4 border-b border-line py-2.5 last:border-b-0">
                    <dt className="text-ink-2">Phone</dt>
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

          <section className="rounded-panel bg-surface p-5">
            <h2 className="t-title text-ink">Proof of transfer</h2>
            <p className="t-body-sm mt-1.5 text-muted">
              Screenshot the confirmation from {transfer.ticketPlatform === "other" ? "the platform" : "the app"}.
              Required — it protects your payout if the buyer reports a problem.
            </p>
            <label className="mt-4 flex min-h-24 cursor-pointer items-center justify-center gap-2.5 rounded-panel border border-dashed border-control bg-canvas p-5 text-center transition-colors hover:border-ink has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-ink">
              <Icon name={evidencePath ? "check" : "upload"} size={20} className={evidencePath ? "text-success" : "text-muted"} />
              <span className="text-[15px] font-medium text-ink">
                {evidencePath ? `✓ ${evidenceName}` : uploading ? "Uploading…" : "Choose a screenshot"}
              </span>
              {/* sr-only, NOT hidden. `display:none` removes the input from the
                  tab order, and "I've sent the tickets" stays disabled until
                  evidencePath is set — so a keyboard-only seller could not
                  complete the sale at all, and would be auto-refunded at the
                  24h deadline. CreateListingForm hit the same trap and fixed
                  it the same way. */}
              <input
                type="file"
                accept="image/jpeg,image/png,image/webp,image/heic,application/pdf"
                aria-label="Upload proof of transfer"
                className="sr-only"
                onChange={(e) => handlePick(e.target.files?.[0])}
              />
            </label>
          </section>

          <Alert tone="warning">
            Only mark this sent after you&apos;ve actually completed the transfer in the ticket
            platform. False confirmations put your payout and account at risk.
          </Alert>

          <Button
            variant="primary"
            size="lg"
            className="w-full"
            disabled={isPending || uploading || deliveryMissing || !evidencePath}
            onClick={handleSend}
            pending={isPending}
            pendingLabel="Marking sent…"
          >
            I&apos;ve sent the tickets
          </Button>
        </>
      ) : null}

      {transfer.status === "seller_sent" ? (
        <>
          <Alert tone="info">
            Tickets marked sent. Waiting for the buyer to confirm receipt.
          </Alert>
          <section className="rounded-panel bg-surface p-5">
            <h2 className="t-title text-ink">Payout</h2>
            {payoutParagraph ? <p className="t-body mt-2 text-ink-2">{payoutParagraph}</p> : null}
            <p className="t-body-sm mt-2 text-muted">
              If the buyer reports an issue, your payout is held pending review.
            </p>
          </section>
        </>
      ) : null}

      {stateAlert ? <Alert tone={stateAlert.tone}>{stateAlert.text}</Alert> : null}
    </div>
  );
}
