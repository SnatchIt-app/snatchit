"use server";

import { revalidatePath } from "next/cache";
import { getAuthedUser } from "@/lib/auth/session";
import {
  confirmReceipt,
  disputeTransfer,
  getTransferForBuyer,
  getTransferForSeller,
  markTransferSent,
  markViewed,
  setDeliveryInfo,
  uploadTransferEvidence,
  type TransferResult,
} from "@/lib/transfers";
import { isOwnEvidencePath } from "@/lib/evidence-path";

export async function setDeliveryInfoAction(
  transferId: string,
  email: string | null,
  phone: string | null,
): Promise<TransferResult> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  // Ownership is enforced by the RPC (auth.uid() must be buyer_id); this is a
  // fast fail so we don't hand a raw Postgres error to the UI.
  const t = await getTransferForBuyer(user.id, transferId);
  if (!t) return { error: "This transfer no longer exists." };

  const result = await setDeliveryInfo(transferId, email, phone);
  if (result.ok) revalidatePath(`/transfer/receive/${transferId}`);
  return result;
}

export async function markViewedAction(transferId: string): Promise<void> {
  const user = await getAuthedUser();
  if (!user) return;
  await markViewed(transferId);
}

export async function uploadEvidenceAction(file: File): Promise<{ path?: string; error?: string }> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  return uploadTransferEvidence(user.id, file);
}

export async function markTransferSentAction(
  transferId: string,
  evidencePath: string,
): Promise<TransferResult> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };

  const t = await getTransferForSeller(user.id, transferId);
  if (!t) return { error: "This transfer no longer exists." };
  if (!evidencePath) return { error: "Upload a screenshot of the transfer confirmation first." };

  // evidencePath arrives from the client, so it cannot be trusted. Without this
  // a seller could pass any string — including another user's proof-docs path —
  // and clear the payout risk engine's EVIDENCE_MISSING signal without ever
  // uploading anything. Pin it to the exact shape uploadTransferEvidence
  // produces, under this seller's own uid prefix.
  if (!isOwnEvidencePath(user.id, evidencePath)) {
    return { error: "That evidence file could not be verified. Please upload it again." };
  }
  // Same gate mobile enforces: the seller cannot send until the buyer has said
  // where to send. Without it the seller transfers into a void.
  if (!t.delivery_email && !t.delivery_phone) {
    return { error: "The buyer hasn't provided their delivery details yet." };
  }

  const result = await markTransferSent(user.id, transferId, evidencePath);
  if (result.ok) {
    revalidatePath(`/transfer/send/${transferId}`);
    revalidatePath("/account/listings");
  }
  return result;
}

export async function confirmReceiptAction(transferId: string): Promise<TransferResult> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  const t = await getTransferForBuyer(user.id, transferId);
  if (!t) return { error: "This transfer no longer exists." };

  const result = await confirmReceipt(transferId);
  if (result.ok) {
    revalidatePath(`/transfer/receive/${transferId}`);
    revalidatePath("/account/purchases");
  }
  return result;
}

export async function disputeTransferAction(transferId: string): Promise<TransferResult> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  const t = await getTransferForBuyer(user.id, transferId);
  if (!t) return { error: "This transfer no longer exists." };

  const result = await disputeTransfer(user.id, transferId);
  if (result.ok) {
    revalidatePath(`/transfer/receive/${transferId}`);
    revalidatePath("/account/purchases");
  }
  return result;
}
