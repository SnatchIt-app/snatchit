import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getAuthedUser } from "@/lib/auth/session";

export type AppNotification = {
  id: string;
  type: string;
  title: string;
  body: string | null;
  link: string | null;
  read_at: string | null;
  created_at: string;
};

const COLUMNS = "id, type, title, body, link, read_at, created_at";

/** Newest first, capped at 50 — this is an inbox view, not a full archive. */
export async function listMyNotifications(): Promise<AppNotification[]> {
  const user = await getAuthedUser();
  if (!user) return [];

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("notifications")
    .select(COLUMNS)
    .eq("user_id", user.id)
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) throw new Error(`notifications query failed: ${error.message}`);
  return (data ?? []) as AppNotification[];
}

/**
 * Rendered in the global header on every page, so this fails closed (0, no
 * badge) rather than throwing — a missing table or transient query error
 * must never take down navigation on pages that have nothing to do with
 * notifications.
 */
export async function unreadNotificationCount(): Promise<number> {
  const user = await getAuthedUser();
  if (!user) return 0;

  try {
    const supabase = await createSupabaseServerClient();
    const { count, error } = await supabase
      .from("notifications")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .is("read_at", null);
    if (error) return 0;
    return count ?? 0;
  } catch {
    return 0;
  }
}
