import "server-only";

import { createClient } from "@supabase/supabase-js";
import { SUPABASE_ANON_KEY, SUPABASE_URL } from "@/lib/env";

/**
 * Auth emails the web sends (sign-up confirmation, password reset, email change) have to work
 * wherever the person opens them: on another device, or in another browser on the same phone
 * (Gmail handing the link to Safari, an in-app browser, a different desktop browser).
 *
 * The SSR clients cannot do that. @supabase/ssr forces the PKCE flow, and a PKCE link only
 * completes in the browser that requested it, because the code verifier lives in that browser's
 * cookies. Opened anywhere else, GoTrue verifies the token, redirects with ?code=, and the page
 * has nothing to exchange it with: "Link expired" (owner, iPhone, 2026-10-14; auth logs show the
 * verify succeeded and no /token exchange followed).
 *
 * So these three requests use the implicit flow. GoTrue still checks the one-time token, its
 * expiry and single use at /auth/v1/verify; on success it hands the session to /auth/confirm in
 * the URL fragment, which needs no browser state, and the page stores it as cookies. The email
 * templates are unchanged ({{ .ConfirmationURL }}), so the native app's snatchit:// links are too.
 */
export function emailLinkAuth() {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error("Supabase env missing — check NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY");
  }
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { flowType: "implicit", persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  }).auth;
}

export type EmailLinkResult = { error: { message: string; status?: number; name: string } | null };

/**
 * Starts an email change for the signed-in person, implicit flow. GoTrue authenticates the access
 * token; no session is created, refreshed or rotated here (setSession on a second client would
 * rotate the refresh token and sign the person out of the cookie session).
 */
export async function requestEmailChange(
  accessToken: string,
  newEmail: string,
  redirectTo: string,
): Promise<EmailLinkResult> {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error("Supabase env missing — check NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY");
  }
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user?redirect_to=${encodeURIComponent(redirectTo)}`, {
    method: "PUT",
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ email: newEmail }),
    cache: "no-store",
  });
  if (res.ok) return { error: null };
  let message = `Email change failed (${res.status})`;
  try {
    const body = (await res.json()) as { msg?: string; message?: string; error_description?: string };
    message = body.msg ?? body.message ?? body.error_description ?? message;
  } catch {
    /* keep the status message */
  }
  return { error: { message, status: res.status, name: "AuthApiError" } };
}
