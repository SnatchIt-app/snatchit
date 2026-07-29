"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireAuthedUser } from "@/lib/auth/session";
import type { ActionState } from "@/lib/auth/actions";

const DISPLAY_NAME_MAX = 50;
const FULL_NAME_MAX = 100;
const PHONE_MAX = 20;

function str(formData: FormData, key: string): string {
  const v = formData.get(key);
  return typeof v === "string" ? v.trim() : "";
}

/** Editable fields only: display_name, full_name, phone_number. Everything
 * else on `profiles` (verification flags, Stripe fields, admin flags, wallet
 * balance) is server/trigger/webhook-owned and never client-writable here. */
export async function updateProfileAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  let user;
  try {
    user = await requireAuthedUser();
  } catch {
    return { error: "Your session expired. Log in again." };
  }

  const fullName = str(formData, "fullName");
  const displayName = str(formData, "displayName");
  const phoneNumber = str(formData, "phoneNumber");

  const fieldErrors: Record<string, string> = {};
  if (fullName.length > FULL_NAME_MAX) fieldErrors.fullName = `Keep it under ${FULL_NAME_MAX} characters.`;
  if (!displayName) fieldErrors.displayName = "Display name can't be empty.";
  if (displayName.length > DISPLAY_NAME_MAX) {
    fieldErrors.displayName = `Keep it under ${DISPLAY_NAME_MAX} characters.`;
  }
  if (phoneNumber.length > PHONE_MAX) fieldErrors.phoneNumber = `Keep it under ${PHONE_MAX} characters.`;
  if (Object.keys(fieldErrors).length > 0) return { fieldErrors };

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase
    .from("profiles")
    .update({
      full_name: fullName || null,
      display_name: displayName,
      phone_number: phoneNumber || null,
    })
    .eq("id", user.id);

  if (error) {
    console.error("[profile] update failed", { code: error.code });
    return { error: "Couldn't save your changes. Please try again." };
  }

  revalidatePath("/account/profile");
  revalidatePath("/account");
  return { success: true, message: "Profile updated." };
}
