/**
 * Seller "one clear next action" (checklist item 39 / CFT-408) — the pure rule, tested where it lives.
 *
 * `sellerNextAction` turns ONE seller row's server facts — the listing status and the transfer's
 * {status, expires_at, transfer_evidence_path} — plus the device clock into at most one line:
 *
 *   pending, before expires_at          "Send by <local time from expires_at>"
 *   pending, expires_at missing/bad     "Send the tickets"         (no time is invented)
 *   pending, device clock past it       neutral: never "expired", never "checking", never "send"
 *   seller_sent with no proof           "Add proof"                (no deadline: the server has none)
 *   expired (server status)             the existing do-not-send sentence
 *   reversed / disputed / buyer_confirmed / auto_released / anything else   nothing
 *
 * Owner, 2026-09-19 (12c718b1 L17912): "A phone-clock deadline alone must not encourage sending
 * tickets or assert that a refund occurred." A (2026-10-21): expires_at is a display deadline only;
 * the server's expiry sweep is the authority. And the send screen's TRANSFER_EXPIRY_COPY.seller is
 * NOT reused: it says a status check is running, and My Listings runs none.
 */
import { describe, expect, it } from 'vitest';

import {
  msUntilNextSellerLineChange,
  SELLER_NEXT_ACTION_COPY,
  sellerActionOpensOrder,
  sellerNextAction,
  type SellerNextAction,
} from '@/src/lib/seller/nextAction';
import { ATTACH_COPY } from '@/src/lib/transfer/markSent';
import { SELLER_ORDER_CLOSED_COPY, TRANSFER_EXPIRY_COPY, transferStatusCopy } from '@/src/lib/transfer/transferState';

/** The device zone is read on purpose ("local time"), so every time assertion pins it. */
function inZone<T>(tz: string, body: () => T): T {
  const previous = process.env.TZ;
  process.env.TZ = tz;
  try {
    return body();
  } finally {
    // An unset TZ must come back unset: assigning undefined stores the string "undefined", an
    // invalid zone that quietly behaves like UTC for every later test in the file.
    if (previous === undefined) delete process.env.TZ;
    else process.env.TZ = previous;
  }
}

const DEADLINE = '2026-10-21T21:14:00-04:00';        // a Wednesday in New York
const BEFORE = Date.parse('2026-10-21T12:00:00-04:00');
const AFTER = Date.parse('2026-10-21T21:15:00-04:00');

const sold = (transfer: Parameters<typeof sellerNextAction>[0]['transfer']) => ({ listingStatus: 'sold', transfer });

describe('pending, before the deadline — "Send by <local time>"', () => {
  it('SN1: the time is expires_at in the device zone, in the shared row format', () => {
    inZone('America/New_York', () => {
      const a = sellerNextAction(sold({ status: 'pending', expires_at: DEADLINE }), BEFORE);
      expect(a).toEqual({ kind: 'send_by', line: 'Send by Wed 21 Oct · 21:14', tone: 'warning' });
    });
    // Same instant, a reader in London: the local clock is already Thursday 02:14 (BST).
    inZone('Europe/London', () => {
      expect(sellerNextAction(sold({ status: 'pending', expires_at: DEADLINE }), BEFORE)?.line)
        .toBe('Send by Thu 22 Oct · 02:14');
    });
  });

  it('SN2: the time comes only from expires_at — the device clock never moves it', () => {
    inZone('America/New_York', () => {
      const early = sellerNextAction(sold({ status: 'pending', expires_at: DEADLINE }), BEFORE - 6 * 3_600_000);
      const late = sellerNextAction(sold({ status: 'pending', expires_at: DEADLINE }), AFTER - 120_000);
      expect(early?.line).toBe('Send by Wed 21 Oct · 21:14');
      expect(late?.line).toBe(early?.line);
    });
  });

  it('SN3: a missing or unparseable expires_at shows the action with NO time', () => {
    for (const expires_at of [null, undefined, '', 'not-a-date']) {
      const a = sellerNextAction(sold({ status: 'pending', expires_at }), BEFORE);
      expect(a, String(expires_at)).toEqual({ kind: 'send', line: 'Send the tickets', tone: 'warning' });
      expect(a?.line).not.toMatch(/\d/);
    }
    // The sentence is the seller's existing pending title, not new copy.
    expect(SELLER_NEXT_ACTION_COPY.send).toBe(transferStatusCopy('pending', 'seller').title);
  });

  it('SN4: other server timestamps on the row are never used as the send deadline', () => {
    const row = { status: 'pending', expires_at: null, auto_release_at: DEADLINE, created_at: DEADLINE } as never;
    expect(sellerNextAction(sold(row), BEFORE)?.line).toBe('Send the tickets');
  });
});

