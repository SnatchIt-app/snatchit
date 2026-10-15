/**
 * Stripe Connect onboarding returns here (create-connect-account's STRIPE_CONNECT_RETURN_URL /
 * STRIPE_CONNECT_REFRESH_URL → https://app.snatchitapp.com/payout-return and /payout-refresh).
 * The same URLs serve web and native: the native app opens onboarding in an auth session whose
 * callback scheme is `snatchit`, so a link to these app routes closes it and lands in the app,
 * which re-checks the real status itself (C, 2026-10-15). Nothing here trusts the return.
 */
export const APP_PAYOUT_RETURN = "snatchit://payout-return";
export const APP_PAYOUT_REFRESH = "snatchit://payout-refresh";

/** Where a signed-out visitor continues on the web: log in, then the payout settings. */
export const PAYOUT_SETTINGS_PATH = "/account/settings";
export const PAYOUT_LOGIN_HREF = `/login?next=${encodeURIComponent(PAYOUT_SETTINGS_PATH)}`;

/**
 * Presentation only: phones and tablets are offered the app handoff; desktops get the web path.
 * Never used to redirect — the visitor chooses.
 */
export function isMobileUserAgent(ua: string | null | undefined): boolean {
  return typeof ua === "string" && /\b(iPhone|iPad|iPod|Android)\b/i.test(ua);
}
