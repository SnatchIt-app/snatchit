/**
 * src/lib/tickets/pendingOrders.ts — the buyer's orders that have no tickets yet, for the Tickets tab
 * (D's 167 `public.list_my_primary_orders()`, `20261027015500`, DARK until applied; contract
 * D/CONTRACTS-D.md §7).
 *
 * Row: 182's `get_my_primary_orders` columns verbatim (order_id, status, total_minor, currency,
 * created_at, atoms_issued, payment_state, charge_total_minor) plus `event_session_id` and the event
 * `title`; the caller's own orders across all sessions, newest first. A NULL uid raises 28000.
 *
 * Why: a paid-but-unconfirmed purchase has no atoms, so before this it was visible only on its event's
 * ticket page — a buyer whose app was killed after the PaymentSheet found "No tickets yet" and nothing
 * else. One item per session still in flight links back to that page.
 *
 * Rules held here:
 *   - the words are the ticket page's: `issuanceHint` over the session's orders, ORDER_COPY titles;
 *     settled sessions (`issued` / `none`) have no item, an unknown status is "Status unavailable";
 *   - no amount, ever (A, 2026-10-26): `charge_total_minor` is NULL until finalize and `total_minor` is
 *     face value; nothing is derived from the tier price or carried from the checkout response;
 *   - PGRST202 (167 not applied) shows nothing; a failed read is `failed`, never an empty list, and a
 *     failed refresh keeps what is on screen.
 */
import { supabase } from '@/src/lib/supabase';

import { isOrderRow, type RpcResult } from './entitlementReads';
import { issuanceHint, ORDER_COPY, type IssuanceHint, type PrimaryOrderRow } from './primaryOrders';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const AUTH_CODES: ReadonlySet<string> = new Set(['42501', '28000', 'PGRST301']);

export type InFlightHint = Exclude<IssuanceHint, 'issued' | 'none'>;

export interface PendingOrderItem {
  sessionId: string;
  title: string;
  status: string;
  hint: InFlightHint;
}

export type PendingOrdersLoad =
  | { kind: 'idle' }
  | { kind: 'not_ready' }
  | { kind: 'signed_out' }
  | { kind: 'failed' }
  | { kind: 'ready'; items: PendingOrderItem[] };

export const PENDING_ORDERS_COPY = {
  title: 'Orders in progress',
  untitled: 'Your event',
  statusUnavailable: 'Status unavailable',
  failed: 'We couldn’t check for orders in progress. Pull down to try again.',
} as const;

const STATUS_FOR: Record<InFlightHint, string> = {
  awaiting_confirmation: ORDER_COPY.awaiting.title,
  payment_processing: ORDER_COPY.processing.title,
  paid_pending: ORDER_COPY.paidPending.title,
  payment_failed: ORDER_COPY.failed.title,
  unknown: PENDING_ORDERS_COPY.statusUnavailable,
};

/** Rows newest first, as the read returns them → one item per in-flight session, in that order. */
export function pendingOrderItems(rows: readonly unknown[]): PendingOrderItem[] {
  const groups = new Map<string, { title: string | null; orders: PrimaryOrderRow[] }>();
  for (const r of rows) {
    if (!isOrderRow(r)) continue;
    const ext = r as PrimaryOrderRow & { event_session_id?: unknown; title?: unknown };
    if (typeof ext.event_session_id !== 'string' || !UUID_RE.test(ext.event_session_id)) continue;
    const g = groups.get(ext.event_session_id) ?? { title: null, orders: [] };
    if (g.title === null && typeof ext.title === 'string' && ext.title.trim()) g.title = ext.title.trim();
    g.orders.push(r);
    groups.set(ext.event_session_id, g);
  }
  const items: PendingOrderItem[] = [];
  for (const [sessionId, g] of groups) {
    const hint = issuanceHint(g.orders);
    if (hint === 'issued' || hint === 'none') continue;
    items.push({ sessionId, title: g.title ?? PENDING_ORDERS_COPY.untitled, status: STATUS_FOR[hint], hint });
  }
  return items;
}

export function parsePendingOrdersReply(res: RpcResult): PendingOrdersLoad {
  if (res.error) {
    const code = res.error.code ?? '';
    if (code === 'PGRST202') return { kind: 'not_ready' };
    if (AUTH_CODES.has(code)) return { kind: 'signed_out' };
    return { kind: 'failed' };
  }
  if (!Array.isArray(res.data)) return { kind: 'failed' };
  return { kind: 'ready', items: pendingOrderItems(res.data) };
}

export async function readPendingOrders(read: () => Promise<RpcResult>): Promise<PendingOrdersLoad> {
  try {
    return parsePendingOrdersReply(await read());
  } catch {
    return { kind: 'failed' };
  }
}

export const pendingOrdersRpc = (): Promise<RpcResult> =>
  supabase.rpc('list_my_primary_orders') as unknown as Promise<RpcResult>;

/** A failed refresh keeps the items on screen; any other answer replaces what was there. */
export function keepPendingOnFailure(prev: PendingOrdersLoad, next: PendingOrdersLoad): PendingOrdersLoad {
  return next.kind === 'failed' && prev.kind === 'ready' ? prev : next;
}

/** What the tab shows: the items, or the failed line; null when there is nothing to say. */
export function pendingBlockView(load: PendingOrdersLoad): { items: PendingOrderItem[]; failed: boolean } | null {
  if (load.kind === 'failed') return { items: [], failed: true };
  if (load.kind === 'ready' && load.items.length > 0) return { items: load.items, failed: false };
  return null;
}
