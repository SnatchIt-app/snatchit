/**
 * src/lib/primary/discovery.ts — buyer discovery and session detail for PRIMARY tickets
 * (CONTRACTS C1; registry 182 = D's #170, DARK until applied; A reviews, C consumes).
 *
 *   public.list_primary_sessions_on_sale()   anon + auth → (event_id, session_id, title, venue_name,
 *                                            neighborhood, starts_at, doors_at, age_restriction, status)
 *   public.get_primary_session(p_session_id) anon + auth → one row (session, event, venue, ticket_types)
 *                                            or ZERO rows for unknown/draft/announced/cancelled — that is
 *                                            "not available", never an error and never an existence leak.
 *
 * Display rules held here:
 *   - times: the session's `*_local` strings + the venue `timezone` (A's rule from D's 162); the list
 *     rows carry only instants, so the list shows times through the session read (see the screen);
 *   - tiers: the server's `on_sale_now` decides; the device clock never puts a tier on sale. `remaining`
 *     only distinguishes sold out — no counts are shown (no invented scarcity);
 *   - prices (A's all-in rule, US live-event ticket pricing): a tier shows ONLY the server's
 *     `all_in_price_minor` — face + buyer fee, computed with the checkout's own rounding (half-up on
 *     `fee.buyer_service_bps`; requested from D on 182's tier rows). Face value is never shown as the
 *     price. While the field is absent, or null because the fee is unset, the tier shows no price and
 *     reads "Not on sale yet" (not purchasable).
 */
import { supabase } from '@/src/lib/supabase';
import { isNetworkError } from '@/src/lib/ui/loadState';

import { sessionFactsFromRow, type RpcReader, type RpcResult, type SessionFacts } from '@/src/lib/tickets/entitlementReads';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export interface DiscoveryRow {
  eventId: string;
  sessionId: string;
  title: string;
  venueName: string | null;
  neighborhood: string | null;
  startsAt: string;
  doorsAt: string | null;
  ageRestriction: string | null;
  status: string;
}

const s = (v: unknown): string | null => (typeof v === 'string' && v.length > 0 ? v : null);

export function parseDiscoveryRows(data: unknown): DiscoveryRow[] | null {
  if (!Array.isArray(data)) return null;
  const out: DiscoveryRow[] = [];
  for (const raw of data) {
    if (!raw || typeof raw !== 'object') continue;
    const r = raw as Record<string, unknown>;
    const eventId = s(r.event_id); const sessionId = s(r.session_id); const title = s(r.title); const startsAt = s(r.starts_at); const status = s(r.status);
    if (!eventId || !sessionId || !UUID_RE.test(sessionId) || !title || !startsAt || !status) continue;
    out.push({
      eventId, sessionId, title, startsAt, status,
      venueName: s(r.venue_name), neighborhood: s(r.neighborhood), doorsAt: s(r.doors_at), ageRestriction: s(r.age_restriction),
    });
  }
  return out;
}

export interface PrimaryTier {
  ticket_type_id: string;
  name: string;
  price_minor: number;
  currency: string;
  visibility: string;
  display_rank: number;
  sale_starts_at: string | null;
  sale_ends_at: string | null;
  on_sale_now: boolean;
  remaining: number;
  /** Face + buyer fee in integer cents (server rounding). Absent until 182 carries it; null while the fee is unset. */
  all_in_price_minor?: number | null;
}

function isTier(v: unknown): v is PrimaryTier {
  if (!v || typeof v !== 'object') return false;
  const t = v as Record<string, unknown>;
  return (
    typeof t.ticket_type_id === 'string' && typeof t.name === 'string' && typeof t.price_minor === 'number' &&
    typeof t.currency === 'string' && typeof t.on_sale_now === 'boolean' && typeof t.remaining === 'number' &&
    typeof t.display_rank === 'number' &&
    (t.sale_starts_at === null || typeof t.sale_starts_at === 'string') &&
    (t.sale_ends_at === null || typeof t.sale_ends_at === 'string')
  );
}

export interface PrimarySessionDetail {
  sessionId: string;
  facts: SessionFacts;
  description: string | null;
  neighborhood: string | null;
  tiers: PrimaryTier[];
}

export function parsePrimarySession(row: unknown): PrimarySessionDetail | null {
  const facts = sessionFactsFromRow(row);
  if (!facts) return null;
  const r = row as Record<string, unknown>;
  const session = r.session as Record<string, unknown>;
  const event = r.event as Record<string, unknown>;
  const venue = (r.venue && typeof r.venue === 'object' ? r.venue : {}) as Record<string, unknown>;
  const sessionId = s(session.session_id);
  if (!sessionId) return null;
  const tiers = (Array.isArray(r.ticket_types) ? r.ticket_types : []).filter(isTier).sort((a, b) => a.display_rank - b.display_rank);
  return { sessionId, facts, description: s(event.description), neighborhood: s(venue.neighborhood), tiers };
}

