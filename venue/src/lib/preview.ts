/**
 * Preview controls. Two query parameters drive every surface:
 *
 *   ?role=<principal>   who is looking (default venue_manager) — lib/roles.ts
 *   ?state=<state>      force a surface state: loading · empty · error · denied · nodata
 *
 * `nodata` is the "filtered to nothing" state, kept distinct from `empty`
 * ("no sales yet") on purpose — spec §9.7 says collapsing them makes an
 * operator think the event failed.
 */
import { DATA_SOURCE, type DataSource } from "@/lib/env";
import { DEFAULT_PRINCIPAL, isPrincipal, type Principal } from "@/lib/roles";

export const PREVIEW_STATES = ["live", "loading", "empty", "error", "denied", "nodata"] as const;
export type PreviewState = (typeof PREVIEW_STATES)[number];

export type SearchParams = Record<string, string | string[] | undefined>;

export type PreviewContext = {
  role: Principal;
  state: PreviewState;
  /** Where rows come from. Fixtures by default; database mode reads as the signed-in user. */
  source?: DataSource;
  /** false when capacity/held/sold are not readable (database mode) — surfaces then show `remaining` only. */
  countersAvailable?: boolean;
  /** false in database mode: no write path is wired, so no action control is offered. */
  writesEnabled?: boolean;
  /** Database mode: true only once `role` was derived from the caller's verified grants at this scope (lib/page.ts). */
  verifiedRole?: boolean;
  /** Database mode: the route's own org/venue, so navigation never points at the sample fixture ids. */
  scope?: { orgId: string; venueId: string };
};

function first(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

export function readPreviewContext(sp: SearchParams | undefined): PreviewContext {
  const roleRaw = first(sp?.role);
  const stateRaw = first(sp?.state);
  if (DATA_SOURCE === "database") {
    // Preview controls are fixture-mode only: the role comes from verified grants (lib/page.ts) and no state is forced.
    return { role: DEFAULT_PRINCIPAL, state: "live", source: "database", countersAvailable: false, writesEnabled: false };
  }
  const role = isPrincipal(roleRaw) ? roleRaw : DEFAULT_PRINCIPAL;
  const state = (PREVIEW_STATES as readonly string[]).includes(stateRaw ?? "") ? (stateRaw as PreviewState) : "live";
  return { role, state, source: "fixtures", countersAvailable: true, writesEnabled: true };
}

/** Build a link that keeps the current role/state so the reviewer can walk the flow in one persona. */
export function withPreview(href: string, ctx: PreviewContext, overrides: Partial<PreviewContext> = {}): string {
  const role = overrides.role ?? ctx.role;
  const state = overrides.state ?? ctx.state;
  const params = new URLSearchParams();
  if (role !== DEFAULT_PRINCIPAL) params.set("role", role);
  if (state !== "live") params.set("state", state);
  const q = params.toString();
  return q ? `${href}?${q}` : href;
}

/**
 * The label every surface shows so nobody mistakes the demo for live operations.
 * Short enough to stay on one line on a phone; the sentence under it in the
 * strip carries the consequence.
 */
export const DEMO_DATA_LABEL = "Demo — sample data";
export const DEMO_DATA_SUBLABEL = "Invented venue and events. Nothing here sells, refunds, pays out or scans a real ticket.";

/**
 * What each demo "action" would have done, said plainly. The form posts the
 * backend call it stands for as `?did=`, which is fine for a URL, but the
 * message a person reads must not be a schema name. Anything unmapped falls
 * back to a sentence that still tells the truth without naming an object.
 */
export const DEMO_ACTION_LABEL: Record<string, string> = {
  "catalog.create_event": "created a draft event",
  "catalog.set_event_status": "moved this event to its next status",
  "catalog.create_event_session": "added a session",
  "catalog.set_resale_policy": "changed the resale rules for this event",
  "venue.create_ticket_type": "added a ticket type",
  "venue.create_inventory_batch": "put a new release on sale",
  "venue.release_inventory_hold": "released those held seats back on sale",
  "venue.open_door_manifest": "opened the door manifest, freezing transfers for this session",
  "venue.close_door_manifest": "closed this door manifest episode",
  "venue.create_door_pin": "issued a door PIN",
  "venue.revoke_door_pin": "revoked that door PIN",
};

/** The plain description for a `?did=` value, never the value itself. */
export function demoActionLabel(did: string): string | null {
  const base = did.split(" ")[0];
  return DEMO_ACTION_LABEL[base] ?? (base.startsWith("venue.request_export") ? "started preparing that download" : base.startsWith("escalate") ? "passed that flagged scan to Snatch It with your note" : null);
}

/** Kept for callers written against the previous name. */
export const PREVIEW_DATA_LABEL = DEMO_DATA_LABEL;
