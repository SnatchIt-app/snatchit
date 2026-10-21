/**
 * tests/order-support-mailto.test.ts — the order-aware support email (CFT-406 / item 34, slice 1).
 *
 * "I haven't received my tickets" should carry the order and its status into the support flow, so the
 * user does not hunt for IDs or retype the story (owner's checklist item 34). The only channel is the
 * support inbox, so slice 1 is a prefilled mailto. What these tests pin:
 *
 *  - ENCODING (RFC 6068): spaces are %20 (never '+'), line breaks are %0D%0A, non-ASCII is UTF-8
 *    percent-encoded, and the reserved characters a seller can type into an event name ('&', '=',
 *    '?', '#', '%', '+') cannot end the subject or body early or start a new header.
 *  - THE STATUS WORD is the badge's word, from the same derivation the order screens use, for every
 *    status the server writes — expired, reversed and disputed included.
 *  - NO PII: whatever else the row carries (delivery email/phone, names, Stripe ids), the email holds
 *    the event name, the order ID, the status word, the role, and an empty "What happened:" prompt.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  mailtoUrl,
  openOrderSupportMail,
  ORDER_SUPPORT_COPY,
  orderSupportDraft,
  orderSupportStatusWord,
  SUPPORT_EMAIL,
  type OrderSupportRow,
} from '@/src/lib/support/orderSupport';

const ID = '3f2a9c1b-7d4e-4a8f-9b6c-2e1d0a9f8c7b';

const row = (over: Partial<OrderSupportRow> & Record<string, unknown> = {}): OrderSupportRow => ({
  id: ID,
  status: 'seller_sent',
  buyer_confirmed_at: null,
  dispute_resolution: null,
  listing: { event_name: 'Neon Choir' },
  ...over,
}) as OrderSupportRow;

/** The decoded subject and body of a mailto URL, read the way a mail client reads them. */
function parse(url: string): { to: string; subject: string; body: string; rawQuery: string } {
  expect(url.startsWith('mailto:')).toBe(true);
  const [toPart, query = ''] = url.slice('mailto:'.length).split('?');
  const params = new Map<string, string>();
  for (const pair of query.split('&')) {
    const eq = pair.indexOf('=');
    params.set(pair.slice(0, eq), decodeURIComponent(pair.slice(eq + 1)));
  }
  return { to: toPart, subject: params.get('subject') ?? '', body: params.get('body') ?? '', rawQuery: query };
}

describe('OS1 · the support address', () => {
  it('is the address the Support screen already uses (the screen is a route module, so the value is pinned, not imported)', () => {
    expect(SUPPORT_EMAIL).toBe('support@snatchitapp.com');
    const screen = readFileSync(resolve(__dirname, '..', 'app/settings/support.tsx'), 'utf8');
    expect(screen).toContain(`'${SUPPORT_EMAIL}'`);
    expect(screen).toContain('mailto:');
  });
});

