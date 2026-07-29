import "server-only";

import { LISTING_COLUMNS, type WebListing } from "@/lib/listings";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getAuthedUser } from "@/lib/auth/session";

export type SavedListing = {
  id: string;
  created_at: string;
  listing: WebListing | null; // null when the listing was deleted after saving
};

/**
 * Rendered on every listing card, so this fails closed (unsaved) rather than
 * throwing — a missing table or transient error must not break browsing.
 */
export async function isListingSaved(listingId: string): Promise<boolean> {
  const user = await getAuthedUser();
  if (!user) return false;

  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase
      .from("saved_listings")
      .select("id")
      .eq("user_id", user.id)
      .eq("listing_id", listingId)
      .maybeSingle();
    if (error) return false;
    return Boolean(data);
  } catch {
    return false;
  }
}

/** The signed-in user's saved listings, newest first. Empty when signed out. */
export async function listSavedListings(): Promise<SavedListing[]> {
  const user = await getAuthedUser();
  if (!user) return [];

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("saved_listings")
    .select(`id, created_at, listing:listings(${LISTING_COLUMNS})`)
    .eq("user_id", user.id)
    .order("created_at", { ascending: false });

  if (error) throw new Error(`saved_listings query failed: ${error.message}`);
  return ((data ?? []) as unknown as SavedListing[]).map((row) => ({
    ...row,
    listing: row.listing ?? null,
  }));
}

/** Used on the account overview card — fails closed to 0 rather than throwing. */
/**
 * Batch-fetches which of the given listing ids are saved by the current
 * user, in one query — used so a grid of cards doesn't fire one query per
 * card. Fails closed (empty set) rather than throwing.
 */
export async function getSavedListingIdSet(listingIds: string[]): Promise<Set<string>> {
  const user = await getAuthedUser();
  if (!user || listingIds.length === 0) return new Set();

  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase
      .from("saved_listings")
      .select("listing_id")
      .eq("user_id", user.id)
      .in("listing_id", listingIds);
    if (error || !data) return new Set();
    return new Set(data.map((row) => row.listing_id as string));
  } catch {
    return new Set();
  }
}

export async function savedListingsCount(): Promise<number> {
  const user = await getAuthedUser();
  if (!user) return 0;

  try {
    const supabase = await createSupabaseServerClient();
    const { count, error } = await supabase
      .from("saved_listings")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id);
    if (error) return 0;
    return count ?? 0;
  } catch {
    return 0;
  }
}
