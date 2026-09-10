import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createSupabaseServerClient, SupabaseConfigError } from "@/lib/supabase/server";
import { mapReadError, transportFailure, type ReadFailure, type ReadResult } from "@/lib/db/read-result";
import { mapBatches, mapEvents, mapTicketTypes, type BatchRow, type EventRow, type PolicyRow, type SessionRow, type TicketTypeRow } from "@/lib/db/rows";
import type { Event, InventoryBatch, TicketType } from "@/lib/types";

/**
 * Authenticated read adapters — slice 1 (events list + event setup, read side).
 *
 * Every read goes through the `venue_api` schema (six security_invoker views;
 * migration 20260910120000). Authorization is the base tables' RLS and column
 * grants evaluated as the signed-in user; this file adds nothing and hides
 * nothing. The UI role switch never reaches this layer.
 */
const SCHEMA = "venue_api";

type Client = SupabaseClient<Record<string, never>, typeof SCHEMA>;

async function client(read: string): Promise<{ ok: true; c: Client } | ReadFailure> {
  try {
    const c = (await createSupabaseServerClient()).schema(SCHEMA) as unknown as Client;
    return { ok: true, c };
  } catch (e) {
    return { ok: false, kind: e instanceof SupabaseConfigError ? "config" : "error", message: e instanceof Error ? e.message : "client unavailable", read };
  }
}

async function select<T>(read: string, q: PromiseLike<{ data: T | null; error: { code?: string | null; message?: string | null } | null; status?: number }>): Promise<ReadResult<T>> {
  try {
    const { data, error, status } = await q;
    if (error) return mapReadError(read, error, status);
    return { ok: true, data: (data ?? ([] as unknown as T)) as T };
  } catch (e) {
    return transportFailure(read, e);
  }
}

/** B1 — venue_api.events + event_sessions + resale_policies, scoped to one venue by the route. */
export async function dbListEvents(venueId: string): Promise<ReadResult<Event[]>> {
  const cl = await client("venue_api.events");
  if (!cl.ok) return cl;
  const events = await select<EventRow[]>("venue_api.events", cl.c.from("events").select("event_id,venue_id,org_id,title,status").eq("venue_id", venueId));
  if (!events.ok) return events;
  const ids = events.data.map((e) => e.event_id);
  if (ids.length === 0) return { ok: true, data: [] };
  const sessions = await select<SessionRow[]>("venue_api.event_sessions", cl.c.from("event_sessions").select("session_id,event_id,session_label,starts_at,ends_at,doors_at,door_open_at,status").in("event_id", ids));
  if (!sessions.ok) return sessions;
  const policies = await select<PolicyRow[]>("venue_api.resale_policies", cl.c.from("resale_policies").select("policy_id,scope_kind,venue_id,event_id,mode,version").in("event_id", ids));
  if (!policies.ok) return policies;
  return { ok: true, data: mapEvents(events.data, sessions.data, policies.data) };
}

/** B1/B4 — one event with its sessions; a non-visible id is indistinguishable from a missing one (null). */
export async function dbGetEvent(eventId: string): Promise<ReadResult<Event | null>> {
  const cl = await client("venue_api.events");
  if (!cl.ok) return cl;
  const events = await select<EventRow[]>("venue_api.events", cl.c.from("events").select("event_id,venue_id,org_id,title,status").eq("event_id", eventId).limit(1));
  if (!events.ok) return events;
  if (events.data.length === 0) return { ok: true, data: null };
  const sessions = await select<SessionRow[]>("venue_api.event_sessions", cl.c.from("event_sessions").select("session_id,event_id,session_label,starts_at,ends_at,doors_at,door_open_at,status").eq("event_id", eventId));
  if (!sessions.ok) return sessions;
  const policies = await select<PolicyRow[]>("venue_api.resale_policies", cl.c.from("resale_policies").select("policy_id,scope_kind,venue_id,event_id,mode,version").eq("event_id", eventId));
  if (!policies.ok) return policies;
  return { ok: true, data: mapEvents(events.data, sessions.data, policies.data)[0] ?? null };
}

/** C1 — venue_api.ticket_types (hidden types appear only for manager / org-plane callers, by RLS). */
export async function dbListTicketTypes(eventId: string): Promise<ReadResult<TicketType[]>> {
  const cl = await client("venue_api.ticket_types");
  if (!cl.ok) return cl;
  const rows = await select<TicketTypeRow[]>("venue_api.ticket_types", cl.c.from("ticket_types").select("ticket_type_id,event_id,kind,name,price_minor,currency,visibility").eq("event_id", eventId));
  if (!rows.ok) return rows;
  return { ok: true, data: mapTicketTypes(rows.data) };
}

/** C3 — venue_api.inventory_batches: `remaining` only; capacity/held/sold are not client-readable (081 E-29). */
export async function dbListBatches(eventId: string): Promise<ReadResult<InventoryBatch[]>> {
  const cl = await client("venue_api.inventory_batches");
  if (!cl.ok) return cl;
  const types = await select<{ ticket_type_id: string }[]>("venue_api.ticket_types", cl.c.from("ticket_types").select("ticket_type_id").eq("event_id", eventId));
  if (!types.ok) return types;
  const ids = types.data.map((t) => t.ticket_type_id);
  if (ids.length === 0) return { ok: true, data: [] };
  const rows = await select<BatchRow[]>("venue_api.inventory_batches", cl.c.from("inventory_batches").select("batch_id,ticket_type_id,event_session_id,release_kind,remaining").in("ticket_type_id", ids));
  if (!rows.ok) return rows;
  return { ok: true, data: mapBatches(rows.data) };
}
