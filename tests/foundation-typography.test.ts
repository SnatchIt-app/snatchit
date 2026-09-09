/**
 * tests/foundation-typography.test.ts — the React Native type resolver.
 *
 * ONE DEFECT THIS GUARDS: a line box near `fontSize` clips the tops of glyphs on
 * both native platforms — Android via includeFontPadding, iOS by anchoring the
 * font descent to the bottom of the box. Oswald is a tall condensed face and the
 * brand's display leading is deliberately sub-1.0 (the live site computes 0.82),
 * so every display token is below the metric-derived floor as designed.
 *
 * The token keeps the designed value, because the web renders it correctly and
 * `packages/design-tokens/src/brand.ts` mirrors it for the web. `textStyle()` is
 * what React Native consumes, and it raises the line box. These assertions are on
 * the resolver, not on the token, which is the whole point of the split.
 */

import { describe, expect, it, vi, beforeEach } from 'vitest';

async function load() {
  vi.resetModules();
  vi.doMock('react-native', () => ({ Platform: { OS: 'ios' } }));
  vi.doMock('expo-font', () => ({ useFonts: () => [true, null] }));
  for (const [pkg, weight, name] of [
    ['@expo-google-fonts/oswald', '700Bold', 'Oswald_700Bold'],
    ['@expo-google-fonts/inter', '400Regular', 'Inter_400Regular'],
    ['@expo-google-fonts/inter', '500Medium', 'Inter_500Medium'],
    ['@expo-google-fonts/inter', '600SemiBold', 'Inter_600SemiBold'],
    ['@expo-google-fonts/inter', '700Bold', 'Inter_700Bold'],
  ] as const) {
    vi.doMock(`${pkg}/${weight}`, () => ({ [name]: `${name}-asset` }));
  }
  const typography = await import('../src/theme/typography');
  const v2 = await import('../src/theme/v2');
  const fonts = await import('../src/theme/fonts');
  return { typography, v2, fonts };
}

beforeEach(() => { vi.resetModules(); });

describe('type resolver — line box', () => {
  it('never returns a line height below the font size, for any token', async () => {
    const { typography, v2 } = await load();
    for (const token of Object.keys(v2.type) as (keyof typeof v2.type)[]) {
      const style = typography.textStyle(token);
      const size = style.fontSize as number;
      const lh = style.lineHeight as number;
      expect(lh, `${token} would clip on Android`).toBeGreaterThanOrEqual(size);
    }
  });

  it('actually raises the display tokens that are designed below the floor', async () => {
    const { typography, v2 } = await load();
    // If this stops finding any, the token file changed and the resolver may no
    // longer be earning its place — check before deleting it.
    const raised = (Object.keys(v2.type) as (keyof typeof v2.type)[]).filter(
      (k) => v2.type[k].lineHeight < v2.type[k].size,
    );
    expect(raised.length).toBeGreaterThan(0);
    for (const token of raised) {
      expect(typography.textStyle(token).lineHeight).toBeGreaterThan(v2.type[token].lineHeight);
    }
  });

  it('leaves the body scale exactly as designed', async () => {
    const { typography, v2 } = await load();
    // Body tokens already have generous leading. The resolver must not touch
    // them, or reading text silently loosens.
    for (const token of ['title', 'body', 'bodySm', 'label', 'micro'] as const) {
      expect(typography.textStyle(token).lineHeight).toBe(v2.type[token].lineHeight);
    }
  });

  it('holds the metric-derived Oswald cap floor, and no looser', async () => {
    const { typography } = await load();
    // The floor is ceil(size * 1.25): the smallest box that clears Oswald's cap
    // (810/1000) above an iOS-anchored descent (up to usWinDescent 377/1000) at
    // every display size, and still far tighter than Oswald's natural 1.48 leading
    // so the compressed poster character survives. It is a floor, not a redesign.
    expect(typography.safeLineHeight(44, 40)).toBe(55);
    expect(typography.safeLineHeight(34, 32)).toBe(43);
    expect(typography.safeLineHeight(26, 26)).toBe(33);
    // Already clear of the floor (generous body leading): untouched.
    expect(typography.safeLineHeight(15, 22)).toBe(22);
  });
});

describe('type resolver — the rest of the token travels', () => {
  it('carries uppercase, tracking and the price figures to the Text', async () => {
    const { typography } = await load();
    const display = typography.textStyle('displayLg');
    expect(display.textTransform).toBe('uppercase');
    expect(display.letterSpacing).toBeLessThan(0);

    const body = typography.textStyle('body');
    expect(body.textTransform).toBeUndefined();

    // Tabular figures must reach the Text or live bid prices jitter. Declaring
    // the variant on the token is not enough on its own.
    expect(typography.textStyle('price').fontVariant).toContain('tabular-nums');
  });

  it('resolves families through the loader, so an unregistered face falls back', async () => {
    const { typography, fonts, v2 } = await load();

    fonts.__setFacesLoadedForTest(true);
    expect(typography.textStyle('displayLg').fontFamily).toBe(v2.font.display);
    expect(typography.textStyle('body').fontFamily).toBe(v2.font.body);
    expect(typography.textStyle('label').fontFamily).toBe(v2.font.bodyBold);

    // Before the faces register, React Native must be handed `undefined` so it
    // uses the system face rather than an unregistered family name.
    fonts.__setFacesLoadedForTest(false);
    expect(typography.textStyle('displayLg').fontFamily).toBeUndefined();
  });

  it('collapses motion durations under the OS reduced-motion setting', async () => {
    const { typography, v2 } = await load();
    expect(typography.duration('swift', false)).toBe(v2.motion.swift);
    expect(typography.duration('swift', true)).toBe(1);
  });

  it('publishes the easing in the form React Native accepts', async () => {
    const { typography } = await load();
    // A CSS cubic-bezier string is useless to Animated; the control points are not.
    expect(typography.EASING_BEZIER).toHaveLength(4);
    for (const n of typography.EASING_BEZIER) expect(typeof n).toBe('number');
  });
});
