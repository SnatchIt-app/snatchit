/**
 * The app states no service time it does not control (owner's decision, 2026-09-24, routed through A
 * and E; A specified the test).
 *
 * WHAT WENT: "We review reports within 24 hours" (the report confirmation), "Reports are reviewed by
 * the Snatch It team within 24 hours" (the privacy page), "Our team typically reviews within 24
 * hours" (the buyer's dispute block) and "We aim to respond within 1 to 2 business days" (support).
 * Each was a service-level commitment with nothing behind it: no queue, no rota and no operator SLA
 * exists to keep them, and a support inbox cannot promise a business-day turnaround. What the product
 * DOES is still stated — reports are reviewed and acted on, a report freezes the seller's payout —
 * and only the clock is gone.
 *
 * WHAT STAYS, and is this suite's witness: the seller's attestation on the create screen, "I confirm
 * I own these tickets and will transfer them within 24 hours of sale." That is a commitment the
 * SELLER makes, and the 24-hour send deadline enforces it (061:111) — the opposite case to the four
 * above, which is exactly why a blanket search for the phrase would be the wrong test.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOTS = ['app', 'src'];
const SKIP = new Set(['_dev', 'node_modules']);

/** Every consumer source file, `_dev` harnesses excluded — they are not user-facing. */
function sources(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    if (SKIP.has(name)) continue;
    const full = join(dir, name);
    if (statSync(full).isDirectory()) sources(full, out);
    else if (/\.tsx?$/.test(full)) out.push(full);
  }
  return out;
}

/** Comments stripped: a phrase quoted in a rationale is not a phrase the app says. */
const code = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const FILES = ROOTS.flatMap((r) => sources(r));
const ATTESTATION = 'src/screens/CreateListingScreen.tsx';

/**
 * RC3 S6 (POLICY_WORDING §2, owner direction 2026-10-13): the Terms now carry three refund sentences
 * that name a time — the seller's 24-hour send window (a product rule, not our review time), the
 * bank's "typically 5 to 10 business days" (Stripe's guidance about the card issuer, not our
 * response) and "after 10 business days, contact support" (a user instruction). None is a turnaround
 * WE promise for reviewing or replying, which is what this guard forbids. They are admitted by EXACT
 * text in that one file: any other 24-hour or business-day phrase there still fails.
 */
const LEGAL = 'app/settings/legal.tsx';
const POLICY_REFUND_SENTENCES = [
  "If the seller doesn't mark the tickets as sent within 24 hours after your payment goes through, the order is cancelled automatically and a full refund of what you paid, including the service fee, is issued to your original payment method.",
  'Issuing a refund starts it with our payment processor, Stripe. It can show as pending for a while, and in rare cases a refund fails. Once it completes, how long it takes to appear depends on your bank or card issuer, typically 5 to 10 business days.',
  "If a refund hasn't appeared after 10 business days, contact support@snatchitapp.com.",
];
/** The rendered text of a JSX file: entities and line wraps resolved, so a sentence can be matched whole. */
const rendered = (src: string) => src.replace(/&apos;/g, "'").replace(/&amp;/g, '&').replace(/\s+/g, ' ');
const withoutPolicyRefundSentences = (src: string) =>
  POLICY_REFUND_SENTENCES.reduce((acc, sentence) => acc.split(sentence).join(''), rendered(src));

describe('no promised turnaround anywhere in the consumer app', () => {
  it('ST0 (witness): the search sees real files, and finds the ONE legitimate use of the phrase', () => {
    // Without this, a zero below could be an empty file list or a broken matcher.
    expect(FILES.length).toBeGreaterThan(100);
    const attestation = code(ATTESTATION);
    expect(attestation).toContain('will transfer them within 24 hours of sale');
    expect(/within 24 hours/.test(attestation)).toBe(true);
  });

  it('ST1: no file promises a review time, a typical review or a business-day response', () => {
    const offenders: string[] = [];
    for (const rel of FILES) {
      const src = rel === LEGAL ? withoutPolicyRefundSentences(code(rel)) : code(rel);
      for (const [pattern, what] of [
        [/within 24 hours/, 'a 24-hour promise'],
        [/typically reviews/, 'a typical review time'],
        [/business day/i, 'a business-day response'],
      ] as const) {
        if (!pattern.test(src)) continue;
        // The seller's own obligation is the one legitimate use, and only in that one sentence.
        if (rel === ATTESTATION && /will transfer them within 24 hours of sale/.test(src)) continue;
        offenders.push(`${rel}: ${what}`);
      }
    }
    expect(offenders).toEqual([]);
  });

  it('ST1c: the admitted refund sentences are live in the Terms, verbatim, and promise no review or reply time', () => {
    const legal = rendered(code(LEGAL));
    for (const sentence of POLICY_REFUND_SENTENCES) {
      expect(legal, sentence).toContain(sentence);                 // the exemption covers real text, not a dead list
      expect(sentence).not.toMatch(/we (review|aim|respond|reply)|our team (reviews|responds)|typically reviews/i);
    }
    // And the exemption is exact: the same file with one word changed is an offender again.
    const drifted = legal.replace('within 24 hours after your payment', 'within 24 hours of your payment');
    expect(/within 24 hours/.test(POLICY_REFUND_SENTENCES.reduce((a, s) => a.split(s).join(''), drifted))).toBe(true);
  });

  it('ST1b: two OTHER kinds of time survive, and must — a statutory duty and a user instruction', () => {
    /*
     * The rule is about turnarounds WE promise for reviewing and replying. It is not "no number of
     * hours anywhere", and a sweep written that way would delete two things that should stay. Pinned
     * so the next pass does not take them:
     *   - the data-request response, which is a statutory obligation, not a service level we chose;
     *   - "contact us if nothing arrives within 2 hours", which is an instruction TO the user about
     *     when to act, not a claim about what we will do.
     */
    expect(code('app/settings/privacy.tsx')).toContain('We will respond to data requests within 30 days.');
    const instructions = code('src/lib/platformInstructions.ts');
    expect(instructions).toMatch(/if nothing arrives within 2 hours/);
    expect(instructions).toMatch(/haven\\'t received anything within 2 hours/);
  });

  it('ST2: what the product does is still stated — only the clock was removed', () => {
    expect(code('app/report/[type]/[id].tsx')).toContain('We review reports and act on what we find.');
    expect(code('app/settings/privacy.tsx')).toContain('Reports are reviewed by the Snatch It team.');
    expect(code('app/settings/support.tsx')).toMatch(/a description of the issue/);
    const transfer = code('src/lib/transfer/transferState.ts');
    expect(transfer).toContain("The seller's payout is frozen until this is resolved.");
    expect(transfer).toContain('Your payout is frozen until the report is resolved.');
  });
});
