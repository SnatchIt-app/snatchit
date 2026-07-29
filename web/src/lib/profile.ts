import "server-only";

import type { Profile } from "@snatchit/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getAuthedUser } from "@/lib/auth/session";

export type MyProfile = Pick<
  Profile,
  "id" | "full_name" | "display_name" | "phone_number" | "is_verified_buyer" | "is_verified_seller" | "created_at"
> & { email: string | null };

/** The signed-in user's own profile, or null if not authenticated. */
export async function getMyProfile(): Promise<MyProfile | null> {
  const user = await getAuthedUser();
  if (!user) return null;

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name, display_name, phone_number, is_verified_buyer, is_verified_seller, created_at")
    .eq("id", user.id)
    .maybeSingle();

  if (error || !data) return null;
  return { ...(data as Omit<MyProfile, "email">), email: user.email };
}
