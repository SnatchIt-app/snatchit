/**
 * Tickets tab — orders that have no tickets yet (lane C, 2026-10-26; D's 167
 * `public.list_my_primary_orders()`, DARK until applied, contract D/CONTRACTS-D.md §7).
 *
 * Pinned:
 *   - one item per session whose orders are still in flight (pending, or a status the client does not
 *     know), in the read's newest-first order, linking to that session's ticket page;
 *   - the words are the ticket page's (`issuanceHint` + ORDER_COPY), never success, never an amount —
 *     `charge_total_minor` is NULL until finalize and face value is never what the buyer paid (A's rule);
 *   - a missing function (PGRST202) shows nothing; a failed read is its own line, never "no orders";
 *     a failed refresh keeps what is on screen;
 *   - the screen reads it only on a real load (never under the harness fixture), and the component owns
 *     no route.
 *
 * Negative controls (run by hand, each must FAIL): keep settled sessions (PO2); read PGRST202 as failed
 * (PO6); replace shown items on a failed refresh (PO7); put the amount on an item (PO5).
 */
import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';

import {
  PENDING_ORDERS_COPY,
  keepPendingOnFailure,
  parsePendingOrdersReply,
  pendingBlockView,
  pendingOrderItems,
  readPendingOrders,
  type PendingOrdersLoad,
} from '@/src/lib/tickets/pendingOrders';
import { ORDER_COPY } from '@/src/lib/tickets/primaryOrders';

vi.mock('@/src/lib/supabase', () => ({ supabase: { rpc: () => { throw new Error('not used in tests'); } } }));

const S1 = '11111111-1111-4111-8111-111111111111';
const S2 = '22222222-2222-4222-8222-222222222222';
const S3 = '33333333-3333-4333-8333-333333333333';

let n = 0;
const row = (over: Record<string, unknown> = {}) => ({
  order_id: `0000000${n++}-0000-4000-8000-000000000000`.slice(0, 36),
  status: 'pending',
  total_minor: 2000,
  currency: 'USD',
  created_at: '2026-10-26T21:00:00Z',
  atoms_issued: 0,
  payment_state: 'none',
  charge_total_minor: null,
  event_session_id: S1,
  title: 'Lantern Night',
  ...over,
});

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '').replace(/\{\/\*[\s\S]*?\*\/\}/g, '');
const src = (p: string) => strip(readFileSync(p, 'utf8'));

describe('pendingOrderItems', () => {
  it('PO1: one item per in-flight session, newest first, with the ticket page’s words', () => {
    const items = pendingOrderItems([
      row({ event_session_id: S2, title: 'Midnight Arcade' }),
      row({ event_session_id: S1 }),
      row({ event_session_id: S2, status: 'cancelled' }),
    ]);
    expect(items).toEqual([
      { sessionId: S2, title: 'Midnight Arcade', status: ORDER_COPY.awaiting.title, hint: 'awaiting_confirmation' },
      { sessionId: S1, title: 'Lantern Night', status: ORDER_COPY.awaiting.title, hint: 'awaiting_confirmation' },
    ]);
  });

  it('PO2: a session whose orders are all settled has no item — its tickets (or their absence) are elsewhere', () => {
    expect(pendingOrderItems([
      row({ event_session_id: S1, status: 'paid', atoms_issued: 2 }),
      row({ event_session_id: S2, status: 'cancelled' }),
      row({ event_session_id: S3, status: 'expired' }),
      row({ event_session_id: S3, status: 'refunded' }),
    ])).toEqual([]);
  });

  it('PO3: readable payment states keep their own words; an unknown status says the status is unavailable', () => {
    const items = pendingOrderItems([
      row({ event_session_id: S1, payment_state: 'processing' }),
      row({ event_session_id: S2, payment_state: 'failed' }),
      row({ event_session_id: S3, status: 'on_hold' }),
    ]);
    expect(items.map((i) => [i.hint, i.status])).toEqual([
      ['payment_processing', ORDER_COPY.processing.title],
      ['payment_failed', ORDER_COPY.failed.title],
      ['unknown', PENDING_ORDERS_COPY.statusUnavailable],
    ]);
    expect(pendingOrderItems([row({ payment_state: 'succeeded' })])[0].status).toBe(ORDER_COPY.paidPending.title);
  });

  it('PO4: a row without a usable session id, or malformed, is dropped; a missing title has neutral words', () => {
    expect(pendingOrderItems([row({ event_session_id: null }), row({ event_session_id: 'fixture-s1' }), { nope: 1 }, null])).toEqual([]);
    expect(pendingOrderItems([row({ title: '  ' })])[0].title).toBe(PENDING_ORDERS_COPY.untitled);
    expect(pendingOrderItems([row({ title: null })])[0].title).toBe(PENDING_ORDERS_COPY.untitled);
  });

  it('PO5: no item carries an amount — not the charge (NULL until finalize), not face value', () => {
    const [item] = pendingOrderItems([row({ charge_total_minor: 2200, total_minor: 2000 })]);
    expect(Object.keys(item).sort()).toEqual(['hint', 'sessionId', 'status', 'title']);
    expect(JSON.stringify(item)).not.toMatch(/22\.00|20\.00|2200|2000/);
  });
});