describe('pending, device clock past expires_at — neutral wording', () => {
  const past = (now: number) => sellerNextAction(sold({ status: 'pending', expires_at: DEADLINE }), now) as SellerNextAction;

  it('SN5: the line is neutral — it never says expired, never claims a check, never says to send', () => {
    const a = past(AFTER);
    expect(a.kind).toBe('window_passed');
    expect(a.tone).toBe('neutral');
    expect(a.line).toBe(SELLER_NEXT_ACTION_COPY.windowPassed);
    expect(a.line).not.toMatch(/expir/i);
    expect(a.line).not.toMatch(/checking|being checked/i);
    expect(a.line).not.toMatch(/^Send (by|the|now)/);
    expect(a.line).not.toMatch(/refund/i);
    // Not the send screen's string: that one asserts a status check is running.
    expect(a.line).not.toBe(TRANSFER_EXPIRY_COPY.seller);
    expect(a.line).not.toBe(TRANSFER_EXPIRY_COPY.sellerLastCheckedOpen);
  });

  it('SN6: the switch happens AT the deadline (same boundary as the send screen countdown)', () => {
    const at = Date.parse(DEADLINE);
    expect(past(at).kind).toBe('window_passed');
    expect(past(at - 1).kind).toBe('send_by');
  });

  it('SN7: once past, no time is shown — the deadline is display only, the sweep decides', () => {
    expect(past(AFTER).line).not.toMatch(/\d/);
  });
});

describe('seller_sent — "Add proof" only while there is no proof', () => {
  it('SN8: no evidence path → Add proof, the send screen\'s own button word, with no deadline', () => {
    for (const transfer_evidence_path of [null, undefined, '']) {
      const a = sellerNextAction(sold({ status: 'seller_sent', expires_at: DEADLINE, transfer_evidence_path }), AFTER);
      expect(a, String(transfer_evidence_path)).toEqual({ kind: 'add_proof', line: 'Add proof', tone: 'warning' });
    }
    expect(SELLER_NEXT_ACTION_COPY.addProof).toBe(ATTACH_COPY.cta);
  });

  it('SN9: a stored proof means nothing left to do', () => {
    expect(sellerNextAction(sold({ status: 'seller_sent', transfer_evidence_path: 'u/t/proof.jpg' }), BEFORE)).toBeNull();
  });
});

describe('states with no seller action', () => {
  it('SN10: reversed, disputed, confirmed and released show nothing — never a send, never a proof', () => {
    for (const status of ['reversed', 'disputed', 'buyer_confirmed', 'auto_released']) {
      // Worst case for a leak: a future deadline and no proof on the row.
      expect(sellerNextAction(sold({ status, expires_at: DEADLINE, transfer_evidence_path: null }), BEFORE), status).toBeNull();
      expect(sellerNextAction(sold({ status, expires_at: DEADLINE, transfer_evidence_path: null }), AFTER), status).toBeNull();
    }
  });

  it('SN11: an unknown status shows nothing', () => {
    expect(sellerNextAction(sold({ status: 'something_new', expires_at: DEADLINE }), BEFORE)).toBeNull();
  });

  it('SN12: no transfer, or a listing that is not sold, shows nothing (parity with the old send line)', () => {
    expect(sellerNextAction(sold(null), BEFORE)).toBeNull();
    expect(sellerNextAction(sold(undefined), BEFORE)).toBeNull();
    for (const listingStatus of ['active', 'reserved']) {
      expect(sellerNextAction({ listingStatus, transfer: { status: 'pending', expires_at: DEADLINE } }, BEFORE)).toBeNull();
    }
  });
});

