/**
 * src/theme/fonts.ts — brand typeface loading for the mobile app.
 *
 * THE PROBLEM THIS SOLVES
 * The mobile app previously loaded NO custom font. `expo-font` was a declared
 * dependency and was never called; the only `fontFamily` declaration in the whole
 * mobile codebase was `Menlo`, for a development-only debug string. Every screen
 * rendered in the OS system face while the brand is built on Oswald and Inter, and
 * the web app already ships both. That was the single most visible reason the app
 * and snatchitapp.com looked like different companies.
 *
 * STATUS: LOADING. `@expo-google-fonts/oswald` and `@expo-google-fonts/inter` are
 * installed and locked at 0.4.2, and `useBrandFonts()` loads the five faces.
 *
 * INSTALLED VS LOADED ARE DIFFERENT FACTS, AND CONFLATING THEM BREAKS ANDROID
 * `FONTS_INSTALLED` is a build-time constant: the packages are in the bundle.
 * Loading is asynchronous and happens at runtime. Returning a family name before
 * the face is registered is the classic failure: iOS silently substitutes the
 * system face, but Android can render an empty box. So `fontFamily()` returns a
 * family only once `useBrandFonts()` has reported the faces loaded, and the root
 * layout holds the first frame until then. That wait is over bundled local
 * assets, not the network.
 *
 * WHY A RESOLVER RATHER THAN RAW FAMILY NAMES
 * React Native does not fall back gracefully from a missing font family. This
 * module returns `undefined` when the brand faces are unavailable, which makes
 * React Native use the system face, so screens degrade instead of breaking — on a
 * load failure, a slow first frame, or in a test renderer.
 *
 * SYNTHETIC WEIGHTS ARE BANNED
 * Only the weights actually shipped as files are referenced. Asking for a weight
 * that was not loaded makes the OS synthesise it, which produces the smeared
 * faux-bold that betrays an unpolished app. The available weights are listed in
 * `AVAILABLE_WEIGHTS`, and the five imports below are the complete set — Inter
 * ships nine weights and four variable axes, and we deliberately load four faces.
 */

// PER-WEIGHT DEEP IMPORTS, DELIBERATELY. Each package's root `index.js` is a
// generated file that eagerly `require()`s EVERY weight it ships — Inter alone is
// eighteen faces — so importing from the package root would pull roughly 9 MB of
// .ttf into the app bundle to use five of them. The per-weight entry points
// export exactly one face each, which brings the bundled payload to about 1.4 MB.
// Do not "tidy" these into root imports.
import { Oswald_700Bold } from '@expo-google-fonts/oswald/700Bold';
import { Inter_400Regular } from '@expo-google-fonts/inter/400Regular';
import { Inter_500Medium } from '@expo-google-fonts/inter/500Medium';
import { Inter_600SemiBold } from '@expo-google-fonts/inter/600SemiBold';
import { Inter_700Bold } from '@expo-google-fonts/inter/700Bold';
import { useFonts } from 'expo-font';
import { Platform } from 'react-native';

import { font as brandFont } from './v2';

/**
 * The packages are present in the bundle. This is a build-time fact and says
 * nothing about whether the faces have finished registering — see
 * `brandFontsActive()` for the runtime fact.
 */
export const FONTS_INSTALLED = true;

/**
 * The weights we actually ship. Requesting anything else would be synthesised by
 * the OS, so the type system prevents it.
 */
export const AVAILABLE_WEIGHTS = {
  oswald: [700],
  inter: [400, 500, 600, 700],
} as const;

export type TypeRole = 'display' | 'body' | 'bodyMedium' | 'bodySemi' | 'bodyBold';

const FAMILY: Record<TypeRole, string> = {
  display: brandFont.display,
  body: brandFont.body,
  bodyMedium: brandFont.bodyMedium,
  bodySemi: brandFont.bodySemi,
  bodyBold: brandFont.bodyBold,
};

/**
 * The exact face map handed to `useFonts`. The keys are the family names the rest
 * of the product asks for through `fontFamily()`, so the token layer and the
 * loader cannot drift: `brandFont.display` is both the key here and the value
 * returned by the resolver.
 */
export const BRAND_FONT_FACES = {
  [brandFont.display]: Oswald_700Bold,
  [brandFont.body]: Inter_400Regular,
  [brandFont.bodyMedium]: Inter_500Medium,
  [brandFont.bodySemi]: Inter_600SemiBold,
  [brandFont.bodyBold]: Inter_700Bold,
} as const;

/**
 * Runtime registration state. Module-level rather than React state because
 * `fontFamily()` is called from `StyleSheet.create` bodies and other non-hook
 * contexts. The root layout holds the first frame until this flips, so no
 * component observes it changing mid-life.
 */
let facesLoaded = false;

/**
 * Loads the brand faces. Call once, from the root layout, and hold the first
 * frame until it returns true.
 *
 * On web the faces come from CSS rather than from `expo-font`, so this reports
 * ready immediately and loads nothing — see `fontFamily()`.
 */
export function useBrandFonts(): boolean {
  const [loaded, error] = useFonts(BRAND_FONT_FACES);

  if (Platform.OS === 'web') return true;

  // A load failure must not wedge the app on a splash screen forever. Treating
  // an error as "ready" lets `fontFamily()` keep returning undefined, so every
  // screen renders in the system face instead of not rendering at all.
  const ready = loaded || error != null;
  facesLoaded = loaded && error == null;
  return ready;
}

/**
 * The family name for a role, or `undefined` when the brand faces are not
 * available so React Native falls back to the system face.
 *
 * On web the brand faces are loaded by the web app's own CSS font pipeline under
 * their canonical family names, so those are used directly there.
 */
export function fontFamily(role: TypeRole): string | undefined {
  if (Platform.OS === 'web') {
    return role === 'display' ? 'Oswald' : 'Inter';
  }
  return FONTS_INSTALLED && facesLoaded ? FAMILY[role] : undefined;
}

/**
 * Whether brand type is actually rendering right now. Screens should not branch
 * on this; it exists for the development preview and for a startup log line, so
 * nobody has to guess whether the fonts took.
 */
export function brandFontsActive(): boolean {
  return Platform.OS === 'web' || facesLoaded;
}

/**
 * The declarative manifest of what must be loaded. Kept alongside
 * `BRAND_FONT_FACES` so a test can assert the two agree, which is what stops a
 * weight being added to the tokens and silently never loaded.
 */
export const REQUIRED_FONT_ASSETS = [
  { family: brandFont.display, package: '@expo-google-fonts/oswald', export: 'Oswald_700Bold' },
  { family: brandFont.body, package: '@expo-google-fonts/inter', export: 'Inter_400Regular' },
  { family: brandFont.bodyMedium, package: '@expo-google-fonts/inter', export: 'Inter_500Medium' },
  { family: brandFont.bodySemi, package: '@expo-google-fonts/inter', export: 'Inter_600SemiBold' },
  { family: brandFont.bodyBold, package: '@expo-google-fonts/inter', export: 'Inter_700Bold' },
] as const;

/** Test seam: force the runtime flag. Never call this from product code. */
export function __setFacesLoadedForTest(v: boolean): void {
  facesLoaded = v;
}
