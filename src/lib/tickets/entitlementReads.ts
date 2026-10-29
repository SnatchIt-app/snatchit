/**
 * src/lib/tickets/entitlementReads.ts — the network edge of the buyer's entitlement screen, with
 * every transport injected so the rules are testable without Supabase.
 *
 *   mintCredential      → edge `credential-sign`, body exactly `{ ticket_atom_id }` (spec §3.2: no
 *                         version or key id from the client). The response is admitted only through
 *                         `parseCredentialResponse`.
 *   readMyAtoms         → `public.get_my_ticket_atoms(p_event_session_id)`  (registry 182, D; PENDING)
 *   readMyPrimaryOrders → `public.get_my_primary_orders(p_event_session_id)` (registry 182, D; PENDING)
 *   readPrimarySession  → `public.get_primary_session(p_session_id)` (registry 182, D; PENDING): the event
 *                         facts in the venue's own zone (`timezone`, `*_local`) and the age note. 0 rows
 *                         (draft/announced/cancelled/unknown) and failures are both `null` facts.
 *   (orders → words: primaryOrders.ts `issuanceHint`, A's C5 payment_state ruling.)
 *   bindOwnerFromAuthEvent / watchEntitlementSignOut → the cache follows the session (Q04).
 *
 * Failure vocabulary is the app's: a failed read is `failed`, never an empty list (a count of zero
 * is a claim shaped like a fact).
 */
import { supabase } from '@/src/lib/supabase';
import { isNetworkError } from '@/src/lib/ui/loadState';

import {
  parseCredentialResponse,
  type AtomsLoad,
  type Credential,
  type CredentialRefusal,
  type MyTicketAtom,
} from './entitlement';
import { bindEntitlementOwner } from './entitlementStore';
import type { PrimaryOrderRow } from './primaryOrders';

export type { PrimaryOrderRow } from './primaryOrders';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const AUTH_CODES: ReadonlySet<string> = new Set(['42501', '28000', 'PGRST301']);

// ── Edge function ────────────────────────────────────────────────────────────

/** Calls an edge function; resolves to the HTTP status (null when nothing came back) and parsed JSON. */
export type Invoker = (name: string, body: unknown) => Promise<{ status: number | null; body: unknown }>;

export async function mintCredential(
  invoke: Invoker,
  atomId: string,
): Promise<{ ok: true; credential: Credential } | { ok: false; reason: CredentialRefusal }> {
  if (!UUID_RE.test(atomId)) return { ok: false, reason: 'unavailable' };
  let res: { status: number | null; body: unknown };
  try {
    res = await invoke('credential-sign', { ticket_atom_id: atomId });
  } catch {
    return { ok: false, reason: 'offline' };
  }
  return parseCredentialResponse(res.status, res.body);
}

/**
 * Adapts supabase-js: a non-2xx answer arrives as a FunctionsHttpError whose `context` is the
 * Response; a fetch failure as FunctionsFetchError (no response at all); a relay failure as
 * FunctionsRelayError (the platform answered, not the function).
 */
export const supabaseInvoker: Invoker = async (name, body) => {
  const { data, error } = await supabase.functions.invoke(name, { body: body as Record<string, unknown> });
  if (!error) return { status: 200, body: data };
  const ctx = (error as { context?: unknown }).context;
  if (ctx && typeof ctx === 'object' && typeof (ctx as { status?: unknown }).status === 'number') {
    const response = ctx as { status: number; json?: () => Promise<unknown> };
    let parsed: unknown = null;
    try { parsed = response.json ? await response.json() : null; } catch { parsed = null; }
    return { status: response.status, body: parsed };
  }
  if ((error as { name?: string }).name === 'FunctionsRelayError') return { status: 502, body: null };
  return { status: null, body: null };
};

// ── RPC reads ────────────────────────────────────────────────────────────────

export type RpcResult = { data: unknown; error: { code?: string | null; message?: string | null } | null };
export type RpcReader = (eventSessionId: string) => Promise<RpcResult>;

const ATOM_STATES: ReadonlySet<string> = new Set(['issued', 'active', 'scanned', 'voided', 'expired']);

function isAtomRow(v: unknown): v is MyTicketAtom {
  if (!v || typeof v !== 'object') return false;
  const r = v as Record<string, unknown>;
  return (
    typeof r.ticket_atom_id === 'string' && UUID_RE.test(r.ticket_atom_id) &&
    typeof r.serial_no === 'number' &&
    typeof r.ticket_type_id === 'string' &&
    typeof r.ticket_type_name === 'string' &&
    typeof r.state === 'string' &&
    typeof r.resale_state === 'string' &&
    typeof r.credential_version === 'number' &&
    (r.issued_at === null || typeof r.issued_at === 'string')
  );
}

function failureOf(error: { code?: string | null; message?: string | null } | null, isOffline: boolean): AtomsLoad {
  if (error?.code && AUTH_CODES.has(error.code)) return { kind: 'failed', failure: 'signed_out' };
  if (isOffline || isNetworkError(error)) return { kind: 'failed', failure: 'offline' };
  return { kind: 'failed', failure: 'unavailable' };
}