describe('parsePendingOrdersReply / readPendingOrders', () => {
  it('PO6: 167 not applied shows nothing; signed out is its own state; any other failure is failed, never none', async () => {
    expect(parsePendingOrdersReply({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } })).toEqual({ kind: 'not_ready' });
    expect(parsePendingOrdersReply({ data: null, error: { code: '28000', message: 'orders_unauthenticated' } })).toEqual({ kind: 'signed_out' });
    expect(parsePendingOrdersReply({ data: null, error: { code: '42501', message: 'x' } })).toEqual({ kind: 'signed_out' });
    expect(parsePendingOrdersReply({ data: null, error: { code: 'XX000', message: 'boom' } })).toEqual({ kind: 'failed' });
    expect(parsePendingOrdersReply({ data: { not: 'an array' }, error: null })).toEqual({ kind: 'failed' });
    expect(parsePendingOrdersReply({ data: [], error: null })).toEqual({ kind: 'ready', items: [] });
    expect(await readPendingOrders(async () => { throw new Error('Network request failed'); })).toEqual({ kind: 'failed' });
    expect(await readPendingOrders(async () => ({ data: [row()], error: null }))).toEqual({
      kind: 'ready', items: [{ sessionId: S1, title: 'Lantern Night', status: ORDER_COPY.awaiting.title, hint: 'awaiting_confirmation' }],
    });
  });

  it('PO7: a failed refresh keeps the items on screen; a fresh answer replaces them', () => {
    const shown: PendingOrdersLoad = { kind: 'ready', items: pendingOrderItems([row()]) };
    expect(keepPendingOnFailure(shown, { kind: 'failed' })).toBe(shown);
    expect(keepPendingOnFailure(shown, { kind: 'ready', items: [] })).toEqual({ kind: 'ready', items: [] });
    expect(keepPendingOnFailure({ kind: 'idle' }, { kind: 'failed' })).toEqual({ kind: 'failed' });
    expect(keepPendingOnFailure(shown, { kind: 'not_ready' })).toEqual({ kind: 'not_ready' });
  });

  it('PO8: the block shows only items or the failed line — nothing for idle, not deployed, signed out or zero items', () => {
    expect(pendingBlockView({ kind: 'idle' })).toBeNull();
    expect(pendingBlockView({ kind: 'not_ready' })).toBeNull();
    expect(pendingBlockView({ kind: 'signed_out' })).toBeNull();
    expect(pendingBlockView({ kind: 'ready', items: [] })).toBeNull();
    const items = pendingOrderItems([row()]);
    expect(pendingBlockView({ kind: 'ready', items })).toEqual({ items, failed: false });
    expect(pendingBlockView({ kind: 'failed' })).toEqual({ items: [], failed: true });
  });

  it('PO9: the read is exactly the owner-scoped 167 RPC with no argument and no filter chain', () => {
    const m = src('src/lib/tickets/pendingOrders.ts');
    expect(m).toContain("supabase.rpc('list_my_primary_orders')");
    expect(m).not.toMatch(/rpc\('list_my_primary_orders',/);
    expect(m).not.toMatch(/list_my_primary_orders'\)[\s\S]*\.(select|eq|filter)\(/);
  });
});

describe('Tickets screen + block — source contracts', () => {
  const screen = src('app/(tabs)/tickets.tsx');
  const block = src('src/components/tickets/PendingOrdersBlock.tsx');

  it('S1: pending orders are read only on a real load (after the harness short-circuit) and merged keep-on-failure', () => {
    const shortCircuit = screen.indexOf('if (fixture) return;');
    const read = screen.indexOf('readPendingOrders(pendingOrdersRpc)');
    expect(shortCircuit).toBeGreaterThan(-1);
    expect(read).toBeGreaterThan(shortCircuit);
    expect(screen).toMatch(/setPending\(\(prev\) => keepPendingOnFailure\(prev, next\)\)/);
  });

  it('S2: the block opens the session’s ticket page through the screen’s onOpen; it owns no route and shows no amount', () => {
    expect(screen).toContain('onOpen={(sessionId) => router.push(`/ticket/${sessionId}`)}');
    expect(block).not.toMatch(/router\.|from 'expo-router'/);
    expect(block).toContain('onOpen: (sessionId: string) => void');
    expect(block).not.toMatch(/amount|charge_total|total_minor|formatUsd|toFixed|USD/);
    expect(block).toContain('PENDING_ORDERS_COPY.title');
  });

  it('S3: with no ticket groups but an order in flight, the list still renders: the block, then "No tickets yet"', () => {
    expect(screen).toContain('sections.length === 0 && !pendingBlock ? (');
    expect(screen).toMatch(/ListHeaderComponent=\{pendingBlock \? \(\s*<PendingOrdersBlock/);
    expect(screen).toMatch(/ListEmptyComponent=\{\s*<EmptyState title="No tickets yet" body="Tickets you own will show up here\." \/>/);
  });
});

describe('harness — sample renders only', () => {
  it('S4: v3-tickets renders the real block from literal rows through pendingOrderItems, under the sample caveat, going nowhere', () => {
    const h = src('app/_dev/v3-tickets.tsx');
    expect(h).toMatch(/case 'pending-orders':\s*return <PendingOrdersSample failed=\{variant === 'failed'\} \/>;/);
    expect(h).toContain('pendingOrderItems(PENDING_ORDER_ROWS)');
    expect(h).toMatch(/function PendingOrdersSample[\s\S]*?\{SAMPLE_TICKETS_LABEL\}[\s\S]*?<PendingOrdersBlock/);
    expect(h).toMatch(/onOpen=\{\(\) => \{\}\}/);
    expect(h).not.toMatch(/function PendingOrdersSample[\s\S]*?router\./);
  });
});
