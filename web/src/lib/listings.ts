import "server-only";

import { cache } from "react";
import type { Listing, Profile } from "@snatchit/types";
import { BUYER_FEE_RATE } from "@snatchit/core";
import { hasSupabaseEnv, STORAGE_BASE_URL } from "@/lib/env";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { FIXTURE_LISTINGS, FIXTURE_SELLER } from "@/lib/fixtures";

/** The listing fields the web UI consumes (subset of the shared Listing type). */
export type WebListing = Pick<
  Listing,
  | "id"
  | "seller_id"
  | "event_name"
  | "venue"
  | "neighborhood"
  | "category"
  | "status"
  | "auction_status"
  | "event_date"
  | "event_time"
  | "ticket_type"
  | "quantity"
  | "starting_bid"
  | "current_bid"
  | "buy_now_enabled"
  | "buy_now_price"
  | "cover_image_path"
  | "ends_at"
  | "bid_count"
  | "ticket_platform"
  | "transfer_method"
> & { created_at: string | null };

export type SellerSummary = Pick<
  Profile,
  "id" | "display_name" | "is_verified_seller" | "created_at"
>;

export const LISTING_COLUMNS =
  "id, seller_id, event_name, venue, neighborhood, category, status, auction_status, event_date, event_time, ticket_type, quantity, starting_bid, current_bid, buy_now_enabled, buy_now_price, cover_image_path, ends_at, bid_count, ticket_platform, transfer_method, created_at";

export type BrowseSort = "ending" | "newest" | "price_asc" | "price_desc";

export interface BrowseFilters {
  q?: string;
  category?: string;
  neighborhood?: string;
  /** 'buy_now' = Buy Now enabled; 'auction' = bidding only. */
  type?: "buy_now" | "auction";
  /** Max ALL-IN price in dollars (fee-inclusive, matching displayed prices). */
  maxPrice?: number;
  sort?: BrowseSort;
}

/**
 * Data source note (Phase 0 proof): filters run server-side through
 * PostgREST (.eq/.ilike/.lte) against the current small catalog. Before
 * production web scale this must move to the report's §13 search plan:
 * Postgres FTS (websearch_to_tsquery) + pg_trgm, cursor pagination, and the
 * `events` aggregation table. The public SELECT RLS policy powering this is
 * the same one the mobile feed uses.
 */
export async function getActiveListings(filters: BrowseFilters = {}, limit = 24): Promise<WebListing[]> {
  if (!hasSupabaseEnv) return applyFiltersLocally(FIXTURE_LISTINGS, filters);

  const supabase = await createSupabaseServerClient();
  let query = supabase
    .from("listings")
    .select(LISTING_COLUMNS)
    .eq("status", "active")
    .eq("auction_status", "active")
    .gt("ends_at", new Date().toISOString());

  if (filters.q) {
    const safe = filters.q.replace(/[,()%\\]/g, " ").trim();
    if (safe) query = query.or(`event_name.ilike.%${safe}%,venue.ilike.%${safe}%`);
  }
  if (filters.category) query = query.eq("category", filters.category);
  if (filters.neighborhood) query = query.eq("neighborhood", filters.neighborhood);
  if (filters.type === "buy_now") query = query.eq("buy_now_enabled", true);
  if (filters.type === "auction") query = query.eq("buy_now_enabled", false);
  if (filters.maxPrice && filters.maxPrice > 0) {
    // Displayed prices are all-in; convert the cap back to a base-price bound.
    query = query.lte("current_bid", Math.floor(filters.maxPrice / (1 + BUYER_FEE_RATE)));
  }

  switch (filters.sort) {
    case "newest":
      query = query.order("created_at", { ascending: false });
      break;
    case "price_asc":
      query = query.order("current_bid", { ascending: true });
      break;
    case "price_desc":
      query = query.order("current_bid", { ascending: false });
      break;
    case "ending":
    default:
      query = query.order("ends_at", { ascending: true });
      break;
  }

  const { data, error } = await query.limit(limit);
  if (error) throw new Error(`listings query failed: ${error.message}`);
  return (data ?? []) as WebListing[];
}

/** cache() dedupes the generateMetadata + page fetch into one query. */
export const getListing = cache(async (id: string): Promise<WebListing | null> => {
  if (!UUID_RE.test(id)) return null;
  if (!hasSupabaseEnv) return FIXTURE_LISTINGS.find((l) => l.id === id) ?? null;

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("listings")
    .select(LISTING_COLUMNS)
    .eq("id", id)
    .maybeSingle();
  if (error) throw new Error(`listing query failed: ${error.message}`);
  return (data as WebListing) ?? null;
});

export async function getSellerSummary(sellerId: string): Promise<SellerSummary | null> {
  if (!hasSupabaseEnv) return FIXTURE_SELLER.id === sellerId ? FIXTURE_SELLER : null;

  const supabase = await createSupabaseServerClient();
  const { data } = await supabase
    .from("profiles")
    .select("id, display_name, is_verified_seller, created_at")
    .eq("id", sellerId)
    .maybeSingle();
  return (data as SellerSummary) ?? null;
}

export async function getRelatedListings(listing: WebListing, limit = 4): Promise<WebListing[]> {
  const all = await getActiveListings({ category: listing.category }, limit + 1);
  const related = all.filter((l) => l.id !== listing.id);
  if (related.length < limit) {
    const fill = (await getActiveListings({}, limit + 4)).filter(
      (l) => l.id !== listing.id && !related.some((r) => r.id === l.id),
    );
    related.push(...fill);
  }
  return related.slice(0, limit);
}

export function coverImageUrl(path: string): string {
  return `${STORAGE_BASE_URL}/auction-media/${path}`;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function applyFiltersLocally(listings: WebListing[], f: BrowseFilters): WebListing[] {
  let out = listings.filter((l) => l.status === "active");
  if (f.q) {
    const q = f.q.toLowerCase();
    out = out.filter(
      (l) => l.event_name.toLowerCase().includes(q) || l.venue.toLowerCase().includes(q),
    );
  }
  if (f.category) out = out.filter((l) => l.category === f.category);
  if (f.neighborhood) out = out.filter((l) => l.neighborhood === f.neighborhood);
  if (f.type === "buy_now") out = out.filter((l) => l.buy_now_enabled);
  if (f.type === "auction") out = out.filter((l) => !l.buy_now_enabled);
  if (f.maxPrice) out = out.filter((l) => l.current_bid <= Math.floor(f.maxPrice! / (1 + BUYER_FEE_RATE)));
  switch (f.sort) {
    case "newest":
      out = [...out].sort((a, b) => (b.created_at ?? "").localeCompare(a.created_at ?? ""));
      break;
    case "price_asc":
      out = [...out].sort((a, b) => a.current_bid - b.current_bid);
      break;
    case "price_desc":
      out = [...out].sort((a, b) => b.current_bid - a.current_bid);
      break;
    default:
      out = [...out].sort((a, b) => a.ends_at.localeCompare(b.ends_at));
  }
  return out;
}
