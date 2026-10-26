/**
 * src/lib/tickets/entitlement.ts — the buyer's admission entitlement, presentation side
 * (Q02–Q05, 2026-10-26 sprint, lane C).
 *
 * One ADMISSION ENTITLEMENT = one kernel ticket atom (kernel.tickets row). Its facts come from the
 * server: `state` (issued | active | scanned | voided | expired), `resale_state` (none | listed |
 * locked | refund_hold | dispute_hold) and `credential_version`. This module only maps those facts
 * to what the screen may SAY; it never decides that a ticket is valid, and it never builds a code.
 *
 * The QR is the SNATCHIT-TICKET-CRED-V1 compact token minted by the `credential-sign` edge function
 * for the atom's owner (body `{ ticket_atom_id }`, owner derived from the JWT). The client treats
 * the token as an opaque string: it is drawn, never decoded, never assembled, never cached past the
 * server's TTL. `parseCredentialResponse` admits exactly the documented success body and maps the
 * documented refusals; anything else is "unavailable" and no code is drawn.
 *
 * CONTRACT STATUS (CONTRACTS.md, lane A): the per-atom owner read that supplies `MyTicketAtom` rows
 * (`public.get_my_ticket_atoms(p_event_session_id)`) is REQUESTED, not deployed; the paid-but-unissued
 * hint (`IssuanceHint`) is REQUESTED. The credential-sign response shape is read from the edge source
 * in this tree. Nothing here is a claim that any of it is live.
 */

import { ORDER_COPY, type IssuanceHint } from './primaryOrders';

export type AtomState = 'issued' | 'active' | 'scanned' | 'voided' | 'expired';
export type ResaleState = 'none' | 'listed' | 'locked' | 'refund_hold' | 'dispute_hold';

/** One row of the requested owner-scoped per-atom read. */
export interface MyTicketAtom {
  ticket_atom_id: string;
  serial_no: number;
  ticket_type_id: string;
  ticket_type_name: string;
  state: AtomState;
  resale_state: ResaleState;
  credential_version: number;
  issued_at: string | null;
}

/** What the screen may say about one entitlement. Only `ready` may ask for a code. */
export type EntitlementDisplay = 'ready' | 'used' | 'revoked' | 'expired' | 'held' | 'unknown';

const LIVE_STATES: ReadonlySet<string> = new Set<AtomState>(['issued', 'active']);
const HELD_RESALE: ReadonlySet<string> = new Set<ResaleState>(['listed', 'locked', 'refund_hold', 'dispute_hold']);

export function entitlementDisplay(atom: Pick<MyTicketAtom, 'state' | 'resale_state'>): EntitlementDisplay {
  switch (atom.state) {
    case 'scanned': return 'used';
    case 'voided': return 'revoked';
    case 'expired': return 'expired';
    default:
      if (!LIVE_STATES.has(atom.state)) return 'unknown';
      if (atom.resale_state === 'none') return 'ready';
      if (HELD_RESALE.has(atom.resale_state)) return 'held';
      return 'unknown';
  }
}

export function canRequestCredential(display: EntitlementDisplay): boolean {
  return display === 'ready';
}

export const ENTITLEMENT_COPY: Record<EntitlementDisplay, { badge: string; body: string }> = {
  ready: { badge: 'Ready', body: 'Show this code at the door. Staff will also check your ID.' },
  used: { badge: 'Used', body: 'This ticket has been scanned for entry.' },
  revoked: { badge: 'Revoked', body: 'This ticket is no longer accepted for entry.' },
  expired: { badge: 'Expired', body: 'This event has ended.' },
  held: { badge: 'On hold', body: 'This ticket is listed or on hold, so it can’t be used for entry right now.' },
  unknown: { badge: 'Status unknown', body: 'We couldn’t confirm this ticket’s status. Pull down to refresh.' },
};

// ── Screen-level state ───────────────────────────────────────────────────────

export type AtomsFailure = 'offline' | 'unavailable' | 'signed_out';
export type AtomsLoad =
  | { kind: 'loading' }
  | { kind: 'failed'; failure: AtomsFailure }
  | { kind: 'ready'; atoms: MyTicketAtom[] };

