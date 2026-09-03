/**
 * tests/brand-fonts.test.ts — the brand typeface loader.
 *
 * Three failures this guards, all of which are silent in a running app:
 *
 *  1. BUNDLE BLOAT. Each @expo-google-fonts package's root `index.js` eagerly
 *     `require()`s every weight it ships. Inter ships eighteen faces. Importing
 *     from the package root instead of the per-weight entry point puts ~9 MB of
 *     .ttf in the app bundle to use five of them, and nothing warns you.
 *  2. A SYNTHESISED WEIGHT. A weight added to the design tokens but never loaded
 *     makes the OS fake it, producing the smeared faux-bold that reads as an
 *     unpolished app.
 *  3. AN UNREGISTERED FAMILY. Returning a family name before the face has loaded
 *     makes iOS silently substitute the system face and can make Android render
 *     an empty box.
 *
 * The first is checked against the real files on disk rather than through the
 * bundler, because that is the only place the truth lives.
 */

import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { describe, expect, it, vi } from 'vitest';

const repoRoot = resolve(__dirname, '..');
const fontsSource = readFileSync(resolve(repoRoot, 'src/theme/fonts.ts'), 'utf8');

/** family -> [package, per-weight subpath, exported const] */
const FACES: ReadonlyArray<readonly [string, string, string]> = [
  ['@expo-google-fonts/oswald', '700Bold', 'Oswald_700Bold'],
  ['@expo-google-fonts/inter', '400Regular', 'Inter_400Regular'],
  ['@expo-google-fonts/inter', '500Medium', 'Inter_500Medium'],
  ['@expo-google-fonts/inter', '600SemiBold', 'Inter_600SemiBold'],
  ['@expo-google-fonts/inter', '700Bold', 'Inter_700Bold'],
];

describe('brand font packaging', () => {
  it('imports per-weight entry points, never the package root', () => {
    // A root import is the bundle-size regression. It is legal TypeScript and
    // renders identically, so only this assertion catches it.
    expect(fontsSource).not.toMatch(/from '@expo-google-fonts\/(oswald|inter)'/);
    for (const [pkg, weight, name] of FACES) {
      expect(fontsSource, `${name} must be imported from ${pkg}/${weight}`).toContain(
        `from '${pkg}/${weight}'`,
      );
    }
  });

  it('every face resolves to a real file that exports the expected const', () => {
    for (const [pkg, weight, name] of FACES) {
      const dir = resolve(repoRoot, 'node_modules', pkg, weight);
      const entry = resolve(dir, 'index.js');
      expect(existsSync(entry), `${pkg}/${weight}/index.js is missing`).toBe(true);
      const src = readFileSync(entry, 'utf8');
      // The generated entry exports exactly this one face.
      expect(src).toContain(`export const ${name} = require('./${name}.ttf')`);
      expect(existsSync(resolve(dir, `${name}.ttf`)), `${name}.ttf is missing`).toBe(true);
    }
  });

  it('keeps the bundled typeface payload proportionate', () => {
    // Five faces, ~1.4 MB. The guard is deliberately loose: it exists to catch a
    // root import silently dragging in the whole family, not to police kilobytes.
    const { statSync } = require('node:fs') as typeof import('node:fs');
    const total = FACES.reduce(
      (sum, [pkg, weight, name]) =>
        sum + statSync(resolve(repoRoot, 'node_modules', pkg, weight, `${name}.ttf`)).size,
      0,
    );
    expect(total).toBeLessThan(3 * 1024 * 1024);
  });
});

describe('brand font resolver', () => {
  it('returns no family until the faces have actually registered', async () => {
    vi.resetModules();
    vi.doMock('react-native', () => ({ Platform: { OS: 'ios' } }));
    vi.doMock('expo-font', () => ({ useFonts: () => [false, null] }));
    for (const [pkg, weight, name] of FACES) {
      vi.doMock(`${pkg}/${weight}`, () => ({ [name]: 1 }));
    }

    const mod = await import('../src/theme/fonts');
    const { font } = await import('../src/theme/v2');

    // Installed is a build-time fact; registered is a runtime one. Conflating
    // the two is what puts an empty box on an Android screen.
    expect(mod.FONTS_INSTALLED).toBe(true);

    mod.__setFacesLoadedForTest(false);
    expect(mod.fontFamily('display')).toBeUndefined();
    expect(mod.fontFamily('body')).toBeUndefined();
    expect(mod.brandFontsActive()).toBe(false);

    mod.__setFacesLoadedForTest(true);
    expect(mod.fontFamily('display')).toBe(font.display);
    expect(mod.fontFamily('bodyBold')).toBe(font.bodyBold);
    expect(mod.brandFontsActive()).toBe(true);

    vi.doUnmock('react-native');
    vi.doUnmock('expo-font');
  });

  it('loads exactly the faces the design tokens ask for, and no others', async () => {
    vi.resetModules();
    vi.doMock('react-native', () => ({ Platform: { OS: 'ios' } }));
    vi.doMock('expo-font', () => ({ useFonts: () => [true, null] }));
    for (const [pkg, weight, name] of FACES) {
      vi.doMock(`${pkg}/${weight}`, () => ({ [name]: `${name}-asset` }));
    }

    const { BRAND_FONT_FACES, REQUIRED_FONT_ASSETS, AVAILABLE_WEIGHTS } = await import(
      '../src/theme/fonts'
    );
    const { font } = await import('../src/theme/v2');

    // The manifest and the real load map must name the same families. This is
    // what fails if a weight is added to the tokens and never loaded.
    expect(Object.keys(BRAND_FONT_FACES).sort()).toStrictEqual(
      REQUIRED_FONT_ASSETS.map((a) => a.family).sort(),
    );
    expect(Object.keys(BRAND_FONT_FACES).sort()).toStrictEqual(
      [font.display, font.body, font.bodyMedium, font.bodySemi, font.bodyBold].sort(),
    );
    for (const [family, asset] of Object.entries(BRAND_FONT_FACES)) {
      expect(asset, `${family} resolved to nothing`).toBeTruthy();
    }

    // One Oswald weight, four Inter weights, five faces. No italics, no extra
    // variants: Inter ships eighteen and we deliberately carry four.
    expect(REQUIRED_FONT_ASSETS).toHaveLength(
      AVAILABLE_WEIGHTS.oswald.length + AVAILABLE_WEIGHTS.inter.length,
    );
    expect(REQUIRED_FONT_ASSETS.filter((a) => a.package.endsWith('/inter'))).toHaveLength(4);
    for (const a of REQUIRED_FONT_ASSETS) {
      expect(a.export).not.toMatch(/Italic/);
    }

    vi.doUnmock('react-native');
    vi.doUnmock('expo-font');
  });
});
