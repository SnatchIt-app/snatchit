"use server";

import { redirect } from "next/navigation";
import { requireAuthedUser } from "@/lib/auth/session";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { callEdgeFunction } from "@/lib/edge-functions";

export type DeleteAccountResult = { error?: string };

/**
 * Mirrors app/settings/index.tsx executeDeleteAccount — same edge function,
 * same "cancel active listings, anonymize financial records, delete the
 * rest" server-side behavior. The double-confirmation happens client-side
 * (DeleteAccountButton) before this ever runs.
 */
export async function deleteAccountAction(): Promise<DeleteAccountResult> {
  await requireAuthedUser();

  const result = await callEdgeFunction("delete-account", {});
  if (result.error) return { error: result.error };

  const supabase = await createSupabaseServerClient();
  await supabase.auth.signOut();
  redirect("/");
}
