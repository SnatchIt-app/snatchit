/**
 * src/lib/tickets/ticketState.ts — pure presentation logic for owned tickets.
 *
 * All mapping from the Core vocabulary to user-facing labels/tones lives here so
 * it is tested once and the screen stays declarative. The words stay truthful to
 * the contract; only the phrasing is ours. No color-only state — every status has
 * a word. No AI language.
 */

import type { BadgeTone } from '@/src/components/ui/Badge';
import type {
  FulfillmentStatus,
  MyTicketGroup,
  OwnershipStatus,
  TicketsError,
} from './types';

// ─── Ownership status (from kernel.tickets.state) ───────────────────────────

export function ownershipLabel(status: OwnershipStatus): string {
  switch (status) {
    case 'valid': return 'Valid';
    case 'used': return 'Used';
    case 'void': return 'Void';
    case 'expired': return 'Expired';
  }
}

export function ownershipTone(status: OwnershipStatus): BadgeTone {
  switch (status) {
    case 'valid': return 'success';
    case 'used': return 'neutral';
    case 'void': return 'danger';
    case 'expired': return 'neutral';
  }
}

// ─── Fulfillment / delivery status (from kernel.tickets.resale_state) ────────

export function fulfillmentLabel(status: FulfillmentStatus): string {
  switch (status) {
    case 'held': return 'Owned';
    case 'listed': return 'Listed for resale';
    case 'in_transfer': return 'Transfer in progress';
    case 'payment_hold': return 'Payment hold';
    case 'disputed': return 'Disputed';
  }
}

export function fulfillmentTone(status: FulfillmentStatus): BadgeTone {
  switch (status) {
    case 'held': return 'neutral';
    case 'listed': return 'neutral';
    case 'in_transfer': return 'neutral';
    case 'payment_hold': return 'warning';
    case 'disputed': return 'danger';
  }
}

/**
 * 'held' is the ordinary "you own it" state and needs no badge — showing it on
 * every card is noise. Every other fulfillment state is worth surfacing.
 */
export function showFulfillmentBadge(status: FulfillmentStatus): boolean {
  return status !== 'held';
}

// ─── Quantity ───────────────────────────────────────────────────────────────

export function quantityLabel(n: number): string {
  return `${n} ${n === 1 ? 'ticket' : 'tickets'}`;
}

/** Compact "2 x GA" style used on a row. */
export function ticketTypeLine(group: Pick<MyTicketGroup, 'quantity' | 'ticket_type_name'>): string {
  return `${group.quantity} x ${group.ticket_type_name}`;
}

// ─── Time / date ────────────────────────────────────────────────────────────

/**
 * Absolute instant -> a short local date+time label, e.g. "Sat, Oct 4 - 10:00 PM".
 * Defensive: an unparseable value returns ''. Uses the device locale/timezone via
 * toLocale*; the classification itself is never recomputed here (the server's
 * time_class is authoritative).
 */
export function eventDateLabel(iso: string | null | undefined): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const date = d.toLocaleDateString(undefined, {
    weekday: 'short', month: 'short', day: 'numeric',
  });
  const time = d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  return `${date} - ${time}`;
}

// ─── Sectioning & grouping (order-preserving) ───────────────────────────────

export function splitByTimeClass(rows: MyTicketGroup[]): {
  upcoming: MyTicketGroup[];
  past: MyTicketGroup[];
} {
  const upcoming: MyTicketGroup[] = [];
  const past: MyTicketGroup[] = [];
  for (const r of rows) (r.time_class === 'past' ? past : upcoming).push(r);
  return { upcoming, past };
}

export interface EventGroup {
  /** Stable list key: the session plus its event. */
  key: string;
  event_session_id: string;
  event_title: string;
  session_label: string | null;
  starts_at: string;
  ends_at: string | null;
  venue_name: string;
  artwork_ref: string | null;
  time_class: MyTicketGroup['time_class'];
  /** The distinct (ownership x fulfillment x type) rows for this session. */
  rows: MyTicketGroup[];
}

/**
 * Collapse the flat contract rows into per-session visual groups WITHOUT
 * destroying any state distinction: every distinct row stays its own entry under
 * the event. Server order is preserved (first appearance of a session fixes its
 * position), so the section ordering the RPC guarantees is untouched.
 */
export function groupByEvent(rows: MyTicketGroup[]): EventGroup[] {
  const order: string[] = [];
  const byKey = new Map<string, EventGroup>();
  for (const r of rows) {
    const key = r.event_session_id;
    let g = byKey.get(key);
    if (!g) {
      g = {
        key,
        event_session_id: r.event_session_id,
        event_title: r.event_title,
        session_label: r.session_label,
        starts_at: r.starts_at,
        ends_at: r.ends_at,
        venue_name: r.venue_name,
        artwork_ref: r.artwork_ref,
        time_class: r.time_class,
        rows: [],
      };
      byKey.set(key, g);
      order.push(key);
    }
    g.rows.push(r);
  }
  return order.map((k) => byKey.get(k) as EventGroup);
}

// ─── Error classification ───────────────────────────────────────────────────

/**
 * Map a supabase-js error to the screen's state. Auth failures (42501 anon /
 * 28000 tickets_unauthenticated) route to sign-in; everything else is a
 * retryable transient. The raw SQLSTATE/message is never shown to the user.
 */
export function classifyTicketsError(error: { code?: string | null } | null | undefined): TicketsError {
  const code = error?.code ?? '';
  if (code === '42501' || code === '28000') return 'auth';
  return 'retry';
}
