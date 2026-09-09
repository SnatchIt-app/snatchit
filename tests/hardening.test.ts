/**
 * tests/hardening.test.ts — Phase 12 hardening regression guards.
 *
 * Source-level guards that pin the objective fixes made in the accessibility /
 * Dynamic Type / responsive / keyboard pass, so a later edit cannot silently
 * reintroduce a fixed-height clip, a hardcoded dock clearance, a missing keyboard
 * wrap, or an unlabeled control. Behavioural, not snapshot.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');

describe('Dynamic Type — chrome grows, never clips', () => {
  it('the font-scale cap is consumed (no longer dead code)', () => {
    const button = read('src/components/ui/Button.tsx');
    const badge = read('src/components/ui/Badge.tsx');
    const chip = read('src/components/ui/Chip.tsx');
    for (const src of [button, badge, chip]) {
      expect(src).toContain('MAX_DISPLAY_FONT_SCALE');
      expect(src).toContain('maxFontSizeMultiplier');
    }
  });

  it('shared primitives use minHeight (not a fixed height that clips enlarged text)', () => {
    expect(read('src/components/ui/Button.tsx')).toContain('minHeight: HEIGHT[size]');
    expect(read('src/components/ui/Badge.tsx')).toContain('minHeight: 20');
    expect(read('src/components/ui/Chip.tsx')).toContain('minHeight: 32');
    expect(read('src/components/ui/Input.tsx')).toContain('minHeight: 50');
    // and no fixed-height regression on these primitives
    expect(read('src/components/ui/Button.tsx')).not.toMatch(/height: HEIGHT\[size\]/);
  });

  it('no screen disables font scaling as a shortcut', () => {
    for (const rel of ['src/components/ui/Button.tsx', 'app/(tabs)/tickets.tsx', 'src/screens/PlaceBidScreen.tsx']) {
      expect(read(rel)).not.toContain('allowFontScaling={false}');
    }
  });
});

describe('Responsive — dock clearance is derived, not hardcoded', () => {
  it('explore results clear the floating dock via useDockClearance', () => {
    const explore = read('app/(tabs)/explore.tsx');
    expect(explore).toContain('useDockClearance');
    expect(explore).toContain('paddingBottom: dockClearance');
    expect(explore).not.toMatch(/paddingBottom:\s*96/);
  });
});

describe('Keyboard — forms keep their submit reachable', () => {
  it('verify-phone, transfer/receive, and the shared Sheet avoid the keyboard', () => {
    expect(read('app/settings/verify-phone.tsx')).toContain('KeyboardAvoidingView');
    expect(read('app/transfer/receive/[id].tsx')).toContain('KeyboardAvoidingView');
    expect(read('src/components/ui/Sheet.tsx')).toContain('KeyboardAvoidingView');
  });
});

describe('Accessibility — icon-only / toggle controls are labeled', () => {
  it('the shared retry control names itself and exposes busy', () => {
    const ss = read('src/components/ScreenState.tsx');
    expect(ss).toContain('accessibilityLabel="Retry"');
    expect(ss).toMatch(/accessibilityState=\{\{ busy: retrying/);
  });

  it('disclosure toggles expose expanded state', () => {
    expect(read('src/components/PlatformInstructions.tsx')).toMatch(/accessibilityState=\{\{ expanded: tipsExpanded/);
    expect(read('app/settings/legal.tsx')).toMatch(/accessibilityState=\{\{ expanded: fullTermsOpen/);
  });

  it('the delivery form labels its inputs and its submit', () => {
    const f = read('src/components/DeliveryInfoForm.tsx');
    expect(f).toContain('accessibilityLabel="Email for ticket transfer"');
    expect(f).toContain('accessibilityLabel="Phone number for ticket transfer"');
    expect(f).toContain('accessibilityLabel="Save delivery info"');
  });

  it('the seller listing card announces status and price, not just the title', () => {
    expect(read('src/components/SellerListingCard.tsx')).toContain('accessibilityLabel={a11yLabel}');
  });
});
