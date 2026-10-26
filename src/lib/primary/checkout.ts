/**
 * src/lib/primary/checkout.ts — the buyer's PRIMARY ticket checkout client (CONTRACTS C3).
 *
 * PAYMENTS SURFACE: reviewed by A before any merge. New file; touches no gated file
 * (src/lib/payments.ts, src/lib/checkout/*) and builds no new payment stack — the PaymentSheet is the
 * same Stripe module the resale checkout uses.
 *
 * Edge `primary-checkout` (supabase/functions/primary-checkout/index.ts, undeployed; `verify_jwt`):
 *   request  { session_id, items:[{ticket_type_id, quantity}], hold_ids:[uuid], command_key,
 *              expected_total_cents? }
 *   200      { order_id, clientSecret, paymentIntentId, amount (FACE), buyer_fee, seller_fee: 0,
 *              total (ALL-IN charge), currency, customerId, customerEphemeralKeySecret }
 *   refusals 401 · 403 identity_erased | deletion_pending · 404 not_found · 409 not_on_sale |
 *            session_terminal | hold_invalid | total_mismatch {server_total_cents} | org_not_eligible |
 *            precondition_failed | command_key_session_mismatch | already_paid ·
 *            503 service_fee_unset | service_fee_out_of_range · 429 · 500
 *
 * `already_paid` is not a refusal: the order this command key names is paid, so the flow is `submitted`
 * and the buyer goes to the ticket page (A's review, 2026-10-26). Offering "try again" would replay the
 * same key into the same 409 forever.
 *
 * Price authority: the server. The edge mints the PaymentIntent for `total`; the client only shows it.
 * `expected_total_cents` is sent only once a total has been SHOWN (an absent value is never a mismatch,
 * `_shared/money.ts` totalMismatch), so a retry under the same command key cannot charge a total the
 * buyer did not see. The edge tells clients to re-check `total === amount + buyer_fee` before showing
 * anything; a quote that fails that check is "unavailable", never a price.
 *
 * Issuance is webhook-only (C4). Nothing here, and nothing after the PaymentSheet, is a success state:
 * the flow ends at `submitted`, and the ticket screen says "Awaiting payment confirmation" until atoms
 * exist.
 *
 * HOLD: CONTRACT PENDING — D's registry 167 (`20261027015500`, pgTAP 234; A's ruling 2026-10-26):
 * `public.reserve_primary_tier(p_session_id, p_ticket_type_id, p_quantity, p_command_key)` →
 * {status, hold_id, expires_at, quantity} (server picks the public-sale batch; same idempotency /
 * oversell / cap semantics; `tier_not_on_sale` from 185) and `public.release_primary_hold(p_hold_id,
 * p_command_key)`. Until 167 lands the hold stays an injected adapter; buyers get no `venue` exposure.
 */

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type Invoker = (name: string, body: unknown) => Promise<{ status: number | null; body: unknown }>;

export interface CheckoutItem {
  ticketTypeId: string;
  quantity: number;
}

export interface PrimaryQuote {
  orderId: string;
  clientSecret: string;
  paymentIntentId: string;
  /** Face value (venue entitlement) — itemises the total; never shown as "the price". */
  faceMinor: number;
  buyerFeeMinor: number;
  /** The all-in charge. The only figure shown as what the buyer pays. */
  totalMinor: number;
  customerId: string;
  ephemeralKeySecret: string;
}

export type CheckoutRefusal =
  | 'not_on_sale'
  | 'ended'
  | 'hold_expired'
  | 'sales_unavailable'
  | 'not_found'
  | 'account_blocked'
  | 'refused'
  | 'signed_out'
  | 'rate_limited'
  | 'offline'
  | 'unavailable';

export type QuoteResult =
  | { ok: true; quote: PrimaryQuote }
  | { ok: false; reason: 'price_changed'; serverTotalMinor: number | null }
  | { ok: false; reason: 'already_paid' }
  | { ok: false; reason: CheckoutRefusal };

const isMinor = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v >= 0;
const isStr = (v: unknown): v is string => typeof v === 'string' && v.length > 0;

