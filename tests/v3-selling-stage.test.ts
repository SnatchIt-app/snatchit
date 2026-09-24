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

  it('SL3: the inline helper states the buyer side of the value being typed — the net lives at the sticky', async () => {
    const s = src();
    /*
     * RETARGETED (A's fee rulings, 2026-09-24). Two words changed, and both are claims:
     *   - "Buyers pay FROM $X total" on the starting bid, because the figure is the all-in on the
     *     STARTING bid and an auction settles on the winning one, which can only be higher;
     *   - the sticky's sub-line now names the net's BASIS, through `proceedsBasis`. "after the seller
     *     fee" alone named the deduction and left the basis unstated, so an auction-only listing read
     *     as a promise of exactly that net.
     */
    expect(s).toMatch(/helper=\{[^}]*`Buyers pay from \$\{summary\.buyerAllInLabel\}`/);
    expect(s).not.toContain('`You get ${summary.sellerNet} · buyers pay ${summary.buyerAllInLabel}`');
    // The sticky carries the seller's net with the one fee clause, and the clause names the basis.
    expect(s).toContain('proceedsBasis({ buyNowEnabled, buyNowPriceSet: buyNowPriceNum > 0 })');
    const { proceedsBasis } = await import('@/src/lib/sell/sellState');
    expect(proceedsBasis({ buyNowEnabled: true, buyNowPriceSet: true })).toBe('at the Buy Now price, after the seller fee');
    const auction = proceedsBasis({ buyNowEnabled: false, buyNowPriceSet: false });
    expect(auction).toContain('after the seller fee');
    expect(auction).toMatch(/least/);                       // the auction figure is a FLOOR
    expect(auction).toMatch(/higher winning bid pays more/);
  });

  it('SL4: one validation summary, at the action, only after a submit finds failures', () => {
    const s = src();
    expect(s).toContain('Fix the highlighted fields before listing.');
    // The gate is the sticky's ternary: valid → net; else submitted → the summary; else the hint.
    expect(s).toMatch(/summary\.valid \? \([\s\S]{0,900}\) : submitted \? \([\s\S]{0,300}Fix the highlighted fields/);
  });

  it('SL6 (R-4): the review card keeps Event / Tickets / Selling and drops the two money rows', () => {
    const s = src();
    expect(s).toContain('<ReviewRow label="Event"');
    expect(s).toContain('<ReviewRow label="Selling"');
    expect(s).not.toContain('<ReviewRow label="Buyer pays"');
    expect(s).not.toContain('<ReviewRow label="You receive"');
    expect(s).toMatch(/summary\.valid \? \(\s*<View style=\{sx\.reviewCard\}>/);
  });

  it('SL5: "Image added" stays secondary ink — green is reserved for confirmed money states', () => {
    const s = code('src/components/ui/MediaUpload.tsx');
    expect(s).toContain("'Image added'");
    expect(s).not.toMatch(/helper:\s*\{[^}]*status\.success/);
  });
});

/**
 * The V3 surface (2026-09-24): composition `pkg7-create-after.png`, tokens `pkg8-create-dark/
 * light.png`, validation states `pkg3-create-invalid.png`. Presentation only — the sell-state
 * shipped-source guards keep pinning the gate chain and the whole-dollar insert.
 */
describe('Create — the V3 surface', () => {
  const s = () => code('src/screens/CreateListingScreen.tsx');

  it('SL7: the title speaks the screen-title voice; sections are uppercase eyebrows, not Oswald display', () => {
    const src = s();
    expect(src).toMatch(/textStyle\('screenTitle'\), sx\.pageTitle/);
    expect(src).toMatch(/textStyle\('label'\), sx\.sectionTitle/);
    expect(src).not.toContain("textStyle('displaySm')");
    expect(src).not.toContain("textStyle('displayMd')");
  });

  it('SL8: no square controls remain — stepper, checkbox, panels take the role radii', () => {
    const src = s();
    expect(src).toMatch(/stepBtn: \{[^}]*borderRadius: v2\.radius\.md/);
    expect(src).toMatch(/checkbox: \{[^}]*borderRadius: v2\.radius\.sm/);
    expect(src).toMatch(/reviewCard: \{[^}]*borderRadius: v2\.radius\.md/);
    expect(src).toMatch(/riskBanner: \{[^}]*borderRadius: v2\.radius\.md/);
    expect(src).toMatch(/helperPanel: \{[^}]*borderRadius: v2\.radius\.sm/);
  });

  it('SL9: transfer method is a picker row opening a sheet (board annotation ②), same two values', () => {
    const src = s();
    expect(src).toMatch(/label="Transfer method"/);
    expect(src).toContain('setTransferOpen(true)');
    expect(src).toMatch(/<Sheet\s+visible=\{transferOpen\}/);
    // The V2 inline chips for transfer method are gone; ticket type keeps its chips.
    expect(src).not.toMatch(/TRANSFER_METHODS\.map\(\(\{ value, label \}\) => \(\s*<Chip/);
    expect(src).toMatch(/TICKET_TYPES\.map\(\(t\) => \(\s*<Chip/);
  });

  it('SL10: the CTA is the tall pill, and a fixture makes the screen preview-only before the first gate', () => {
    const src = s();
    expect(src).toMatch(/label=\{submitCtaLabel\(quantity\)\}\s+size="lg"/);
    // The harness can never walk the submit chain: the guard precedes setSubmitted and every gate.
    expect(src).toMatch(/async function handlePublish\(\) \{\s*if \(fixture\) return;\s*setSubmitted\(true\);/);
  });
});
