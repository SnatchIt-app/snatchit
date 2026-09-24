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

/**
 * A's review of ca27d282 passed the gated read and named three more surfaces asserting the same
 * thing the body copy no longer does. The badge is the loudest of them: "Received", in success tone,
 * shown to a buyer who reported non-receipt and lost.
 */
describe('the other surfaces that asserted receipt', () => {
  it('DR7: the badge for an operator decision does not say "Received"', async () => {
    const { transferStatusMeta } = await import('@/src/lib/transfer/transferState');
    for (const role of ['buyer', 'seller'] as const) {
      const meta = transferStatusMeta('buyer_confirmed', role, { buyerConfirmed: false });
      expect(meta.label, role).toBe('Resolved');
      // Not a success for the buyer: they asked for help and the decision went the other way.
      expect(meta.tone, role).toBe('neutral');
    }
    // A real confirmation is unchanged, including the default with no option passed.
    expect(transferStatusMeta('buyer_confirmed', 'buyer', { buyerConfirmed: true })).toEqual({ label: 'Received', tone: 'success' });
    expect(transferStatusMeta('buyer_confirmed')).toEqual({ label: 'Received', tone: 'success' });
  });

  it('DR8: both transfer screens pass the fact to the badge, not just to the body', () => {
    for (const rel of ['app/transfer/receive/[id].tsx', 'app/transfer/send/[id].tsx']) {
      const src = read(rel);
      expect(src, rel).toMatch(/transferStatusMeta\([^)]*buyerConfirmed/s);
    }
  });

  it('DR9: the Bids board does not label an operator decision "Received"', async () => {
    const { bidPresentation } = await import('@/src/lib/bids/bidState');
    const ME = 'me';
    const row = (extra: Record<string, unknown>) => ({
      id: 'b1', amount: 10000, bidder_user_id: ME, listing_id: 'l1',
      listing: { id: 'l1', seller_id: 's1', auction_status: 'ended', current_bid: 10000, winner_user_id: ME },
      purchaseTransferStatus: 'buyer_confirmed', ...extra,
    });
    // Same status, two causes: the board must not read "Received" for the operator decision.
    const decided = bidPresentation(row({ purchaseBuyerConfirmedAt: null }) as never, ME);
    expect(decided.label).toBe('Resolved');
    const confirmed = bidPresentation(row({ purchaseBuyerConfirmedAt: '2026-09-20T00:00:00Z' }) as never, ME);
    expect(confirmed.label).toBe('Received');
  });

  it('DR10: a seller-win payout line says only what the payout fields state', async () => {
    const src = read('app/transfer/send/[id].tsx');
    // Under a hold or a manual review the payout is NOT being processed, so the operator-decision
    // branch defers to the same hold/review lines the seller_sent board already uses.
    const block = src.slice(src.indexOf("transfer.status === 'buyer_confirmed'"), src.indexOf('AUTO_RELEASED'));
    expect(block).toMatch(/payout_review_status/);
    expect(block).toMatch(/sellerHoldLine|SELLER_HELD|holdLine/);
    // A genuine confirmation overrides holds and pays immediately, so its wording is untouched.
    expect(block).toMatch(/byBuyer/);
  });
});
