/**
 * src/theme/typography.ts — the React Native rendering layer for the brand type scale.
 *
 * WHY THIS EXISTS RATHER THAN AN EDIT TO `v2.ts`
 * The brand's display leading is deliberately sub-1.0 — the live site computes
 * 136.4px of leading on a 166.4px face, and that stacked, poster-like tightness is
 * the signature. On the web it renders correctly. React Native does not agree:
 * when the line box is near `fontSize`, both platforms clip the tops of glyphs —
 * Android via includeFontPadding, iOS by anchoring the font descent to the bottom
 * of the line box — and Oswald is a tall condensed face, so it clips badly. See
 * `MIN_LINE_HEIGHT_RATIO` for the metric-derived floor.
 *
 * The fix belongs HERE, not in the token, for two reasons:
 *
 *  1. `src/theme/v2.ts` is mirrored byte-for-byte by
 *     `packages/design-tokens/src/brand.ts`, which the web app consumes. Forcing
 *     React Native's floor onto the shared token would loosen the marketing-true
 *     leading on a platform that renders it correctly, to work around a limitation
 *     that platform does not have.
 *  2. A token records the design. A renderer resolves it for its own platform.
 *
 * So the token keeps the designed value and every React Native consumer reads its
 * styles through `textStyle()`, which raises the line box to the smallest value
 * that cannot clip. The result is still the tightest leading React Native can
 * render, and it is uniform across both platforms we ship.
 *
 * RULE: no screen or primitive reads `v2.type.*` directly. They call `textStyle()`.
 */

import { Platform, type TextStyle } from 'react-native';

import { fontFamily, type TypeRole } from './fonts';
import * as v2 from './v2';

export type TypeToken = keyof typeof v2.type;

/**
 * The minimum multiple of the font size that React Native can render without
 * clipping a tall condensed face.
 *
 * Every display token is uppercase-only, so the binding constraint is Oswald's
 * cap box, not its ascenders. iOS TextKit anchors the font descent to the bottom
 * of the line box, leaving `lineHeight − descent` above the baseline. Oswald_700Bold
 * (unitsPerEm 1000) has capHeight 810 and descent 289, so caps need at least
 * `(810 + 289) / 1000 = 1.10 em`; under iOS's win-descent anchoring (usWinDescent
 * 377) the floor rises to `(810 + 377) / 1000 = 1.187 em`. An earlier 1.02 value —
 * tuned against Android's includeFontPadding model, not iOS — sat below both and
 * clipped the tops of caps on device (e.g. the "YOUR BIDS" heading, and the old
 * Home wordmark before it became the SN logo). 1.25 clears the strict iOS case on
 * all four display sizes with a safety margin, while staying well under Oswald's
 * natural 1.48 leading so the poster-tight display stacking is preserved and the
 * generously-led body scale is unaffected.
 */
const MIN_LINE_HEIGHT_RATIO = 1.25;

/** Which loaded face a token wants. Mirrors `v2.font`, which is the same map. */
const ROLE_FOR_FAMILY: Record<string, TypeRole> = {
  [v2.font.display]: 'display',
  [v2.font.body]: 'body',
  [v2.font.bodyMedium]: 'bodyMedium',
  [v2.font.bodySemi]: 'bodySemi',
  [v2.font.bodyBold]: 'bodyBold',
};

/**
 * The smallest line height that renders the token's designed leading without
 * clipping. Returns the designed value untouched when it already clears the floor,
 * so the body scale — which is designed with generous leading — is unaffected.
 */
export function safeLineHeight(fontSize: number, designed: number): number {
  return Math.max(designed, Math.ceil(fontSize * MIN_LINE_HEIGHT_RATIO));
}

/**
 * The React Native style for a brand type token.
 *
 * `fontFamily` resolves to `undefined` until the brand faces register, which makes
 * React Native fall back to the system face rather than render nothing — see
 * `src/theme/fonts.ts`. Uppercase travels with the token because forgetting it is
 * how a display style silently stops being a display style.
 */
export function textStyle(token: TypeToken): TextStyle {
  const t = v2.type[token];
  const style: TextStyle = {
    fontFamily: fontFamily(ROLE_FOR_FAMILY[t.family] ?? 'body'),
    fontSize: t.size,
    lineHeight: safeLineHeight(t.size, t.lineHeight),
    letterSpacing: t.letterSpacing,
  };
  if (t.uppercase) style.textTransform = 'uppercase';
  // Prices only. Tabular figures stop digits jittering as a live bid updates, and
  // the variant has to reach the Text — declaring it on the token is not enough.
  if ('fontVariant' in t && t.fontVariant) {
    style.fontVariant = [...t.fontVariant] as TextStyle['fontVariant'];
  }
  return style;
}

/**
 * Motion durations, collapsed to a single frame when the OS asks for reduced
 * motion. Every animated primitive reads its duration through this.
 */
export function duration(token: keyof typeof v2.motion, reduceMotion: boolean): number {
  const value = v2.motion[token];
  if (typeof value !== 'number') return 0;
  return reduceMotion ? 1 : value;
}

/**
 * The brand easing, in the form React Native's Animated API actually accepts.
 * `v2.motion.easingCss` is for web consumers; passing that string to Animated does
 * nothing, so the four control points are exported here instead.
 */
export const EASING_BEZIER = v2.motion.easingBezier;

/**
 * Minimum interactive target. Every primitive either meets it with real padding or
 * makes up the difference with `hitSlop`.
 */
export const MIN_TOUCH_TARGET = 44;

/** iOS reports a font scale; the display scale caps its growth so headlines cannot push a CTA off screen. */
export const MAX_DISPLAY_FONT_SCALE = Platform.OS === 'ios' ? 1.3 : 1.3;