describe('OS2 · subject and body', () => {
  it('subject is "Order <short ref> · <status word>" with the first 8 characters of the order ID (the admin console\'s short form)', () => {
    const d = orderSupportDraft(row(), 'buyer')!;
    expect(d.subject).toBe('Order 3f2a9c1b · Marked sent');
    expect(d.shortRef).toBe('3f2a9c1b');
    expect(d.orderId).toBe(ID);
  });

  it('body is exactly: event, full order ID, status word, role, then an empty "What happened:" prompt', () => {
    const d = orderSupportDraft(row(), 'buyer')!;
    expect(d.body).toBe(
      ['Event: Neon Choir', `Order ID: ${ID}`, 'Status: Marked sent', 'Role: Buyer', '', 'What happened:', ''].join('\r\n'),
    );
    expect(orderSupportDraft(row({ status: 'pending' }), 'seller')!.body).toBe(
      ['Event: Neon Choir', `Order ID: ${ID}`, 'Status: Pending', 'Role: Seller', '', 'What happened:', ''].join('\r\n'),
    );
  });

  it('a missing event name drops the Event line instead of inventing one', () => {
    for (const listing of [null, undefined, { event_name: null }, { event_name: '   ' }]) {
      const d = orderSupportDraft(row({ listing }), 'buyer')!;
      expect(d.body.startsWith(`Order ID: ${ID}\r\n`)).toBe(true);
      expect(d.body).not.toMatch(/Event:|Untitled/);
    }
  });

  it('no order ID, no email: a blank or malformed ID returns null, so no action is offered', () => {
    expect(orderSupportDraft(row({ id: '' }), 'buyer')).toBeNull();
    expect(orderSupportDraft(row({ id: '   ' }), 'buyer')).toBeNull();
    expect(orderSupportDraft(row({ id: 'abc def' }), 'buyer')).toBeNull();
    expect(orderSupportDraft(row({ id: `${ID}\r\nBcc: x@example.test` }), 'buyer')).toBeNull();
  });

  it('only a uuid is an order ID: harness fixture IDs and other non-uuid strings get no email', () => {
    // The dev/sandbox harness mounts the order screens with id 'fixture-order' (app/_dev/v3-tickets.tsx);
    // a live draft to the production inbox about an order that does not exist is the side effect the
    // screens' fixture mode avoids elsewhere (write: !fixture).
    for (const id of [
      'fixture-order', 'fixture-listing', '3f2a9c1b', ID.replace(/-/g, ''), `${ID}-0`, `x${ID}`,
      ID.slice(0, -1), ID.replace('3f2a9c1b', '3f2a9c1g'), `{${ID}}`,
    ]) {
      expect(orderSupportDraft(row({ id }), 'buyer'), id).toBeNull();
    }
    // Case-insensitive, and surrounding whitespace is still trimmed before the check.
    expect(orderSupportDraft(row({ id: ID.toUpperCase() }), 'buyer')?.orderId).toBe(ID.toUpperCase());
    expect(orderSupportDraft(row({ id: ` ${ID} ` }), 'buyer')?.orderId).toBe(ID);
  });

  it('an event name is one line: CR/LF, tabs and Unicode line separators collapse to single spaces', () => {
    const d = orderSupportDraft(row({ listing: { event_name: 'Neon\r\nChoir\tLive\u2028Tour  ' } }), 'buyer')!;
    expect(d.body.split('\r\n')[0]).toBe('Event: Neon Choir Live Tour');
    expect(d.body.split('\r\n')).toHaveLength(7);
  });

  it('control characters that \\s does not cover (NUL, ESC, DEL, C1 NEL) are removed from the line too', () => {
    // NEL (U+0085) is a line break to some mail clients; NUL/ESC/DEL have no place in a header value.
    const d = orderSupportDraft(row({ listing: { event_name: 'Neon\u0000Choir\u0085Live\u001bTour\u007fNight' } }), 'buyer')!;
    expect(d.body.split('\r\n')[0]).toBe('Event: Neon Choir Live Tour Night');
    expect(d.url).not.toMatch(/%00|%1B|%7F|%C2%85/);
  });

  it('a very long event name is capped, on a character boundary', () => {
    const d = orderSupportDraft(row({ listing: { event_name: '🎤'.repeat(500) } }), 'buyer')!;
    const line = d.body.split('\r\n')[0].slice('Event: '.length);
    expect(Array.from(line).length).toBeLessThanOrEqual(200);
    expect(line.endsWith('…')).toBe(true);
    expect(line).not.toMatch(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])/);
  });
});

