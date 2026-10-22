/**
 * Session cookies are host-only: never a Domain attribute.
 *
 * The console (admin.snatchitapp.com), the venue dashboard
 * (venue.snatchitapp.com) and the consumer web app share the parent domain.
 * A cookie set with Domain=.snatchitapp.com would be sent to every one of
 * them, so one app's Supabase session would ride along to the others. A
 * cookie without Domain stays on the exact host that set it. The console
 * passes no cookieOptions.domain to @supabase/ssr, and every cookie the
 * library asks us to write goes through here, so a domain can never leak in
 * from a default or a future option.
 */
export function hostOnlyCookie<T extends { domain?: unknown }>(options: T | undefined): Omit<T, "domain"> {
  if (!options) return {} as Omit<T, "domain">;
  const { domain: _ignored, ...rest } = options;
  void _ignored;
  return rest;
}

/**
 * True on a Vercel production or preview deployment, where the console is
 * served over https only, so a session cookie can carry Secure. Local
 * `next dev` on http://localhost never qualifies: a browser drops a Secure
 * cookie set over plain http. Exact values, trimmed; anything else is "not
 * hosted".
 */
export function secureSessionCookies(vercelEnv: string | null | undefined): boolean {
  const v = (vercelEnv ?? "").trim();
  return v === "production" || v === "preview";
}

/** Read once from the inlined NEXT_PUBLIC_VERCEL_ENV (the same switch env.ts and env-policy.ts use). */
export const SESSION_COOKIES_SECURE = secureSessionCookies(process.env.NEXT_PUBLIC_VERCEL_ENV);

/**
 * Options for every session cookie the console writes (server client, proxy
 * refresh, proxy redirect): host-only (hostOnlyCookie), Secure on a hosted
 * deployment, and never HttpOnly. The TOTP enrol/verify flow runs in the
 * browser — components/auth/MfaFlow.tsx uses lib/supabase/client.ts, a
 * createBrowserClient with no cookie accessors, so @supabase/ssr reads the
 * session from document.cookie — and an HttpOnly session cookie would leave
 * that client signed out at /mfa. httpOnly is therefore forced false by
 * construction, as the domain is dropped by construction.
 */
export function sessionCookie<T extends { domain?: unknown; httpOnly?: unknown }>(options: T | undefined): Omit<T, "domain" | "httpOnly"> & { httpOnly: false; secure?: true } {
  const { httpOnly: _ignored, ...dropped } = hostOnlyCookie(options) as Omit<T, "domain">;
  void _ignored;
  // Omit<Omit<T, "domain">, "httpOnly"> and Omit<T, "domain" | "httpOnly"> are the same keys, but
  // TypeScript cannot reduce the nested form while T is unresolved; the cast states what the destructure did.
  const rest = dropped as Omit<T, "domain" | "httpOnly">;
  return SESSION_COOKIES_SECURE ? { ...rest, httpOnly: false, secure: true } : { ...rest, httpOnly: false };
}
