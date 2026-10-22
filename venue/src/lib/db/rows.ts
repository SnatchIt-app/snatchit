/**
 * Pure row → domain mappers for the venue_api views. No I/O, unit-tested.
 * Unknown enum values are mapped to the safest neutral so a bad row never
 * renders as a legal state.
 */
import type { Event, EventSession, EventStatus, InventoryBatch, ReleaseKind, ResaleDisplay, ResaleMode, SessionStatus, TicketKind, TicketType, Visibility } from "@/lib/types";
import { isOrgRole, isVenueRole, type GrantSet } from "@/lib/roles";

export type EventRow = { event_id: string; venue_id: string; org_id: string; title: string; status: string };
export type SessionRow = { session_id: string; event_id: string; session_label: string | null; starts_at: string; ends_at: string | null; doors_at: string | null; door_open_at: string | null; status: string };
export type PolicyRow = { policy_id: string; scope_kind: string; venue_id: string | null; event_id: string | null; mode: string; version: number };
export type TicketTypeRow = { ticket_type_id: string; event_id: string; kind: string; name: string; price_minor: number; currency: string; visibility: string };
export type BatchRow = { batch_id: string; ticket_type_id: string; event_session_id: string; release_kind: string; remaining: number };
/** venue_api.venues as the caller reads it; a venue whose row is not readable is simply absent. */
export type VenueApprovalRow = { venue_id: string; approval_status: string };

const EVENT_STATUS: EventStatus[] = ["draft", "announced", "on_sale", "live", "completed", "cancelled"];
const SESSION_STATUS: SessionStatus[] = ["scheduled", "live", "completed", "cancelled"];
const RESALE: ResaleMode[] = ["off", "transfers_only", "fixed_cap", "face_value_queue", "buy_now", "auction", "offer"];
const RELEASE: ReleaseKind[] = ["public_sale", "promoter_hold", "comp", "door", "presale"];

function pick<T extends string>(allowed: readonly T[], v: string, fallback: T): T {
  return (allowed as readonly string[]).includes(v) ? (v as T) : fallback;
}

export function mapEvents(events: EventRow[], sessions: SessionRow[], policies: PolicyRow[], venues: VenueApprovalRow[]): Event[] {
  const approved = new Set(venues.filter((v) => v.approval_status === "approved").map((v) => v.venue_id));
  return events.map((e) => {
    const mine: EventSession[] = sessions
      .filter((s) => s.event_id === e.event_id)
      .sort((a, b) => a.starts_at.localeCompare(b.starts_at))
      .map((s) => ({ sessionId: s.session_id, eventId: s.event_id, label: s.session_label, startsAt: s.starts_at, doorsAt: s.doors_at, endsAt: s.ends_at, status: pick(SESSION_STATUS, s.status, "scheduled"), doorOpenAt: s.door_open_at }));
    // In-force policy, resolved the way the server does (088 create_native_listing / buy_now): an
    // event-scope policy for this event wins over a venue-scope one for its venue, then the highest
    // version; no policy at all is off (spec §7.7, C11).
    const policy = policies
      .filter((p) => (p.scope_kind === "event" && p.event_id === e.event_id) || (p.scope_kind === "venue" && p.venue_id === e.venue_id))
      .sort((a, b) => Number(b.scope_kind === "event") - Number(a.scope_kind === "event") || b.version - a.version)[0];
    // RLS (078 catalog_resale_policy_sel_public) hides two kinds of row from every client that the server (088,
    // definer, no approval check) still resolves:
    //   - a draft's own event-scope rows (`e.status <> 'draft'`), while its venue's venue-wide row stays visible;
    //   - every venue-wide row of a venue that is not approved (`v.approval_status = 'approved'`), own staff included.
    // In both cases what the caller sees can resolve to another mode than the one that applies, so such an event is
    // only readable when one of its own event-scope rows is visible; otherwise the mode is unknown, never the
    // venue's and never "off". A venue whose row the caller cannot read counts as not approved.
    const hidden = e.status === "draft" || !approved.has(e.venue_id);
    const resaleMode: ResaleDisplay = hidden && policy?.scope_kind !== "event" ? "not_readable" : policy ? pick(RESALE, policy.mode, "off") : "off";
    return {
      eventId: e.event_id,
      orgId: e.org_id,
      venueId: e.venue_id,
      title: e.title,
      status: pick(EVENT_STATUS, e.status, "draft"),
      resaleMode,
      promoterCount: null, // venue.promoter is not readable in this slice
      sessions: mine,
    };
  });
}

export function mapTicketTypes(rows: TicketTypeRow[]): TicketType[] {
  return rows.map((t) => ({
    ticketTypeId: t.ticket_type_id,
    eventId: t.event_id,
    name: t.name,
    kind: pick<TicketKind>(["admission", "table"], t.kind, "admission"),
    priceMinor: t.price_minor,
    visibility: pick<Visibility>(["hidden", "public", "door_only"], t.visibility, "hidden"),
  }));
}

/** capacity/held/sold are unknown to clients: they are set to remaining/0/0 and flagged so no surface renders them as counters. */
export function mapBatches(rows: BatchRow[]): InventoryBatch[] {
  return rows.map((b) => ({
    batchId: b.batch_id,
    ticketTypeId: b.ticket_type_id,
    sessionId: b.event_session_id,
    releaseKind: pick(RELEASE, b.release_kind, "public_sale"),
    capacity: b.remaining,
    held: 0,
    sold: 0,
    lowThreshold: 0,
    countersKnown: false,
  }));
}

/** `name` is display-only (the events eyebrow); entry is decided by venue_id/org_id alone. */
export type VenueScopeRow = { venue_id: string; org_id: string; name?: string | null };
export type StaffRoleRow = { venue_id: string; role: string };
export type OrgRoleRow = { org_id: string; role: string };

/** Only grants for the route's venue/org count; unknown labels are dropped, never guessed. */
export function mapGrants(staff: StaffRoleRow[], org: OrgRoleRow[], venueId: string, orgId: string): GrantSet {
  return {
    venueRoles: staff.filter((r) => r.venue_id === venueId).map((r) => r.role).filter(isVenueRole),
    orgRoles: org.filter((r) => r.org_id === orgId).map((r) => r.role).filter(isOrgRole),
  };
}
