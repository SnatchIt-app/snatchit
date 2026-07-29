"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getAuthedUser } from "@/lib/auth/session";

export type ToggleSaveResult = { saved: boolean; error?: string };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Toggles a listing's saved state for the current user. Returns the
 * resulting state so the caller doesn't have to guess; { error } means the
 * caller should redirect to login (unauthenticated) or show a retry.
 */
export async function toggleSaveAction(listingId: string, currentlySaved: boolean): Promise<ToggleSaveResult> {
  if (!UUID_RE.test(listingId)) return { saved: currentlySaved, error: "Invalid listing." };

  const user = await getAuthedUser();
  if (!user) return { saved: currentlySaved, error: "AUTH_REQUIRED" };

  const supabase = await createSupabaseServerClient();

  if (currentlySaved) {
    const { error } = await supabase
      .from("saved_listings")
      .delete()
      .eq("user_id", user.id)
      .eq("listing_id", listingId);
    if (error) {
      console.error("[favorites] unsave failed", { code: error.code });
      return { saved: true, error: "Couldn't remove this listing. Try again." };
    }
    revalidatePath("/account/saved");
    return { saved: false };
  }

  const { error } = await supabase
    .from("saved_listings")
    .insert({ user_id: user.id, listing_id: listingId })
    .select("id")
    .maybeSingle();
  // Unique violation = already saved (race between tabs/devices) — treat as success.
  if (error && error.code !== "23505") {
    console.error("[favorites] save failed", { code: error.code });
    return { saved: false, error: "Couldn't save this listing. Try again." };
  }
  revalidatePath("/account/saved");
  return { saved: true };
}