export function parsePrimaryCheckoutResponse(status: number | null, body: unknown): QuoteResult {
  if (status === null) return { ok: false, reason: 'offline' };
  const b = (body && typeof body === 'object' ? body : {}) as Record<string, unknown>;
  const code = typeof b.code === 'string' ? b.code : '';
  if (status === 200) {
    const currency = typeof b.currency === 'string' ? b.currency.toLowerCase() : '';
    if (
      isStr(b.order_id) && isStr(b.clientSecret) && isStr(b.paymentIntentId) &&
      isMinor(b.amount) && isMinor(b.buyer_fee) && isMinor(b.total) && currency === 'usd' &&
      b.total === b.amount + b.buyer_fee &&
      isStr(b.customerId) && isStr(b.customerEphemeralKeySecret)
    ) {
      return {
        ok: true,
        quote: {
          orderId: b.order_id, clientSecret: b.clientSecret, paymentIntentId: b.paymentIntentId,
          faceMinor: b.amount, buyerFeeMinor: b.buyer_fee, totalMinor: b.total,
          customerId: b.customerId, ephemeralKeySecret: b.customerEphemeralKeySecret,
        },
      };
    }
    return { ok: false, reason: 'unavailable' };
  }
  if (status === 401) return { ok: false, reason: 'signed_out' };
  if (status === 429) return { ok: false, reason: 'rate_limited' };
  switch (code) {
    case 'total_mismatch': return { ok: false, reason: 'price_changed', serverTotalMinor: isMinor(b.server_total_cents) ? b.server_total_cents : null };
    case 'already_paid': return { ok: false, reason: 'already_paid' };
    case 'not_on_sale': return { ok: false, reason: 'not_on_sale' };
    case 'session_terminal': return { ok: false, reason: 'ended' };
    case 'hold_invalid': return { ok: false, reason: 'hold_expired' };
    case 'service_fee_unset':
    case 'service_fee_out_of_range':
    case 'org_not_eligible': return { ok: false, reason: 'sales_unavailable' };
    case 'not_found': return { ok: false, reason: 'not_found' };
    case 'identity_erased':
    case 'deletion_pending': return { ok: false, reason: 'account_blocked' };
    case 'precondition_failed':
    case 'command_key_session_mismatch': return { ok: false, reason: 'refused' };
    default: return { ok: false, reason: 'unavailable' };
  }
}

export async function requestPrimaryQuote(
  invoke: Invoker,
  req: { sessionId: string; items: CheckoutItem[]; holdIds: string[]; commandKey: string; shownTotalMinor: number | null },
): Promise<QuoteResult> {
  const itemsOk = req.items.length > 0 && req.items.length <= 50 &&
    req.items.every((i) => UUID_RE.test(i.ticketTypeId) && Number.isInteger(i.quantity) && i.quantity > 0 && i.quantity <= 100);
  const holdsOk = req.holdIds.length > 0 && req.holdIds.length <= 100 && req.holdIds.every((h) => UUID_RE.test(h));
  const keyOk = req.commandKey.trim().length > 0 && req.commandKey.length <= 200;
  if (!UUID_RE.test(req.sessionId) || !itemsOk || !holdsOk || !keyOk) return { ok: false, reason: 'unavailable' };
  const body: Record<string, unknown> = {
    session_id: req.sessionId,
    items: req.items.map((i) => ({ ticket_type_id: i.ticketTypeId, quantity: i.quantity })),
    hold_ids: req.holdIds,
    command_key: req.commandKey,
  };
  if (req.shownTotalMinor !== null) body.expected_total_cents = req.shownTotalMinor;
  let res: { status: number | null; body: unknown };
  try {
    res = await invoke('primary-checkout', body);
  } catch {
    return { ok: false, reason: 'offline' };
  }
  return parsePrimaryCheckoutResponse(res.status, res.body);
}

/**
 * One key per purchase intent: the screen draws `attemptId` once (random) when the buyer starts a
 * purchase and keeps it for every retry and double tap, so the server replays instead of creating a
 * second order. No clock in the key.
 */
export function attemptCommandKey(sessionId: string, attemptId: string): string {
  const safe = (v: string) => v.replace(/[^A-Za-z0-9-]/g, '');
  return `pc-${safe(sessionId)}-${safe(attemptId)}`.slice(0, 200);
}

