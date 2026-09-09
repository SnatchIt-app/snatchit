/**
 * tests/tickets.test.ts — the Tickets ownership model + Phase 11 source guards.
 *
 * The pure mappers (ownership/fulfillment vocab, quantity, error classification,
 * sectioning, event grouping) are pinned here. The screen/API/nav are effect- and
 * RN-heavy, so their contract-critical properties are guarded from the shipped
 * source: exact RPC, no owner argument, no .select chaining, no kernel.tickets, no
 * price, no Ticket Detail / QR / Wallet, five-item nav, ownership icon.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  classifyTicketsError,
  eventDateLabel,
  fulfillmentLabel,
  fulfillmentTone,
  groupByEvent,
  ownershipLabel,
  ownershipTone,
  quantityLabel,
  showFulfillmentBadge,
  splitByTimeClass,
} from '../src/lib/tickets/ticketState';
import type { FulfillmentStatus, MyTicketGroup, OwnershipStatus } from '../src/lib/tickets/types';
import { navItems, COLLAPSING_ROUTES } from '../src/lib/nav/navItems';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
/** Absence guards inspect CODE, not the doc comments that describe what's absent. */
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

function row(over: Partial<MyTicketGroup> = {}): MyTicketGroup {
  return {
    event_id: 'e', event_session_id: 's', event_title: 'Show', session_label: null,
    starts_at: new Date().toISOString(), ends_at: null, doors_at: null,
    venue_id: 'v', venue_name: 'Venue', artwork_ref: null,
    ticket_type_id: 't', ticket_type_name: 'GA', ticket_type_kind: 'admission',
    quantity: 1, ownership_status: 'valid', fulfillment_status: 'held', time_class: 'upcoming',
    ...over,
  };
}

describe('ownership vocabulary', () => {
  const all: OwnershipStatus[] = ['valid', 'used', 'void', 'expired'];
  it('every status has a truthful label and a restrained tone', () => {
    for (const s of all) {
      expect(ownershipLabel(s)).toMatch(/\w/);
      expect(['neutral', 'success', 'warning', 'danger', 'count']).toContain(ownershipTone(s));
    }
    expect(ownershipLabel('valid')).toBe('Valid');
    expect(ownershipLabel('used')).toBe('Used');
    expect(ownershipTone('void')).toBe('danger');   // not usable, destructive
    expect(ownershipTone('valid')).toBe('success');
  });
});

describe('fulfillment vocabulary', () => {
  const all: FulfillmentStatus[] = ['held', 'listed', 'in_transfer', 'payment_hold', 'disputed'];
  it('every status maps to a label + tone; held needs no badge', () => {
    for (const s of all) {
      expect(fulfillmentLabel(s)).toMatch(/\w/);
      expect(['neutral', 'success', 'warning', 'danger', 'count']).toContain(fulfillmentTone(s));
    }
    expect(showFulfillmentBadge('held')).toBe(false);
    expect(showFulfillmentBadge('listed')).toBe(true);
    expect(fulfillmentTone('payment_hold')).toBe('warning');
    expect(fulfillmentTone('disputed')).toBe('danger');
  });
});

describe('quantity', () => {
  it('is singular for 1 and plural otherwise', () => {
    expect(quantityLabel(1)).toBe('1 ticket');
    expect(quantityLabel(2)).toBe('2 tickets');
    expect(quantityLabel(0)).toBe('0 tickets');
  });
});

describe('error classification', () => {
  it('maps auth SQLSTATEs to auth and everything else to retry', () => {
    expect(classifyTicketsError({ code: '42501' })).toBe('auth');
    expect(classifyTicketsError({ code: '28000' })).toBe('auth');
    expect(classifyTicketsError({ code: 'PGRST301' })).toBe('retry');
    expect(classifyTicketsError({})).toBe('retry');
    expect(classifyTicketsError(null)).toBe('retry');
  });
});