/**
 * The order read's verdict (primaryOrders.ts `issuanceHint`, CONTRACTS C5 + A's payment_state ruling).
 * Re-exported so screens import one vocabulary.
 */
export type { IssuanceHint } from './primaryOrders';

export type DetailState =
  | { kind: 'loading' }
  | { kind: 'failed'; failure: AtomsFailure }
  | { kind: 'awaiting_confirmation' }
  | { kind: 'payment_processing' }
  | { kind: 'pending_issuance' }
  | { kind: 'payment_failed' }
  | { kind: 'not_on_account' }
  | { kind: 'inconsistent' }
  | { kind: 'empty' }
  | { kind: 'atoms'; atoms: MyTicketAtom[] };

/**
 * `expectedQuantity` is the group row's quantity from get_my_tickets (what the person was told they
 * own). A per-atom read of zero against an expectation above zero is a contradiction between two
 * server reads, shown as such — never as "no tickets". With atoms on screen the orders add only
 * their own line (the order list); they never hide an atom or invent one.
 */
export function detailState(load: AtomsLoad, issuance: IssuanceHint, expectedQuantity: number): DetailState {
  if (load.kind === 'loading') return { kind: 'loading' };
  if (load.kind === 'failed') return { kind: 'failed', failure: load.failure };
  if (load.atoms.length > 0) return { kind: 'atoms', atoms: load.atoms };
  switch (issuance) {
    case 'awaiting_confirmation': return { kind: 'awaiting_confirmation' };
    case 'payment_processing': return { kind: 'payment_processing' };
    case 'paid_pending': return { kind: 'pending_issuance' };
    case 'payment_failed': return { kind: 'payment_failed' };
    case 'issued': return { kind: 'not_on_account' };
    default: break;
  }
  if (expectedQuantity > 0) return { kind: 'inconsistent' };
  return { kind: 'empty' };
}

export const DETAIL_COPY = {
  awaiting_confirmation: ORDER_COPY.awaiting,
  payment_processing: ORDER_COPY.processing,
  pending_issuance: ORDER_COPY.paidPending,
  payment_failed: ORDER_COPY.failed,
  not_on_account: ORDER_COPY.elsewhere,
  inconsistent: { title: 'Couldn’t load your tickets', body: 'We couldn’t load the tickets for this event. Pull down to try again.' },
  empty: { title: 'No tickets for this event', body: 'Tickets you own for this event will show up here.' },
  offline: { title: 'You’re offline', body: 'Your tickets will load when you’re back online.' },
  unavailable: { title: 'Couldn’t load your tickets', body: 'Something went wrong on our side. Pull down to try again.' },
  signed_out: { title: 'Sign in required', body: 'Sign in to see your tickets.' },
} as const;

// ── Credential (the QR payload) ──────────────────────────────────────────────

export interface Credential {
  /** The compact token, opaque to the client. Drawn as-is in byte mode. */
  token: string;
  credential_version: number;
  signing_key_id: string;
  /** The signed `exp` restated as a timestamp — shown as text, never used to authorise anything. */
  not_after: string;
  ttl_seconds: number;
}

export type CredentialRefusal =
  | 'not_owner'
  | 'atom_terminal'
  | 'signing_unavailable'
  | 'rate_limited'
  | 'signed_out'
  | 'offline'
  | 'unavailable';

export type CredentialState =
  | { kind: 'idle' }
  | { kind: 'minting' }
  | { kind: 'ready'; credential: Credential; receivedAtMs: number }
  | { kind: 'refused'; reason: CredentialRefusal };

const MAX_TOKEN_CHARS = 8192;
const B64URL_SEGMENT = /^[A-Za-z0-9_-]+$/;

/** The wire shape SCANNER-CONTRACT-v1 §1 strictly reads: three unpadded base64url segments, ≤ 8192 chars. */
export function looksLikeCompactToken(value: unknown): value is string {
  if (typeof value !== 'string' || value.length === 0 || value.length > MAX_TOKEN_CHARS) return false;
  const parts = value.split('.');
  return parts.length === 3 && parts.every((p) => p.length > 0 && B64URL_SEGMENT.test(p));
}

const SIGNING_CODES: ReadonlySet<string> = new Set([
  'signing_key_unavailable',
  'signing_context_unrecognized',
  'signing_unhealthy',
]);