describe('OS3 · RFC 6068 encoding', () => {
  it('spaces are %20, never "+"; line breaks are %0D%0A, never a bare %0A', () => {
    const d = orderSupportDraft(row(), 'buyer')!;
    const { rawQuery } = parse(d.url);
    expect(rawQuery).not.toMatch(/[ +\r\n]/);
    expect(rawQuery).toContain('Order%203f2a9c1b');
    expect(rawQuery).toContain('%0D%0A');
    expect(rawQuery.replace(/%0D%0A/g, '')).not.toMatch(/%0A|%0D/);
  });

  it('the middle dot and non-ASCII are UTF-8 percent-encoded', () => {
    const d = orderSupportDraft(row({ listing: { event_name: 'Café Ñu 🎤' } }), 'buyer')!;
    const { rawQuery, body } = parse(d.url);
    expect(rawQuery).toContain('%C2%B7');            // ·
    expect(rawQuery).toContain('Caf%C3%A9');         // é
    expect(rawQuery).toContain('%F0%9F%8E%A4');      // 🎤
    expect(rawQuery).not.toMatch(/[^\x21-\x7E]/);    // nothing outside printable ASCII
    expect(body.split('\r\n')[0]).toBe('Event: Café Ñu 🎤');
  });

  it('reserved characters in an event name stay inside the body: no early end, no extra header', () => {
    const name = 'Rock & Roll ?=#% + Friends&cc=attacker@example.test';
    const d = orderSupportDraft(row({ listing: { event_name: name } }), 'buyer')!;
    const { to, subject, body, rawQuery } = parse(d.url);
    expect(to).toBe(SUPPORT_EMAIL);
    expect(rawQuery.split('&').map((p) => p.split('=')[0])).toEqual(['subject', 'body']);
    expect(subject).toBe('Order 3f2a9c1b · Marked sent');
    expect(body.split('\r\n')[0]).toBe(`Event: ${name}`);
    for (const enc of ['%26', '%3F', '%3D', '%23', '%25', '%2B']) expect(rawQuery).toContain(enc);
  });

  it('a lone surrogate in an event name does not throw (encodeURIComponent would) and becomes U+FFFD', () => {
    const d = orderSupportDraft(row({ listing: { event_name: 'Bad\uD800Name\uDC00' } }), 'buyer')!;
    expect(parse(d.url).body.split('\r\n')[0]).toBe('Event: Bad\uFFFDName\uFFFD');
  });

  it('decoding the URL gives back exactly the draft (round trip)', () => {
    for (const status of ['pending', 'seller_sent', 'buyer_confirmed', 'auto_released', 'disputed', 'expired', 'reversed']) {
      const d = orderSupportDraft(row({ status }), 'seller')!;
      const p = parse(d.url);
      expect(p.to).toBe(SUPPORT_EMAIL);
      expect(p.subject).toBe(d.subject);
      expect(p.body).toBe(d.body);
    }
  });

  it('mailtoUrl normalises any bare LF or CR in a body to CRLF', () => {
    const url = mailtoUrl(SUPPORT_EMAIL, 'a b', 'one\ntwo\rthree\r\nfour');
    expect(url).toBe(`mailto:${SUPPORT_EMAIL}?subject=a%20b&body=one%0D%0Atwo%0D%0Athree%0D%0Afour`);
  });
});

describe('OS4 · every transfer status gets the badge\'s word', () => {
  const cases: [string, Partial<OrderSupportRow>, 'buyer' | 'seller', string][] = [
    ['pending', {}, 'buyer', 'Pending'],
    ['pending', {}, 'seller', 'Pending'],
    ['seller_sent', {}, 'buyer', 'Marked sent'],
    ['seller_sent', {}, 'seller', 'Marked sent'],
    ['buyer_confirmed', { buyer_confirmed_at: '2026-10-20T10:00:00Z' }, 'buyer', 'Received'],
    ['buyer_confirmed', { buyer_confirmed_at: '2026-10-20T10:00:00Z' }, 'seller', 'Received'],
    // An operator's seller-win decision: no buyer confirmation, so the badge never says "Received".
    ['buyer_confirmed', { buyer_confirmed_at: null }, 'buyer', 'Resolved'],
    ['buyer_confirmed', { buyer_confirmed_at: null }, 'seller', 'Resolved'],
    ['auto_released', {}, 'buyer', 'Released'],
    ['auto_released', {}, 'seller', 'Released'],
    ['disputed', { dispute_resolution: null }, 'buyer', 'Issue'],
    ['disputed', { dispute_resolution: null }, 'seller', 'Issue'],
    ['disputed', { dispute_resolution: 'resolved_buyer_refunded' }, 'buyer', 'Resolved'],
    ['disputed', { dispute_resolution: 'resolved_partial_refund' }, 'seller', 'Resolved'],
    ['disputed', { dispute_resolution: 'some_future_ruling' }, 'buyer', 'Resolved'],
    ['expired', {}, 'buyer', 'Expired'],
    ['expired', {}, 'seller', 'Expired'],
    // `reversed` is the seller's payout event; the buyer's word is neutral.
    ['reversed', {}, 'seller', 'Payout reversed'],
    ['reversed', {}, 'buyer', 'Closed'],
    // A status this build does not know: the badge's own fallback, never an invented word.
    ['refund_pending', {}, 'buyer', 'refund pending'],
  ];
  for (const [status, over, role, word] of cases) {
    it(`${status} · ${role} · ${JSON.stringify(over)} → "${word}"`, () => {
      expect(orderSupportStatusWord(row({ status, ...over }), role)).toBe(word);
      const d = orderSupportDraft(row({ status, ...over }), role)!;
      expect(d.subject).toBe(`Order 3f2a9c1b · ${word}`);
      expect(d.body).toContain(`\r\nStatus: ${word}\r\n`);
      expect(d.body).toContain(`\r\nRole: ${role === 'buyer' ? 'Buyer' : 'Seller'}\r\n`);
    });
  }

  it('a blank status leaves the status out rather than ending the subject on a dangling dot', () => {
    const d = orderSupportDraft(row({ status: '' }), 'buyer')!;
    expect(d.subject).toBe('Order 3f2a9c1b');
    expect(d.body).not.toContain('Status:');
  });
});