/** 16 random bytes as hex — injected randomness (react-native-get-random-values provides crypto). */
export function newAttemptId(randomBytes: (n: number) => Uint8Array): string {
  return Array.from(randomBytes(16), (b) => b.toString(16).padStart(2, '0')).join('');
}

export type CheckoutState =
  | { kind: 'idle' }
  | { kind: 'holding' }
  | { kind: 'quoting' }
  | { kind: 'quoted'; quote: PrimaryQuote }
  | { kind: 'price_changed'; serverTotalMinor: number | null }
  | { kind: 'paying'; quote: PrimaryQuote }
  | { kind: 'payment_failed'; quote: PrimaryQuote }
  | { kind: 'submitted'; orderId: string | null }
  | { kind: 'refused'; reason: CheckoutRefusal };

export type CheckoutEvent =
  | { type: 'quote'; result: QuoteResult }
  | { type: 'sheet'; outcome: 'completed' | 'canceled' | 'failed' };

/** Pure transitions. There is no success state: the last one is `submitted`. */
export function checkoutStep(state: CheckoutState, ev: CheckoutEvent): CheckoutState {
  if (ev.type === 'quote') {
    const r = ev.result;
    if (r.ok) return { kind: 'quoted', quote: r.quote };
    if (r.reason === 'price_changed') return { kind: 'price_changed', serverTotalMinor: r.serverTotalMinor };
    if (r.reason === 'already_paid') return { kind: 'submitted', orderId: null };
    return { kind: 'refused', reason: r.reason };
  }
  if (state.kind !== 'paying') return state;
  switch (ev.outcome) {
    case 'completed': return { kind: 'submitted', orderId: state.quote.orderId };
    case 'canceled': return { kind: 'quoted', quote: state.quote };
    default: return { kind: 'payment_failed', quote: state.quote };
  }
}

export function formatUsd(minor: number): string {
  if (!isMinor(minor)) return '—';
  return `$${Math.floor(minor / 100).toLocaleString('en-US')}.${String(minor % 100).padStart(2, '0')}`;
}

export const PRIMARY_CHECKOUT_COPY = {
  totalLabel: 'Total',
  faceLabel: 'Tickets',
  feeLabel: 'Service fee',
  payAction: 'Pay',
  priceChanged: {
    title: 'The total changed',
    body: 'Review the new total before you pay.',
  },
  submitted: {
    title: 'Awaiting payment confirmation',
    body: 'We’ll show your tickets as soon as your payment is confirmed. This usually takes a moment.',
  },
  paymentFailed: 'Your payment didn’t go through. You can try again.',
  refusal: {
    not_on_sale: 'This event isn’t on sale right now.',
    ended: 'This event has ended or was cancelled.',
    hold_expired: 'Your ticket hold ran out. Choose your tickets again.',
    sales_unavailable: 'Ticket sales aren’t available yet for this event.',
    not_found: 'We couldn’t find this event or ticket type.',
    account_blocked: 'This account can’t buy tickets right now. Contact support if you think this is wrong.',
    refused: 'We couldn’t start this purchase. Choose your tickets again.',
    signed_out: 'Sign in to buy tickets.',
    rate_limited: 'Too many attempts. Try again in a minute.',
    offline: 'You’re offline. Connect and try again.',
    unavailable: 'We couldn’t start checkout. Try again.',
  } satisfies Record<CheckoutRefusal, string>,
} as const;

/**
 * Resume after a 3-D Secure redirect or a killed app: the edge replays the same PaymentIntent for the
 * same command key. If Stripe already reports it succeeded / processing / awaiting capture, the buyer
 * must not be shown the sheet again — the flow is `submitted` and the ticket page waits for the webhook.
 * (Stripe's status, read from the SDK; it never authorises anything here, it only stops a second sheet.)
 */
export function intentAlreadyPaid(status: string | null | undefined): boolean {
  return status === 'Succeeded' || status === 'Processing' || status === 'RequiresCapture';
}

/** The PaymentSheet's result → the flow's sheet outcome. No error = the sheet completed (not "paid"). */
export function sheetOutcome(error: { code?: string | null } | null | undefined): 'completed' | 'canceled' | 'failed' {
  if (!error) return 'completed';
  return error.code === 'Canceled' ? 'canceled' : 'failed';
}