describe('server expired — the existing do-not-send sentence', () => {
  it('SN13: the server status wins over the device clock, and the copy is reused verbatim', () => {
    for (const now of [BEFORE, AFTER]) {
      const a = sellerNextAction(sold({ status: 'expired', expires_at: DEADLINE }), now);
      expect(a).toEqual({ kind: 'do_not_send', line: SELLER_ORDER_CLOSED_COPY.expired.body, tone: 'warning' });
    }
    expect(SELLER_NEXT_ACTION_COPY.doNotSend).toContain("Don't transfer the tickets");
  });

  it('SN14: "expired" is said only when the SERVER status says it', () => {
    const statuses = ['pending', 'seller_sent', 'buyer_confirmed', 'auto_released', 'disputed', 'reversed', 'expired'];
    const expiresValues = [DEADLINE, null, 'not-a-date'];
    for (const status of statuses) {
      for (const expires_at of expiresValues) {
        for (const now of [BEFORE, AFTER]) {
          const line = sellerNextAction(sold({ status, expires_at, transfer_evidence_path: null }), now)?.line ?? '';
          if (status !== 'expired') expect(line, `${status} ${expires_at} ${now}`).not.toMatch(/expir/i);
        }
      }
    }
  });
});

describe('exactly one action, and where the row goes', () => {
  it('SN15: the result is one line or nothing — never a list', () => {
    for (const status of ['pending', 'seller_sent', 'expired', 'disputed']) {
      const a = sellerNextAction(sold({ status, expires_at: DEADLINE, transfer_evidence_path: null }), BEFORE);
      if (a) {
        expect(typeof a.line).toBe('string');
        expect(a.line.length).toBeGreaterThan(0);
        expect(a.line).not.toContain('\n');
      }
    }
  });

  it('SN16: the send and proof actions open the order; the closed and empty cases do not', () => {
    inZone('America/New_York', () => {
      const open = (t: Parameters<typeof sellerNextAction>[0]['transfer'], now = BEFORE) =>
        sellerActionOpensOrder(sellerNextAction(sold(t), now));
      expect(open({ status: 'pending', expires_at: DEADLINE })).toBe(true);
      expect(open({ status: 'pending', expires_at: null })).toBe(true);
      expect(open({ status: 'pending', expires_at: DEADLINE }, AFTER)).toBe(true);   // the order screen re-reads
      expect(open({ status: 'seller_sent', transfer_evidence_path: null })).toBe(true);
      expect(open({ status: 'expired', expires_at: DEADLINE })).toBe(false);
      expect(open({ status: 'disputed' })).toBe(false);
      expect(sellerActionOpensOrder(null)).toBe(false);
    });
  });
});

describe('the zone pin itself', () => {
  it('SN17: inZone puts an unset TZ back unset (not the string "undefined", which reads as UTC)', () => {
    const saved = process.env.TZ;
    delete process.env.TZ;
    try {
      inZone('Europe/London', () => {});
      expect('TZ' in process.env).toBe(false);
      // ...and a zone that was set comes back as that zone.
      process.env.TZ = 'Asia/Tokyo';
      inZone('Europe/London', () => {});
      expect(process.env.TZ).toBe('Asia/Tokyo');
    } finally {
      if (saved === undefined) delete process.env.TZ;
      else process.env.TZ = saved;
    }
  });
});

describe('when does a row change on its own (E, D-2.3: no line outlives its deadline)', () => {
  const NOW = Date.parse('2026-10-21T20:00:00Z');
  const row = (status: string, expires_at: string | null, listingStatus = 'sold') =>
    ({ listingStatus, transfer: { status, expires_at } });

  it('SN18: the soonest pending deadline still ahead on a sold row — and nothing else — sets the delay', () => {
    expect(msUntilNextSellerLineChange([
      row('pending', '2026-10-21T23:00:00Z'),
      row('pending', '2026-10-21T20:02:00Z'),          // the soonest: 120 000 ms
      row('pending', '2026-10-21T19:00:00Z'),          // already past: its line has changed
      row('pending', 'not a date'),
      row('pending', null),
      row('seller_sent', '2026-10-21T20:00:30Z'),      // not a send deadline
      row('expired', '2026-10-21T20:00:10Z'),          // server fact, clock-independent
      row('pending', '2026-10-21T20:00:05Z', 'active'), // not sold: no action line at all
    ], NOW)).toBe(120_000);
  });

  it('SN19: no row that changes with the clock → no timer; the boundary itself is not "ahead"', () => {
    expect(msUntilNextSellerLineChange([], NOW)).toBeNull();
    expect(msUntilNextSellerLineChange([row('seller_sent', null), row('expired', '2026-10-22T00:00:00Z')], NOW)).toBeNull();
    expect(msUntilNextSellerLineChange([row('pending', '2026-10-21T20:00:00Z')], NOW)).toBeNull();
    expect(msUntilNextSellerLineChange([{ listingStatus: 'sold', transfer: null }], NOW)).toBeNull();
  });
});
