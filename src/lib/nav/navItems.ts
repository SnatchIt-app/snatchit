/**
 * src/lib/nav/navItems.ts — the primary navigation destinations.
 *
 * The dock renders whatever this returns, so the future five-destination model is
 * a data change, not a component rewrite. TICKETS is defined but NOT included by
 * default: it ships only when Core exposes the canonical ticket contract, and it
 * slots between Bids and Profile. Search is deliberately absent — it lives inside
 * Home/discovery, never as a primary destination.
 *
 * Icons are SF Symbol names resolved by components/ui/icon-symbol (SF on iOS,
 * Material on Android) — one coherent family, no emoji.
 */

export type NavKey = 'home' | 'create' | 'bids' | 'tickets' | 'profile';

export interface NavItem {
  key: NavKey;
  /** The expo-router tab route name under app/(tabs). */
  route: string;
  /** Short accessible name; also the optional compact label. */
  label: string;
  /** SF Symbol name for IconSymbol. */
  icon: string;
}

const HOME: NavItem = { key: 'home', route: 'home', label: 'Home', icon: 'house.fill' };
// V3 (owner ruling 2026-09-22): labelled "Sell" — the verb for what the screen does. The key,
// the route, the destination and the behaviour are unchanged.
const CREATE: NavItem = { key: 'create', route: 'create', label: 'Sell', icon: 'plus.circle.fill' };
const BIDS: NavItem = { key: 'bids', route: 'bids', label: 'Bids', icon: 'tag.fill' };
// V3 (owner 2026-09-22, O-5): the visible label AND the accessible name are "You". The key, the
// route and the destination are unchanged — this is the same tab.
const PROFILE: NavItem = { key: 'profile', route: 'profile', label: 'You', icon: 'person.fill' };
/**
 * Tickets = tickets I actually OWN (not bids). The icon reads as ownership, never
 * as scanning — no scanner/QR glyph. Held out of the default set until the
 * contract exists.
 */
const TICKETS: NavItem = { key: 'tickets', route: 'tickets', label: 'Tickets', icon: 'ticket.fill' };

/**
 * The destinations to render. `tickets: true` inserts Tickets between Bids and
 * Profile — the approved five-item order (Home, Create, Bids, Tickets, Profile) —
 * without any layout change. Defaults to the four shipped destinations.
 */
export function navItems({ tickets = false }: { tickets?: boolean } = {}): NavItem[] {
  return tickets ? [HOME, CREATE, BIDS, TICKETS, PROFILE] : [HOME, CREATE, BIDS, PROFILE];
}

/**
 * Adaptive collapse is a GLOBAL rule: every scrollable primary tab collapses the
 * dock on downward scroll and expands it on upward/near-top. Create is included
 * (device revision) — its form scrolls like any other, and its List ticket CTA is
 * a separate surface that always clears the dock.
 */
export const COLLAPSING_ROUTES: readonly string[] = ['home', 'create', 'bids', 'tickets', 'profile'];

export function isCollapsingRoute(route: string | undefined): boolean {
  return route != null && COLLAPSING_ROUTES.includes(route);
}
