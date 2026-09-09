/**
 * src/lib/tickets/fixtures.ts — DEV-ONLY sample tickets for device review.
 *
 * Production returns [] today (native issuance is disabled server-side), so these
 * frontend-only fixtures let the owner review populated states on a physical
 * iPhone. They are NEVER written to any server and are gated behind __DEV__ and
 * an explicit in-screen toggle (off by default); real RPC data always wins. See
 * the Phase 11 report.
 *
 * Shapes conform exactly to MyTicketGroup (the same contract rows the RPC emits).
 */

import type { MyTicketGroup } from './types';

const daysFromNow = (n: number): string => {
  const d = new Date();
  d.setDate(d.getDate() + n);
  return d.toISOString();
};

/** Every ownership x fulfillment x time_class combination worth eyeballing. */
export const DEV_TICKET_FIXTURES: MyTicketGroup[] = [
  // One upcoming event, three distinct rows (held x2, listed x1, in_transfer x1).
  {
    event_id: 'dev-e1', event_session_id: 'dev-s1',
    event_title: 'Rooftop After Dark', session_label: 'Main',
    starts_at: daysFromNow(9), ends_at: null, doors_at: null,
    venue_id: 'dev-v1', venue_name: 'Bass Hall',
    artwork_ref: null,
    ticket_type_id: 'dev-t1', ticket_type_name: 'General Admission', ticket_type_kind: 'admission',
    quantity: 2, ownership_status: 'valid', fulfillment_status: 'held', time_class: 'upcoming',
  },
  {
    event_id: 'dev-e1', event_session_id: 'dev-s1',
    event_title: 'Rooftop After Dark', session_label: 'Main',
    starts_at: daysFromNow(9), ends_at: null, doors_at: null,
    venue_id: 'dev-v1', venue_name: 'Bass Hall',
    artwork_ref: null,
    ticket_type_id: 'dev-t1', ticket_type_name: 'General Admission', ticket_type_kind: 'admission',
    quantity: 1, ownership_status: 'valid', fulfillment_status: 'listed', time_class: 'upcoming',
  },
  {
    event_id: 'dev-e1', event_session_id: 'dev-s1',
    event_title: 'Rooftop After Dark', session_label: 'Main',
    starts_at: daysFromNow(9), ends_at: null, doors_at: null,
    venue_id: 'dev-v1', venue_name: 'Bass Hall',
    artwork_ref: null,
    ticket_type_id: 'dev-t2', ticket_type_name: 'VIP Table', ticket_type_kind: 'table',
    quantity: 1, ownership_status: 'valid', fulfillment_status: 'in_transfer', time_class: 'upcoming',
  },
  // A second upcoming event with a very long title + a payment_hold + a disputed row.
  {
    event_id: 'dev-e2', event_session_id: 'dev-s2',
    event_title: 'The Extremely Long Headliner Name That Should Wrap Gracefully Downtown',
    session_label: null,
    starts_at: daysFromNow(21), ends_at: null, doors_at: null,
    venue_id: 'dev-v2', venue_name: 'Downtown Amphitheater',
    artwork_ref: null,
    ticket_type_id: 'dev-t3', ticket_type_name: 'GA', ticket_type_kind: 'admission',
    quantity: 1, ownership_status: 'valid', fulfillment_status: 'payment_hold', time_class: 'upcoming',
  },
  {
    event_id: 'dev-e2', event_session_id: 'dev-s2',
    event_title: 'The Extremely Long Headliner Name That Should Wrap Gracefully Downtown',
    session_label: null,
    starts_at: daysFromNow(21), ends_at: null, doors_at: null,
    venue_id: 'dev-v2', venue_name: 'Downtown Amphitheater',
    artwork_ref: null,
    ticket_type_id: 'dev-t3', ticket_type_name: 'GA', ticket_type_kind: 'admission',
    quantity: 1, ownership_status: 'valid', fulfillment_status: 'disputed', time_class: 'upcoming',
  },
  // Past: used, expired, void.
  {
    event_id: 'dev-e3', event_session_id: 'dev-s3',
    event_title: 'Winter Warehouse', session_label: 'Main',
    starts_at: daysFromNow(-14), ends_at: daysFromNow(-14), doors_at: null,
    venue_id: 'dev-v1', venue_name: 'Bass Hall',
    artwork_ref: null,
    ticket_type_id: 'dev-t4', ticket_type_name: 'GA', ticket_type_kind: 'admission',
    quantity: 2, ownership_status: 'used', fulfillment_status: 'held', time_class: 'past',
  },
  {
    event_id: 'dev-e4', event_session_id: 'dev-s4',
    event_title: 'Autumn Sessions', session_label: null,
    starts_at: daysFromNow(-40), ends_at: daysFromNow(-40), doors_at: null,
    venue_id: 'dev-v2', venue_name: 'Downtown Amphitheater',
    artwork_ref: null,
    ticket_type_id: 'dev-t5', ticket_type_name: 'GA', ticket_type_kind: 'admission',
    quantity: 1, ownership_status: 'expired', fulfillment_status: 'held', time_class: 'past',
  },
  {
    event_id: 'dev-e5', event_session_id: 'dev-s5',
    event_title: 'Cancelled Showcase', session_label: null,
    starts_at: daysFromNow(-3), ends_at: daysFromNow(-3), doors_at: null,
    venue_id: 'dev-v1', venue_name: 'Bass Hall',
    artwork_ref: null,
    ticket_type_id: 'dev-t6', ticket_type_name: 'GA', ticket_type_kind: 'admission',
    quantity: 1, ownership_status: 'void', fulfillment_status: 'held', time_class: 'past',
  },
];
