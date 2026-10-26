/**
 * src/lib/tickets/primaryOrders.ts — the buyer's primary orders for one session, as the ticket
 * screen may describe them (CONTRACTS C5; registry 182 `public.get_my_primary_orders`, D, PENDING).
 *
 * Row: (order_id, status, total_minor, currency, created_at, atoms_issued, payment_state), newest
 * first, `buyer_id = auth.uid()` only. `status` is the raw `venue.order` status (pending | paid |
 * cancelled | expired | refunded). `payment_state` comes from the order↔payment link that
 * `finalize_primary_order` writes; before finalize there is no link, so a PENDING order reads
 * `none` today — "unpaid" and "paid, awaiting the webhook" are indistinguishable (A's ruling).
 *
 * Rules held here:
 *   - (pending, none) is "Awaiting payment confirmation", never "unpaid", never success;
 *   - nothing here draws or implies a code — atoms (and credential-sign) are the only source;
 *   - amounts are integer minor units in USD; anything else is shown as unavailable, never $0.00;
 *   - an order status the client does not know is "Status unavailable", and the hint is `unknown`.
 */

export type OrderStatus = 'pending' | 'paid' | 'cancelled' | 'expired' | 'refunded';
export type PaymentState = 'none' | 'processing' | 'succeeded' | 'failed';

export interface PrimaryOrderRow {
  order_id: string;
  status: OrderStatus;
  total_minor: number;
  currency: string;
  created_at: string;
  atoms_issued: number;
  payment_state: PaymentState;
}

const ORDER_STATUSES: ReadonlySet<string> = new Set<OrderStatus>(['pending', 'paid', 'cancelled', 'expired', 'refunded']);

/**
 * What the orders say about tickets that are not on screen yet:
 *   awaiting_confirmation  pending, no payment link (the only pending state readable today)
 *   payment_processing     pending, payment processing        (readable once PENDING-A C5-1 lands)
 *   paid_pending           pending, payment succeeded, nothing issued yet
 *   payment_failed         pending, payment failed
 *   issued                 a paid order issued atoms — if none are on this account, they are elsewhere
 *   none                   no order needs the screen's attention
 *   unknown                the read failed or carried a status the client does not know
 */
export type IssuanceHint =
  | 'awaiting_confirmation'
  | 'payment_processing'
  | 'paid_pending'
  | 'payment_failed'
  | 'issued'
  | 'none'
  | 'unknown';

function pendingHint(o: PrimaryOrderRow): IssuanceHint {
  switch (o.payment_state) {
    case 'processing': return 'payment_processing';
    case 'succeeded': return 'paid_pending';
    case 'failed': return 'payment_failed';
    default: return 'awaiting_confirmation';
  }
}

/** `orders` newest first, as the read returns them; `null` = the read failed or is not deployed. */
export function issuanceHint(orders: readonly PrimaryOrderRow[] | null): IssuanceHint {
  if (orders === null) return 'unknown';
  if (orders.some((o) => !ORDER_STATUSES.has(o.status))) return 'unknown';
  const pending = orders.find((o) => o.status === 'pending');
  if (pending) return pendingHint(pending);
  if (orders.some((o) => o.status === 'paid' && o.atoms_issued > 0)) return 'issued';
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

function amountLabel(totalMinor: unknown, currency: unknown): string {
  if (currency !== 'USD' && currency !== 'usd') return '—';
  if (typeof totalMinor !== 'number' || !Number.isInteger(totalMinor) || totalMinor < 0) return '—';
  return `$${Math.floor(totalMinor / 100).toLocaleString('en-US')}.${String(totalMinor % 100).padStart(2, '0')}`;
}

function issuedCount(n: number): string {
  return n === 1 ? '1 ticket issued' : `${n} tickets issued`;
}

export interface OrderLine {
  orderId: string;
  status: string;
  amount: string;
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
    case 'refunded':
      status = 'Refunded';
      break;
    case 'cancelled':
      status = o.atoms_issued === 0 ? 'Cancelled · no tickets issued' : 'Cancelled';
      break;
    case 'expired':
      status = o.atoms_issued === 0 ? 'Expired · no tickets issued' : 'Expired';
      break;
    default:
      status = 'Status unavailable';
  }
  return { orderId: o.order_id, status, amount: amountLabel(o.total_minor, o.currency) };
}
