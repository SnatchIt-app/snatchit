/**
 * tests/auth-brand-mark.test.ts — the SN mark on the auth screens is centred.
 *
 * It previously sat at the left edge because each screen inlined the Image as a
 * bare child of a column. It now uses one shared component whose mark is the sole
 * child of a full-width, centre-aligned row — the same construction the approved
 * Home header uses, so it is centred to the SCREEN, not to leftover space.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');

const AUTH_SCREENS = ['login', 'signup', 'reset-password'] as const;

describe('auth brand mark', () => {
  const mark = read('src/components/auth/AuthBrandMark.tsx');

  it('is centred by a full-width centred row (true screen centring)', () => {
    expect(mark).toContain("row: { alignItems: 'center'");
    // the mark is the row's only child, so no sibling can push it off centre
    expect((mark.match(/<Image/g) ?? []).length).toBe(1);
    // never centred by a guessed offset or a leftover-space layout
    expect(mark).not.toMatch(/justifyContent: 'space-between'|marginLeft:|left:/);
  });

  it('uses the same construction as the approved Home header', () => {
    expect(read('src/components/discovery/HomeHeader.tsx')).toContain("markRow: { alignItems: 'center' }");
  });

  it('keeps the official asset and its size/ratio', () => {
    expect(mark).toContain("require('@/brand/sn-logo-white.png')");
    expect(mark).toContain('SN_MARK_HEIGHT = 30');   // unchanged size
    expect(mark).toContain('1024 / 371');            // intrinsic ratio pinned
  });

  it('adds no plate, wordmark, glow or red treatment', () => {
    expect(mark).not.toMatch(/backgroundColor|borderWidth|shadow|tintColor|brand\.red|Snatch It<\/Text>/);
  });

  AUTH_SCREENS.forEach((screen) => {
    it(`${screen} uses the shared shell and has no inline left-aligned copy`, () => {
      const src = read(`app/(auth)/${screen}.tsx`);
      expect(src).toContain('<AuthScreen>');
      // the old inline, left-aligned implementation is gone
      expect(src).not.toContain('sn-logo-white.png');
      expect(src).not.toMatch(/mark: \{ height: 30/);
    });
  });
});

describe('auth shell — the mark is pinned, only the form reacts to the keyboard', () => {
  const shell = read('src/components/auth/AuthScreen.tsx');

  it('renders the mark OUTSIDE the keyboard-responsive region', () => {
    const headerAt = shell.indexOf('<AuthBrandMark />');
    const kavAt = shell.indexOf('<KeyboardAvoidingView');
    expect(headerAt).toBeGreaterThan(-1);
    expect(kavAt).toBeGreaterThan(-1);
    // the mark is emitted before the KAV opens, so it is not inside it
    expect(headerAt).toBeLessThan(kavAt);
  });

  it('pins the header with safe-area-aware spacing, not a hardcoded Y', () => {
    expect(shell).toContain('insets.top + v2.space.xl');
    expect(shell).toContain('useSafeAreaInsets');
    // no absolute positioning or per-device magic numbers
    expect(shell).not.toMatch(/position: 'absolute'|top: \d{2,}/);
  });

  it('does not vertically centre the mark: only the form body is centred', () => {
    // the centring that used to drag the mark upward now lives on the form body
    expect(shell).toMatch(/body: \{[\s\S]*?justifyContent: 'center'/);
    expect(shell).not.toMatch(/header: \{[^}]*justifyContent: 'center'/);
  });

  it('keeps the form keyboard-accessible', () => {
    expect(shell).toContain('KeyboardAvoidingView');
    expect(shell).toContain("keyboardShouldPersistTaps=\"handled\"");
    expect(shell).toContain('flexGrow: 1'); // centres when there is room, scrolls when there is not
  });

  it('no auth screen keeps its own keyboard/centring container any more', () => {
    for (const screen of AUTH_SCREENS) {
      const src = read(`app/(auth)/${screen}.tsx`);
      expect(src).not.toContain('KeyboardAvoidingView');
      expect(src).not.toMatch(/inner: \{ flex: 1[^}]*justifyContent: 'center' \}/);
    }
  });
});
