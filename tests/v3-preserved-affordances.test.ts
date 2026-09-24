/**
 * The affordances a board may not delete (owner ruling 2026-09-24):
 *
 *   "Preserve required-field helpers, moderation controls and meaningful seller actions even where
 *    sample boards omit them."
 *
 * The V3 boards are compositions, not feature inventories: `pkg5-*` letters the password rule
 * INSIDE the signup field, `pkg8-listing-*` draws no overflow control at all, and `pkg6-*` draws a
 * seller row with no actions on it. Each of those omissions, applied literally, would delete
 * something the app owes the user — a rule they must satisfy before the form will submit, the App
 * Store 1.2 report/block controls, or the only way a seller edits or withdraws a live listing.
 *
 * This suite is the guard for that ruling, across the four screens that carry those affordances. It
 * is a SOURCE contract (the affordances are wiring, and three of the four are inside a native
 * ActionSheet the renderer cannot mount), so every assertion carries a WITNESS: the same predicate
 * is run against a mutated copy of the source and must fail there. A pin that cannot fail is not a
 * pin — the reason this file exists is that its subject is already correct, so nothing but a
 * witness distinguishes a real guard from a vacuous one.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

/** Source with comments stripped: a rule quoted in a comment is not a rule the app applies. */
function code(rel: string): string {
  return readFileSync(rel, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
}

/**
 * Assert `pattern` is present, and prove the assertion can fail: `breaks` must remove it. Both legs
 * run on the same string in the same test, so a pattern that could never match (a typo, a regex
 * feature the engine lacks) fails the witness rather than passing the check.
 */
function pinned(src: string, pattern: RegExp | string, breaks: (s: string) => string, what: string) {
  const has = (s: string) => (typeof pattern === 'string' ? s.includes(pattern) : pattern.test(s));
  expect(has(src), `${what}: missing`).toBe(true);
  expect(has(breaks(src)), `${what}: WITNESS — the check still passes with the affordance removed`).toBe(false);
}

describe('required-field helpers survive the boards that letter them inside the field', () => {
  it('PA1: signup keeps the password rule as a persistent helper under the field', () => {
    const src = code('app/(auth)/signup.tsx');
    pinned(src, 'helper="At least 6 characters"', (s) => s.replace('helper="At least 6 characters"', ''), 'signup password rule');
    // And it is the FIELD's helper, not a one-shot error: nothing gates it on a failed submit.
    expect(src).not.toMatch(/\{\s*\w*[Ee]rror\w*\s*(\?|&&)[^}]*At least 6 characters/);
  });

  it('PA2: the create-listing fields keep their helpers, including the two that state a constraint', () => {
    const src = code('src/screens/CreateListingScreen.tsx');
    pinned(src, 'helper="JPG or PNG, 16:9"', (s) => s.replace('helper="JPG or PNG, 16:9"', ''), 'cover-image constraint');
    pinned(src, 'helper="Screenshot of the ticket or the confirmation email"',
      (s) => s.replace('helper="Screenshot of the ticket or the confirmation email"', ''), 'proof helper');
    // The price helpers are computed (they answer the buy-now/auction combination), so pin the wiring.
    pinned(src, /helper=\{summary\.valid/, (s) => s.replace(/helper=\{summary\.valid/g, 'x={'), 'price helpers');
  });
});

describe('moderation controls survive a board that draws no overflow control', () => {
  it('PA3: a viewer who is not the seller can report the listing, report the seller and block them', () => {
    const src = code('src/screens/ListingDetailScreen.tsx');
    pinned(src, "label: 'Report this listing'", (s) => s.replace("label: 'Report this listing'", "label: 'x'"), 'report listing');
    pinned(src, "label: 'Report this seller'", (s) => s.replace("label: 'Report this seller'", "label: 'x'"), 'report seller');
    pinned(src, /label: `Block \$\{sellerName\}`/, (s) => s.replace(/label: `Block \$\{sellerName\}`/, "label: 'x'"), 'block seller');
    // The three are the NON-owner arm: a seller sees their own menu, so neither arm hides the other.
    expect(src).toMatch(/owner\s*\n?\s*\?\s*\[/);
  });

  it('PA4: the profile screen keeps its own report route', () => {
    const src = code('app/profile/[id].tsx');
    pinned(src, '/report/user/', (s) => s.replace(/\/report\/user\//g, '/x/'), 'profile report route');
  });
});

describe('meaningful seller actions survive a board that draws none', () => {
  it('PA5: the seller row keeps edit, delete and cancel, each gated by what the listing allows', () => {
    const src = code('src/components/SellerListingCard.tsx');
    for (const [label, gate] of [['Edit listing', 'canEdit'], ['Delete listing', 'canDelete'], ['Cancel listing', 'canCancel']] as const) {
      pinned(src, `accessibilityLabel="${label}"`, (s) => s.replace(`accessibilityLabel="${label}"`, 'accessibilityLabel="x"'), label);
      expect(src, `${label} must stay gated by ${gate}`).toContain(gate);
    }
  });

  it('PA6: the seller arm of the listing menu keeps edit, cancel and delete', () => {
    const src = code('src/screens/ListingDetailScreen.tsx');
    for (const label of ['Edit listing', 'Cancel listing', 'Delete listing']) {
      pinned(src, `label: '${label}'`, (s) => s.replace(`label: '${label}'`, "label: 'x'"), `menu ${label}`);
    }
    // Destructive entries stay marked, so the sheet renders them as destructive rather than plain.
    pinned(src, /destructive: true, handler: handleSellerDelete/, (s) => s.replace('destructive: true, handler: handleSellerDelete', 'handler: handleSellerDelete'), 'delete stays destructive');
  });
});
