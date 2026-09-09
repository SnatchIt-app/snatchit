/**
 * The preview's ONLY data access layer.
 *
 * Every function here returns fixtures from src/fixtures/venue.ts. Each one
 * is annotated with the read the real dashboard would perform (spec §20 read
 * index), so wiring later is a substitution, not a redesign. There is no
 * Supabase client in this package and no write path at all: every "action"
 * in the UI is a form that posts back to the same page with `?did=` and
 * renders a "preview only — nothing saved" outcome.
 *
 * `PreviewState` (from `?state=`) is applied uniformly: `loading` and `error`
 * are decided by the page, `denied` by the role matrix, `empty`/`nodata` by
 * returning empty sets so each surface renders its own specific copy.
 */
import * as F from "@/fixtures/venue";
import type { PreviewState } from "@/lib/preview";
import type { Event, EventSession } from "@/lib/types";

export class PreviewReadError extends Error {
  constructor(public readonly read: string) {
    super(`preview: simulated read failure for ${read}`);
  }
}

function gate<T>(state: PreviewState, read: string, live: T, empty: T): T {
  if (state === "error") throw new PreviewReadError(read);
  if (state === "empty" || state === "nodata") return empty;
  return live;
}

/** B1 — T catalog.event, catalog.event_session, venue.inventory_batch, catalog.resale_policy */
export function listEvents(state: PreviewState): Event[] {
  return gate(state, "catalog.event", F.EVENTS, []);
}
export function getEvent(eventId: string): Event | null {
  return F.EVENTS.find((e) => e.eventId === eventId) ?? null;
}
export function getSession(sessionId: string): EventSession | null {
  for (const e of F.EVENTS) for (const s of e.sessions) if (s.sessionId === sessionId) return s;
  return null;
}
/** Spec §6.1 zone 1 — sessions whose starts_at is today or status = live. */
export function tonightSessions(now: Date): { event: Event; session: EventSession }[] {
  const out: { event: Event; session: EventSession }[] = [];
  const day = new Intl.DateTimeFormat("en-US", { timeZone: F.VENUE.timeZone, year: "numeric", month: "2-digit", day: "2-digit" });
  const today = day.format(now);
  for (const e of F.EVENTS) for (const s of e.sessions) if (s.status === "live" || day.format(new Date(s.startsAt)) === today) out.push({ event: e, session: s });
  return out;
}

/** C1 — T venue.ticket_type */
export function listTicketTypes(state: PreviewState, eventId: string) {
  return gate(state, "venue.ticket_type", F.TICKET_TYPES.filter((t) => t.eventId === eventId), []);
}
/** C3 — T venue.inventory_batch (counters staff-scoped; `remaining` public) */
export function listBatches(state: PreviewState, eventId: string) {
  const ids = new Set(F.TICKET_TYPES.filter((t) => t.eventId === eventId).map((t) => t.ticketTypeId));
  return gate(state, "venue.inventory_batch", F.BATCHES.filter((b) => ids.has(b.ticketTypeId)), []);
}
/** C4 — T venue.inventory_hold */
export function listHolds(state: PreviewState, eventId: string) {
  const batchIds = new Set(listBatches("live", eventId).map((b) => b.batchId));
  return gate(state, "venue.inventory_hold", F.HOLDS.filter((h) => batchIds.has(h.batchId)), []);
}

/** D1 — R venue.list_attendees(p_session_id, p_filters, p_cursor) — holder-keyed, column-scoped, audited per page */
export function listAttendees(state: PreviewState, sessionId: string, filter?: { q?: string; checkIn?: string }) {
  let rows = F.ROSTER.filter((r) => r.sessionId === sessionId);
  if (filter?.q) {
    const q = filter.q.trim().toLowerCase();
    rows = rows.filter((r) => r.name.toLowerCase().includes(q) || r.customerRef.toLowerCase() === q || (r.email ?? "").toLowerCase() === q);
  }
  if (filter?.checkIn === "not_scanned") rows = rows.filter((r) => r.checkIn.kind === "not_scanned");
  if (filter?.checkIn === "admitted") rows = rows.filter((r) => r.checkIn.kind === "admitted");
  return gate(state, "venue.list_attendees", rows, []);
}
/** H1 — T venue.order, venue.order_item (purchaser view, MONEY) */
export function listOrders(state: PreviewState, sessionId: string) {
  return gate(state, "venue.order", F.ORDERS.filter((o) => o.sessionId === sessionId), []);
}

/** G1 — T venue.door_pin (never pin_hash) */
export function listPins(state: PreviewState, sessionId: string) {
  return gate(state, "venue.door_pin", F.PINS.filter((p) => p.sessionId === sessionId), []);
}
/** G2 — T venue.scan_device */
export function listDevices(state: PreviewState) {
  return gate(state, "venue.scan_device", F.DEVICES, []);
}
/** G3/G8/G9 — R catalog.effective_freeze_at; T venue.door_manifest */
export function listManifestEpisodes(state: PreviewState, sessionId: string) {
  return gate(state, "venue.door_manifest", F.MANIFEST_EPISODES.filter((m) => m.sessionId === sessionId), []);
}
/** G4 — T venue.scan (live counters) */
export function scanCounters(state: PreviewState, sessionId: string) {
  const zero = { ...F.SCANS, admitted: 0, duplicate: 0, invalid: 0, frozen: 0, fraudReview: 0, lastScanAt: null, arrivalsPer5Min: [] as number[] };
  return gate(state, "venue.scan", sessionId === "smp_ses_sat_0912" ? F.SCANS : zero, zero);
}
/** G7 — T venue.scan (fraud_flag / duplicate / fraud_review) */
export function listFlags(state: PreviewState, sessionId: string) {
  return gate(state, "venue.scan#flags", sessionId === "smp_ses_sat_0912" ? F.FLAGS : [], []);
}
/** A8/L1 — R venue.list_activity */
export function recentActivity(state: PreviewState) {
  return gate(state, "venue.list_activity", F.ACTIVITY, []);
}
