import "server-only";

import { mapReadError, transportFailure, type ReadResult } from "@/lib/db/read-result";
import { isUuid } from "@/lib/page";
import { createSupabaseServerClient } from "@/lib/supabase/server";

/**
 * What a night may sell, and what is already allocated against it — the read
 * that lets the pool form show its boundaries instead of making the operator
 * discover them from a refusal.
 *
 * `venue_api.session_capacity` (migration 166) is a security_invoker view over
 * a definer set-returning function, one row per session the caller may read,
 * with the same authority as `set_session_sales_capacity`: org owner/admin of
 * the event's org, or the bound venue_manager. A caller without that authority
 * simply gets no row — which this module reports as "not known", never as zero.
 * pgTAP 233 pins that these numbers ARE the setter's boundaries.
 *
 * `sales_capacity` null means unlimited, and then `remaining_to_allocate` is
 * null too. `allocated` is the sum of EVERY release on the session, comps and
 * door stock included.
 */
const SCHEMA = "venue_api";
const READ = "venue_api.session_capacity";

export type SessionCapacity = {
  sessionId: string;
  /** null = unlimited. */
  salesCapacity: number | null;
  /** Σ capacity of every release on this session (all release kinds). */
  allocated: number;
  /** null when the pool is unlimited. */
  remainingToAllocate: number | null;
  /** The venue's planning capacity, when one is set. */
  capacityHint: number | null;
};

type RpcResponse = { data: unknown; error: { code?: string; message?: string } | null; status?: number };
type Client = { from(v: string): { select(cols: string): { in(col: string, vals: string[]): PromiseLike<RpcResponse> } } };

const int = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) ? v : null);

/** One row → a capacity, or null if the row is not the shape 166 promises. */
export function parseSessionCapacity(v: unknown): SessionCapacity | null {
  if (!v || typeof v !== "object" || Array.isArray(v)) return null;
  const r = v as Record<string, unknown>;
  const sessionId = typeof r.session_id === "string" && isUuid(r.session_id) ? r.session_id : null;
  const allocated = int(r.allocated);
  if (!sessionId || allocated === null) return null;
  const salesCapacity = r.sales_capacity === null ? null : int(r.sales_capacity);
  if (r.sales_capacity !== null && salesCapacity === null) return null;
  const remaining = r.remaining_to_allocate === null ? null : int(r.remaining_to_allocate);
  if (r.remaining_to_allocate !== null && remaining === null) return null;
  // Unlimited means no remainder to speak of; a number there would be a server bug, so it is not rendered.
  return {
    sessionId,
    salesCapacity,
    allocated,
    remainingToAllocate: salesCapacity === null ? null : remaining,
    capacityHint: r.capacity_hint === null ? null : int(r.capacity_hint),
  };
}

/** Capacities for the sessions given, keyed by session id. A session with no row is absent, not zero. */
export async function dbSessionCapacities(sessionIds: string[]): Promise<ReadResult<Record<string, SessionCapacity>>> {
  const ids = sessionIds.filter((id) => typeof id === "string" && isUuid(id));
  if (ids.length === 0) return { ok: true, data: {} };
  let c: Client;
  try {
    c = (await createSupabaseServerClient()).schema(SCHEMA) as unknown as Client;
  } catch (e) {
    return { ok: false, kind: "config", message: e instanceof Error ? e.message : "Supabase client unavailable", read: READ };
  }
  let res: RpcResponse;
  try {
    res = await c.from("session_capacity").select("session_id,sales_capacity,allocated,remaining_to_allocate,capacity_hint").in("session_id", ids);
  } catch (e) {
    return transportFailure(READ, e);
  }
  if (res.error) return mapReadError(READ, res.error, res.status);
  const rows = Array.isArray(res.data) ? res.data : [];
  const out: Record<string, SessionCapacity> = {};
  for (const row of rows) {
    const parsed = parseSessionCapacity(row);
    // A malformed row is dropped rather than rendered as a number the server did not send.
    if (parsed && ids.includes(parsed.sessionId)) out[parsed.sessionId] = parsed;
  }
  return { ok: true, data: out };
}
