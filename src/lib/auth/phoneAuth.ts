/**
 * src/lib/auth/phoneAuth.ts — the phone OTP contract, expressed as pure functions.
 *
 * WHAT THIS IS NOT: it is not an SMS implementation. Snatch It already sends codes
 * through Supabase Auth (provider `twilio_verify`, phone provider enabled,
 * `phone_autoconfirm` false, so a code is always really checked server side). The
 * screens call `signInWithOtp` / `verifyOtp` / `updateUser({ phone })` directly.
 * What lives here is everything around those calls that is worth testing without a
 * network: the number format the provider expects, the mask we show back, and the
 * mapping from a provider error to a sentence a person can act on.
 *
 * ACCOUNT SAFETY. Sign in sends `shouldCreateUser: false`. A number with no account
 * then comes back as `otp_disabled` and NOTHING is created. That is the whole reason
 * `classifyOtpError` exists: the screen must be able to tell "no account here, go and
 * sign up" apart from "that code was wrong", and it must never read a create-user
 * response as a successful sign in.
 */

import { normalizeUSPhone } from '@/src/utils/phone';

/** Matches the cooldown the shipped settings/verify-phone screen already uses. */
export const RESEND_COOLDOWN_S = 30;

/** Miami launch is US only, so the country code is fixed rather than picked. */
export const DEFAULT_COUNTRY_CODE = '+1';

/** Sign in leads with the phone; email and password stay as the second way in. */
export type SignInMethod = 'phone' | 'email';
export const DEFAULT_SIGN_IN_METHOD: SignInMethod = 'phone';

/** The two states of the phone path. Verification is a step, not a screen. */
export type PhoneSignInStep = 'enter_phone' | 'enter_code';

/**
 * The E.164 string Supabase Auth expects, or null when the digits are not a valid
 * US mobile number. Everything that talks to the provider goes through here, so a
 * screen can never send a half-typed number.
 */
export function toE164US(input: string | null | undefined): string | null {
  const d = normalizeUSPhone(input);
  if (d === null) return null;
  // Same NANP rule the profile fields enforce, so one number cannot be valid in
  // one part of the app and invalid in another.
  if (!/^[2-9]\d{2}[2-9]\d{6}$/.test(d)) return null;
  return `${DEFAULT_COUNTRY_CODE}${d}`;
}

/**
 * What the verification step shows back: enough for the person to recognise their
 * own number, not enough to expose it to someone reading over their shoulder.
 *
 *   "+13055551234" -> "••• ••• 1234"
 */
export function maskE164(e164: string | null | undefined): string {
  const digits = (e164 ?? '').replace(/\D+/g, '');
  const last4 = digits.slice(-4);
  if (last4.length < 4) return '••• ••• ••••';
  return `••• ••• ${last4}`;
}

/** Why an OTP call failed, in product terms rather than provider terms. */
export type OtpFailure =
  | 'unknown_account'
  | 'invalid_number'
  | 'number_taken'
  | 'send_failed'
  | 'wrong_code'
  | 'expired_code'
  | 'rate_limited'
  | 'network'
  | 'unknown';

type ProviderError = { code?: string | null; message?: string | null; status?: number | null } | null | undefined;

/**
 * Map a Supabase Auth error onto an `OtpFailure`.
 *
 * `stage` matters because the provider reuses codes: `otp_expired` covers both a
 * wrong code and a stale one, and only the send stage can report "no account".
 * Codes are read first and the message text second, because the string is the part
 * that changes between provider releases.
 */
export function classifyOtpError(err: ProviderError, stage: 'send' | 'verify'): OtpFailure {
  const code = (err?.code ?? '').toLowerCase();
  const msg = (err?.message ?? '').toLowerCase();

  // Rate limiting comes back on both stages and must never read as a bad code.
  if (code.includes('rate_limit') || /rate limit|too many|for security purposes/.test(msg)) return 'rate_limited';

  if (/network request failed|fetch failed|timed out|timeout/.test(msg)) return 'network';

  if (stage === 'send') {
    // shouldCreateUser:false + a number with no account. Nothing was created.
    if (code === 'otp_disabled' || /signups not allowed for otp/.test(msg)) return 'unknown_account';
    if (code === 'phone_exists' || /already registered|already been registered/.test(msg)) return 'number_taken';
    if (code === 'validation_failed' || /invalid phone|invalid format|unable to validate phone/.test(msg)) return 'invalid_number';
    if (code === 'sms_send_failed' || /error sending|sms/.test(msg)) return 'send_failed';
    return 'unknown';
  }

  if (code === 'otp_expired' || /expired/.test(msg)) return 'expired_code';
  if (/invalid|incorrect|token has expired or is invalid|does not match/.test(msg)) return 'wrong_code';
  return 'unknown';
}

/**
 * The sentence shown to the person. Short, plain, and free of provider names,
 * error codes and system text. No em dash anywhere in this map.
 */
export function otpErrorCopy(failure: OtpFailure): string {
  switch (failure) {
    case 'unknown_account':  return "This number isn't linked to an account.";
    case 'invalid_number':   return 'Enter a valid US mobile number.';
    case 'number_taken':     return 'That number is already on another account.';
    case 'send_failed':      return "We couldn't send the code. Try again.";
    case 'wrong_code':       return "That code didn't match. Check the text and try again.";
    case 'expired_code':     return 'That code expired. Send a new one.';
    case 'rate_limited':     return 'Too many attempts. Wait a few minutes and try again.';
    case 'network':          return 'Connection problem. Check your signal and try again.';
    default:                 return 'Something went wrong. Please try again.';
  }
}

/** True when the number has no account, so the screen can offer Sign up instead. */
export function isUnknownAccount(err: ProviderError): boolean {
  return classifyOtpError(err, 'send') === 'unknown_account';
}

/** Resend is available only once the cooldown has run out. */
export function canResend(cooldownRemaining: number, busy: boolean): boolean {
  return !busy && cooldownRemaining <= 0;
}

/** The label the resend control carries, so the wait is visible rather than implied. */
export function resendLabel(cooldownRemaining: number): string {
  return cooldownRemaining > 0 ? `Resend code in ${cooldownRemaining}s` : 'Resend code';
}
