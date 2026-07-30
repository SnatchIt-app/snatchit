import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";

/**
 * US phone verification via Supabase's phone_change OTP flow — ported 1:1
 * from mobile's app/settings/verify-phone.tsx + src/utils/phone.ts.
 *
 *   1. supabase.auth.updateUser({ phone: '+1XXXXXXXXXX' }) → Supabase texts
 *      an OTP via Twilio (configured at the Supabase-project level; no
 *      provider code lives here).
 *   2. supabase.auth.verifyOtp({ phone, token, type: 'phone_change' }) →
 *      sets auth.users.phone + phone_confirmed_at.
 *
 * Server truth: auth.users.phone_confirmed_at, read by the RLS guard in
 * migration 038 via public.phone_verified(). Both calls operate on the
 * caller's own session (cookie-bound via createSupabaseServerClient) — the
 * Supabase Auth API takes no userId param for either, so callers here don't
 * need one either.
 *
 * Privacy: the number is used ONLY for verification. Never shown on public
 * profiles, never used for marketing.
 */

// NANP: exactly 10 digits; area code and exchange digit 1 can't be 0/1.
// Matches mobile's isValidUSPhone() exactly.
const NANP_RE = /^[2-9]\d{2}[2-9]\d{6}$/;

/**
 * Mirrors mobile's normalizeUSPhone() + isValidUSPhone(): strips
 * non-digits, drops a leading "1" country-code prefix for 11-digit input,
 * then requires the remaining 10 digits to satisfy NANP. Returns the
 * formatted +1XXXXXXXXXX string, or null if the input isn't a valid US
 * number.
 */
function toE164(rawPhone: string): string | null {
  const digits = rawPhone.replace(/\D+/g, "");
  const tenDigits =
    digits.length === 10 ? digits : digits.length === 11 && digits.startsWith("1") ? digits.slice(1) : null;
  if (!tenDigits || !NANP_RE.test(tenDigits)) return null;
  return `+1${tenDigits}`;
}

export type PhoneOtpResult = { error?: string };

/** Mirrors VerifyPhoneScreen.sendCode's supabase.auth.updateUser call exactly. */
export async function sendPhoneOtp(rawPhone: string): Promise<PhoneOtpResult> {
  const e164 = toE164(rawPhone);
  if (!e164) return { error: "Enter a valid US mobile number." };

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.updateUser({ phone: e164 });
  if (!error) return {};

  const msg = error.message;
  if (/rate|too many/i.test(msg)) return { error: "Too many attempts. Please wait a few minutes and try again." };
  return { error: msg };
}

/** Mirrors VerifyPhoneScreen.verifyCode's supabase.auth.verifyOtp call exactly. */
export async function verifyPhoneOtp(rawPhone: string, code: string): Promise<PhoneOtpResult> {
  const e164 = toE164(rawPhone);
  if (!e164) return { error: "Enter a valid US mobile number." };

  const token = code.trim();
  if (token.length !== 6) return { error: "Enter the 6-digit code from the text message." };

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.verifyOtp({ phone: e164, token, type: "phone_change" });
  if (!error) return {};

  const msg = error.message;
  if (/expired/i.test(msg)) return { error: "That code expired. Tap Resend to get a new one." };
  if (/invalid/i.test(msg)) return { error: "That code didn't match. Check the text and try again." };
  return { error: msg };
}
