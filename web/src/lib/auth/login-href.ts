import { safeInternalPath } from "@/lib/auth/redirect";

// Pages a "Log in" link must not send someone back to.
const AUTH_PAGES = ["/login", "/signup", "/forgot-password", "/reset-password", "/auth/"];
// Query keys that may carry a credential (Stripe's payment_intent_client_secret, auth codes,
// tokens). Never carried into a login link, its URL or a Referer.
const SECRET_KEY = /secret|token|code|password|otp/i;

/**
 * "/login?next=<this page>" for a link or push from the current page, keeping its query
 * (browse filters, a listing's state) minus anything credential-like. Plain "/login" from the
 * auth pages themselves or when the result isn't a safe internal path. The login page and the
 * sign-in action re-sanitize next regardless.
 */
export function loginHrefFor(pathname: string, search = ""): string {
  if (AUTH_PAGES.some((p) => (p.endsWith("/") ? pathname.startsWith(p) : pathname === p))) return "/login";
  const params = new URLSearchParams(search);
  for (const key of [...params.keys()]) if (SECRET_KEY.test(key)) params.delete(key);
  const query = params.toString();
  const next = safeInternalPath(pathname + (query ? `?${query}` : ""), "");
  return next && next !== "/" ? `/login?next=${encodeURIComponent(next)}` : "/login";
}
