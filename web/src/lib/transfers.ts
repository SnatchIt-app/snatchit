import "server-only";

import { cache } from "react";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { callEdgeFunction } from "@/lib/edge-functions";
import {
  MIME_FOR_EXTENSION,
  evidenceStoragePath,
  validateEvidenceFile,
} from "@/lib/evidence-upload";

/**
 * Transfer lifecycle — the post-purchase leg.
 *
 * RULES (from the live schema + the 2026-08-03 payout incident). Breaking any
 * of these moves money incorrectly:
 *
 *  - NEVER write `transfers` directly from here. `authenticated` holds
 *    column-level UPDATE on every column and the RLS UPDATE policies only
 *    check party membership, so a direct .update() would bypass the state
 *    machine. Every mutation goes through the SECURITY DEFINER RPCs, exactly
 *    as mobile does.
 *  - NEVER touch payout_released_at / stripe_transfer_id. Payout is written
 *    once, atomically, by the edge functions.
 *  - Buyer confirmation goes through the `confirm-and-release` edge function,
 *    never confirm_transfer_received directly — the edge function owns the
 *    dispute rechecks, rate limit, and the Stripe idempotency key shared with
 *    the cron path.
 *  - A disputed transfer never pays out. Do not add any path that releases.
 *  - `expires_at` (24h) is the SELLER's deadline to send; `auto_release_at`
 *    (72h) is the BUYER's review window. Different clocks, different meaning.
 *
 * PII: only `display_name` is selected from the buyer/seller profile join.
 * profiles still has a public SELECT policy with full column grants (043 is
 * drafted but deliberately unapplied), so `select('*')` on that join would
 * leak phone, full_name, wallet_balance, stripe ids.
 */

export type TransferStatus =
  | "pending"
  | "seller_sent"
  | "buyer_confirmed"
  | "disputed"
  | "expired"
  | "auto_released"
  | "reversed";

const TRANSFER_COLUMNS =
  "id, listing_id, status, transfer_method, expires_at, auto_release_at, payout_released_at, payout_review_status, delivery_email, delivery_phone, transfer_evidence_path, seller_sent_at, buyer_confirmed_at, disputed_at, created_at";

