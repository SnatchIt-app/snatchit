import "server-only";

import { APP_CONFIG } from "@snatchit/core";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getPayoutStatus, type PayoutStatus } from "@/lib/payouts";

export type RiskGate = { allowed: boolean; reason: string; riskTier: string | null };

export type ListingGates = {
  phoneVerified: boolean;
  payoutStatus: PayoutStatus;
  risk: RiskGate;
};

type RiskRow = { allowed: boolean; reason: string; risk_tier: string | null };

/**
 * Mirrors the three pre-flight checks CreateListingScreen.handlePublish runs
 * (phone, payout, risk tier) — phone and payout are UX previews of the same
 * conditions the live listings INSERT RLS policy enforces
 * (seller_id = auth.uid() AND profiles.stripe_onboarding_complete AND
 * phone_verified()); risk is the advisory, RLS-unenforced can_create_listing
 * RPC, which fails open on error same as mobile.
 */
export async function getListingGates(userId: string): Promise<ListingGates> {
  const supabase = await createSupabaseServerClient();
  const [{ data: userData }, payout, riskResult] = await Promise.all([
    supabase.auth.getUser(),
    getPayoutStatus(),
    supabase.rpc("can_create_listing", { p_seller_id: userId }),
  ]);

  const riskRows = riskResult.data as RiskRow[] | null;
  const risk = riskRows?.[0];

  return {
    phoneVerified: userData.user?.phone_confirmed_at != null,
    payoutStatus: payout.status,
    risk: risk
      ? { allowed: risk.allowed, reason: risk.reason, riskTier: risk.risk_tier }
      : { allowed: true, reason: "ok", riskTier: null },
  };
}

const IMAGE_BUCKETS = {
  cover: { bucket: "auction-media", folder: "covers" },
  proof: { bucket: "proof-docs", folder: "proofs" },
} as const;

export type ImageKind = keyof typeof IMAGE_BUCKETS;

/** Mirrors useImageUpload.ts: <userId>/<folder>/<timestamp>.<ext> path convention. */
export async function uploadListingImage(
  userId: string,
  kind: ImageKind,
  file: File,
): Promise<{ path?: string; error?: string }> {
  if (!(APP_CONFIG.ALLOWED_IMAGE_TYPES as readonly string[]).includes(file.type)) {
    return { error: "Unsupported image type. Use JPEG, PNG, WEBP, or HEIC." };
  }
  if (file.size > APP_CONFIG.MAX_IMAGE_SIZE_MB * 1024 * 1024) {
    return { error: `Image must be under ${APP_CONFIG.MAX_IMAGE_SIZE_MB}MB.` };
  }

  const { bucket, folder } = IMAGE_BUCKETS[kind];
  const ext = file.name.split(".").pop() || "jpg";
  const path = `${userId}/${folder}/${Date.now()}.${ext}`;

  const supabase = await createSupabaseServerClient();
  const bytes = new Uint8Array(await file.arrayBuffer());
  const { error } = await supabase.storage.from(bucket).upload(path, bytes, {
    contentType: file.type,
    upsert: false,
    cacheControl: "3600",
  });
  if (error) return { error: error.message };
  return { path };
}

export type CreateListingPayload = {
  eventName: string;
  venue: string;
  neighborhood: string;
  category: string;
  eventDate: string; // "YYYY-MM-DD"
  eventTime: string; // "HH:MM:SS"
  ticketType: string;
  quantity: number;
  transferMethod: string;
  restrictions: string | null;
  startingBid: number;
  buyNowEnabled: boolean;
  buyNowPrice: number | null;
  durationHours: number;
  ticketPlatform: string;
  coverImagePath: string;
  proofImagePath: string;
  sellerCommitmentAccepted: boolean;
};

function mapListingError(msg: string): string {
  if (msg.includes("row-level security") || msg.includes("permission denied")) {
    return "You don't have permission to create a listing yet — make sure your phone is verified and payouts are set up.";
  }
  return msg;
}

/** Mirrors CreateListingScreen.handlePublish's insert exactly — direct table insert, no RPC. */
export async function createListing(
  sellerId: string,
  p: CreateListingPayload,
): Promise<{ id?: string; error?: string }> {
  const supabase = await createSupabaseServerClient();
  const endsAt = new Date(Date.now() + p.durationHours * 3_600_000);

  const { data, error } = await supabase
    .from("listings")
    .insert({
      seller_id: sellerId,
      event_name: p.eventName.trim(),
      venue: p.venue.trim(),
      neighborhood: p.neighborhood,
      event_date: p.eventDate,
      event_time: p.eventTime,
      ticket_type: p.ticketType,
      quantity: p.quantity,
      transfer_method: p.transferMethod,
      restrictions: p.restrictions?.trim() || null,
      starting_bid: p.startingBid,
      buy_now_enabled: p.buyNowEnabled,
      buy_now_price: p.buyNowEnabled ? p.buyNowPrice : null,
      duration_hours: p.durationHours,
      ends_at: endsAt.toISOString(),
      current_bid: p.startingBid,
      cover_image_path: p.coverImagePath,
      ticket_platform: p.ticketPlatform,
      proof_of_ownership_path: p.proofImagePath,
      seller_commitment_accepted_at: p.sellerCommitmentAccepted ? new Date().toISOString() : null,
      category: p.category,
    })
    .select("id")
    .single();

  if (error) return { error: mapListingError(error.message) };
  return { id: (data as { id: string }).id };
}