/**
 * `status` is the HTTP status (null when no response arrived); `body` the parsed JSON, if any.
 * A success is admitted only when every documented field has its documented type and the token
 * has the wire shape. Nothing else ever yields a drawable credential.
 */
export function parseCredentialResponse(
  status: number | null,
  body: unknown,
): { ok: true; credential: Credential } | { ok: false; reason: CredentialRefusal } {
  if (status === null) return { ok: false, reason: 'offline' };
  const b = (body && typeof body === 'object' ? body : {}) as Record<string, unknown>;
  const code = typeof b.code === 'string' ? b.code : '';
  if (status === 200) {
    if (
      looksLikeCompactToken(b.token) &&
      typeof b.credential_version === 'number' && Number.isInteger(b.credential_version) && b.credential_version >= 0 &&
      typeof b.signing_key_id === 'string' &&
      typeof b.not_after === 'string' &&
      typeof b.ttl_seconds === 'number' && b.ttl_seconds > 0
    ) {
      return {
        ok: true,
        credential: {
          token: b.token,
          credential_version: b.credential_version,
          signing_key_id: b.signing_key_id,
          not_after: b.not_after,
          ttl_seconds: b.ttl_seconds,
        },
      };
    }
    return { ok: false, reason: 'unavailable' };
  }
  if (status === 401) return { ok: false, reason: 'signed_out' };
  if (status === 403 && code === 'not_owner') return { ok: false, reason: 'not_owner' };
  if (status === 409 && code === 'atom_terminal') return { ok: false, reason: 'atom_terminal' };
  if (status === 429) return { ok: false, reason: 'rate_limited' };
  if (SIGNING_CODES.has(code)) return { ok: false, reason: 'signing_unavailable' };
  return { ok: false, reason: 'unavailable' };
}

/**
 * Stale = the server TTL has elapsed on a MONOTONIC clock since receipt, or the atom's
 * credential_version moved on (a reissue). The device wall clock never decides this.
 */
export function credentialStale(state: CredentialState, nowMs: number, versionNow: number): boolean {
  if (state.kind !== 'ready') return false;
  if (state.credential.credential_version !== versionNow) return true;
  return nowMs - state.receivedAtMs >= state.credential.ttl_seconds * 1000;
}

/**
 * Refusals that say the CODE ITSELF is no longer good for this person: the server refused the
 * ticket (terminal, not theirs) or the session (signed out). A code on screen is withdrawn.
 */
const WITHDRAWS_CODE: ReadonlySet<CredentialRefusal> = new Set(['not_owner', 'atom_terminal', 'signed_out']);

/**
 * C-R4 (E, 2026-10-26): the state after a mint answers. A refresh that is refused for a transient
 * reason (rate limit, offline, signing briefly unavailable, unreadable answer) keeps a code that
 * is still within its server TTL and version, with a short note; the code goes only when the
 * server says the ticket or the session is no longer good, or when `credentialStale` says so.
 */
export function afterMint(
  prev: CredentialState,
  result: { ok: true; credential: Credential } | { ok: false; reason: CredentialRefusal },
  nowMs: number,
  versionNow: number,
): { state: CredentialState; note: string | null } {
  if (result.ok) return { state: { kind: 'ready', credential: result.credential, receivedAtMs: nowMs }, note: null };
  if (prev.kind === 'ready' && !WITHDRAWS_CODE.has(result.reason) && !credentialStale(prev, nowMs, versionNow)) {
    return { state: prev, note: REFRESH_KEPT_NOTE };
  }
  return { state: { kind: 'refused', reason: result.reason }, note: null };
}

export const REFRESH_KEPT_NOTE = 'Couldn’t refresh the code just now. The code shown is the one you already have.';

export const CREDENTIAL_COPY: Record<CredentialRefusal, string> = {
  not_owner: 'This ticket isn’t on this account.',
  atom_terminal: 'This ticket can’t be used for entry any more.',
  signing_unavailable: 'Entry codes are temporarily unavailable. Try again in a moment.',
  rate_limited: 'Too many requests. Try again in a minute.',
  signed_out: 'Sign in again to show your entry code.',
  offline: 'You’re offline. Your entry code needs a connection to load.',
  unavailable: 'Couldn’t load your entry code. Try again.',
};
