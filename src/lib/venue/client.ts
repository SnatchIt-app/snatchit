/**
 * src/lib/venue/client.ts — typed client for the venue-native (direct) ticketing RPCs.
 *
 * WHAT THIS IS
 * Every function here wraps one deployed Phase-2 RPC (migrations 076-092, live in
 * production but dark). Signatures were read from the deployed catalog, not guessed.
 *
 * WHAT THIS IS NOT
 * This module does not activate anything. It cannot run until two things happen,
 * neither of which is authorized yet:
 *   1. PostgREST exposes the `venue` and `catalog` schemas (today: only
 *      public, graphql_public, kernel).
 *   2. `feature.native_issuance_enabled` is set true in catalog.platform_config.
 * Until then every call fails closed, which is the intended behavior.
 *
 * COMMAND KEYS
 * Every mutating Phase-2 RPC takes a command key and is idempotent on it. The key
 * must be stable for a given user intent so a retry replays rather than duplicates.
 * Callers pass their own key for anything money-adjacent; `commandKey()` is for
 * one-shot UI actions where a fresh attempt is genuinely a new intent.
 */

import { supabase } from '@/src/lib/supabase';
import type {
  CheckoutItem,
  InventoryBatch,
  InventoryHold,
  PrimaryOrder,
  ReleaseKind,
  RpcResult,
  TicketType,
  TicketTypeKind,
  TicketTypeVisibility,
  VenueRole,
} from './types';

/** Generates a fresh command key. Use a caller-owned stable key for money paths. */
export function commandKey(prefix: string): string {
  const safe = prefix.replace(/[^A-Za-z0-9._:-]/g, '').slice(0, 24);
  return `${safe}-${globalThis.crypto?.randomUUID?.() ?? Date.now().toString(36)}`.slice(0, 64);
}

/**
 * Normalizes a Postgres error into something safe to render.
 * Phase-2 RPCs raise `<code>: <detail>` strings; we surface the code and a
 * human sentence, never the raw driver message.
 */
function normalizeError(error: { message?: string; code?: string } | null): RpcResult<never> {
  const raw = error?.message ?? 'Something went wrong.';
  const match = /^([a-z_]+):\s*(.*)$/.exec(raw);
  const code = match?.[1] ?? error?.code ?? 'unknown';

  const friendly: Record<string, string> = {
    insufficient_privilege: 'You do not have permission to do that.',
    precondition_failed: 'That is not possible right now.',
    not_found: 'We could not find that.',
    invalid_input: 'Some of those details are not valid.',
    feature_disabled: 'That is not available yet.',
    sold_out: 'Those tickets just sold out.',
    idempotency_conflict: 'That request was already submitted with different details.',
  };

  return {
    ok: false,
    code,
    message: friendly[code] ?? 'Something went wrong. Please try again.',
  };
}

/** The venue schema is not exposed yet; every call routes through this guard. */
async function callVenue<T>(fn: string, args: Record<string, unknown>): Promise<RpcResult<T>> {
  const { data, error } = await (supabase as any).schema('venue').rpc(fn, args);
  if (error) return normalizeError(error);
  return { ok: true, data: data as T };
}

async function callCatalog<T>(fn: string, args: Record<string, unknown>): Promise<RpcResult<T>> {
  const { data, error } = await (supabase as any).schema('catalog').rpc(fn, args);
  if (error) return normalizeError(error);
  return { ok: true, data: data as T };
}

async function callKernel<T>(fn: string, args: Record<string, unknown>): Promise<RpcResult<T>> {
  const { data, error } = await (supabase as any).schema('kernel').rpc(fn, args);
  if (error) return normalizeError(error);
  return { ok: true, data: data as T };
}

/* ────────────────────────────────────────────────────────────────────────────
 * Authority
 * ──────────────────────────────────────────────────────────────────────────── */

/** kernel.has_venue_role(p_venue_id, p_roles[]) — the gate for every venue screen. */
export async function hasVenueRole(venueId: string, roles: VenueRole[]): Promise<boolean> {
  const res = await callKernel<boolean>('has_venue_role', {
    p_venue_id: venueId,
    p_roles: roles,
  });
  return res.ok ? res.data === true : false;
}

/* ────────────────────────────────────────────────────────────────────────────
 * Event setup (organizer side)
 * ──────────────────────────────────────────────────────────────────────────── */

