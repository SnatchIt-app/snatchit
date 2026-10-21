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