/** The owner's atoms for one event session. Rows outside the contract shape are dropped. */
export async function readMyAtoms(read: RpcReader, eventSessionId: string, isOffline: boolean): Promise<AtomsLoad> {
  let res: RpcResult;
  try {
    res = await read(eventSessionId);
  } catch (e) {
    return failureOf({ message: e instanceof Error ? e.message : null }, isOffline);
  }
  if (res.error) return failureOf(res.error, isOffline);
  if (!Array.isArray(res.data)) return { kind: 'failed', failure: 'unavailable' };
  const atoms = res.data.filter(isAtomRow);
  // Unknown state words stay as they are: entitlementDisplay maps them to 'unknown', never 'ready'.
  void ATOM_STATES;
  return { kind: 'ready', atoms };
}

export const atomsRpc: RpcReader = (eventSessionId) =>
  supabase.rpc('get_my_ticket_atoms', { p_event_session_id: eventSessionId }) as unknown as Promise<RpcResult>;

function isOrderRow(v: unknown): v is PrimaryOrderRow {
  if (!v || typeof v !== 'object') return false;
  const r = v as Record<string, unknown>;
  return (
    typeof r.order_id === 'string' &&
    typeof r.status === 'string' &&
    typeof r.total_minor === 'number' &&
    typeof r.currency === 'string' &&
    typeof r.created_at === 'string' &&
    typeof r.atoms_issued === 'number' &&
    typeof r.payment_state === 'string'
  );
}

/** Null on any failure, so the caller's hint is `unknown` — never `none`. */
export async function readMyPrimaryOrders(read: RpcReader, eventSessionId: string): Promise<PrimaryOrderRow[] | null> {
  try {
    const res = await read(eventSessionId);
    if (res.error || !Array.isArray(res.data)) return null;
    return res.data.filter(isOrderRow);
  } catch {
    return null;
  }
}

export const ordersRpc: RpcReader = (eventSessionId) =>
  supabase.rpc('get_my_primary_orders', { p_event_session_id: eventSessionId }) as unknown as Promise<RpcResult>;

// ── Session facts (get_primary_session) ─────────────────────────────────────

/** The subset of `get_primary_session` the ticket screen shows. Times are the venue's own clock. */
export interface SessionFacts {
  title: string | null;
  venueName: string | null;
  address: string | null;
  sessionLabel: string | null;
  /** IANA zone of the venue, e.g. 'America/New_York'. */
  timezone: string | null;
  /** 'YYYY-MM-DD HH24:MI' in the venue zone (D's 182 format). */
  startsAtLocal: string | null;
  doorsAtLocal: string | null;
  /** Absolute instant, for the zone abbreviation only. */
  startsAt: string | null;
  /** all_ages | 18_plus | 21_plus | null (not specified). Display only — the door checks ID. */
  ageRestriction: string | null;
}

const str = (v: unknown): string | null => (typeof v === 'string' && v.length > 0 ? v : null);

export function sessionFactsFromRow(row: unknown): SessionFacts | null {
  if (!row || typeof row !== 'object') return null;
  const r = row as Record<string, unknown>;
  const session = (r.session && typeof r.session === 'object' ? r.session : null) as Record<string, unknown> | null;
  const event = (r.event && typeof r.event === 'object' ? r.event : null) as Record<string, unknown> | null;
  const venue = (r.venue && typeof r.venue === 'object' ? r.venue : null) as Record<string, unknown> | null;
  if (!session || !event) return null;
  return {
    title: str(event.title),
    venueName: str(venue?.name),
    address: str(venue?.address),
    sessionLabel: str(session.session_label),
    timezone: str(session.timezone) ?? str(venue?.timezone),
    startsAtLocal: str(session.starts_at_local),
    doorsAtLocal: str(session.doors_at_local),
    startsAt: str(session.starts_at),
    ageRestriction: str(event.age_restriction),
  };
}

/** 0 rows (not available for this session) and any failure are both `null`: the screen falls back. */
export async function readPrimarySession(read: RpcReader, sessionId: string): Promise<SessionFacts | null> {
  try {
    const res = await read(sessionId);
    if (res.error || !Array.isArray(res.data) || res.data.length === 0) return null;
    return sessionFactsFromRow(res.data[0]);
  } catch {
    return null;
  }
}

export const sessionRpc: RpcReader = (sessionId) =>
  supabase.rpc('get_primary_session', { p_session_id: sessionId }) as unknown as Promise<RpcResult>;

// ── Session binding ──────────────────────────────────────────────────────────

/** Synchronous on purpose (auth-js holds its lock while listeners run; see savedListings.ts). */
export function bindOwnerFromAuthEvent(event: string, session: { user?: { id?: string | null } | null } | null): void {
  if (event === 'SIGNED_OUT' && session === null) {
    bindEntitlementOwner(null);
    return;
  }
  const id = session?.user?.id;
  if (id) bindEntitlementOwner(id);
}

let watching = false;
export function watchEntitlementSignOut(): void {
  if (watching) return;
  try {
    supabase.auth.onAuthStateChange((event, session) => { bindOwnerFromAuthEvent(event, session); });
    watching = true;
  } catch {
    // No auth client (tests, a broken build): the screen still binds the owner on every read.
  }
}
