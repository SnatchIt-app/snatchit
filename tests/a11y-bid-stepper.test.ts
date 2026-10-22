/**
 * The bid amount is one adjustable control for VoiceOver (C a11y audit 2026-10-21, finding 4).
 *
 * The stepper was two separate buttons around a static amount: after "Raise bid" nothing said the new
 * figure, and a swipe up/down did nothing. The amount is now `adjustable` with increment/decrement
 * actions that call the same increase/decrease the buttons do, under the same freezes: nothing moves
 * while a bid is in flight, and decrement stops at the floor. The buttons stay. No visual change.
 * Source contract with a witness. Not a device result.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

const src = readFileSync('src/screens/PlaceBidScreen.tsx', 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const amount = (s: string) => {
  const at = s.indexOf('style={s.bigAmount}');
  expect(at).toBeGreaterThan(-1);
  return s.slice(at, s.indexOf('</Text>', at));
};

describe('bid amount as an adjustable control', () => {
  it('BS1: the amount is adjustable, labelled, and carries its value', () => {
    const a = amount(src);
    expect(a).toContain('accessibilityRole="adjustable"');
    expect(a).toContain('accessibilityLabel="Your bid"');
    expect(a).toContain('accessibilityValue={{ text: fmt$(selectedBid) }}');
    // Witness: without the role the same check fails.
    expect(amount(src.replace('accessibilityRole="adjustable"', '')).includes('accessibilityRole="adjustable"')).toBe(false);
  });

  it('BS2: increment/decrement call the buttons\' own handlers, under the same freezes', () => {
    const a = amount(src);
    expect(a).toMatch(/accessibilityActions=\{\[\{ name: 'increment' \}, \{ name: 'decrement' \}\]\}/);
    expect(a).toMatch(/if \(submitting\) return;/);
    expect(a).toMatch(/actionName === 'increment'\) increase\(\)/);
    expect(a).toMatch(/actionName === 'decrement' && !atFloor\) decrease\(\)/);
  });

  it('BS3: the visible buttons are unchanged (regression guard)', () => {
    expect(src).toContain('accessibilityLabel="Lower bid"');
    expect(src).toContain('accessibilityLabel="Raise bid"');
    expect(src).toContain('disabled={atFloor || submitting}');
  });
});

describe('sell quantity as an adjustable control (same finding, the Sell form)', () => {
  const sell = readFileSync('src/screens/CreateListingScreen.tsx', 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
  const value = (s: string) => {
    const at = s.indexOf('style={[textStyle(\'price\'), sx.stepVal]}');
    expect(at).toBeGreaterThan(-1);
    return s.slice(at, s.indexOf('</Text>', at));
  };

  it('QS1: the quantity is adjustable, labelled, carries its value, and steps through the same rules', () => {
    const v = value(sell);
    expect(v).toContain('accessibilityRole="adjustable"');
    expect(v).toContain('accessibilityLabel="Quantity"');
    expect(v).toContain('accessibilityValue={{ text: String(quantity) }}');
    expect(v).toMatch(/actionName === 'increment'\) setQuantity\(\(q\) => q \+ 1\)/);
    expect(v).toMatch(/actionName === 'decrement'\) setQuantity\(\(q\) => Math\.max\(1, q - 1\)\)/);
    expect(value(sell.replace('accessibilityRole="adjustable"', '')).includes('accessibilityRole="adjustable"')).toBe(false);
  });
});
