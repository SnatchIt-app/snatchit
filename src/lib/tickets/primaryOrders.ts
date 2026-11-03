/**
 * src/lib/tickets/primaryOrders.ts — the buyer's primary orders for one session, as the ticket
 * screen may describe them (CONTRACTS C5; registry 182 `public.get_my_primary_orders`, D, PENDING).
 *
 * Row: (order_id, status, total_minor, currency, created_at, atoms_issued, payment_state), newest
 * first, `buyer_id = auth.uid()` only. `status` is the raw `venue.order` status (pending | paid |
 * partially_refunded | cancelled | refunded — 082's check; 182 returns it as stored. There is no 'expired':
 * D's trace CHK-3 — anything else is unknown).
 * `payment_state` comes from the order↔payment link that
 * `finalize_primary_order` writes; before finalize there is no link, so a PENDING order reads
 * `none` today — "unpaid" and "paid, awaiting the webhook" are indistinguishable (A's ruling).
 *
 * Rules held here:
 *   - (pending, none) is "Awaiting payment confirmation", never "unpaid", never success;
 *   - nothing here draws or implies a code — atoms (and credential-sign) are the only source;
 *   - the order's `total_minor` is FACE value (venue entitlement, per the primary-checkout edge) and is
 *     never shown as what the buyer paid. A's all-in rule: the only amount shown is the CHARGED total
 *     (`charge_total_minor`, requested from D on this read); without it the line shows no amount;
 *   - an order status the client does not know is "Status unavailable", and the hint is `unknown`;
 *     a failed read is `read_failed` — two different things, neither ever "no tickets";
 *   - an abandoned checkout stays pending forever (edge RES-1, accepted), so a pending order is in
 *     flight only while it is newer than every paid order.
 */

export type OrderStatus = 'pending' | 'paid' | 'partially_refunded' | 'cancelled' | 'refunded';
export type PaymentState = 'none' | 'processing' | 'succeeded' | 'failed';

export interface PrimaryOrderRow {
  order_id: string;
  status: OrderStatus;
  total_minor: number;
  currency: string;
  created_at: string;
  atoms_issued: number;
  payment_state: PaymentState;
  /** The charged all-in total (payments.total). Requested from D on 182/167; absent today. */
  charge_total_minor?: number | null;
}

const ORDER_STATUSES: ReadonlySet<string> = new Set<OrderStatus>(['pending', 'paid', 'partially_refunded', 'cancelled', 'refunded']);
/** Paid, whole or with part of it refunded: the order settled, and issued whatever atoms it says. */
const PAID_STATUSES: ReadonlySet<string> = new Set<OrderStatus>(['paid', 'partially_refunded']);

/**
 * What the orders say about tickets that are not on screen yet:
 *   awaiting_confirmation  pending, no payment link (the only pending state readable today)
 *   payment_processing     pending, payment processing        (readable once PENDING-A C5-1 lands)
 *   paid_pending           pending, payment succeeded, nothing issued yet
 *   payment_failed         pending, payment failed
 *   issued                 a paid (or partly refunded) order issued atoms — if none are on this
 *                          account, they are elsewhere
 *   none                   no order needs the screen's attention
 *   unknown                the read carried a status the client does not know
 *   read_failed            the read failed or is not deployed — never `none`
 */
export type IssuanceHint =
  | 'awaiting_confirmation'
  | 'payment_processing'
  | 'paid_pending'
  | 'payment_failed'
  | 'issued'
  | 'none'
  | 'unknown'
  | 'read_failed';

function pendingHint(o: PrimaryOrderRow): IssuanceHint {
  switch (o.payment_state) {
    case 'processing': return 'payment_processing';
    case 'succeeded': return 'paid_pending';
    case 'failed': return 'payment_failed';
    default: return 'awaiting_confirmation';
  }
}

/**
 * `orders` newest first, as the read returns them; `null` = the read failed or is not deployed.
 * Rows that were read can never be `read_failed` (the overload says so to pendingOrders.ts).
 */
export function issuanceHint(orders: readonly PrimaryOrderRow[]): Exclude<IssuanceHint, 'read_failed'>;
export function issuanceHint(orders: readonly PrimaryOrderRow[] | null): IssuanceHint;
export function issuanceHint(orders: readonly PrimaryOrderRow[] | null): IssuanceHint {
  if (orders === null) return 'read_failed';
  if (orders.some((o) => !ORDER_STATUSES.has(o.status))) return 'unknown';
  // Newest first: a pending order is in flight only while nothing newer has settled — an order paid, refunded,
  // or cancelled after it means the buyer moved on, and an abandoned checkout stays pending (RES-1).
  for (const o of orders) {
    if (o.status !== 'pending') break;
    return pendingHint(o);
  }
  if (orders.some((o) => PAID_STATUSES.has(o.status) && o.atoms_issued > 0)) return 'issued';
  return 'none';
}

export const ORDER_COPY = {
  awaiting: {
    title: 'Awaiting payment confirmation',
    body: 'We haven’t confirmed your payment yet. Your tickets will appear here once it’s confirmed. Pull down to check again.',
  },
  processing: {
    title: 'Payment processing',
    body: 'Your payment is still being processed. Your tickets will appear here once it clears. Pull down to check again.',
  },
  paidPending: {
    title: 'Issuance pending',
    body: 'Your payment is confirmed. Your tickets are being issued — this usually takes a moment. Pull down to check again.',
  },
  failed: {
    title: 'Payment didn’t go through',
    body: 'No tickets were issued for this payment.',
  },
  elsewhere: {
    title: 'No tickets on this account',
    body: 'Your order for this event was issued, but its tickets aren’t on this account now. Contact support if you didn’t move them.',
  },
} as const;

function amountLabel(totalMinor: unknown, currency: unknown): string | null {
  if (currency !== 'USD' && currency !== 'usd') return null;
  if (typeof totalMinor !== 'number' || !Number.isInteger(totalMinor) || totalMinor < 0) return null;
  return `$${Math.floor(totalMinor / 100).toLocaleString('en-US')}.${String(totalMinor % 100).padStart(2, '0')}`;
}

function issuedCount(n: number): string {
  return n === 1 ? '1 ticket issued' : `${n} tickets issued`;
}

export interface OrderLine {
  orderId: string;
  status: string;
  /** The charged all-in total, or null — face value is never shown as the amount paid. */
  amount: string | null;
}

/** One line per order for the screen's order list. States only what the row says. */
export function orderStatusLine(o: PrimaryOrderRow): OrderLine {
  let status: string;
  switch (o.status) {
    case 'pending':
      status = o.payment_state === 'processing' ? ORDER_COPY.processing.title
        : o.payment_state === 'succeeded' ? 'Payment confirmed · issuing tickets'
        : o.payment_state === 'failed' ? ORDER_COPY.failed.title
        : ORDER_COPY.awaiting.title;
      break;
    case 'paid':
      status = o.atoms_issued > 0 ? `Paid · ${issuedCount(o.atoms_issued)}` : 'Paid · tickets being issued';
      break;
    case 'partially_refunded':
      // Initiated, never completed (A's interim refund-wording ruling, 2026-09-24; v3-refund-initiated-wording RI1).
      status = 'Partial refund initiated';
      break;
    case 'refunded':
      status = 'Refunded';
      break;
    case 'cancelled':
      status = o.atoms_issued === 0 ? 'Cancelled · no tickets issued' : 'Cancelled';
      break;
    default:
      status = 'Status unavailable';
  }
  return { orderId: o.order_id, status, amount: amountLabel(o.charge_total_minor, o.currency) };
}
