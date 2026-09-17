"use server";

import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { safeInternalPath } from "@/lib/auth/redirect";

export type LoginState = { error?: string; values?: { email?: string } };

function field(formData: FormData, key: string): string {
  const v = formData.get(key);
  return typeof v === "string" ? v.trim() : "";
}

export async function signInAction(_prev: LoginState, formData: FormData): Promise<LoginState> {
  const email = field(formData, "email").toLowerCase();
  const password = formData.get("password");
  const next = safeInternalPath(field(formData, "next") || null, "/");

  if (!email || typeof password !== "string" || !password) {
    return { error: "Enter your email and password.", values: { email } };
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) {
    // Generic on purpose: never reveal whether the account exists or is an operator.
    console.warn("[auth] signIn failed", { status: error.status, name: error.name });
    return { error: "Sign-in failed. Check your email and password.", values: { email } };
  }

  // Password sign-in yields aal1; the console requires aal2 everywhere.
  const { data } = await supabase.auth.getClaims();
  if (data?.claims?.aal === "aal2") redirect(next);
  redirect(`/mfa?next=${encodeURIComponent(next)}`);
}

export async function signOutAction(): Promise<void> {
  const supabase = await createSupabaseServerClient();
  await supabase.auth.signOut();
  redirect("/login");
}
