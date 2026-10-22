import type { CookieOptionsWithName } from "@supabase/ssr";

/**
 * The venue session cookie's name. @supabase/ssr's default is sb-<first host label of the Supabase URL>-auth-token,
 * which admin uses too. In production the apps are on different hosts, but on localhost both run on host localhost
 * (admin :3200, venue :3300; browsers do not separate cookies by port) against the same Supabase URL, so the default
 * name made the venue's HttpOnly cookie take the place of admin's, whose MFA runs in the browser and must read it.
 * @supabase/ssr turns cookieOptions.name into the auth storageKey, so the session is stored as
 * sb-venue-auth-token[.N] (and sb-venue-auth-token-code-verifier for PKCE) by both SSR clients alike. The
 * acceptance kit's /^sb-.+-auth-token(\.\d+)?$/ still matches it.
 */
export const SESSION_COOKIE_NAME = "sb-venue-auth-token";

/**
 * Name and attributes of the @supabase/ssr session cookies (access + refresh token).
 * Both SSR clients (server.ts and proxy.ts) use this one set, so a write, a refresh and a sign-out
 * clear always address the same cookie.
 *   - name: the venue's own (above), never admin's.
 *   - secure: never sent over plain http, not even on a first request typed without https.
 *     Chrome treats localhost over plain http as a secure context, so a local `next start`
 *     and the acceptance kit keep working.
 *   - httpOnly: no script can read the refresh token. Nothing in the browser needs it: every
 *     Supabase call is server-side, and tests/domain-readiness.test.ts fails if client code
 *     starts reading the session.
 *   - sameSite lax and path /. No domain on purpose: the cookies stay host-only and are never
 *     shared with admin.snatchitapp.com, snatchitapp.com or any other sibling host.
 */
export function sessionCookieOptions(): CookieOptionsWithName {
  return { name: SESSION_COOKIE_NAME, path: "/", sameSite: "lax", secure: true, httpOnly: true };
}
