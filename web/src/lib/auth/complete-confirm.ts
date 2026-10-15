import type { SupabaseClient } from "@supabase/supabase-js";
import type { ConfirmLink } from "@/lib/auth/confirm-link";
import { safeInternalPath } from "@/lib/auth/redirect";

type Auth = Pick<SupabaseClient["auth"], "setSession" | "verifyOtp" | "initialize" | "getSession">;
type OtpType = "signup" | "recovery" | "email" | "email_change" | "invite" | "magiclink";

export type ConfirmOutcome =
  | { status: "signed_in"; route: string }
  | { status: "first_confirmation" }
  | { status: "invalid" };

/**
 * What /auth/confirm does with an email link, given the browser auth client. Pure apart from the
 * client, so the page's real behaviour is testable against auth-js.
 *   implicit   — the session came in the fragment (web emails; any device): setSession, which
 *                checks the token with the server before storing it
 *   token_hash — verifyOtp
 *   pkce       — the client exchanged ?code= while initialising (same browser only)
 */
export async function completeConfirm(link: ConfirmLink, auth: Auth, next: string | null): Promise<ConfirmOutcome> {
  let ok = false;
  let type: string | null = null;

  if (link.kind === "implicit") {
    const { error } = await auth.setSession({ access_token: link.accessToken, refresh_token: link.refreshToken });
    ok = !error;
    type = link.type;
  } else if (link.kind === "token_hash") {
    const { error } = await auth.verifyOtp({ type: link.type as OtpType, token_hash: link.tokenHash });
    ok = !error;
    type = link.type;
  } else if (link.kind === "pkce") {
    const { error } = await auth.initialize();
    const { data } = await auth.getSession();
    ok = !error && !!data.session;
  } else if (link.kind === "message") {
    return { status: "first_confirmation" };
  }

  if (!ok) return { status: "invalid" };
  // ?recovery=1: the page offers "Cancel" (sign out this browser) only to someone who came from a
  // reset link, not to a signed-in user who opened Password from settings.
  if (type === "recovery") return { status: "signed_in", route: "/reset-password?recovery=1" };
  if (type === "email_change") return { status: "signed_in", route: "/account/settings?email_changed=1" };
  return { status: "signed_in", route: safeInternalPath(next, "/account") };
}