/** catalog.create_event(p_venue_id, p_title, p_first_session jsonb, p_command_key) */
export async function createEvent(params: {
  venueId: string;
  title: string;
  startsAt: string;
  endsAt?: string;
  key?: string;
}): Promise<RpcResult<{ event_id: string }>> {
  return callCatalog('create_event', {
    p_venue_id: params.venueId,
    p_title: params.title,
    p_first_session: { starts_at: params.startsAt, ends_at: params.endsAt ?? null },
    p_command_key: params.key ?? commandKey('evt'),
  });
}

/** catalog.publish_event(p_event_id, p_target_status, p_command_key) */
export async function publishEvent(
  eventId: string,
  targetStatus: 'published' | 'draft',
  key?: string,
): Promise<RpcResult<{ status: string }>> {
  return callCatalog('publish_event', {
    p_event_id: eventId,
    p_target_status: targetStatus,
    p_command_key: key ?? commandKey('pub'),
  });
}

/** venue.create_ticket_type(p_event_id, p_kind, p_name, p_price_minor, p_visibility, p_command_key) */
export async function createTicketType(params: {
  eventId: string;
  kind: TicketTypeKind;
  name: string;
  priceMinor: number;
  visibility: TicketTypeVisibility;
  key?: string;
}): Promise<RpcResult<{ ticket_type_id: string }>> {
  return callVenue('create_ticket_type', {
    p_event_id: params.eventId,
    p_kind: params.kind,
    p_name: params.name,
    p_price_minor: params.priceMinor,
    p_visibility: params.visibility,
    p_command_key: params.key ?? commandKey('tt'),
  });
}

/** venue.create_inventory_batch(p_ticket_type_id, p_session_id, p_release_kind, p_capacity, p_shard_count, p_command_key) */
export async function createInventoryBatch(params: {
  ticketTypeId: string;
  sessionId: string;
  releaseKind: ReleaseKind;
  capacity: number;
  /** Shards spread contention. 0 lets the server choose. */
  shardCount?: number;
  key?: string;
}): Promise<RpcResult<{ batch_id: string }>> {
  return callVenue('create_inventory_batch', {
    p_ticket_type_id: params.ticketTypeId,
    p_session_id: params.sessionId,
    p_release_kind: params.releaseKind,
    p_capacity: params.capacity,
    p_shard_count: params.shardCount ?? 0,
    p_command_key: params.key ?? commandKey('batch'),
  });
}

/** venue.set_ticket_type_price(p_ticket_type_id, p_price_minor, p_reason_code, p_command_key) */
export async function setTicketTypePrice(params: {
  ticketTypeId: string;
  priceMinor: number;
  reasonCode: string;
  key?: string;
}): Promise<RpcResult<{ status: string }>> {
  return callVenue('set_ticket_type_price', {
    p_ticket_type_id: params.ticketTypeId,
    p_price_minor: params.priceMinor,
    p_reason_code: params.reasonCode,
    p_command_key: params.key ?? commandKey('price'),
  });
}

/** venue.set_batch_capacity(p_batch_id, p_new_capacity, p_reason_code, p_command_key) */
export async function setBatchCapacity(params: {
  batchId: string;
  newCapacity: number;
  reasonCode: string;
  key?: string;
}): Promise<RpcResult<{ status: string }>> {
  return callVenue('set_batch_capacity', {
    p_batch_id: params.batchId,
    p_new_capacity: params.newCapacity,
    p_reason_code: params.reasonCode,
    p_command_key: params.key ?? commandKey('cap'),
  });
}

/* ────────────────────────────────────────────────────────────────────────────
 * Buying (fan side)
 * ──────────────────────────────────────────────────────────────────────────── */

/**
 * venue.reserve_primary_inventory(p_batch_id, p_quantity, p_command_key)
 *
 * Takes a short-lived hold so a buyer can pay without the inventory moving.
 * The hold expires on a TTL and is swept by `sweep-expired-inventory-holds`.
 * The command key MUST be stable for the buyer's attempt so a retry does not
 * take a second hold against the same intent.
 */
export async function reserveInventory(params: {
  batchId: string;
  quantity: number;
  key: string;
}): Promise<RpcResult<InventoryHold>> {
  return callVenue('reserve_primary_inventory', {
    p_batch_id: params.batchId,
    p_quantity: params.quantity,
    p_command_key: params.key,
  });
}

