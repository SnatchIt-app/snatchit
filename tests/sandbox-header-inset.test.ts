/**
 * F-SELL-2 — every screen header, header control and top toast clears the SANDBOX badge.
 *
 * Device observation (owner, Build 18 = aad5f75, largest accessibility text, DV-S2 step 1):
 * the SANDBOX badge did not clear the "My Listings" header. Source: `app/my-listings.tsx`
 * paid `insets.top` straight from the safe area, while F-SELL-1 had moved the tabs, Home
 * header, Sell form and Edit listing to `useTopInset()` (status bar + the badge's fixed
 * 20 pt on sandbox builds). Ten more surfaces followed the same pattern, plus the outbid
 * toast. The badge overlays every stack screen (all card pushes, `headerShown: false`,
 * no modals) and is `pointerEvents="none"`, so the defect is visual and sandbox-only.
 *
 * What these tests hold:
 *  - production spacing is unchanged: without the badge the helper returns the status-bar
 *    inset exactly, and every site keeps its own spacing token;
 *  - the offset holds at every text size: the badge never scales, so its height stays
 *    SANDBOX_BADGE_EXTRA at the normal and the largest accessibility size, and nothing in
 *    the helper reads a font scale;
 *  - no doubled spacing: screens that host a shared header (settings, auth, listing hero,
 *    outbid toast) pay no top inset of their own, and no surface pays both;
 *  - no screen reads the raw top inset any more (the badge itself and the helper excepted).
 * Rendering on a device is the next candidate's device rows; this is source and pure logic.
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { SANDBOX_BADGE_EXTRA, topInset } from '@/src/lib/nav/keyboardLift';

const ROOT = resolve(__dirname, '..');
const read = (p: string) => readFileSync(join(ROOT, p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '').replace(/\{\/\*[\s\S]*?\*\/\}/g, '');

function walk(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(join(ROOT, dir))) {
    const rel = join(dir, name);
    const st = statSync(join(ROOT, rel));
    if (st.isDirectory()) { if (name !== 'node_modules') walk(rel, out); }
    else if (/\.(tsx|ts)$/.test(name)) out.push(rel);
  }
  return out;
}

describe('the helper: production unchanged, sandbox adds the badge, no text-size input', () => {
  it('production returns the status-bar inset exactly; sandbox adds SANDBOX_BADGE_EXTRA', () => {
    for (const insetTop of [0, 20, 47, 59]) {
      expect(topInset({ insetTop, sandbox: false })).toBe(insetTop);
      expect(topInset({ insetTop, sandbox: true })).toBe(insetTop + SANDBOX_BADGE_EXTRA);
    }
    expect(SANDBOX_BADGE_EXTRA).toBe(20);
  });

  it('the offset does not depend on the text size: the helper reads no font scale', () => {
    const helper = stripComments(read('src/lib/nav/navInsets.ts'));
    const lift = stripComments(read('src/lib/nav/keyboardLift.ts'));
    for (const src of [helper, lift]) {
      expect(src).not.toMatch(/fontScale|getFontScale|PixelRatio/);
    }
  });

  it('normal and largest text: the badge never scales, so its height is SANDBOX_BADGE_EXTRA at every size', () => {
    const layout = stripComments(read('app/_layout.tsx'));
    expect(layout).toContain("<Text style={styles.sandboxBadgeText} allowFontScaling={false}>");
    expect(layout).toContain('lineHeight: SANDBOX_BADGE_EXTRA - 6');
    expect(layout).toMatch(/sandboxBadge: \{[\s\S]*?paddingBottom: 6,/);
    expect(layout).toContain("<View style={[styles.sandboxBadge, { paddingTop: insets.top }]} pointerEvents=\"none\">");
    // every route is a card push with no native header, so the badge overlays all of them
    expect(layout).toContain('<Stack screenOptions={{ headerShown: false,');
    expect(layout).not.toMatch(/presentation:\s*'(modal|formSheet|transparentModal|fullScreenModal)'/);
  });
});

// Each site keeps the spacing token it had, so production spacing is identical.
const SITES: { file: string; expr: string }[] = [
  { file: 'app/my-listings.tsx', expr: 'paddingTop: topPad + v2.space.sm' },
  { file: 'app/settings/index.tsx', expr: 'paddingTop: topPad + v2.space.sm' },
  { file: 'app/transfer/send/[id].tsx', expr: 'paddingTop: topPad + v2.space.sm' },
  { file: 'app/transfer/receive/[id].tsx', expr: 'paddingTop: topPad + v2.space.sm' },
  { file: 'src/screens/PlaceBidScreen.tsx', expr: 'paddingTop: topPad + v2.space.sm' },
  { file: 'src/components/account/SettingsHeader.tsx', expr: 'paddingTop: topPad + v2.space.sm' },
  { file: 'src/components/auth/AuthScreen.tsx', expr: 'paddingTop: topPad + v2.space.xl' },
  { file: 'src/components/listing/ListingHero.tsx', expr: 'top: topPad + v2.space.sm' },
  { file: 'src/components/listing/OutbidToast.tsx', expr: 'paddingTop: v2.space.sm + topPad' },
];

describe('the eleven surfaces use the badge-aware inset with their original spacing', () => {
  for (const { file, expr } of SITES) {
    it(file, () => {
      const src = stripComments(read(file));
      expect(src).toContain('const topPad = useTopInset();');
      expect(src).toContain(expr);
      expect(src).not.toMatch(/insets\.top/);
    });
  }
  it('src/screens/checkout/CheckoutNative.tsx (top bar and both confirmation bodies)', () => {
    const src = stripComments(read('src/screens/checkout/CheckoutNative.tsx'));
    expect(src.split('const topPad = useTopInset();').length - 1).toBe(3);
    expect(src).toContain('paddingTop: topPad + v2.space.sm');
    expect(src.split('paddingTop: topPad + v2.space.xxl').length - 1).toBe(2);
    expect(src).not.toMatch(/insets\.top/);
    // the bottom bars still pay the bottom inset
    expect(src.split('insets.bottom').length - 1).toBe(3);
  });
});

describe('no doubled spacing', () => {
  const HOSTS: { component: string; tag: RegExp }[] = [
    { component: 'SettingsHeader', tag: /<SettingsHeader\b/ },
    { component: 'AuthScreen', tag: /<AuthScreen\b/ },
    { component: 'ListingHero', tag: /<ListingHero\b/ },
    { component: 'OutbidToast', tag: /<OutbidToast\b/ },
  ];
  const files = [...walk('app'), ...walk('src')];

  for (const { component, tag } of HOSTS) {
    it(`screens that render ${component} pay no top inset of their own`, () => {
      const hosts = files.filter((f) => !f.endsWith(`${component}.tsx`) && tag.test(read(f)));
      expect(hosts.length).toBeGreaterThan(0);
      for (const f of hosts) {
        const src = stripComments(read(f));
        expect({ f, topInset: /useTopInset\(\)|insets\.top/.test(src) }).toEqual({ f, topInset: false });
      }
    });
  }

  it('no file both reads the raw top inset and the badge-aware one (the helper that defines it excepted)', () => {
    for (const f of files.filter((x) => x !== join('src', 'lib', 'nav', 'navInsets.ts'))) {
      const src = stripComments(read(f));
      expect({ f, both: /insets\.top/.test(src) && /useTopInset\(\)/.test(src) }).toEqual({ f, both: false });
    }
  });
});

describe('sweep: nothing reads the raw top inset except the badge and the helper', () => {
  it('app/ and src/', () => {
    const allowed = new Set(['app/_layout.tsx', 'src/lib/nav/navInsets.ts']);
    const offenders = [...walk('app'), ...walk('src')]
      .filter((f) => !allowed.has(relative(ROOT, join(ROOT, f))))
      .filter((f) => /insets\.top|useSafeAreaInsets\(\)\.top/.test(stripComments(read(f))));
    expect(offenders).toEqual([]);
  });
});
