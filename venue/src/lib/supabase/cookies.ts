import type { CookieOptionsWithName } from "@supabase/ssr";

/**
 * Attributes of the @supabase/ssr session cookies (sb-<ref>-auth-token[.N], access + refresh token).
 * Both SSR clients (server.ts and proxy.ts) use this one set, so a write, a refresh and a sign-out
 * clear always address the same cookie.
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
  return { path: "/", sameSite: "lax", secure: true, httpOnly: true };
}
