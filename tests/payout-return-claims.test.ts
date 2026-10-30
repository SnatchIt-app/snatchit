/**
 * tests/payout-return-claims.test.ts — F5: returning from Stripe confirms nothing.
 *
 * Stripe calls the Connect `return_url` whenever the seller leaves onboarding — finished or not.
 * app/payout-return.tsx rendered a success Badge "Connected", the header "Payout setup complete"
 * and "Your Stripe account is connected" UNCONDITIONALLY on arrival, then auto-routed to Profile.
 * Owner truth: returning from another app never confirms or releases anything. Found by the
 * read-only critical-flow audit of d27aa449; contract set by A (2026-10-12).
 *
 * Contract: this screen claims nothing. It sends the seller to /settings/payout-setup, which
 * verifies the real status through the `status_only` probe and owns the settled wording
 * ("Not connected" / "Connected") — that screen's strings are untouched here.
 *
 * Mutant this file must kill: restoring the unconditional badge.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

const read = (rel: string) => readFileSync(rel, 'utf8');
const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const ret = strip(read('app/payout-return.tsx'));
const setup = read('app/settings/payout-setup.tsx');

describe('F5 · the Stripe return screen makes no claim', () => {
  it('PR1: no "Connected" badge, no "complete", no "is connected" on arrival', () => {
    expect(ret).not.toMatch(/label=["']Connected["']/);
    expect(ret).not.toMatch(/tone=["']success["']/);
    expect(ret).not.toMatch(/Payout setup complete/);
    expect(ret).not.toMatch(/is connected/i);
    expect(ret).not.toMatch(/ready to receive payouts/i);
  });

  it('PR2: it routes to the screen that verifies, not to Profile', () => {
    expect(ret).toContain("'/settings/payout-setup'");
    expect(ret).not.toContain("'/(tabs)/profile'");
  });

  it('PR3: payout-setup still owns the settled wording, verified through status_only — untouched', () => {
    expect(setup).toContain('status_only');
    expect(setup).toContain("statusLabel: 'Not connected'");
    expect(setup).toContain("statusLabel: 'Connected'");
  });

  it('PR4: the interim copy is the one neutral sentence, listed in the handoff, and nothing else is asserted', () => {
    // One sentence, present tense, describes what the app is doing — not what happened.
    expect(ret).toContain('Checking your payout setup');
    expect(ret).not.toMatch(/success|complete|connected/i);
  });
});
