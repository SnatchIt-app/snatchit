/**
 * The app must not tell a person they did something they did not do.
 *
 * A transfer reaches `buyer_confirmed` two ways: the buyer confirms receipt, or an operator resolves
 * a dispute in the seller's favour. The client keyed its copy on the STATUS ALONE, so after a
 * seller-win decision the buyer — who had just lost a dispute — was told "You confirmed receipt.
 * Enjoy the event.", and the seller was told "The buyer confirmed they received the tickets."
 *
 * A verified at source (gate `aadf996e`) that the deployed server already distinguishes them:
 * `resolve_transfer_dispute` (065:119-152) is the only seller-win writer and never touches
 * `buyer_confirmed_at`; the only writer of that column is the buyer's own
 * `confirm_transfer_received` (0550:191-205); `guard_transfer_state_columns` (065:239) blocks direct
 * writes. So `buyer_confirmed_at IS NULL` on a `buyer_confirmed` row means "not the buyer".
 *
 * The key is deliberately the timestamp, not `dispute_resolution`: an older manual-runbook shape
 * exists with `dispute_resolution` NULL and `disputed_at` set, and the timestamp covers both.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { transferStatusCopy } from '@/src/lib/transfer/transferState';

const read = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('a dispute decision is not a confirmation', () => {
  it('DR1: the buyer is never told they confirmed receipt when an operator decided', () => {
    const copy = transferStatusCopy('buyer_confirmed', 'buyer', { buyerConfirmed: false });
    expect(copy.body).not.toMatch(/you confirmed|you received/i);
    // …and it must not suggest money is coming back.
    expect(`${copy.title} ${copy.body}`).not.toMatch(/refund|refunded|returned/i);
    // It says what actually happened, in the buyer's own terms.
    expect(copy.body).toMatch(/dispute/i);
  });

  it('DR2: the buyer who really did confirm still gets the confirming sentence', () => {
    const copy = transferStatusCopy('buyer_confirmed', 'buyer', { buyerConfirmed: true });
    expect(copy.body).toMatch(/you confirmed receipt/i);
  });

  it('DR3: the seller-win seller copy matches the server notice and does not imply a completed payout', () => {
    const copy = transferStatusCopy('buyer_confirmed', 'seller', { buyerConfirmed: false });
    expect(copy.title).toBe('Dispute resolved in your favour');
    expect(copy.body).not.toMatch(/buyer confirmed/i);
    // Payout state is the server's to state, not this sentence's.
    expect(`${copy.title} ${copy.body}`).not.toMatch(/payout (has been )?released|payout is being processed/i);
  });

  it('DR4: the seller whose buyer really confirmed still gets the confirming sentence', () => {
    const copy = transferStatusCopy('buyer_confirmed', 'seller', { buyerConfirmed: true });
    expect(copy.body).toMatch(/buyer confirmed/i);
  });

  it('DR5: the default is the confirming sentence — callers that pass nothing are unchanged', () => {
    expect(transferStatusCopy('buyer_confirmed', 'buyer').body).toMatch(/you confirmed receipt/i);
    expect(transferStatusCopy('seller_sent', 'buyer').body).toMatch(/seller's update/i);
  });

  it('DR6: both screens read the distinguishing column and pass it through', () => {
    const receive = read('app/transfer/receive/[id].tsx');
    const send = read('app/transfer/send/[id].tsx');
    for (const [name, src] of [['receive', receive], ['send', send]] as const) {
      expect(src, `${name} must select the column`).toMatch(/buyer_confirmed_at/);
      expect(src, `${name} must branch on it`).toMatch(/buyerConfirmed: /);
    }
    // The seller screen's own payout sentence no longer asserts the buyer's action either.
    const block = send.slice(send.indexOf("transfer.status === 'buyer_confirmed'"), send.indexOf('AUTO_RELEASED'));
    expect(block).not.toMatch(/'The buyer confirmed they received the tickets\./);
  });
});