export type TransferView = {
  id: string;
  listing_id: string;
  status: TransferStatus;
  transfer_method: string;
  expires_at: string | null;
  auto_release_at: string | null;
  payout_released_at: string | null;
  payout_review_status: string | null;
  delivery_email: string | null;
  delivery_phone: string | null;
  transfer_evidence_path: string | null;
  seller_sent_at: string | null;
  buyer_confirmed_at: string | null;
  disputed_at: string | null;
  created_at: string | null;
  counterpartyName: string | null;
  eventName: string;
  venue: string;
  ticketPlatform: string;
  coverImagePath: string;
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type Joined<T> = T | T[] | null | undefined;

type Row = Record<string, unknown> & {
  seller?: Joined<{ display_name: string | null }>;
  buyer?: Joined<{ display_name: string | null }>;
  listing?: Joined<{
    event_name: string;
    venue: string;
    ticket_platform: string;
    cover_image_path: string;
  }>;
};

/** PostgREST embeds come back as an object or a single-element array. */
function one<T>(v: Joined<T>): T | null {
  if (!v) return null;
  return Array.isArray(v) ? (v[0] ?? null) : v;
}

function shape(row: Row, side: "buyer" | "seller"): TransferView {
  const counterparty = one(side === "buyer" ? row.seller : row.buyer);
  const listing = one(row.listing);
  return {
    ...(row as unknown as Omit<TransferView, "counterpartyName" | "eventName" | "venue" | "ticketPlatform" | "coverImagePath">),
    counterpartyName: counterparty?.display_name ?? null,
    eventName: listing?.event_name ?? "Ticket",
    venue: listing?.venue ?? "",
    ticketPlatform: listing?.ticket_platform ?? "other",
    coverImagePath: listing?.cover_image_path ?? "",
  };
}

/** Buyer's own transfer. RLS also scopes this, the .eq is defence in depth. */
export const getTransferForBuyer = cache(async (userId: string, transferId: string): Promise<TransferView | null> => {
  if (!UUID_RE.test(transferId)) return null;
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase
    .from("transfers")
    .select(
      `${TRANSFER_COLUMNS}, seller:profiles!seller_id(display_name), listing:listings!listing_id(event_name, venue, ticket_platform, cover_image_path)`,
    )
    .eq("id", transferId)
    .eq("buyer_id", userId)
    .maybeSingle();
  return data ? shape(data as unknown as Row, "buyer") : null;
});

/** Seller's own transfer. */
export const getTransferForSeller = cache(async (userId: string, transferId: string): Promise<TransferView | null> => {
  if (!UUID_RE.test(transferId)) return null;
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase
    .from("transfers")
    .select(
      `${TRANSFER_COLUMNS}, buyer:profiles!buyer_id(display_name), listing:listings!listing_id(event_name, venue, ticket_platform, cover_image_path)`,
    )
    .eq("id", transferId)
    .eq("seller_id", userId)
    .maybeSingle();
  return data ? shape(data as unknown as Row, "seller") : null;
});

/** Buyer's purchase history — mirrors mobile's bids.tsx transfers query. */
export const getMyPurchases = cache(async (userId: string): Promise<TransferView[]> => {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("transfers")
    .select(
      `${TRANSFER_COLUMNS}, seller:profiles!seller_id(display_name), listing:listings!listing_id(event_name, venue, ticket_platform, cover_image_path)`,
    )
    .eq("buyer_id", userId)
    .order("created_at", { ascending: false });
  // Surface query failures instead of swallowing them. Returning [] here made
  // an RLS or outage failure render as "No purchases yet" / "No sales yet" —
  // a seller with real money in flight would be told they had sold nothing.
  if (error) throw new Error(`transfers query failed: ${error.message}`);
  return ((data ?? []) as unknown as Row[]).map((r) => shape(r, "buyer"));
});

/**
 * Short-lived signed URL for the seller's proof image. proof-docs is private;
 * the "transfer party read" policy lets both parties read this specific path.
 */
export async function getEvidenceUrl(path: string): Promise<string | null> {
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.storage.from("proof-docs").createSignedUrl(path, 3600);
  return data?.signedUrl ?? null;
}

export type TransferResult = { ok?: true; error?: string; warning?: string };

function mapTransferError(msg: string): string {
  if (msg.includes("Only the seller")) return "Only the seller can mark tickets as sent.";
  if (msg.includes("Only the buyer")) return "Only the buyer can do that.";
  if (msg.includes("current status")) return "This transfer has already moved on. Refresh the page.";
  if (msg.includes("Transfer not found")) return "This transfer no longer exists.";
  if (msg.includes("under review") || msg.includes("dispute")) {
    return "This order is under review. Payout is frozen until it's resolved.";
  }
  return msg;
}

/** Buyer supplies where the tickets should be sent. Gates the seller's send. */
export async function setDeliveryInfo(
  transferId: string,
  email: string | null,
  phone: string | null,
): Promise<TransferResult> {
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("set_transfer_delivery_info", {
    p_transfer_id: transferId,
    p_delivery_email: email,
    p_delivery_phone: phone,
  });
  if (error) return { error: mapTransferError(error.message) };
  return { ok: true };
}

/** Fire-and-forget — feeds the BUYER_NEVER_VIEWED payout risk signal. */
export async function markViewed(transferId: string): Promise<void> {
  const supabase = await createSupabaseServerClient();
  await supabase.rpc("mark_transfer_viewed", { p_transfer_id: transferId });
}

/**
 * Seller's evidence upload. Path shape is required by the proof-docs insert
 * policy (053), which scopes writes to `<userId>/`.
 *
 * Type, size and extension are validated by evidence-upload.ts. This used to
 * accept anything: contentType came straight from file.type and the storage
 * key took its extension from the client filename, so an HTML or SVG file
 * uploaded as evidence would later be handed to the buyer as a signed URL and
 * rendered — stored XSS on the storage origin. The extension now comes from
 * the validated MIME type, so a filename cannot smuggle one through.
 */
export async function uploadTransferEvidence(
  userId: string,
  file: File,
): Promise<{ path?: string; error?: string }> {
  const check = validateEvidenceFile(file.type, file.size);
  if (!check.ok) return { error: check.error };

  const path = evidenceStoragePath(userId, check.extension, Date.now());
  const supabase = await createSupabaseServerClient();
  const bytes = new Uint8Array(await file.arrayBuffer());
  const { error } = await supabase.storage.from("proof-docs").upload(path, bytes, {
    // Normalised from the allow-list, not echoed from the client, so the
    // stored object can never be served as text/html.
    contentType: MIME_FOR_EXTENSION[check.extension] ?? "application/octet-stream",
    upsert: false,
    cacheControl: "3600",
  });
  if (error) return { error: error.message };
  return { path };
}

/**
 * pending -> seller_sent.
 *
 * All THREE keys are always sent: mark_transfer_sent has a 2-arg legacy
 * overload, and PostgREST picks the overload by exact key set. Omitting
 * p_transfer_evidence_path silently hits the 2-arg version, dropping the
 * evidence write — which then classifies the payout as EVIDENCE_MISSING /
 * HIGH risk and diverts it to manual review.
 */
export async function markTransferSent(
  userId: string,
  transferId: string,
  evidencePath: string,
): Promise<TransferResult> {
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("mark_transfer_sent", {
    p_transfer_id: transferId,
    p_user_id: userId,
    p_transfer_evidence_path: evidencePath,
  });
  if (error) return { error: mapTransferError(error.message) };
  return { ok: true };
}

/**
 * Buyer confirms receipt, which also releases the payout.
 *
 * Goes through the confirm-and-release edge function (server-to-server — its
 * CORS allowlist is snatchitapp.com only). That function owns the dispute
 * rechecks and the Stripe idempotency key shared with the cron path.
 *
 * Critical: once confirmation is recorded, a payout problem is an ops issue,
 * never a buyer-facing failure. `payout_status: 'pending_review'` is SUCCESS.
 */
export async function confirmReceipt(transferId: string): Promise<TransferResult> {
  type ConfirmResponse = {
    success?: boolean;
    already_released?: boolean;
    payout_status?: string;
    warning?: string;
  };

  let res: ConfirmResponse & { error?: string };
  try {
    res = await callEdgeFunction<ConfirmResponse>("confirm-and-release", { transfer_id: transferId });
  } catch (e) {
    // callEdgeFunction THROWS on a missing session, missing env, or a network
    // failure — it only returns { error } for non-2xx responses. A server
    // action that throws reaches the client as an opaque rejection, so the
    // buyer would get no feedback at all on the one action that moves money.
    // Convert to the standard result shape, keeping the AUTH_REQUIRED
    // convention so the panel redirects to login instead of showing an error.
    const msg = e instanceof Error ? e.message : "";
    if (msg === "No active session") return { error: "AUTH_REQUIRED" };
    return {
      error: "We couldn't reach the confirmation service. Nothing was charged or released — please try again.",
    };
  }

  if (res.error) return { error: mapTransferError(res.error) };
  if (res.payout_status === "pending_review") {
    return { ok: true, warning: "Receipt confirmed. The seller's payout is queued for a routine review." };
  }
  return { ok: true, warning: res.warning };
}

/** seller_sent -> disputed. Mobile sends only the id; reason stays null. */
export async function disputeTransfer(userId: string, transferId: string): Promise<TransferResult> {
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("buyer_dispute_transfer", {
    p_transfer_id: transferId,
    p_user_id: userId,
  });
  if (error) return { error: mapTransferError(error.message) };
  return { ok: true };
}
