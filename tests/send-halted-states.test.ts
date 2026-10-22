/**
 * F-SELL-STATES-1: a reversed or disputed transfer never tells the seller to send.
 *
 * The seller's Send screen showed the platform instructions and "Send tickets to" on any status that
 * wasn't already-sent or closed. A's lifecycle facts (production bodies, 2026-10-21):
 * - freeze_transfer_for_dispute can set `disputed` on a transfer that is still pending (never sent);
 * - `reversed` can, rarely, be reached without a send (a seller-win chargeback resolution, then a
 *   reversed payout).
 * So both states must hide the send instructions whether or not anything was sent. The heading
 * becomes the neutral "Buyer's delivery details" used for a closed order. What the screen SAYS on a
 * reversed payout is an owner wording question; this change only stops the wrong instruction.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { sellerSendHalted } from '@/src/lib/transfer/transferState';

const send = readFileSync('app/transfer/send/[id].tsx', 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('sellerSendHalted', () => {
  it('SH1: reversed and disputed halt sending; the live states do not', () => {
    expect(sellerSendHalted('reversed')).toBe(true);
    expect(sellerSendHalted('disputed')).toBe(true);
    for (const s of ['pending', 'seller_sent', 'buyer_confirmed', 'auto_released', 'expired']) {
      expect(sellerSendHalted(s), s).toBe(false);
    }
  });
});

describe('the Send screen', () => {
  it('SH2: the platform instructions are gated on the halt as well', () => {
    const gate = '{!alreadySent && !orderClosed && !sendHalted ? (';
    // The pin. (A's review: the old "witness" swapped the string out and asserted it was gone, which
    // can never fail. SH1 exercises sellerSendHalted itself; this pins the screen to it.)
    expect(send).toContain(gate);
    expect(send.match(/sellerSendHalted\(transfer\.status\)/g)?.length).toBe(1);
  });

  it('SH3: the heading is neutral on a halted order, as on a closed one', () => {
    expect(send).toContain(`{orderClosed || sendHalted ? "Buyer's delivery details" : 'Send tickets to'}`);
    expect(send).toContain('const sendHalted = transfer ? sellerSendHalted(transfer.status) : false;');
  });
});
