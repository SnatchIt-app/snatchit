"use server";

import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { SITE_URL } from "@/lib/env";
import { safeInternalPath } from "@/lib/auth/redirect";
import {
  friendlyAuthError,
  isValidEmail,
  isValidPassword,
  validateSignUpFields,
  MIN_PASSWORD_LENGTH,
} from "@/lib/auth/validation";

export type ActionState = {
  error?: string;
  fieldErrors?: Record<string, string>;
  success?: boolean;
  message?: string;
  /** Non-sensitive field values to repopulate the form after a failed
   * round-trip — never include password fields here. */
  values?: Record<string, string>;
};

function str(formData: FormData, key: string): string {
  const v = formData.get(key);
  return typeof v === "string" ? v.trim() : "";
}

export async function signUpAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const firstName = str(formData, "firstName");
  const lastName = str(formData, "lastName");
  const email = str(formData, "email").toLowerCase();
  const password = formData.get("password");
  const confirmPassword = formData.get("confirmPassword");
  const acceptedTerms = formData.get("acceptedTerms") === "on";
  const next = safeInternalPath(str(formData, "next") || null, "/account");

  const fieldErrors = validateSignUpFields({
    firstName,
    lastName,
    email,
    password: typeof password === "string" ? password : "",
    confirmPassword: typeof confirmPassword === "string" ? confirmPassword : "",
    acceptedTerms,
  });
  if (Object.keys(fieldErrors).length > 0) {
    return { fieldErrors, values: { firstName, lastName, email } };
  }

  const fullName = `${firstName} ${lastName}`.trim();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.signUp({
    email,
    password: password as string,
    options: {
      data: { full_name: fullName, display_name: fullName },
      emailRedirectTo: `${SITE_URL}/auth/confirm?next=${encodeURIComponent(next)}`,
    },
  });

  if (error) {
    console.error("[auth] signUp failed", { status: error.status, name: error.name });
    return { error: friendlyAuthError(error.message), values: { firstName, lastName, email } };
  }

  // Email confirmation required (default project setting) — no session yet.
  if (!data.session) {
    return {
      success: true,
      message: "Check your email to confirm your account, then log in.",
    };
  }

  redirect(next);
}

export async function signInAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const email = str(formData, "email").toLowerCase();
  const password = formData.get("password");
  const next = safeInternalPath(str(formData, "next") || null, "/account");

  if (!isValidEmail(email) || typeof password !== "string" || !password) {
    return { error: "Enter your email and password.", values: { email } };
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) {
    console.error("[auth] signIn failed", { status: error.status, name: error.name });
    return { error: friendlyAuthError(error.message), values: { email } };
  }

  redirect(next);
}

export async function signOutAction(): Promise<void> {
  const supabase = await createSupabaseServerClient();
  await supabase.auth.signOut();
  redirect("/");
}

export async function requestPasswordResetAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const email = str(formData, "email").toLowerCase();
  // Generic response regardless of validity — never confirm/deny an account
  // exists. Only a clearly malformed email short-circuits (no network call).
  const generic: ActionState = {
    success: true,
    message: "If an account exists for that email, a reset link is on its way.",
  };
  if (!isValidEmail(email)) return generic;

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${SITE_URL}/auth/confirm?next=${encodeURIComponent("/reset-password")}`,
  });
  if (error) {
    console.error("[auth] resetPasswordForEmail failed", { status: error.status, name: error.name });
    if (error.message.toLowerCase().includes("rate limit")) {
      return { error: friendlyAuthError(error.message) };
    }
  }
  return generic;
}

export async function updateEmailAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const newEmail = str(formData, "newEmail").toLowerCase();
  if (!isValidEmail(newEmail)) return { fieldErrors: { newEmail: "Enter a valid email address." } };

  const supabase = await createSupabaseServerClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  if (!claimsData?.claims?.sub) return { error: "Your session expired. Log in again." };

  const { error } = await supabase.auth.updateUser(
    { email: newEmail },
    { emailRedirectTo: `${SITE_URL}/auth/confirm` },
  );
  if (error) {
    console.error("[auth] updateUser (email) failed", { status: error.status, name: error.name });
    return { error: friendlyAuthError(error.message) };
  }

  return {
    success: true,
    message: `Check ${newEmail} for a confirmation link to finish changing your email.`,
  };
}

export async function updatePasswordAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const password = formData.get("password");
  const confirmPassword = formData.get("confirmPassword");

  if (typeof password !== "string" || !isValidPassword(password)) {
    return { fieldErrors: { password: `Password must be at least ${MIN_PASSWORD_LENGTH} characters.` } };
  }
  if (password !== confirmPassword) {
    return { fieldErrors: { confirmPassword: "Passwords don't match." } };
  }

  const supabase = await createSupabaseServerClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  if (!claimsData?.claims?.sub) {
    return { error: "That link has expired or already been used. Request a new one." };
  }

  const { error } = await supabase.auth.updateUser({ password });
  if (error) {
    console.error("[auth] updateUser (password) failed", { status: error.status, name: error.name });
    return { error: friendlyAuthError(error.message) };
  }

  redirect("/login?reset=success");
}
