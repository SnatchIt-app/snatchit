"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getAuthedUser } from "@/lib/auth/session";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Both actions write ONLY read_at — the notifications table grants
// authenticated users column-level UPDATE on read_at alone (see migration
// 040); a client attempting to change title/body/type/link is rejected by
// Postgres regardless of what this code does.

export async function markNotificationReadAction(id: string): Promise<{ error?: string }> {
  if (!UUID_RE.test(id)) return { error: "Invalid notification." };
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase
    .from("notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("id", id)
    .eq("user_id", user.id);

  if (error) {
    console.error("[notifications] mark read failed", { code: error.code });
    return { error: "Couldn't update this notification." };
  }
  revalidatePath("/account/notifications");
  revalidatePath("/account");
  return {};
}

export async function markAllNotificationsReadAction(): Promise<{ error?: string }> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase
    .from("notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("user_id", user.id)
    .is("read_at", null);

  if (error) {
    console.error("[notifications] mark all read failed", { code: error.code });
    return { error: "Couldn't update your notifications." };
  }
  revalidatePath("/account/notifications");
  revalidatePath("/account");
  return {};
}
