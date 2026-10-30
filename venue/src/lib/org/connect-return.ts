/**
 * Coming back from Stripe Connect onboarding: which routes we own, how the
 * org context survives the round trip, and where the operator lands. Pure, so
 * every rule is a unit test.
 *
 * The edge decides the return and refresh URLs and REFUSES a caller-supplied
 * one; `isSafeRedirect` there also requires https, a host on the allowlist, and
 * **no query and no fragment** (Ruling G §3: "the return and refresh handlers
 * MUST treat every URL-borne value as decoration"). So these two URLs are
 * static and carry nothing — no org id, no session, no status.
 *
 * Which means the context has to survive some other way, and it does so three
 * ways in this order:
 *   1. a first-party cookie this app set before sending the operator to Stripe,
 *   2. failing that, the caller's own org roles read from the database,
 *   3. failing that, we ask — never a guess, never a redirect from input.
 *
 * Nothing here reads a redirect target from anywhere. The only landing paths
 * are built from a uuid this app validated, so an open redirect is not
 * expressible.
 */

/** The two paths this app owns. They are static because the edge's URLs may carry no state. */
export const CONNECT_RETURN_PATH = "/connect/return";
export const CONNECT_REFRESH_PATH = "/connect/refresh";

/**
 * The context cookie. `SameSite=Lax` is required, not a preference: the trip
 * back from Stripe is a top-level cross-site GET, which a `Strict` cookie
 * would not be sent on — the session cookie is Lax for the same reason.
 * HttpOnly because nothing in the browser needs it; host-only (no domain) so
 * it never leaks to a sibling host; short-lived because it describes one
 * onboarding attempt.
 */
export const CONNECT_CONTEXT_COOKIE = "sx_venue_connect_org";
export const CONNECT_CONTEXT_TTL_SECONDS = 1800;

export function connectContextCookieOptions(): { name: string; path: string; sameSite: "lax"; secure: true; httpOnly: true; maxAge: number } {
  return { name: CONNECT_CONTEXT_COOKIE, path: "/", sameSite: "lax", secure: true, httpOnly: true, maxAge: CONNECT_CONTEXT_TTL_SECONDS };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The cookie holds one org id and nothing else. Anything else is discarded, not repaired. */
export function parseConnectContext(raw: string | null | undefined): string | null {
  const v = (raw ?? "").trim();
  return UUID.test(v) ? v.toLowerCase() : null;
}

/** The only landing path this app will send anyone to, built from a validated uuid. */
export function payoutsPath(orgId: string): string | null {
  return UUID.test(orgId) ? `/o/${orgId.toLowerCase()}/payouts` : null;
}

export type Landing =
  /** One org to go to. */
  | { kind: "org"; orgId: string; path: string }
  /** Several, or none matching the cookie: ask rather than guess. */
  | { kind: "choose"; orgIds: string[] }
  /** Signed in, but holds no payouts role anywhere. */
  | { kind: "none" };

/**
 * Where to land, from the cookie and the caller's own eligible orgs. The
 * cookie is a hint and never an authority: it is honoured only if the caller
 * still holds a payouts role in that org, so a stale or planted cookie cannot
 * take anyone somewhere they do not belong.
 */
export function resolveLanding(cookieOrg: string | null, eligibleOrgIds: string[]): Landing {
  const eligible = eligibleOrgIds.map((o) => o.toLowerCase()).filter((o) => UUID.test(o));
  const unique = [...new Set(eligible)];
  if (unique.length === 0) return { kind: "none" };
  const hinted = cookieOrg ? cookieOrg.toLowerCase() : null;
  if (hinted && unique.includes(hinted)) {
    const path = payoutsPath(hinted);
    return path ? { kind: "org", orgId: hinted, path } : { kind: "choose", orgIds: unique };
  }
  if (unique.length === 1) {
    const path = payoutsPath(unique[0]);
    return path ? { kind: "org", orgId: unique[0], path } : { kind: "choose", orgIds: unique };
  }
  return { kind: "choose", orgIds: unique };
}

/**
 * What the page says. The `retry` flag is decoration for the copy only — the
 * state on the page itself is always re-read from the database, never inferred
 * from the URL, which is what Ruling G §3 requires of these handlers.
 */
export const RETURN_COPY = {
  heading: "Back from Stripe",
  body: "Stripe has sent you back. Your payout state is read fresh below — Stripe decides when an account can receive transfers, and it is sometimes a minute behind.",
} as const;

export const REFRESH_COPY = {
  heading: "That setup link expired",
  body: "Stripe links are single-use and short-lived, and this one is spent. Nothing is wrong with your account and nothing was lost. Start the setup again to get a new link.",
} as const;

/** The roles that may see payouts at all (093 §6): org_owner or org_finance. No venue role, ever. */
export function isPayoutsRole(role: string): boolean {
  return role === "org_owner" || role === "org_finance";
}
