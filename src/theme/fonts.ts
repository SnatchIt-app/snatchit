/**
 * src/theme/fonts.ts — brand typeface loading for the mobile app.
 *
 * THE PROBLEM THIS SOLVES
 * The mobile app currently loads NO custom font. `expo-font` is a declared
 * dependency and is never called; the only `fontFamily` declaration in the whole
 * mobile codebase is `Menlo`, for a development-only debug string. Every screen
 * renders in the OS system face while the brand is built on Oswald and Inter, and
 * the web app already ships both. That is the single most visible reason the app
 * and snatchitapp.com look like different companies.
 *
 * STATUS: NOT YET LOADING. See "REMAINING STEP" below.
 *
 * WHY THE FONTS ARE NOT LOADED IN THIS PASS
 * Loading them needs the font binaries, which come from
 * `@expo-google-fonts/oswald` and `@expo-google-fonts/inter`. Adding those to
 * `package.json` without regenerating `package-lock.json` would break CI, which
 * installs with `npm ci` and requires the lock to match. Regenerating the lock
 * was not safe to do from this working copy, whose `node_modules` is borrowed.
 * Shipping a half-installed dependency is worse than shipping a resolver that
 * degrades cleanly, so this module is written to work the moment the packages
 * land and to be harmless until then.
 *
 * REMAINING STEP (one command, then this module starts working with no edits):
 *   npm install @expo-google-fonts/oswald @expo-google-fonts/inter
 * then set `FONTS_INSTALLED` below to true.
 *
 * WHY A RESOLVER RATHER THAN RAW FAMILY NAMES
 * React Native does not fall back gracefully from a missing font family: it can
 * render nothing or throw, depending on platform. `fontFamily()` returns
 * `undefined` when the brand faces are unavailable, which makes React Native use
 * the system face. Screens therefore never break, and they get the brand
 * automatically once the packages are installed.
 *
 * SYNTHETIC WEIGHTS ARE BANNED
 * Only the weights actually shipped as files are referenced. Asking for a weight
 * that was not loaded makes the OS synthesise it, which produces the smeared
 * faux-bold that betrays an unpolished app. The available weights are listed in
 * `AVAILABLE_WEIGHTS`.
 */

import { Platform } from 'react-native';

import { font as brandFont } from './v2';

/**
 * Flip to `true` in the same commit that adds the two font packages. It exists so
 * that the install and the switch-on are one reviewable change, and so nothing
 * silently half-enables.
 */
export const FONTS_INSTALLED = false;

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
 * The family name for a role, or `undefined` when the brand faces are not
 * available so React Native falls back to the system face.
 *
 * On web the brand faces are already loaded by the Next app's own font pipeline,
 * so the CSS family names are used directly there.
 */
export function fontFamily(role: TypeRole): string | undefined {
  if (Platform.OS === 'web') {
    return role === 'display' ? 'Oswald' : 'Inter';
  }
  return FONTS_INSTALLED ? FAMILY[role] : undefined;
}

/**
 * Whether brand type is actually rendering. Screens should not branch on this;
 * it exists for the development preview and for a startup log line, so nobody
 * has to guess whether the fonts took.
 */
export function brandFontsActive(): boolean {
  return Platform.OS === 'web' || FONTS_INSTALLED;
}

/**
 * The map to hand to `useFonts` once the packages are installed.
 *
 * Deliberately written as a function returning a description rather than a live
 * import, because a static import of a missing module is a build error, and the
 * point of this module is that it is safe to land before the install.
 */
export const REQUIRED_FONT_ASSETS = [
  { family: brandFont.display, package: '@expo-google-fonts/oswald', export: 'Oswald_700Bold' },
  { family: brandFont.body, package: '@expo-google-fonts/inter', export: 'Inter_400Regular' },
  { family: brandFont.bodyMedium, package: '@expo-google-fonts/inter', export: 'Inter_500Medium' },
  { family: brandFont.bodySemi, package: '@expo-google-fonts/inter', export: 'Inter_600SemiBold' },
  { family: brandFont.bodyBold, package: '@expo-google-fonts/inter', export: 'Inter_700Bold' },
] as const;
