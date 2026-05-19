/**
 * src/utils/phone.ts
 *
 * Single source of truth for US phone-number handling.
 *
 * Storage convention
 *   The DB stores phone numbers as a clean 10-digit string with no
 *   formatting characters and no country-code prefix, e.g. "3055551234".
 *   The maskPhone() helper in app/(tabs)/profile.tsx already assumes a
 *   digits-only representation and is forward-compatible with this format.
 *
 * Why exact 10 digits (NANP, no +1)
 *   The marketplace currently operates only in Florida. Stripe Connect
 *   does its own international handling for seller payouts; this helper is
 *   for our local profile + ticket-delivery fields, both of which are
 *   US-only. Storing a +1 prefix adds 11 chars and inconsistent formatting
 *   without buying us anything.
 *
 * NANP sanity rules enforced
 *   - exactly 10 digits
 *   - area code first digit must be 2–9 (NANP reserves 0/1)
 *   - exchange (digits 4–6) first digit must be 2–9
 *
 * UX hand-off
 *   - normalizeUSPhone()    — paste-friendly: accepts "(305) 555-1234",
 *                             "305-555-1234", "+1 305 555 1234", "13055551234".
 *   - isValidUSPhone()      — strict boolean for gating Save / Submit.
 *   - formatPhoneDisplay()  — what users see while typing: "(305) 555-1234".
 *   - PHONE_DISPLAY_MAXLENGTH — pass to TextInput maxLength.
 */

/** Strip everything that's not a digit. */
export function digitsOnly(input: string): string {
  return (input ?? '').replace(/\D+/g, '');
}

/**
 * Coerce any user-typed or pasted phone input into a 0-10 digit string
 * suitable for internal state. Drops a leading "1" country-code prefix
 * for 11-digit inputs (so paste of "+1 305 555 1234" yields "3055551234")
 * and caps the result at 10 digits. Use this in TextInput onChangeText:
 *
 *   onChangeText={(v) => setPhone(toPhoneDigits(v))}
 */
export function toPhoneDigits(input: string | null | undefined): string {
  let d = digitsOnly(input ?? '');
  if (d.length === 11 && d.startsWith('1')) d = d.slice(1);
  return d.slice(0, 10);
}

/**
 * Normalize a US phone number to a clean 10-digit string, or null if the
 * input cannot be coerced into a valid US number.
 *
 * Accepted inputs:
 *   "(305) 555-1234"     → "3055551234"
 *   "305-555-1234"       → "3055551234"
 *   "305.555.1234"       → "3055551234"
 *   "+1 305 555 1234"    → "3055551234"
 *   "13055551234"        → "3055551234"
 *   "3055551234"         → "3055551234"
 *   "555-1234"           → null  (too short, not enough digits)
 *   "30555512345"        → null  (too long, no recognisable +1 prefix)
 *
 * Does NOT enforce NANP area-code rules — that's isValidUSPhone()'s job.
 * normalizeUSPhone() just gets the digits into a canonical shape; the
 * validator decides whether the canonical value is acceptable.
 */
export function normalizeUSPhone(input: string | null | undefined): string | null {
  if (!input) return null;
  const d = digitsOnly(input);
  if (d.length === 10) return d;
  if (d.length === 11 && d.startsWith('1')) return d.slice(1);
  return null;
}

/**
 * Strict NANP validation. Returns true if `input` represents a real US
 * phone number once normalized. Use this to enable/disable Save buttons
 * and to assert on the server-side guard.
 */
export function isValidUSPhone(input: string | null | undefined): boolean {
  const d = normalizeUSPhone(input);
  if (d === null) return false;
  // NANP: area code [2-9] [0-9] [0-9], exchange [2-9] [0-9] [0-9], subscriber 4 digits.
  return /^[2-9]\d{2}[2-9]\d{6}$/.test(d);
}

/**
 * Format a partially- or fully-typed phone number for display while the
 * user types. Strips non-digits first, then re-emits with the standard
 * US format. Caller should keep the user's internal value as digits-only
 * via onChangeText={(v) => setPhone(digitsOnly(v).slice(0, 10))}.
 *
 *   ""           → ""
 *   "3"          → "(3"
 *   "30"         → "(30"
 *   "305"        → "(305) "
 *   "3055"       → "(305) 5"
 *   "305555"     → "(305) 555"
 *   "3055551"    → "(305) 555-1"
 *   "3055551234" → "(305) 555-1234"
 *
 * For inputs longer than 10 digits, the extras are dropped so we never
 * render a malformed visual.
 */
export function formatPhoneDisplay(input: string | null | undefined): string {
  // Strip non-digits. If the user pasted an 11-digit number that starts
  // with the country code "1" (e.g. "+1 305 555 1234" → "13055551234"),
  // drop the leading "1" before formatting so we don't visually scramble
  // the area code (otherwise the display shows "(130) 555-5123").
  let d = digitsOnly(input ?? '');
  if (d.length === 11 && d.startsWith('1')) d = d.slice(1);
  d = d.slice(0, 10);

  if (d.length === 0)  return '';
  if (d.length < 4)    return `(${d}`;
  if (d.length === 6)  return `(${d.slice(0, 3)}) ${d.slice(3)}`;
  if (d.length < 7)    return `(${d.slice(0, 3)}) ${d.slice(3)}`;
  return `(${d.slice(0, 3)}) ${d.slice(3, 6)}-${d.slice(6)}`;
}

/**
 * Max length to set on TextInput. `(305) 555-1234` is 14 chars including
 * the parens, space, and hyphen. Anything longer is impossible under the
 * formatter above, but iOS keyboards can paste long strings — capping
 * maxLength avoids visual jitter while paste-handling normalizes.
 */
export const PHONE_DISPLAY_MAXLENGTH = 14;
