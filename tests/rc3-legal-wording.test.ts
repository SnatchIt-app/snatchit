/**
 * tests/rc3-legal-wording.test.ts — RC3 S6: app/settings/legal.tsx carries POLICY_WORDING §3.
 * The sentences are read off the rendered text (JSX entities and line wraps normalised), twice each:
 * once in the summary bullets and once in the full Terms.
 */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const text = readFileSync('app/settings/legal.tsx', 'utf8')
  .replace(/&apos;/g, "'").replace(/&amp;/g, '&').replace(/\s+/g, ' ');

const S = {
  F1: 'Buyers pay a service fee of 10% of the sale price (the Buy Now price or the winning bid, for the whole listing). It is added to the total at checkout and shown before you confirm.',
  F2: 'Sellers pay a marketplace fee of 10% of the same sale price, deducted from the payout.',
  P1: "When the buyer confirms they received the tickets, Snatch It starts the seller's payout straight away. If the payout can't be made at that moment, for example because the seller's payout account isn't ready, it waits for review by our team.",
  P2: 'If the buyer neither confirms nor reports a problem within 72 hours after the seller marks the tickets as sent, the order becomes eligible for release. Snatch It runs risk checks first: depending on the order, the payout is released, held until after the event, or held for manual review.',
  P3: "Once a payout is sent, when it reaches the seller's bank depends on Stripe's payout schedule and the bank. Snatch It doesn't guarantee a date.",
  R1: "If the seller doesn't mark the tickets as sent within 24 hours after your payment goes through, the order is cancelled automatically and a full refund of what you paid, including the service fee, is issued to your original payment method.",
  R2: 'Issuing a refund starts it with our payment processor, Stripe. It can show as pending for a while, and in rare cases a refund fails. Once it completes, how long it takes to appear depends on your bank or card issuer, typically 5 to 10 business days.',
  R3: "If a refund hasn't appeared after 10 business days, contact support@snatchitapp.com.",
};
const count = (needle: string) => text.split(needle).length - 1;

describe('RC3 · legal.tsx wording', () => {
  it('LW1: F1, F2, P1-P3 and R1-R3 each appear in the summary AND the full Terms', () => {
    for (const [k, s] of Object.entries(S)) expect(count(s), k).toBe(2);
  });

  it('LW2: the unconditional auto-release clause is gone, and the base-less fee sentence with it', () => {
    expect(text).not.toContain('(or the auto-release window expires)');
    expect(text).not.toContain('A 10% service fee is added to the buyer');
  });

  it('LW3: what POLICY_WORDING says to keep is kept', () => {
    expect(text).toContain('Snatch It reserves the right to modify fee structures with reasonable notice.');
    expect(text).toContain('transactions are final');
    expect(text).toContain('Snatch It does not guarantee refunds, returns, or exchanges.');
    expect(text).toContain("Payment funds are held by Stripe on Snatch It's behalf until the order is released.");
    expect(text).toContain('All transactions are denominated in USD.');
  });

  it('LW4: R1-R3 follow "transactions are final" / "does not guarantee refunds" in both places', () => {
    const a = text.indexOf('transactions are final.');
    expect(text.indexOf(S.R1, a)).toBeGreaterThan(a);
    const b = text.indexOf('Snatch It does not guarantee refunds, returns, or exchanges.');
    expect(text.indexOf(S.R1, b)).toBeGreaterThan(b);
  });
});
