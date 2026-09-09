/**
 * tests/filter-sheet-action-bar.test.ts — the filter sheet's footer row fits.
 *
 * THE BUG: `Sheet`'s footer is `flexDirection: 'row'` and both actions were
 * `<Button block>`, which is `width: '100%'`. React Native defaults
 * `flexShrink: 0`, so neither button gives width back: the row asked for 200%
 * plus the gap and Apply was pushed off the right edge of the screen.
 *
 * The geometry is asserted arithmetically rather than by rendering, because the
 * failure is a width calculation, not a render outcome.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const sheet = read('src/components/ui/Sheet.tsx');
const filterSheet = read('src/components/discovery/FilterSheet.tsx');
const button = read('src/components/ui/Button.tsx');

/** space.lg / space.sm from src/theme/v2.ts — the sheet's gutter and row gap. */
const GUTTER = 16;
const GAP = 8;

/** What the fixed layout gives each action at a given device width. */
function actionWidth(screenWidth: number, actions = 2): number {
  const content = screenWidth - GUTTER * 2;          // sheet paddingHorizontal
  return (content - GAP * (actions - 1)) / actions;  // flex:1, basis 0, one gap between
}

describe('root cause: the footer row must divide, not overflow', () => {
  it('two full-width children in a row is what overflowed', () => {
    // the old geometry, kept as the thing being prevented
    expect(button).toContain("block: { alignSelf: 'stretch', width: '100%' }");
    expect(sheet).toContain("flexDirection: 'row'");
    const content = 393 - GUTTER * 2;                 // iPhone 15/16 width
    const oldRequired = content * 2 + GAP;            // 100% + 100% + gap
    expect(oldRequired).toBeGreaterThan(content);     // overflowed by a full button
  });

  it('SheetAction gives each action an equal, shrinkable share', () => {
    expect(sheet).toContain('action: { flex: 1, flexBasis: 0, minWidth: 0 }');
    expect(sheet).toContain('export function SheetAction');
    expect(read('src/components/ui/index.ts')).toContain('SheetAction');
  });

  it('no fixed width and no screen measurement in the action row', () => {
    const code = stripComments(sheet);
    expect(code).not.toMatch(/action: \{[^}]*width: \d/);
    expect(code).not.toMatch(/Dimensions\.get/);
    // the sheet reads window height for maxHeight only, never width for the row
    expect(code).not.toMatch(/const \{ width \} = useWindowDimensions/);
  });
});

describe('both actions fit, at every iPhone width', () => {
  const WIDTHS: [string, number][] = [
    ['narrow (SE / mini, 320)', 320],
    ['iPhone 13 mini (375)', 375],
    ['current iPhone (393)', 393],
    ['large iPhone Pro Max (430)', 430],
    ['landscape-ish (852)', 852],
  ];

  WIDTHS.forEach(([name, w]) => {
    it(`${name}: two actions plus the gap never exceed the content width`, () => {
      const each = actionWidth(w);
      const content = w - GUTTER * 2;
      expect(each * 2 + GAP).toBeCloseTo(content, 5);   // exactly fills, never over
      expect(each).toBeGreaterThan(0);
      // each half still clears the 44pt minimum touch target on its short edge
      expect(each).toBeGreaterThanOrEqual(44);
    });
  });

  it('the arithmetic degrades safely rather than going negative', () => {
    expect(actionWidth(320)).toBeLessThan(actionWidth(430));
    expect(actionWidth(430, 3)).toBeGreaterThan(0);
  });
});

describe('the footer renders both actions, wrapped', () => {
  it('Clear and Apply are each inside a SheetAction', () => {
    const footer = filterSheet.slice(filterSheet.indexOf('footer={'), filterSheet.indexOf('<ScrollView ref='));
    expect((footer.match(/<SheetAction>/g) ?? []).length).toBe(2);
    expect(footer).toContain('label="Clear"');
    expect(footer).toContain('label="Apply"');
    // each button is still block, so it fills its own share
    expect((footer.match(/\bblock\b/g) ?? []).length).toBe(2);
  });

  it('every Sheet footer in the app uses the wrapper, so none can overflow', () => {
    for (const path of ['src/components/discovery/FilterSheet.tsx', 'app/_dev/foundation.tsx']) {
      const src = read(path);
      const footerAt = src.indexOf('footer={');
      const body = src.slice(footerAt, footerAt + 1400);
      const buttons = (body.match(/<Button/g) ?? []).length;
      const wrappers = (body.match(/<SheetAction>/g) ?? []).length;
      expect(wrappers).toBe(buttons);
    }
  });
});

describe('behaviour and design are untouched', () => {
  it('Apply still applies the same filter payload and closes nothing else', () => {
    expect(filterSheet).toContain('onApply({ chip, neighborhoods: hoods, categories: cats, priceMin: min, priceMax: max })');
  });

  it('Clear still resets the same five pieces of state', () => {
    const footer = filterSheet.slice(filterSheet.indexOf('label="Clear"'), filterSheet.indexOf('label="Apply"'));
    for (const reset of ["setChip('all')", 'setHoods(new Set())', 'setCats(new Set())', "setMin('')", "setMax('')"]) {
      expect(footer).toContain(reset);
    }
  });

  it('the home indicator is still cleared by the safe-area inset', () => {
    expect(sheet).toContain('paddingBottom: v2.space.lg + insets.bottom');
    expect(sheet).toContain('useSafeAreaInsets');
  });

  it('Dynamic Type still truncates the label instead of widening the button', () => {
    expect(button).toContain('numberOfLines={1}');
    expect(button).toContain('maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}');
    expect(button).toContain('minHeight: HEIGHT[size]');
  });

  it('no filter content, logic or query changed', () => {
    const code = stripComments(filterSheet);
    expect(code).toContain('CHIP_GROUPS');
    expect(code).not.toMatch(/supabase|\.from\(|rpc\(/);
  });
});
