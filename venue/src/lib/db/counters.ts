import "server-only";

import { mapReadError, transportFailure, type ReadResult } from "@/lib/db/read-result";
import { availability, type Availability } from "@/lib/inventory";
import { isUuid } from "@/lib/page";
import { createSupabaseServerClient, SupabaseConfigError } from "@/lib/supabase/server";

/**
 * Inventory counters for staff — slice S1, DARK.
 *
 * venue_api.inventory_batches exposes `remaining` only (081 E-29 withholds capacity/held/sold from every
 * client; adapters.ts flags those batches countersKnown: false). The read E-29 intended for staff is
 * venue.get_inventory_counters(p_event_id) (provisional migration 160 (d)): authority is checked in the
 * definer body (org owner/admin/finance, or venue manager/finance at the event's venue with the E-76
 * venue-org binding), and an unknown event and an unauthorized one raise the same P0002, so the dashboard
 * renders "Couldn't load" for both and never a zero. It is reached through the SECURITY INVOKER wrapper
 * venue_cmd.get_inventory_counters (provisional 161), as the signed-in user.
 *
 * Contract: get_inventory_counters(p_event_id uuid) → rows
 *   { batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold, remaining }.
 *
 * A failure of any kind is a ReadFailure. There is no branch that turns a failure into counters.
 */
const SCHEMA = "venue_cmd";
const READ = "venue_cmd.get_inventory_counters";

export type CounterRow = {
  batch_id: string;
  ticket_type_id: string;
  event_session_id: string;
  release_kind: string;
  capacity: number;
  held: number;
  sold: number;
  remaining: number;
};

/** One tier within one session, summed over its releases (never an event-level capacity — spec §7.6). */
export type TierSessionCounters = {
  sessionId: string;
  ticketTypeId: string;
  capacity: number;
  held: number;
  sold: number;
  remaining: number;
  /** Spec §8.8 / feature F3: sold out and temporarily all held are different states and different chips. */
  state: Availability;
  /** Always true here — these rows come from the counters RPC, not from venue_api's remaining-only view. */
  countersKnown: true;
};

type PgError = { code?: string | null; message?: string | null; details?: string | null; hint?: string | null };
type RpcResponse = { data: unknown; error: PgError | null; status?: number };
type CountersClient = { rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResponse> };

const isInt = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v);
function isCounterRow(r: unknown): r is CounterRow {
  if (typeof r !== "object" || r === null) return false;
  const x = r as Record<string, unknown>;
  return (
    typeof x.batch_id === "string" &&
    typeof x.ticket_type_id === "string" &&
    typeof x.event_session_id === "string" &&
    typeof x.release_kind === "string" &&
    isInt(x.capacity) &&
    isInt(x.held) &&
    isInt(x.sold) &&
    isInt(x.remaining)
  );
}

export async function dbInventoryCounters(eventId: string): Promise<ReadResult<CounterRow[]>> {
  if (typeof eventId !== "string" || !isUuid(eventId)) return { ok: false, kind: "error", message: "Not a valid event id", read: READ };
  let c: CountersClient;
  try {
    c = (await createSupabaseServerClient()).schema(SCHEMA) as unknown as CountersClient;
  } catch (e) {
    return { ok: false, kind: e instanceof SupabaseConfigError ? "config" : "error", message: e instanceof Error ? e.message : "client unavailable", read: READ };
  }
  let res: RpcResponse;
  try {
    res = await c.rpc("get_inventory_counters", { p_event_id: eventId });
  } catch (e) {
    return transportFailure(READ, e);
  }
  if (res.error) {
    const f = mapReadError(READ, res.error, res.status);
    // read-result.ts names F's read-views migration when an object is missing; this read's object is the
    // venue_cmd transport (provisional 161), so the hint is corrected here without touching F's mapper.
    return f.kind === "config" ? { ...f, message: `${res.error.message ?? "Request failed"} (venue_cmd transport — provisional migration 161 not applied?)` } : f;
  }
  // Rows or nothing: a shape this module does not recognise is a failure, never coerced to zero counters.
  if (!Array.isArray(res.data) || !res.data.every(isCounterRow)) return { ok: false, kind: "error", message: "Counters came back in an unexpected shape", read: READ };
  return { ok: true, data: res.data };
}

/**
 * Per (session, tier) roll-up over the counter rows, in first-seen order. The four counters are summed
 * from the server's own columns; the chip state is lib/inventory.ts availability() (spec §8.8), so the
 * sold-out / all-held distinction has exactly one home in the dashboard.
 */
export function rollUpCounters(rows: CounterRow[]): TierSessionCounters[] {
  const out = new Map<string, TierSessionCounters>();
  for (const r of rows) {
    const key = `${r.event_session_id}\u0000${r.ticket_type_id}`;
    const t: TierSessionCounters = out.get(key) ?? { sessionId: r.event_session_id, ticketTypeId: r.ticket_type_id, capacity: 0, held: 0, sold: 0, remaining: 0, state: "available", countersKnown: true };
    t.capacity += r.capacity;
    t.held += r.held;
    t.sold += r.sold;
    t.remaining += r.remaining;
    out.set(key, t);
  }
  return [...out.values()].map((t) => ({ ...t, state: availability(t) }));
}
