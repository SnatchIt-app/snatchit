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
      const src = code(rel);
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
