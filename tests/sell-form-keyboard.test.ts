/**
 * tests/sell-form-keyboard.test.ts — F-SELL-1 (owner, build 17, 2026-09-15):
 * while typing in the seller form the sticky "List ticket" bar floated about
 * 160–200 pt above the keyboard, and the heading crowded the sandbox badge.
 * Root cause (read from the pin): the bar kept the floating-dock lift and the
 * home-indicator inset while the keyboard was up (the dock hides itself while
 * typing), and the badge is an absolute overlay whose height no header adds.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { ctaLift, SANDBOX_BADGE_EXTRA, stickyBottomPadding, topInset } from '@/src/lib/nav/keyboardLift';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

describe('bottom clearance while the keyboard is up', () => {
  it('a sticky bar keeps only its own padding above the keyboard; the home-indicator inset is under it', () => {
    expect(stickyBottomPadding({ keyboardUp: true, insetBottom: 34, base: 12 })).toBe(12);
    expect(stickyBottomPadding({ keyboardUp: false, insetBottom: 34, base: 12 })).toBe(46);
    expect(stickyBottomPadding({ keyboardUp: false, insetBottom: 0, base: 12 })).toBe(12);
  });

  it('the dock lift disappears while the keyboard is up (the dock hides itself) and returns when it closes', () => {
    expect(ctaLift({ keyboardUp: true, dockOffset: 162 })).toBe(0);
    expect(ctaLift({ keyboardUp: false, dockOffset: 162 })).toBe(162);
  });
});

describe('top inset under the sandbox badge', () => {
  it('adds the badge\'s extra height only on sandbox builds', () => {
    expect(SANDBOX_BADGE_EXTRA).toBeGreaterThan(0);
    expect(topInset({ insetTop: 59, sandbox: true })).toBe(59 + SANDBOX_BADGE_EXTRA);
    expect(topInset({ insetTop: 59, sandbox: false })).toBe(59);
  });
});

describe('the screens use the helpers (source contract)', () => {
  it('StickyBar is keyboard-aware', () => {
    const s = stripComments(read('src/components/ui/StickyBar.tsx'));
    expect(s).toContain('useKeyboardUp()');
    expect(s).toContain('stickyBottomPadding({ keyboardUp, insetBottom: insets.bottom, base: v2.space.md })');
    expect(s).not.toContain('paddingBottom: v2.space.md + insets.bottom');
  });

  it('the seller form lifts its bar only while the dock is visible, and pads its heading under the badge', () => {
    const s = stripComments(read('src/screens/CreateListingScreen.tsx'));
    expect(s).toContain('ctaLift({ keyboardUp, dockOffset: ctaDockOffset })');
    expect(s).not.toContain('marginBottom: ctaDockOffset');
    expect(s).toContain('paddingTop: topPad + v2.space.sm');
    expect(s).toContain('const topPad = useTopInset();');
  });

  it('the edit screen pads its heading the same way', () => {
    const s = stripComments(read('app/listing/edit/[id].tsx'));
    expect(s).toContain('const topPad = useTopInset();');
    expect(s).not.toMatch(/paddingTop: insets\.top/);
  });

  it('the sandbox badge sizes itself from the real top inset, not a hardcoded status-bar height', () => {
    const s = stripComments(read('app/_layout.tsx'));
    expect(s).not.toMatch(/paddingTop: 52/);
    expect(s).toContain('SANDBOX_BADGE_EXTRA');
  });
});
