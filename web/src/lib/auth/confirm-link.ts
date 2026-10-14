/**
 * What an email link brought to /auth/confirm. Three shapes reach it:
 *   implicit   — #access_token=…&refresh_token=…&type=… (a client on the implicit flow)
 *   token_hash — ?token_hash=…&type=… (a template that links straight here)
 *   pkce       — ?code=… : the web's own requests (@supabase/ssr defaults to the PKCE flow, so
 *                password reset and sign-up send a code_challenge and GoTrue returns a code)
 * The order is the page's precedence. The pkce link carries no type; `next` decides.
 */
export type ConfirmLink =
  | { kind: "implicit"; accessToken: string; refreshToken: string; type: string | null }
  | { kind: "token_hash"; tokenHash: string; type: string }
  | { kind: "pkce"; code: string }
  /** GoTrue accepted the first of two email-change confirmations; the session comes with the second. */
  | { kind: "message" }
  | { kind: "none" };

export function readConfirmLink(search: URLSearchParams, hash: string): ConfirmLink {
  const h = new URLSearchParams(hash.replace(/^#/, ""));
  const accessToken = h.get("access_token");
  const refreshToken = h.get("refresh_token");
  if (accessToken && refreshToken) return { kind: "implicit", accessToken, refreshToken, type: h.get("type") };

  const tokenHash = search.get("token_hash");
  const type = search.get("type");
  if (tokenHash && type) return { kind: "token_hash", tokenHash, type };

  const code = search.get("code");
  if (code) return { kind: "pkce", code };

  // No credential, but GoTrue says it accepted the link (secure email change, first address).
  // Errors come as error=/error_code= and stay "none".
  if ((h.get("message") || search.get("message")) && !h.get("error") && !search.get("error")) return { kind: "message" };

  return { kind: "none" };
}
