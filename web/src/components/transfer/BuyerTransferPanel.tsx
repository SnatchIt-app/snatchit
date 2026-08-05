"use client";

import { useEffect, useState, useTransition } from "react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import type { TransferView } from "@/lib/transfers";
import {
  confirmReceiptAction,
  disputeTransferAction,
  markViewedAction,
  setDeliveryInfoAction,
} from "@/lib/transfers-actions";
import { PlatformInstructions } from "@/components/transfer/PlatformInstructions";
import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";
import { Button } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";

export function BuyerTransferPanel({
  transfer,
  evidenceUrl,
  countdownLabel,
}: {
  transfer: TransferView;
  evidenceUrl: string | null;
  countdownLabel: string | null;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  const needsDelivery = !transfer.delivery_email && !transfer.delivery_phone;
  const wantsEmail = transfer.transfer_method === "email";
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");

  // Records that the buyer opened the transfer — feeds the BUYER_NEVER_VIEWED
  // payout-risk signal. Fire-and-forget, exactly as mobile does on mount.
  useEffect(() => {
    // Deliberately unawaited, but a rejection (offline, action transport
    // error) must not surface as an unhandled rejection — this signal is
    // best-effort and never worth interrupting the buyer for.
    markViewedAction(transfer.id).catch(() => {});
  }, [transfer.id]);

  function run(fn: () => Promise<{ ok?: true; error?: string; warning?: string }>) {
    setError(null);
    setNotice(null);
    startTransition(async () => {
      let result: { ok?: true; error?: string; warning?: string };
      try {
        result = await fn();
      } catch {
        // A server action that throws rejects here. Without this the buyer
        // would click "I got my tickets" and see nothing happen at all.
        setError("Something went wrong. Check your connection and try again.");
        return;
      }
      if (result.error === "AUTH_REQUIRED") {
        router.push(`/login?next=${encodeURIComponent(`/transfer/receive/${transfer.id}`)}`);
        return;
      }
      if (result.error) return setError(result.error);
      if (result.warning) setNotice(result.warning);
      router.refresh();
    });
  }

  return (
    <div className="space-y-5">
      {error ? <Alert tone="error">{error}</Alert> : null}
      {notice ? <Alert tone="success">{notice}</Alert> : null}

      {/* ── Delivery info gate ── */}
      {needsDelivery && (transfer.status === "pending" || transfer.status === "seller_sent") ? (
        <section className="border border-primary/20 bg-card p-5">
          <p className="eyebrow text-primary/80">Where should the tickets go?</p>
          <p className="mt-2 text-[13px] leading-relaxed text-white/60">
            The seller can&apos;t send until you add this. It&apos;s shared only with them, only
            for this transfer.
          </p>
          <form
            className="mt-4 space-y-4"
            onSubmit={(e) => {
              e.preventDefault();
              const em = wantsEmail ? email.trim() : "";
              const ph = wantsEmail ? "" : phone.replace(/\D/g, "");
              if (wantsEmail && !em) return setError("Enter the email your tickets should go to.");
              if (!wantsEmail && ph.length !== 10) return setError("Enter a valid 10-digit US phone number.");
              run(() => setDeliveryInfoAction(transfer.id, em || null, ph ? `+1${ph}` : null));
            }}
          >
            {wantsEmail ? (
              <Field label="Delivery email" htmlFor="delEmail">
                <Input
                  id="delEmail"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@example.com"
                  autoComplete="email"
                />
              </Field>
            ) : (
              <Field label="Delivery phone" htmlFor="delPhone" hint="The number on your ticket account.">
                <Input
                  id="delPhone"
                  type="tel"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder="(305) 555-1234"
                  inputMode="tel"
                />
              </Field>
            )}
            <Button type="submit" variant="primary" disabled={isPending}>
              {isPending ? "Saving…" : "Save delivery info"}
            </Button>
          </form>
        </section>
      ) : null}

      {/* ── Status-specific body ── */}
      {transfer.status === "pending" && !needsDelivery ? (
        <>
          <Alert tone="success">
            Waiting for the seller to send your tickets.
            {countdownLabel ? ` They have ${countdownLabel}.` : ""}
          </Alert>
          <PlatformInstructions
            platform={transfer.ticketPlatform}
            role="buyer"
            buyerEmail={transfer.delivery_email}
            buyerPhone={transfer.delivery_phone}
          />
        </>
      ) : null}

      {transfer.status === "seller_sent" ? (
        <>
          {evidenceUrl ? (
            <section className="border border-primary/20 bg-card p-5">
              <p className="eyebrow text-primary/80">Seller&apos;s proof</p>
              <p className="mt-2 text-[13px] text-white/60">Review this before confirming.</p>
              <a href={evidenceUrl} target="_blank" rel="noopener noreferrer" className="mt-4 block">
                <Image
                  src={evidenceUrl}
                  alt="Seller's transfer confirmation"
                  width={640}
                  height={480}
                  unoptimized
                  className="h-auto w-full border border-white/10 object-contain"
                />
              </a>
            </section>
          ) : null}

          <PlatformInstructions
            platform={transfer.ticketPlatform}
            role="buyer"
            buyerEmail={transfer.delivery_email}
            buyerPhone={transfer.delivery_phone}
          />

          <Alert tone="error">
            Confirming releases payment to the seller. Only confirm once you can actually see the
            tickets in your account.
          </Alert>

          <div className="flex flex-col gap-3 sm:flex-row">
            <Button
              variant="primary"
              className="flex-1"
              disabled={isPending}
              onClick={() => run(() => confirmReceiptAction(transfer.id))}
            >
              {isPending ? "Confirming…" : "I got my tickets"}
            </Button>
            <Button
              variant="secondary"
              className="flex-1"
              disabled={isPending}
              onClick={() => {
                if (!confirm("Report a problem? This freezes the transfer and notifies support.")) return;
                run(() => disputeTransferAction(transfer.id));
              }}
            >
              I haven&apos;t received them
            </Button>
          </div>
        </>
      ) : null}

      {transfer.status === "buyer_confirmed" || transfer.status === "auto_released" ? (
        <Alert tone="success">Transfer complete. Enjoy the show.</Alert>
      ) : null}

      {transfer.status === "disputed" ? (
        <Alert tone="error">
          Issue reported — our team typically reviews within 24 hours. Your payment stays on hold
          until it&apos;s resolved.
        </Alert>
      ) : null}

      {transfer.status === "expired" ? (
        <Alert tone="error">
          The seller didn&apos;t send in time, so this order was cancelled and refunded in full.
        </Alert>
      ) : null}
    </div>
  );
}
