/**
 * src/lib/tickets/types.ts — the Tickets ownership contract, frontend side.
 *
 * This mirrors public.get_my_tickets() EXACTLY as documented in
 * docs/product-v2/TICKETS_FRONTEND_CONTRACT_HANDOFF.md (Core @ 6dc3ee0). One row
 * per (event session x ticket type x ownership_status x fulfillment_status) group
 * the caller OWNS. Event-first: group by the show, count the tickets.
 *
 * Do not add fields the contract does not return. There is no ticket atom id, no
 * price, no seat data, no owner/credential/payment field — by Core design.
 */

export type OwnershipStatus = 'valid' | 'used' | 'void' | 'expired';

export type FulfillmentStatus =
  | 'held'
  | 'listed'
  | 'in_transfer'
  | 'payment_hold'
  | 'disputed';

export type TicketTimeClass = 'upcoming' | 'past';

export interface MyTicketGroup {
  event_id: string;
  event_session_id: string;
  event_title: string;
  session_label: string | null;
  /** Absolute timestamptz (ISO). Render in local/venue time; never reinterpret as floating. */
  starts_at: string;
  ends_at: string | null;
  doors_at: string | null;
  venue_id: string;
  venue_name: string;
  /** Opaque storage-object path. Resolve through EventMedia; never build a URL by hand. */
  artwork_ref: string | null;
  ticket_type_id: string;
  ticket_type_name: string;
  ticket_type_kind: 'admission' | 'table';
  /** Atoms in this group owned by the caller. >= 1. */
  quantity: number;
  ownership_status: OwnershipStatus;
  fulfillment_status: FulfillmentStatus;
  time_class: TicketTimeClass;
}

/** How the RPC call resolved, for the screen's state machine. */
export type TicketsError = 'auth' | 'retry';
