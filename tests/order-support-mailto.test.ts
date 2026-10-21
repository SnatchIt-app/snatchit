/**
 * tests/order-support-mailto.test.ts — the order-aware support email (CFT-406 / item 34, slice 1).
 *
 * "I haven't received my tickets" should carry the order and its status into the support flow, so the
 * user does not hunt for IDs or retype the story (owner's checklist item 34). The only channel is the
 * support inbox, so slice 1 is a prefilled mailto. What these tests pin:
 *
 *  - ENCODING (RFC 6068): spaces are %20 (never '+'), line breaks are %0D%0A, non-ASCII is UTF-8
 *    percent-encoded, and reserved characters ('&', '=', '?', '#', '%', '+') cannot end the subject or
 *    body early or start a new header. The vehicle is the one free value left in the email: a status
 *    this build does not know reaches the subject and body as the badge's fallback word.
 *  - THE STATUS WORD is the badge's word, from the same derivation the order screens use, for every
 *    status the server writes — expired, reversed and disputed included.
 *  - ONLY THE ORDER (C review M1): the email holds the order ID, the status word, the role, and an
 *    empty "What happened:" prompt. Whatever else the row carries — the event name (seller free text),
 *    delivery email/phone, names, Stripe ids — never reaches the URL.
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

  it('body is exactly: full order ID, status word, role, then an empty "What happened:" prompt', () => {
    const d = orderSupportDraft(row(), 'buyer')!;
    expect(d.body).toBe(
      [`Order ID: ${ID}`, 'Status: Marked sent', 'Role: Buyer', '', 'What happened:', ''].join('\r\n'),
    );
    expect(orderSupportDraft(row({ status: 'pending' }), 'seller')!.body).toBe(
      [`Order ID: ${ID}`, 'Status: Pending', 'Role: Seller', '', 'What happened:', ''].join('\r\n'),
    );
  });

  it('the event name never appears in the subject or body, for any listing (C review M1: it is seller free text)', () => {
    const listings: unknown[] = [
      null, undefined, {}, { event_name: null }, { event_name: '   ' },
      { event_name: 'Neon Choir' },
      { event_name: 'Rock & Roll ?=#% + Friends&cc=attacker@example.test' },
      { event_name: 'Neon\r\nBcc: attacker@example.test\u0085\u2028\u0000\u001b Choir' },
      { event_name: 'Café Ñu 🎤' },
      { event_name: 'Bad\uD800Name' },
    ];
    for (const role of ['buyer', 'seller'] as const) {
      const expected = [`Order ID: ${ID}`, 'Status: Marked sent', `Role: ${role === 'buyer' ? 'Buyer' : 'Seller'}`, '', 'What happened:', ''].join('\r\n');
      for (const listing of listings) {
        const label = JSON.stringify({ role, listing });
        const d = orderSupportDraft(row({ listing }), role)!;
        expect(d.subject, label).toBe('Order 3f2a9c1b · Marked sent');
        expect(d.body, label).toBe(expected);
        const { subject, body, rawQuery } = parse(d.url);
        expect(subject, label).toBe(d.subject);
        expect(body, label).toBe(expected);
        expect(`${subject}\n${body}`, label).not.toMatch(/Event|Neon|Choir|Rock|Friends|attacker|Bcc|Café|Ñu|🎤|Bad|\uFFFD/);
        for (const enc of ['Neon', 'Choir', 'attacker', 'Caf%C3%A9', '%F0%9F%8E%A4', '%EF%BF%BD']) expect(rawQuery, `${label} ${enc}`).not.toContain(enc);
      }
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

  it('a status word is one line: CR/LF, tabs and Unicode line separators collapse to single spaces', () => {
    // An unknown server status reaches the subject and body as the badge's fallback word.
    const d = orderSupportDraft(row({ status: 'Neon\r\nChoir\tLive\u2028Tour  ' }), 'buyer')!;
    expect(d.subject).toBe('Order 3f2a9c1b · Neon Choir Live Tour');
    expect(d.body.split('\r\n')[1]).toBe('Status: Neon Choir Live Tour');
    expect(d.body.split('\r\n')).toHaveLength(6);
  });

  it('control characters that \\s does not cover (NUL, ESC, DEL, C1 NEL) are removed from the status word too', () => {
    // NEL (U+0085) is a line break to some mail clients; NUL/ESC/DEL have no place in a header value.
    const d = orderSupportDraft(row({ status: 'Neon\u0000Choir\u0085Live\u001bTour\u007fNight' }), 'buyer')!;
    expect(d.subject).toBe('Order 3f2a9c1b · Neon Choir Live Tour Night');
    expect(d.body.split('\r\n')[1]).toBe('Status: Neon Choir Live Tour Night');
    expect(d.url).not.toMatch(/%00|%1B|%7F|%C2%85/);
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

  // The vehicle below is a status this build does not know: its badge fallback word is the one free
  // value that still flows into the subject AND the body (the event name never does — C review M1).
  it('the middle dot and non-ASCII (é, Ñ, an emoji) in a status word are UTF-8 percent-encoded', () => {
    for (const role of ['buyer', 'seller'] as const) {
      const d = orderSupportDraft(row({ status: 'Café Ñu 🎤' }), role)!;
      const { rawQuery, subject, body } = parse(d.url);
      expect(rawQuery).toContain('%C2%B7');            // ·
      expect(rawQuery).toContain('Caf%C3%A9');         // é
      expect(rawQuery).toContain('%C3%91u');           // Ñ
      expect(rawQuery).toContain('%F0%9F%8E%A4');      // 🎤
      expect(rawQuery).not.toMatch(/[^\x21-\x7E]/);    // nothing outside printable ASCII
      expect(subject).toBe('Order 3f2a9c1b · Café Ñu 🎤');
      expect(body.split('\r\n')[1]).toBe('Status: Café Ñu 🎤');
    }
  });

  it('reserved characters in a status word stay inside the subject and body: no early end, no extra header', () => {
    const word = 'Rock & Roll ?=#% + Friends&cc=attacker@example.test';
    for (const role of ['buyer', 'seller'] as const) {
      const d = orderSupportDraft(row({ status: word }), role)!;
      const { to, subject, body, rawQuery } = parse(d.url);
      expect(to).toBe(SUPPORT_EMAIL);
      // Only the subject and body params: one literal '&', two literal '=', no '?', '#', '+' or space.
      expect(rawQuery.split('&').map((p) => p.split('=')[0])).toEqual(['subject', 'body']);
      expect(rawQuery.match(/&/g)).toHaveLength(1);
      expect(rawQuery.match(/=/g)).toHaveLength(2);
      expect(rawQuery).not.toMatch(/[?#+ ]/);
      expect(rawQuery).not.toMatch(/%(?![0-9A-F]{2})/);
      expect(subject).toBe(`Order 3f2a9c1b · ${word}`);
      expect(body.split('\r\n')[1]).toBe(`Status: ${word}`);
      for (const enc of ['%26', '%3F', '%3D', '%23', '%25', '%2B']) expect(rawQuery).toContain(enc);
    }
  });

  it('a lone surrogate in a status word does not throw (encodeURIComponent would) and becomes U+FFFD', () => {
    // A throw here fails the test: orderSupportDraft is called directly.
    for (const role of ['buyer', 'seller'] as const) {
      const d = orderSupportDraft(row({ status: 'Bad\uD800Name\uDC00' }), role)!;
      const { subject, body } = parse(d.url);
      expect(subject).toBe('Order 3f2a9c1b · Bad\uFFFDName\uFFFD');
      expect(body.split('\r\n')[1]).toBe('Status: Bad\uFFFDName\uFFFD');
      expect(d.url).toContain('Bad%EF%BF%BDName%EF%BF%BD');
    }
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

describe('OS4b · a status word from the server can never break the email\'s lines (E, D-2.5)', () => {
  it('OS4b: control characters in an unknown status are flattened in the subject and the Status line', () => {
    // An unknown status falls through to the badge's own fallback word; whatever the server sends,
    // it must not start a new line, inject a header-looking line or carry a control character.
    const nasty = 'odd\r\nBcc: x@example.test\u0085\u2028\u0000\u001b';
    for (const role of ['buyer', 'seller'] as const) {
      const d = orderSupportDraft(row({ status: nasty }), role)!;
      const { subject, body } = parse(d.url);
      expect(subject).not.toMatch(/[\u0000-\u001F\u007F-\u009F\u2028\u2029]/);
      const statusLines = body.split('\r\n').filter((l) => l.startsWith('Status: '));
      expect(statusLines).toHaveLength(1);
      expect(statusLines[0]).not.toMatch(/[\u0000-\u001F\u007F-\u009F\u2028\u2029]/);
      // No line of the body may begin with an injected header word.
      expect(body.split('\r\n').some((l) => /^bcc:/i.test(l))).toBe(false);
    }
  });
});

describe('OS5 · no PII leaves in the email', () => {
  it('the event name, delivery email/phone, names, payment and Stripe ids on the row never reach the URL', () => {
    // The screens' joined listing carries the event name and more; none of it may be read (C review M1).
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
        'tr_', 'pi_', 'proof.jpg', 'held', 'Lantern', 'dice', 'Neon', 'Choir', 'Event',
      ]) {
        expect(decoded, secret).not.toContain(secret);
        expect(d.url, secret).not.toContain(encodeURIComponent(secret));
      }
      expect(parse(d.url).body).toBe(
        [`Order ID: ${ID}`, 'Status: Received', `Role: ${role === 'buyer' ? 'Buyer' : 'Seller'}`, '', 'What happened:', ''].join('\r\n'),
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
