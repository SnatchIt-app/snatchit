/**
 * src/lib/listing/ticketPlatforms.ts — the one ticket-platform list.
 *
 * Create offered sixteen platforms and Edit offered six, so a listing created as StubHub,
 * SeatGeek or Gametime could neither show nor keep its own platform once the seller opened Edit.
 * Both screens now read this list, and nothing else declares one.
 *
 * The values are not a product choice made here: migration `033_marketplace_expansion.sql`
 * widened `listings_ticket_platform_check` to exactly these sixteen, so this is the app's copy of
 * the constraint on the column it writes to. `tests/v3-wording-w4-w5.test.ts` parses that
 * migration and asserts the two agree, which is what stops the app drifting from the database.
 *
 * Order is the Miami-market order Create already used — most likely first, `other` last.
 * Confirmed platforms only: see TRANSFER_METHOD_RESEARCH.md.
 */

import type { TicketPlatform } from '@/src/types';

export interface TicketPlatformOption {
  value: TicketPlatform;
  label: string;
}

export const TICKET_PLATFORMS: readonly TicketPlatformOption[] = [
  { value: 'ticketmaster', label: 'Ticketmaster' },
  { value: 'tixr',         label: 'Tixr' },
  { value: 'dice',         label: 'DICE' },
  { value: 'posh',         label: 'Posh' },
  { value: 'eventbrite',   label: 'Eventbrite' },
  { value: 'axs',          label: 'AXS' },
  { value: 'seatgeek',     label: 'SeatGeek' },
  { value: 'mlb_ballpark', label: 'MLB Ballpark' },
  { value: 'fever',        label: 'Fever' },
  { value: 'shotgun',      label: 'Shotgun' },
  { value: 'universe',     label: 'Universe' },
  { value: 'see_tickets',  label: 'See Tickets' },
  { value: 'stubhub',      label: 'StubHub' },
  { value: 'vivid_seats',  label: 'Vivid Seats' },
  { value: 'gametime',     label: 'Gametime' },
  { value: 'other',        label: 'Other' },
];
