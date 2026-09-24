/**
 * No surface states a refund as completed (A's interim ruling, 2026-09-24).
 *
 * WHY. A refund row is written the moment the refund is CREATED. Nothing in today's `payments`
 * columns distinguishes that from one Stripe has settled — a pending refund, a succeeded one and one
 * that later failed all leave the same shape — so "Refunded $X" and "Full refund recorded" asserted a
 * completion no column establishes. Until migration 150 gives the lifecycle its own columns the word
 * is "initiated", and the partial line drops "of $total", which implied a settled shortfall.
 * Reference: REFUND_LIFECYCLE_TRACE_AND_FIX_20260924.md.
 *
 * The witness is the OLD strings: each one must fail this rule, so a test that passes on the new copy
 * cannot also be passing on the copy it replaced.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const FORBIDDEN = [/Refunded \$/, /Refunded \{/, /Full refund/i, /Partly refunded/i];
const SKIP = new Set(['node_modules']);

function sources(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    if (SKIP.has(name)) continue;
    const full = join(dir, name);
    if (statSync(full).isDirectory()) sources(full, out);
    else if (/\.tsx?$/.test(full)) out.push(full);
  }
  return out;
}
const code = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('a refund is stated as initiated, never as completed', () => {
  it('RI0 (witness): the rule REJECTS the strings it replaced', () => {
    for (const old of ['Refunded $120', 'Partly refunded $60 of $120', 'Full refund recorded', 'A full refund of {amount} was recorded for this payment.']) {
      expect(FORBIDDEN.some((re) => re.test(old)), old).toBe(true);
    }
    // And it admits the replacements, so it is not simply rejecting everything.
    for (const now of ['Refund of $120 initiated', 'Partial refund of $60 initiated', 'Refund initiated', 'Refund recorded']) {
      expect(FORBIDDEN.some((re) => re.test(now)), now).toBe(false);
    }
  });

  it('RI1: no consumer source claims a completed refund', () => {
    const offenders: string[] = [];
    for (const rel of [...sources('src'), ...sources('app')]) {
      const src = code(rel);
      for (const re of FORBIDDEN) if (re.test(src)) offenders.push(`${rel}: ${re}`);
    }
    expect(offenders).toEqual([]);
  });

  it('RI2: the two wording sources say "initiated", and the unconfirmed-amount variant is unchanged', async () => {
    const { refundLine } = await import('@/src/lib/transfer/transferState');
    expect(refundLine({ status: 'refunded', amount_refunded_cents: 9900, refunded_at: 'x', total: 9900 }))
      .toBe('Refund of $99 initiated');
    expect(refundLine({ status: null, amount_refunded_cents: 4000, refunded_at: null, total: 9900 }))
      .toBe('Partial refund of $40 initiated');
    // No total to compare against: the neutral line, unchanged.
    expect(refundLine({ status: 'refunded', amount_refunded_cents: null, refunded_at: 'x', total: 9900 }))
      .toBe('Refund recorded');
    expect(refundLine({ status: 'succeeded', amount_refunded_cents: null, refunded_at: null, total: 9900 })).toBeNull();
    const { REFUND_COPY } = await import('@/src/lib/checkout/holdState');
    expect(REFUND_COPY.refunded.title).toBe('Refund initiated');
    expect(REFUND_COPY.partially_refunded.title).toBe('Partial refund initiated');
    expect(REFUND_COPY.refund_unconfirmed.title).toBe('Refund recorded');
    // No timing claim anywhere in the three.
    for (const k of ['refunded', 'partially_refunded', 'refund_unconfirmed'] as const) {
      expect(`${REFUND_COPY[k].title} ${REFUND_COPY[k].body}`).not.toMatch(/within|hours|days|business|soon|shortly/i);
    }
  });

  it('RI3: one rate, not two — the config re-exports the money module\'s constants', async () => {
    const cfg = code('src/config/app.ts');
    expect(cfg).toContain("import { BUYER_FEE_RATE, SELLER_FEE_RATE } from '@/src/lib/money';");
    expect(cfg).toMatch(/^\s*BUYER_FEE_RATE,$/m);
    expect(cfg).not.toMatch(/BUYER_FEE_RATE:\s*0\.\d/);
    const { APP_CONFIG } = await import('@/src/config/app');
    const money = await import('@/src/lib/money');
    expect(APP_CONFIG.BUYER_FEE_RATE).toBe(money.BUYER_FEE_RATE);
    expect(APP_CONFIG.SELLER_FEE_RATE).toBe(money.SELLER_FEE_RATE);
  });
});
