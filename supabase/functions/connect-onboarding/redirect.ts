/**
 * connect-onboarding — redirect allowlist for Stripe account-link return/refresh targets. Import-free and pure:
 * `index.ts` imports FROM here (the door-session/pure.ts pattern), so the rule is unit-tested without Deno.
 *
 * A target must be https, on an allowlisted host, and carry no state (Ruling G §3; see isSafeRedirect's caller).
 * Production's allowlist is exactly BASE_REDIRECT_HOSTS. One extra EXACT host may be added per environment from
 * VENUE_CONNECT_ALLOWED_HOST (the sandbox venue app). A bare hostname only: the pattern admits no scheme, port, path,
 * list or wildcard, so it cannot widen into a pattern match. Unset or malformed adds nothing and the base set stands,
 * which fails closed. Production leaves the secret unset, so no sandbox host is an accepted target there.
 */
export const BASE_REDIRECT_HOSTS: readonly string[] = ['snatchitapp.com', 'www.snatchitapp.com'];

const BARE_HOSTNAME = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;

export function redirectHosts(extraHost: string | null | undefined): ReadonlySet<string> {
  const hosts = new Set(BASE_REDIRECT_HOSTS);
  const extra = (extraHost ?? '').trim().toLowerCase();
  if (BARE_HOSTNAME.test(extra)) hosts.add(extra);
  return hosts;
}

export function isSafeRedirect(raw: string, hosts: ReadonlySet<string>): boolean {
  try {
    const u = new URL(raw);
    return u.protocol === 'https:'
      && hosts.has(u.hostname)
      && u.search === ''
      && u.hash === '';
  } catch {
    return false;
  }
}