export type SessionDetailLoad =
  | { kind: 'loading' }
  | { kind: 'not_available' }
  | { kind: 'failed'; failure: 'offline' | 'unavailable' }
  | { kind: 'ready'; detail: PrimarySessionDetail };

export async function readPrimarySessionDetail(read: RpcReader, sessionId: string, isOffline: boolean): Promise<SessionDetailLoad> {
  if (!UUID_RE.test(sessionId)) return { kind: 'not_available' };
  let res: RpcResult;
  try {
    res = await read(sessionId);
  } catch {
    return { kind: 'failed', failure: isOffline ? 'offline' : 'unavailable' };
  }
  if (res.error) return { kind: 'failed', failure: isOffline || isNetworkError(res.error) ? 'offline' : 'unavailable' };
  if (!Array.isArray(res.data)) return { kind: 'failed', failure: 'unavailable' };
  if (res.data.length === 0) return { kind: 'not_available' };
  const detail = parsePrimarySession(res.data[0]);
  return detail ? { kind: 'ready', detail } : { kind: 'failed', failure: 'unavailable' };
}

export type DiscoveryLoad =
  | { kind: 'loading' }
  | { kind: 'failed'; failure: 'offline' | 'unavailable' }
  | { kind: 'ready'; rows: DiscoveryRow[] };

export async function readDiscovery(read: () => Promise<RpcResult>, isOffline: boolean): Promise<DiscoveryLoad> {
  let res: RpcResult;
  try {
    res = await read();
  } catch {
    return { kind: 'failed', failure: isOffline ? 'offline' : 'unavailable' };
  }
  if (res.error) return { kind: 'failed', failure: isOffline || isNetworkError(res.error) ? 'offline' : 'unavailable' };
  const rows = parseDiscoveryRows(res.data);
  return rows ? { kind: 'ready', rows } : { kind: 'failed', failure: 'unavailable' };
}

export const discoveryRpc = (): Promise<RpcResult> =>
  supabase.rpc('list_primary_sessions_on_sale') as unknown as Promise<RpcResult>;

export const primarySessionRpc: RpcReader = (sessionId) =>
  supabase.rpc('get_primary_session', { p_session_id: sessionId }) as unknown as Promise<RpcResult>;

function usd(minor: unknown, currency: unknown): string {
  if (currency !== 'USD' && currency !== 'usd') return '—';
  if (typeof minor !== 'number' || !Number.isInteger(minor) || minor < 0) return '—';
  return `$${Math.floor(minor / 100).toLocaleString('en-US')}.${String(minor % 100).padStart(2, '0')}`;
}

export interface TierLine {
  name: string;
  /** The ALL-IN price, or null when the server gave none — face value is never shown here. */
  price: string | null;
  status: 'On sale' | 'Sold out' | 'Not on sale yet' | 'Sales ended' | 'Not on sale';
  available: boolean;
}

/**
 * `nowMs` only words a closed window ("yet" vs "ended"); it never opens one — `on_sale_now` decides.
 * Without a server all-in price the tier cannot be bought and shows no price (A's all-in rule).
 */
export function tierLine(t: PrimaryTier, nowMs: number): TierLine {
  const price = typeof t.all_in_price_minor === 'number' ? usd(t.all_in_price_minor, t.currency) : null;
  const shown = price === '—' ? null : price;
  const base = { name: t.name, price: shown };
  if (t.on_sale_now) {
    if (shown === null) return { ...base, status: 'Not on sale yet', available: false };
    return t.remaining > 0 ? { ...base, status: 'On sale', available: true } : { ...base, status: 'Sold out', available: false };
  }
  const starts = t.sale_starts_at ? Date.parse(t.sale_starts_at) : NaN;
  const ends = t.sale_ends_at ? Date.parse(t.sale_ends_at) : NaN;
  if (Number.isFinite(starts) && starts > nowMs) return { ...base, status: 'Not on sale yet', available: false };
  if (Number.isFinite(ends) && ends <= nowMs) return { ...base, status: 'Sales ended', available: false };
  return { ...base, status: 'Not on sale', available: false };
}

export const DISCOVERY_COPY = {
  listTitle: 'Events',
  listEmptyTitle: 'No events on sale right now',
  listEmptyBody: 'Events with tickets on sale will show up here.',
  notAvailableTitle: 'This event isn’t available',
  notAvailableBody: 'It may not be on sale yet, or it may have ended.',
  ticketsHeading: 'Tickets',
  priceNote: 'Prices include all fees.',
  /** `all_in_price_minor` is a ONE-ticket figure (A, 2026-10-26): checkout rounds the fee once per order,
   *  so it is never multiplied — a multi-ticket total exists only as the checkout quote's `total`. */
  perTicket: 'per ticket',
} as const;