describe('sectioning & grouping', () => {
  it('splits by the server time_class, preserving order', () => {
    const rows = [row({ time_class: 'upcoming', event_session_id: 'a' }),
                  row({ time_class: 'past', event_session_id: 'b' }),
                  row({ time_class: 'upcoming', event_session_id: 'c' })];
    const { upcoming, past } = splitByTimeClass(rows);
    expect(upcoming.map((r) => r.event_session_id)).toEqual(['a', 'c']);
    expect(past.map((r) => r.event_session_id)).toEqual(['b']);
  });

  it('keeps distinct ownership/fulfillment states as distinct rows under one event', () => {
    const rows = [
      row({ event_session_id: 's1', fulfillment_status: 'held', quantity: 2 }),
      row({ event_session_id: 's1', fulfillment_status: 'listed', quantity: 1 }),
    ];
    const groups = groupByEvent(rows);
    expect(groups).toHaveLength(1);              // one event card
    expect(groups[0].rows).toHaveLength(2);      // two distinct state rows, not merged
    expect(groups[0].rows.map((r) => r.fulfillment_status)).toEqual(['held', 'listed']);
  });

  it('preserves server order of first appearance across events', () => {
    const rows = [row({ event_session_id: 'z' }), row({ event_session_id: 'a' }), row({ event_session_id: 'z' })];
    expect(groupByEvent(rows).map((g) => g.event_session_id)).toEqual(['z', 'a']);
  });
});

describe('date label', () => {
  it('renders a non-empty label for a valid instant and empty for junk', () => {
    expect(eventDateLabel('2026-10-04T02:00:00Z')).toMatch(/\w/);
    expect(eventDateLabel('not-a-date')).toBe('');
    expect(eventDateLabel(null)).toBe('');
  });
});

describe('navigation — five-item activation', () => {
  it('navItems({tickets:true}) is the approved Home, Create, Bids, Tickets, Profile order', () => {
    expect(navItems({ tickets: true }).map((i) => i.key)).toEqual(['home', 'create', 'bids', 'tickets', 'profile']);
  });

  it('Search/Explore is never a primary destination', () => {
    const keys = navItems({ tickets: true }).map((i) => i.key);
    expect(keys).not.toContain('search');
    expect(keys).not.toContain('explore');
  });

  it('the Tickets icon reads as ownership, not scanning', () => {
    const tickets = navItems({ tickets: true }).find((i) => i.key === 'tickets')!;
    expect(tickets.icon).toBe('ticket.fill');
    expect(tickets.icon).not.toMatch(/qr|barcode|scan|camera/i);
  });

  it('Tickets participates in the shared adaptive-collapse rule', () => {
    expect(COLLAPSING_ROUTES).toContain('tickets');
  });

  it('the dock renders the five-item set (no bespoke Tickets dock)', () => {
    const dock = read('src/components/nav/AdaptiveDock.tsx');
    expect(dock).toContain('navItems({ tickets: true })');
    const layout = read('app/(tabs)/_layout.tsx');
    expect(layout).toContain('name="tickets"');
  });
});

describe('Phase 11 shipped-source guards', () => {
  const api = read('src/lib/tickets/api.ts');
  const screen = read('app/(tabs)/tickets.tsx');
  const group = read('src/components/tickets/TicketEventGroup.tsx');
  const apiCode = stripComments(api);
  const screenCode = stripComments(screen);
  const groupCode = stripComments(group);

  it('calls the exact owner-scoped RPC with no argument and no .select chaining', () => {
    expect(api).toContain("supabase.rpc('get_my_tickets')");
    expect(apiCode).not.toMatch(/rpc\('get_my_tickets',\s*\{/);   // no arguments
    expect(apiCode).not.toMatch(/get_my_tickets'\)[\s\S]*\.select\(/); // no PostgREST filter surface
  });

  it('never touches kernel.tickets directly and reconstructs no price', () => {
    for (const src of [apiCode, screenCode, groupCode]) {
      expect(src).not.toMatch(/kernel[^\n]*tickets/);
      expect(src).not.toMatch(/price|amount_cents|allInLabel|payments/);
    }
  });

  it('builds no QR / barcode / scanner / Apple Wallet surface', () => {
    for (const src of [screenCode, groupCode]) {
      expect(src).not.toMatch(/qr|barcode|scanner|passkit|wallet/i);
    }
  });

  it('creates no Ticket Detail navigation and constructs no raw image URL', () => {
    expect(groupCode).not.toMatch(/router\.(push|replace|navigate)|onPress/); // cards do not navigate
    expect(groupCode).not.toMatch(/https?:\/\//);   // artwork goes through EventMedia, never a hand-built URL
    expect(group).toContain('EventMedia');
  });

  it('empty is a success state and auth failure routes to sign-in', () => {
    expect(screen).toContain('No tickets yet');
    expect(screen).toContain("router.replace('/(auth)/login')");
    expect(screen).toContain('splitByTimeClass');   // uses the server time_class
    expect(screen).not.toContain('tickets_unauthenticated'); // the raw token never reaches the client UI
  });
});
