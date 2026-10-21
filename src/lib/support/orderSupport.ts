/**
 * src/lib/support/orderSupport.ts — the order-aware support email (CFT-406 / item 34, slice 1).
 *
 * Owner's checklist item 34: "I haven't received my tickets" should carry the order and its status
 * into the support flow, so the buyer does not have to find IDs or retype the story. The only support
 * channel is the support inbox (app/settings/support.tsx opens a mailto), so slice 1 prefills one:
 *
 *   Subject  Order <short ref> · <status word>
 *   Body     Event: <event name>
 *            Order ID: <full transfer id>
 *            Status: <status word>
 *            Role: Buyer | Seller
 *
 *            What happened:
 *
 * WHAT IS IN IT, and why. The full transfer id is what the admin console searches (ops.search, 116:
 * a uuid or any 8+ hex prefix of one); the short ref is that id's first 8 characters, the console's
 * own short form (admin/src/lib/format.ts `shortId`). The status word is the badge's word, from the
 * SAME derivation both order screens use for their badge, so the email never says something the screen
 * does not. Every field is one the order's own buyer or seller can already read under RLS.
 *
 * WHAT IS NOT. No delivery email or phone, no names, no payment or Stripe ids, no proof paths: the
 * draft is built from an explicit allowlist of fields, never by spreading the row, so whatever else
 * the caller's row carries cannot reach the URL. No dispute reason and no server intake either — the
 * reason writes into A's dispute lane and an intake needs a migration; both are out of slice 1.
 *
 * ENCODING (RFC 6068). Each value is percent-encoded as UTF-8 (encodeURIComponent: a space is %20,
 * never '+'), body line breaks are CRLF (%0D%0A), and single-line fields are collapsed to one line so a
 * seller-typed event name cannot add a header or end the subject early.
 *
 * Pure: no React Native, no network, no storage. Nothing here is persisted anywhere.
 */

import { transferStatusMeta, type TransferRole } from '@/src/lib/transfer/transferState';
import { disputeDecision, disputedStateMeta } from '@/src/lib/transfer/disputeOutcome';

/**
 * The support inbox. The same value app/settings/support.tsx uses; that file is a route module (it
 * renders a screen), so the value is repeated here rather than imported from it, and
 * tests/order-support-mailto.test.ts pins the two equal.
 */
export const SUPPORT_EMAIL = 'support@snatchitapp.com';

export const ORDER_SUPPORT_COPY = {
  action: 'Contact support about this order',
  hint: "Opens your email app with this order's ID and status filled in. It doesn't change the order.",
  /** The mail app did not open: the address and the order ID as text, so the user can still write. */
  couldNotOpen: (orderId: string) =>
    `Couldn't open your email app. Email ${SUPPORT_EMAIL} and include this order ID: ${orderId}`,
} as const;

/** The fields the draft may read. Anything else on the caller's row is ignored. */
export interface OrderSupportRow {
  id: string;
  status: string;
  /** Presence only — the badge's `buyerConfirmed` input (NULL on buyer_confirmed = an operator's decision). */
  buyer_confirmed_at?: string | null;
  /** A decided dispute's badge reads "Resolved". */
  dispute_resolution?: string | null;
  listing?: { event_name?: string | null } | null;
}

export interface OrderSupportDraft {
  subject: string;
  body: string;
  /** The full transfer id, as the admin console searches it. */
  orderId: string;
  /** Its first 8 characters — the console's short form. */
  shortRef: string;
  url: string;
}

const EVENT_NAME_MAX = 200;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Lone UTF-16 surrogates become U+FFFD: encodeURIComponent throws URIError on them. */
function wellFormed(s: string): string {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      const next = s.charCodeAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) { out += s[i] + s[i + 1]; i++; continue; }
      out += '\uFFFD';
      continue;
    }
    out += c >= 0xdc00 && c <= 0xdfff ? '\uFFFD' : s[i];
  }
  return out;
}

/** One line: control characters and Unicode line/paragraph separators become spaces, runs collapse. */
function oneLine(s: string | null | undefined): string {
  if (s == null) return '';
  return wellFormed(String(s)).replace(/[\u0000-\u001F\u007F-\u009F\u2028\u2029]/g, ' ').replace(/\s+/g, ' ').trim();
}

/** Capped by code point, so a surrogate pair is never split. */
function capped(s: string, max: number): string {
  const chars = Array.from(s);
  return chars.length <= max ? s : `${chars.slice(0, max - 1).join('')}…`;
}

/**
 * The badge's word for this order — the same derivation both order screens use for their Badge:
 * a disputed row through the dispute decision (open → "Issue", decided → "Resolved"), every other
 * status through transferStatusMeta with the buyer-confirmed flag.
 */
export function orderSupportStatusWord(
  row: Pick<OrderSupportRow, 'status' | 'buyer_confirmed_at' | 'dispute_resolution'>,
  role: TransferRole,
): string {
  const status = row.status ?? '';
  const meta = status === 'disputed'
    ? disputedStateMeta(disputeDecision({ status, dispute_resolution: row.dispute_resolution ?? null }), role)
    : transferStatusMeta(status, role, { buyerConfirmed: row.buyer_confirmed_at != null });
  return oneLine(meta.label);
}

/** RFC 6068 mailto: each value UTF-8 percent-encoded, body line breaks as CRLF. `to` is a fixed address. */
export function mailtoUrl(to: string, subject: string, body: string): string {
  const crlf = body.replace(/\r\n|\r|\n/g, '\r\n');
  return `mailto:${to}?subject=${encodeURIComponent(wellFormed(subject))}&body=${encodeURIComponent(wellFormed(crlf))}`;
}

/** The prefilled support email for this order, or null when the row has no usable order id. */
export function orderSupportDraft(row: OrderSupportRow, role: TransferRole): OrderSupportDraft | null {
  const orderId = String(row.id ?? '').trim();
  // A server transfer id is a uuid; anything else — including the dev/sandbox harness's
  // 'fixture-order' — is not composed into an email at all.
  if (!UUID.test(orderId)) return null;
  const shortRef = orderId.slice(0, 8);
  const word = orderSupportStatusWord(row, role);
  const event = capped(oneLine(row.listing?.event_name), EVENT_NAME_MAX);

  const subject = word ? `Order ${shortRef} · ${word}` : `Order ${shortRef}`;
  const body = [
    ...(event ? [`Event: ${event}`] : []),
    `Order ID: ${orderId}`,
    ...(word ? [`Status: ${word}`] : []),
    `Role: ${role === 'seller' ? 'Seller' : 'Buyer'}`,
    '',
    'What happened:',
    '',
  ].join('\r\n');

  return { subject, body, orderId, shortRef, url: mailtoUrl(SUPPORT_EMAIL, subject, body) };
}

/**
 * Open the mail app. False when the opener rejects, throws, or answers `false` — the caller then shows
 * the address as text. Linking.openURL rejects on iOS and Android when nothing can handle the URL.
 */
export async function openOrderSupportMail(url: string, open: (url: string) => Promise<unknown> | unknown): Promise<boolean> {
  try {
    const result = await open(url);
    return result !== false;
  } catch {
    return false;
  }
}
