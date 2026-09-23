/**
 * V3 selling stage (pkg3 §1–§2 under the 2026-09-23 de-dup rule). Source pins: these screens'
 * behaviour suites already exist; what V3 changes is voice and where each money fact lives.
 *
 * Money on Create, each side once outside the standalone review card: the inline helper under
 * the active price field states the BUYER side of that value; the sticky bar carries the
 * SELLER net (the figure being decided) with the one fee clause. Findings F-1…F-8 stay
 * untouched — nothing functional changes here.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

const code = (rel: string) =>
  readFileSync(rel, 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('My listings — five empties that each mean something (§2)', () => {
  it('SL1: distinct sentences per filter, the Sell rename honoured, action only on All', () => {
    const src = code('app/my-listings.tsx');
    expect(src).toContain("'Tap the Sell tab to list your first ticket.'");
    expect(src).not.toContain('Create tab');
    expect(src).toContain("'No tickets waiting to be sent.'");
    // The shared filler is gone: ended and sold each say what lands there.
    expect(src).not.toContain("'Nothing here yet.'");
    expect(src).toContain('closed without a sale');
    expect(src).toContain('Completed sales');
    expect(src).toContain('live right now');
    // Action only on the All empty.
    expect(src).toMatch(/action=\{filter === 'all' \? \{ label: 'Create a listing'/);
  });

  it('SL2: the seller row speaks the display voice and a cancelled row stays readable', () => {
    const src = code('src/components/SellerListingCard.tsx');
    expect(src).toContain('NameText');
    expect(src).toContain('token="nameRow"');
    expect(src).toContain('cardCancelled: { opacity: 0.55 }');
  });
});

describe('Create — money sides once each; the summary at the action (§1)', () => {
  const src = () => code('src/screens/CreateListingScreen.tsx');

  it('SL3: the inline helper states the buyer side of the value being typed — the net lives at the sticky', () => {
    const s = src();
    expect(s).toMatch(/helper=\{[^}]*`Buyers pay \$\{summary\.buyerAllInLabel\}`/);
    expect(s).not.toContain('`You get ${summary.sellerNet} · buyers pay ${summary.buyerAllInLabel}`');
    // The sticky carries the seller's net with the one fee clause.
    expect(s).toContain('after the seller fee');
  });

  it('SL4: one validation summary, at the action, only after a submit finds failures', () => {
    const s = src();
    expect(s).toContain('Fix the highlighted fields before listing.');
    // The gate is the sticky's ternary: valid → net; else submitted → the summary; else the hint.
    expect(s).toMatch(/summary\.valid \? \([\s\S]{0,900}\) : submitted \? \([\s\S]{0,300}Fix the highlighted fields/);
  });

  it('SL5: "Image added" stays secondary ink — green is reserved for confirmed money states', () => {
    const s = code('src/components/ui/MediaUpload.tsx');
    expect(s).toContain("'Image added'");
    expect(s).not.toMatch(/helper:\s*\{[^}]*status\.success/);
  });
});