describe('OS5 · no PII leaves in the email', () => {
  it('delivery email/phone, names, payment and Stripe ids on the row never reach the URL', () => {
    // The screens' joined listing carries more than the name; only the name may be read.
    const listing = { event_name: 'Neon Choir', venue: 'Lantern Room', ticket_platform: 'dice' };
    const full = row({
      status: 'buyer_confirmed',
      buyer_confirmed_at: '2026-10-20T10:00:00Z',
      delivery_email: 'buyer.private@example.test',
      delivery_phone: '+13055554417',
      seller: { display_name: 'Sam Seller' },
      buyer: { display_name: 'Bea Buyer' },
      seller_id: '11111111-1111-4111-8111-111111111111',
      buyer_id: '22222222-2222-4222-8222-222222222222',
      listing_id: '33333333-3333-4333-8333-333333333333',
      stripe_transfer_id: 'tr_FAKE_XFER',
      stripe_payment_intent_id: 'pi_FAKE_PI',
      transfer_evidence_path: 'transfer-evidence/u/proof.jpg',
      payout_review_status: 'held',
      listing,
    });
    for (const role of ['buyer', 'seller'] as const) {
      const d = orderSupportDraft(full, role)!;
      const decoded = `${parse(d.url).subject}\n${parse(d.url).body}`;
      for (const secret of [
        'buyer.private', 'example.test', '3055554417', 'Sam', 'Bea', '1111', '2222', '3333',
        'tr_', 'pi_', 'proof.jpg', 'held', 'Lantern', 'dice',
      ]) {
        expect(decoded, secret).not.toContain(secret);
        expect(d.url, secret).not.toContain(encodeURIComponent(secret));
      }
      expect(parse(d.url).body).toBe(
        ['Event: Neon Choir', `Order ID: ${ID}`, 'Status: Received', `Role: ${role === 'buyer' ? 'Buyer' : 'Seller'}`, '', 'What happened:', ''].join('\r\n'),
      );
    }
  });
});

describe('OS6 · opening the email, and the copy around it', () => {
  it('reports failure when the opener rejects or answers false, success otherwise', async () => {
    expect(await openOrderSupportMail('mailto:x', async () => true)).toBe(true);
    expect(await openOrderSupportMail('mailto:x', async () => undefined)).toBe(true);
    expect(await openOrderSupportMail('mailto:x', async () => false)).toBe(false);
    expect(await openOrderSupportMail('mailto:x', async () => { throw new Error('Unable to open URL'); })).toBe(false);
    expect(await openOrderSupportMail('mailto:x', () => { throw new Error('sync throw'); })).toBe(false);
  });

  it('the fallback names the address and the full order ID as text, and claims nothing was sent', () => {
    const text = ORDER_SUPPORT_COPY.couldNotOpen(ID);
    expect(text).toContain(SUPPORT_EMAIL);
    expect(text).toContain(ID);
    expect(text).not.toMatch(/sent|received|we('| wi)ll reply|within/i);
  });

  it('the action label is the agreed one, and the hint says it does not change the order', () => {
    expect(ORDER_SUPPORT_COPY.action).toBe('Contact support about this order');
    expect(ORDER_SUPPORT_COPY.hint).toMatch(/email/i);
    expect(ORDER_SUPPORT_COPY.hint).toMatch(/doesn't change the order/);
  });
});
