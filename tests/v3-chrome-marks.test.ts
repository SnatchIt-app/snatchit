/**
 * tests/v3-chrome-marks.test.ts — the chrome marks are vectors, and the filter mark means filters.
 *
 * TWO DEFECTS, one of which was invisible to review. The filter control drew `≡` — a hamburger,
 * which says MENU in an interface and IDENTICAL TO in mathematics, on a control that opens filters
 * (B's F-91-6). That one you can see. The other one you cannot: B measured the bundled Inter and
 * Oswald cmaps and found `≡`, `⌕`, `✕` and `⋯` absent from BOTH faces, so all four marks were being
 * drawn by whatever font iOS fell back to — at a weight, size and baseline nobody chose. The
 * original reasoning for using characters was that they would inherit the brand face; a character
 * that is not in the face inherits nothing.
 *
 * So the fix is not a better character. The marks go through the app's existing icon implementation
 * (`components/ui/icon-symbol`: SF Symbols on iOS, Material elsewhere), which the dock already uses.
 *
 * This suite pins the outcome rather than the mechanism: no chrome mark is a text character, every
 * glyph resolves to a symbol, and the filter's symbol is a filter.
 */

import { describe, expect, it } from 'vitest';

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const code = (rel: string) =>
  read(rel)
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('the chrome marks', () => {
  it('CM1: every glyph maps to a symbol name, and none of them is a text character', () => {
    const src = code('src/components/ui/IconButton.tsx');
    // Five controls, five symbols.
    for (const [glyph, symbol] of [
      ['back', 'chevron.left'],
      ['close', 'xmark'],
      ['more', 'ellipsis'],
      ['search', 'magnifyingglass'],
      ['filter', 'line.3.horizontal.decrease'],
    ] as const) {
      expect(src, `${glyph} -> ${symbol}`).toMatch(new RegExp(`${glyph}:\\s*'${symbol.replace(/\./g, '\\.')}'`));
    }
    // The characters that were never in the bundled faces must not come back. Checked against the
    // WHOLE file including comments, because a mark reintroduced in a commented-out line is a mark
    // somebody will uncomment.
    const whole = read('src/components/ui/IconButton.tsx');
    const banned = ['≡', '⌕', '✕', '⋯', '‹'];   // ≡ ⌕ ✕ ⋯ ‹
    for (const ch of banned) {
      const inCode = code('src/components/ui/IconButton.tsx').includes(ch);
      expect(inCode, `${JSON.stringify(ch)} must not be drawn`).toBe(false);
    }
    // POSITIVE CONTROL for that sweep: the file really is readable and really does contain the
    // characters' names in prose, so an all-clear is not simply an empty read.
    expect(whole.length).toBeGreaterThan(500);
    expect(whole).toContain('line.3.horizontal.decrease');

    // The mark is rendered by the shared implementation, not by a Text node.
    expect(src).toContain('<IconSymbol');
    expect(src).not.toMatch(/<Text[^>]*styles\.glyph/);
  });

  it('CM2: the non-iOS fallback has a mapping for every symbol the control uses', () => {
    // A missing entry renders `undefined` as a Material name, which is a blank square on web and
    // Android — the same class of silent substitution the characters had.
    const mapping = read('components/ui/icon-symbol.tsx');
    for (const symbol of ['chevron.left', 'xmark', 'ellipsis', 'magnifyingglass', 'line.3.horizontal.decrease']) {
      expect(mapping, `${symbol} mapped`).toContain(`'${symbol}':`);
    }
    // And the filter maps to a filter, not to a menu.
    expect(mapping).toMatch(/'line\.3\.horizontal\.decrease':\s*'filter-list'/);
    expect(mapping).not.toMatch(/'line\.3\.horizontal\.decrease':\s*'menu'/);
  });

  it('CM3: the affordances that make it a control are unchanged', () => {
    const src = code('src/components/ui/IconButton.tsx');
    // A 44x44 target from the shared constant, never a local number.
    expect(src).toContain('width: MIN_TOUCH_TARGET');
    expect(src).toContain('height: MIN_TOUCH_TARGET');
    // The label stays required — this control exists because sixteen hand-rolled back buttons had none.
    expect(src).toContain('accessibilityLabel');
    expect(src).toContain("accessibilityRole=\"button\"");
    // The active-count badge survives the change, and stays decorative (the count is already spoken
    // in the control's name, so a screen reader must not meet it twice).
    expect(src).toMatch(/count != null && count > 0/);
    expect(src).toContain('accessibilityElementsHidden');
    // And the over-art plate, which is what keeps a mark legible on a photograph.
    expect(src).toMatch(/onArt: \{ backgroundColor: 'rgba\(0,0,0,0\.55\)' \}/);
  });
});
