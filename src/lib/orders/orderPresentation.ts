/**
 * src/lib/orders/orderPresentation.ts — pure presentation logic for the buyer's order screen (V3).
 *
 * The V3 order board (`midnight-order-clean.png` composition, `pkg7-order-after-*.png` copy,
 * `pkg8-order-{dark,light}.png` tokens) leads with an event summary and a four-step PROGRESS
 * track. Everything here is derivation from fields the screen already reads — no effects, no
 * Supabase, no theme — so the truth rules are tested once:
 *
 *  - "You paid" states only what the buyer's OWN settled payment row records (status
 *    'succeeded', a known total, no refund recorded — a refunded row belongs to the closed
 *    blocks' refund story, never to a quiet price row).
 *  - "Payout to seller" is release-gated: `payout_released_at` or the words "not released"
 *    (A's rule — the status alone is never a money claim).
 *  - The confirmation step never reads done unless the BUYER confirmed (`buyer_confirmed_at`);
 *    an operator's dispute decision is not a confirmation, and those statuses render their own
 *    state blocks instead of a track.
 *  - The deadline under "Your confirmation" comes from the server's `auto_release_at` or is the
 *    word "pending" — never a device-derived date, and never the unapproved auto-release
 *    sentence (O-1 stays out of the product).
 */

import { formatCentsV3 } from '@/src/lib/money';
import type { RefundRead } from '@/src/lib/transfer/refundState';

// ─── The event summary lines ────────────────────────────────────────────────

/** "Fri 24 Oct · 19:30 · Lantern Room" from the listing's own columns; absent parts drop out. */
export function orderWhenWhereLine(
  eventDate: string | null | undefined,
  eventTime: string | null | undefined,
  venue: string | null | undefined,
): string {
  const parts: string[] = [];
  const d = parseLocalDate(eventDate);
  if (d) {
    const weekday = d.toLocaleDateString(undefined, { weekday: 'short' });
    const day = d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
    parts.push(`${weekday} ${day}`);
  }
  const t = (eventTime ?? '').match(/^(\d{2}:\d{2})/);
  if (t) parts.push(t[1]);
  if (venue) parts.push(venue);
  return parts.join(' · ');
}

/** "2 × GA · Mobile transfer · DICE"; a missing piece drops out rather than printing a blank. */
export function orderTicketsLine(
  quantity: number | null | undefined,
  ticketType: string | null | undefined,
  transferMethod: string | null | undefined,
  providerName: string | null | undefined,
): string {
  const parts: string[] = [];
  if (quantity != null && quantity > 0 && ticketType) parts.push(`${quantity} × ${ticketType}`);
  if (transferMethod) {
    const words = transferMethod.replace(/_/g, ' ');
    parts.push(words.charAt(0).toUpperCase() + words.slice(1));
  }
  if (providerName) parts.push(providerName);
  return parts.join(' · ');
}

/** "YYYY-MM-DD" parsed as a LOCAL date (never UTC-shifted a day); anything else is null. */
function parseLocalDate(iso: string | null | undefined): Date | null {
  const m = (iso ?? '').match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!m) return null;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return Number.isNaN(d.getTime()) ? null : d;
}

// ─── "You paid" — the buyer's own recorded charge, or nothing ───────────────

/**
 * The all-in figure the buyer's settled payment row records, formatted for display through the
 * V3 money module — or null. Null whenever the read is in flight, failed, found no row, found a
 * row that never succeeded, has no known total, or carries any recorded refund: each of those
 * states either has nothing truthful to say here or belongs to the refund lines, and a quiet
 * price row must never outrun the payment row behind it.
 */
export function youPaidAmount(read: RefundRead): string | null {
  // A's rulings (2026-09-24): the figure needs the read to have succeeded with EXACTLY ONE
  // settled row (two rows are ambiguous — the select has no payment id to match), the row to be
  // SETTLED (succeeded, or refunded: "'You paid' stays true and the existing refund line says
  // the rest" — total is the card charge, amount + buyer_fee), and a known positive total.
  // Never the listing price, never a client computation, never an implied "unpaid" on zero rows.
  if (read.kind !== 'loaded' || !read.facts) return null;
  if (read.rowCount !== 1) return null;
  const { status, total } = read.facts;
  if (status !== 'succeeded' && status !== 'refunded') return null;
  if (total == null || total <= 0) return null;
  return formatCentsV3(total);
}

export const YOU_PAID_LABEL = 'You paid';

// ─── The PROGRESS track ─────────────────────────────────────────────────────

export type OrderStepState = 'done' | 'current' | 'todo';

export interface OrderStep {
  key: 'paid' | 'sent' | 'confirm' | 'payout';
  label: string;
  /** The small line under the label; null renders nothing. */
  sub: string | null;
  state: OrderStepState;
}

export const ORDER_PROGRESS_LABELS = {
  paid: 'You paid',
  sent: 'Seller reported sending',
  confirm: 'Your confirmation',
  payout: 'Payout to seller',
} as const;

export const PAYOUT_NOT_RELEASED = 'not released';
export const PAYOUT_RELEASED = 'released';
export const CONFIRMATION_PENDING = 'pending';

/** "by Sun 09:12" from the server's timestamp, in device-local form; null when unparseable. */
export function shortDeadline(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const weekday = d.toLocaleDateString(undefined, { weekday: 'short' });
  const time = d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
  return `by ${weekday} ${time}`;
}

/**
 * The four steps, or null for the statuses whose story a state block owns (disputed, expired,
 * reversed, auto_released — and a `buyer_confirmed` WITHOUT the buyer's own timestamp, which is
 * an operator's decision and must not paint the confirmation step done).
 */
export function orderProgress(i: {
  status: string;
  buyerConfirmedAt: string | null;
  payoutReleasedAt: string | null;
  autoReleaseAt: string | null;
}): OrderStep[] | null {
  const confirmed = i.status === 'buyer_confirmed' && i.buyerConfirmedAt != null;
  if (i.status !== 'pending' && i.status !== 'seller_sent' && !confirmed) return null;

  const sent = i.status !== 'pending';
  const confirmSub = confirmed ? null : (shortDeadline(i.autoReleaseAt) ?? CONFIRMATION_PENDING);
  const released = i.payoutReleasedAt != null;

  return [
    // No timestamp under "You paid": the transfer row carries no payment-time fact, and this
    // track never invents one (the board's sample time is a named difference).
    { key: 'paid', label: ORDER_PROGRESS_LABELS.paid, sub: null, state: 'done' },
    { key: 'sent', label: ORDER_PROGRESS_LABELS.sent, sub: null, state: sent ? 'done' : 'current' },
    {
      key: 'confirm',
      label: ORDER_PROGRESS_LABELS.confirm,
      sub: confirmSub,
      state: confirmed ? 'done' : sent ? 'current' : 'todo',
    },
    {
      key: 'payout',
      label: ORDER_PROGRESS_LABELS.payout,
      sub: released ? PAYOUT_RELEASED : PAYOUT_NOT_RELEASED,
      state: released ? 'done' : 'todo',
    },
  ];
}

/** One sentence for screen readers: every step, its state, and its sub-line where one exists. */
export function orderProgressA11y(steps: OrderStep[]): string {
  const word = (s: OrderStepState) => (s === 'done' ? 'done' : s === 'current' ? 'current step' : 'not yet');
  return `Progress: ${steps.map((st) => `${st.label}, ${word(st.state)}${st.sub ? `, ${st.sub}` : ''}`).join('. ')}.`;
}
