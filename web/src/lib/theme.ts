/**
 * Appearance preference — the web twin of the native Settings → Appearance
 * screen (System / Light / Dark). Stored in a first-party cookie so the server
 * renders the right theme on the first byte (no flash), and read on the
 * client to update <html data-theme> immediately when the user changes it.
 */
export const THEME_COOKIE = "sn-theme";
export const THEME_PREFERENCES = ["system", "light", "dark"] as const;
export type ThemePreference = (typeof THEME_PREFERENCES)[number];

/** Anything unknown — a missing cookie, a stale value, a tampered one — is "system". */
export function parseThemePreference(value: string | null | undefined): ThemePreference {
  return (THEME_PREFERENCES as readonly string[]).includes(value ?? "") ? (value as ThemePreference) : "system";
}

/** One year, first-party, readable by the page script that applies it. */
export function themeCookieString(pref: ThemePreference): string {
  return `${THEME_COOKIE}=${pref}; Path=/; Max-Age=31536000; SameSite=Lax`;
}
