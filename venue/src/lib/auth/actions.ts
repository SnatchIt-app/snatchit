"use server";

import { redirect } from "next/navigation";
import { createSupabaseServerClient, SupabaseConfigError } from "@/lib/supabase/server";
import { safeInternalPath } from "@/lib/auth/redirect";
import { DATA_SOURCE } from "@/lib/env";

export type LoginState = { error?: string; values?: { email?: string } };

function field(formData: FormData, key: string): string {
  const v = formData.get(key);
  return typeof v === "string" ? v.trim() : "";
}

/** Password sign-in. Reads in this slice need a session at any assurance level (no MFA gate on reads). */
export async function signInAction(_prev: LoginState, formData: FormData): Promise<LoginState> {
  if (DATA_SOURCE !== "database") return { error: "Sign-in is only used in database mode." };
  const email = field(formData, "email").toLowerCase();
  const password = formData.get("password");
  const next = safeInternalPath(field(formData, "next") || null, "/");
  if (!email || typeof password !== "string" || !password) return { error: "Enter your email and password.", values: { email } };

  let supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>;
  try {
    supabase = await createSupabaseServerClient();
  } catch (e) {
    return { error: e instanceof SupabaseConfigError ? `Database mode is not configured: ${e.message}` : "Sign-in unavailable.", values: { email } };
  }
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) {
    // Generic on purpose: never reveal whether the account exists or holds a grant.
    console.warn("[auth] signIn failed", { status: error.status, name: error.name });
    return { error: "Sign-in failed. Check your email and password.", values: { email } };
  }
  redirect(next);
}

export async function signOutAction(): Promise<void> {
  try {
    const supabase = await createSupabaseServerClient();
    await supabase.auth.signOut();
  } catch {
    // Config missing: nothing to sign out of.
  }
  redirect("/login");
}