/** venue.release_inventory_hold(p_hold_id, p_command_key) — call on abandon or back. */
export async function releaseHold(holdId: string, key?: string): Promise<RpcResult<{ status: string }>> {
  return callVenue('release_inventory_hold', {
    p_hold_id: holdId,
    p_command_key: key ?? commandKey('rel'),
  });
}

/**
 * venue.create_primary_checkout(p_session_id, p_items jsonb, p_hold_ids uuid[], p_command_key)
 *
 * Creates the pending order the payment will be attached to. The server is the
 * price authority: `unitPriceMinor` is what the buyer was shown, and a mismatch
 * is rejected rather than silently repriced.
 */
export async function createPrimaryCheckout(params: {
  sessionId: string;
  items: CheckoutItem[];
  holdIds: string[];
  key: string;
}): Promise<RpcResult<PrimaryOrder>> {
  return callVenue('create_primary_checkout', {
    p_session_id: params.sessionId,
    p_items: params.items.map((i) => ({
      ticket_type_id: i.ticketTypeId,
      quantity: i.quantity,
      unit_price_minor: i.unitPriceMinor,
    })),
    p_hold_ids: params.holdIds,
    p_command_key: params.key,
  });
}

/**
 * PAYMENT AND ISSUANCE DO NOT LIVE HERE.
 *
 * `venue.finalize_primary_order` and `kernel.issue_ticket_atoms` are service_role
 * only by design: a client must never be able to mark its own order paid or mint
 * its own tickets. The flow is:
 *
 *   client  -> createPrimaryCheckout()          (this module)
 *   client  -> `primary-checkout` edge function (NOT YET BUILT) mints a Stripe
 *              PaymentIntent against the order
 *   Stripe  -> `stripe-webhook` native branch   (NOT YET BUILT) calls
 *              venue.finalize_primary_order on payment_intent.succeeded, which
 *              issues the tickets inside one transaction
 *
 * The two missing edge artifacts are tracked in
 * PHASE2_PRIMARY_ACTIVATION_GAP_MATRIX.md. Do not work around them by granting a
 * client role access to either RPC.
 */

/* ────────────────────────────────────────────────────────────────────────────
 * Reads
 * ──────────────────────────────────────────────────────────────────────────── */

/** Ticket types a buyer may see for a session. Hidden and unlisted are filtered by RLS. */
export async function listTicketTypes(eventId: string): Promise<RpcResult<TicketType[]>> {
  const { data, error } = await (supabase as any)
    .schema('venue')
    .from('ticket_type')
    .select('ticket_type_id, event_id, kind, name, price_minor, currency, visibility')
    .eq('event_id', eventId)
    .eq('visibility', 'public')
    .order('price_minor', { ascending: true });

  if (error) return normalizeError(error);
  return {
    ok: true,
    data: (data ?? []).map((r: any) => ({
      ticketTypeId: r.ticket_type_id,
      eventId: r.event_id,
      kind: r.kind,
      name: r.name,
      priceMinor: r.price_minor,
      currency: r.currency ?? 'USD',
      visibility: r.visibility,
    })),
  };
}

/**
 * Coarse availability for a session's batches.
 *
 * Deliberately returns a band, never an exact remaining count. Exact counts leak
 * commercial information and invite scraping, and the corpus treats inventory
 * levels as venue-private.
 */
export async function sessionAvailability(
  sessionId: string,
): Promise<RpcResult<Record<string, 'available' | 'low' | 'sold_out'>>> {
  const { data, error } = await (supabase as any)
    .schema('venue')
    .from('inventory_batch')
    .select('batch_id, ticket_type_id, capacity, held, sold')
    .eq('session_id', sessionId);

  if (error) return normalizeError(error);

  const byType: Record<string, 'available' | 'low' | 'sold_out'> = {};
  for (const b of (data ?? []) as InventoryBatch[] & any[]) {
    const remaining = (b.capacity ?? 0) - (b.held ?? 0) - (b.sold ?? 0);
    const band = remaining <= 0 ? 'sold_out' : remaining <= Math.max(5, (b.capacity ?? 0) * 0.1) ? 'low' : 'available';
    const current = byType[b.ticket_type_id];
    // Best band across batches wins: any available batch means the type is available.
    byType[b.ticket_type_id] =
      current === 'available' || band === 'available'
        ? 'available'
        : current === 'low' || band === 'low'
          ? 'low'
          : 'sold_out';
  }
  return { ok: true, data: byType };
}
