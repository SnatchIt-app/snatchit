/**
 * Fixed sign-in and access-check wording. Nothing here echoes server or URL
 * text back to the page, and nothing reveals whether an account exists.
 */

/** Sign-in failure copy by HTTP status: an outage is not the operator's mistake. */
export function signInErrorMessage(status: number | undefined): string {
  if (status === undefined || status === 0 || status >= 500) return "Sign-in is unavailable right now. Try again in a moment.";
  return "Sign-in failed. Check your email and password.";
}

/** Why the operator check could not complete — codes carried in /denied?reason=. */
export const DENIED_REASONS = {
  unavailable: "The console's database could not be reached.",
  check_failed: "The access check returned an error.",
} as const;
export type DeniedReason = keyof typeof DENIED_REASONS;

export function deniedReasonCode(failure: { unavailable?: boolean }): DeniedReason {
  return failure.unavailable ? "unavailable" : "check_failed";
}

/** The text for a reason code. Anything else in the URL (old links, crafted text) gets the generic line — never itself. */
export function deniedReasonText(reason: string | undefined): string {
  return reason && Object.hasOwn(DENIED_REASONS, reason) ? DENIED_REASONS[reason as DeniedReason] : DENIED_REASONS.check_failed;
}
