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

describe('RC3 · C-RC3-1 — no Terms paragraph exceeds the length iOS painted whole', () => {
  /*
   * Written when §6's last line vanished on the RC3 binary and length looked like the cause. It was
   * not (the split node still lost its last line on RC4): the cause is pixel-grid rounding of an
   * on-grid text height at a fractional offset — see LW6 and the textSlack note in legal.tsx. The cap
   * stays as a readability guard for the Terms, nothing more.
   */
  const MAX_RENDERED_CHARS = 1000;
  const source = readFileSync('app/settings/legal.tsx', 'utf8');
  const norm = (t: string) => t.replace(/&apos;/g, "'").replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/\s+/g, ' ').trim();

  it('LW5: every ftBody paragraph and every summary bullet renders at most 1,000 characters', () => {
    const long: string[] = [];
    for (const m of source.matchAll(/<Text style=\{(?:s\.ftBody|\[s\.ftBody[^\]]*\])\}>([\s\S]*?)<\/Text>/g)) {
      const t = norm(m[1]); if (t.length > MAX_RENDERED_CHARS) long.push(`ftBody ${t.length}: ${t.slice(0, 50)}…`);
    }
    for (const m of source.matchAll(/<Bullet s=\{s\}>([\s\S]*?)<\/Bullet>/g)) {
      const t = norm(m[1]); if (t.length > MAX_RENDERED_CHARS) long.push(`Bullet ${t.length}: ${t.slice(0, 50)}…`);
    }
    expect(long).toEqual([]);
  });
});

describe('RC3 · C-RC3-1 — the cause: an on-grid paragraph height can lose a third of a point to rounding', () => {
  /*
   * iOS, RN 0.81.5 Fabric: a Text measured at exactly N × lineHeight (RN ceils every measurement to the
   * pixel grid) can be given a frame 1/3 pt shorter by Yoga's rounding at a fractional absolute offset in a
   * very tall scroll; the renderer draws into that frame and NSLayoutManager drops the whole last line.
   * Observed on the Legal screen (§6 on RC3/RC4, §5 in the lab with a 2,750-pt spacer; a 1/3-pt shift of the
   * content above moved it away). Half a point of bottom padding makes the node height fractional, which
   * makes Yoga round the bottom edge UP, so the text container is never shorter than the text.
   * Device proof: private-evidence/C-session-12c718b1/rc3-legal-lab/ (variant=noslack is the control).
   */
  const src = readFileSync('app/settings/legal.tsx', 'utf8');
  const style = (name: string) => {
    const m = new RegExp(`^\\s+${name}:\\s*\\{([^}]*)\\}`, 'm').exec(src);
    expect(m, `${name} style`).not.toBeNull();
    return m![1];
  };

  it('LW6: every long-paragraph style on the Legal screen carries the half-point bottom slack', () => {
    for (const name of ['ftBody', 'bulletText']) {
      const body = style(name);
      expect(body, name).toMatch(/lineHeight:\s*22/);          // the on-grid height this guards
      expect(body, name).toMatch(/paddingBottom:\s*0\.5\b/);   // the slack
    }
  });

  it('LW6b: the slack is a sub-point, never a visible spacing change', () => {
    for (const name of ['ftBody', 'bulletText']) {
      const m = /paddingBottom:\s*([0-9.]+)/.exec(style(name));
      expect(Number(m![1])).toBeGreaterThan(0);
      expect(Number(m![1])).toBeLessThan(1);
    }
  });
});
