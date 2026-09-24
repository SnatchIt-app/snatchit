/**
 * tests/premium-transfer-wording.test.ts — CFT-402 (item 30): the seller's
 * claim and the buyer's possession never share a word, anywhere.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { buyerAutoReleasedCopy, transferStatusCopy, transferStatusMeta } from '@/src/lib/transfer/transferState';
import { bidPresentation, type BidRowInput } from '@/src/lib/bids/bidState';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const ME = 'me';
const row = (over: Partial<BidRowInput>): BidRowInput => ({
  id: 'b1', amount: 50, bidder_id: ME, created_at: new Date().toISOString(),
  listing: { id: 'l1', event_name: 'x', current_bid: 50, auction_status: 'active', status: 'sold', ends_at: new Date().toISOString(), winner_user_id: ME, buy_now_enabled: false, buy_now_price: null, winning_bid_amount: null },
  ...over,
} as unknown as BidRowInput);

describe('vocabulary: claim ≠ possession', () => {
  it('badge labels: "Marked sent" is the claim, "Received" is possession, "Released" is the money', () => {
    expect(transferStatusMeta('seller_sent').label).toBe('Marked sent');
    expect(transferStatusMeta('buyer_confirmed').label).toBe('Received');
    expect(transferStatusMeta('auto_released').label).toBe('Released');
    // never the bare word that reads as a fact
    expect(transferStatusMeta('seller_sent').label).not.toBe('Sent');
    expect(transferStatusMeta('buyer_confirmed').label).not.toMatch(/complete/i);
  });

  it('role copy keeps "marked … sent" for the seller and "received" for the buyer', () => {
    const buyerSent = transferStatusCopy('seller_sent', 'buyer');
    expect(buyerSent.title).toBe('Seller marked as sent');
    expect(buyerSent.body).toMatch(/not a confirmation/);
    expect(buyerSent.body).not.toMatch(/received|delivered/i);

    const sellerSent = transferStatusCopy('seller_sent', 'seller');
    expect(sellerSent.title).toBe('Marked as sent');
    expect(sellerSent.body).toMatch(/confirm they received/);

    for (const role of ['buyer', 'seller'] as const) {
      const got = transferStatusCopy('buyer_confirmed', role);
      expect(got.title).toBe('Tickets received');
      expect(got.body).toMatch(/confirmed/);
    }
  });

  it('auto-release describes the money, and never claims possession', () => {
    for (const role of ['buyer', 'seller'] as const) {
      const c = transferStatusCopy('auto_released', role);
      expect(c.title).toMatch(/released/i);
      expect(`${c.title} ${c.body}`).not.toMatch(/tickets received|received the tickets/i);
    }
  });

  it('Bids tab rows: seller_sent is "Marked sent", buyer_confirmed is "Received"', () => {
    expect(bidPresentation(row({ purchaseTransferStatus: 'seller_sent' } as any), ME).label).toBe('Marked sent');
    expect(bidPresentation(row({ purchaseTransferStatus: 'seller_sent' } as any), ME).actionHint).toBe('Confirm receipt');
    expect(bidPresentation(row({ purchaseTransferStatus: 'buyer_confirmed' } as any), ME).label).toBe('Received');
  });
});

describe('screens use the vocabulary, not their own words', () => {
  it('receive: pending/sent/confirmed/released/disputed all come from transferStatusCopy', () => {
    const receive = stripComments(read('app/transfer/receive/[id].tsx'));
    for (const st of ['pending', 'buyer_confirmed', 'disputed']) {
      expect(receive, st).toContain(`transferStatusCopy('${st}', 'buyer')`);
    }
    // seller_sent moved into the shared block the screen renders (owner 2026-09-24, one implementation
    // for the screens and the sandbox gallery): the vocabulary is still the shared copy.
    expect(receive).toContain('<BuyerSellerSentBlock autoReleaseAt={transfer.auto_release_at} />');
    expect(stripComments(read('src/components/transfer/TransferStateBlocks.tsx'))).toContain("transferStatusCopy('seller_sent', 'buyer')");
    // Updated 2026-09-19 (owner/A): auto_released goes through buyerAutoReleasedCopy, which returns exactly this
    // shared copy once `payout_released_at` is set, and claims nothing about the money before that.
    expect(receive).toContain('buyerAutoReleasedCopy(transfer.payout_released_at)');
    expect(buyerAutoReleasedCopy('2026-09-19T00:00:00Z')).toEqual(transferStatusCopy('auto_released', 'buyer'));
    expect(buyerAutoReleasedCopy(null)).not.toEqual(transferStatusCopy('auto_released', 'buyer'));
    expect(receive).not.toContain('Transfer complete');
    expect(receive).toContain("Alert.alert('Receipt confirmed', 'You confirmed you received the tickets. Enjoy the event.')");
  });

  it('send: the seller reads "Marked as sent" and "Tickets received", never "Transfer sent/complete"', () => {
    const send = stripComments(read('app/transfer/send/[id].tsx'));
    // F-28 (B pkg7 §6b; owner 2026-09-24): the badge already reads "Marked sent", so the seller_sent
    // block carries only the forward-looking body and NO title repeating the badge. The block
    // component takes an optional title for exactly this case.
    expect(send).toMatch(/transfer\.status === 'seller_sent' \? \(\s*<SellerSentBlock/);
    expect(send).not.toContain('<StateBlock title="Marked as sent"');
    // The block itself (shared with the sandbox gallery) renders body only, no title, for seller_sent.
    const blocks = stripComments(read('src/components/transfer/TransferStateBlocks.tsx'));
    expect(blocks).toMatch(/function StateBlock\(\{ title, tone, children \}: \{ title\?: string/);
    expect(blocks).toMatch(/export function SellerSentBlock[\s\S]*?<StateBlock tone="neutral">/);
    expect(send).toContain('<StateBlock title="Tickets received"');
    // The success is announced for assistive tech - not a dialog repeating it.
    expect(send).not.toContain("Alert.alert('Marked as sent'");
    expect(send).toContain("announceForAccessibility('Marked as sent");
    // Failure feedback untouched: every failure dialog of the mark-sent path is still there.
    expect(send).toContain(`Alert.alert("Couldn't mark as sent"`);
    expect(send).toContain("Alert.alert('Not confirmed yet'");
    expect(send).toContain("Alert.alert('Already marked as sent'");
    expect(send).toContain("Alert.alert('Evidence required'");
    expect(send).toContain(`Alert.alert("Couldn't upload the transfer proof"`);
    expect(send).not.toMatch(/"Transfer sent"|"Transfer complete"|'Sent'/);
  });

  it('listing banner and the legacy badge say "Seller marked sent"', () => {
    expect(read('src/lib/listing/detailState.ts')).toContain("label: 'Seller marked sent'");
    const badge = read('src/components/TransferStatusBadge.tsx');
    expect(badge).toContain("label: 'Seller Marked Sent'");
    expect(badge).toContain("label: 'Tickets Received'");
  });

  it('no surface states the claim as a fact', () => {
    for (const rel of ['app/transfer/receive/[id].tsx', 'app/transfer/send/[id].tsx', 'src/lib/bids/bidState.ts', 'src/lib/listing/detailState.ts', 'src/lib/transfer/transferState.ts']) {
      const code = stripComments(read(rel));
      expect(code, rel).not.toMatch(/label: 'Tickets sent'|'Transfer Sent'|"Transfer sent"/);
    }
  });
});
