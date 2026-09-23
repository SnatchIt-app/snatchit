/**
 * src/lib/design/featureMetrics.ts — the §3 layout values for the V3 home feature, feed/search
 * row and listing hero (owner 2026-09-22; B's package §3).
 *
 * These are FORMULAS and drawn constants, in one module, because §3 forbids hard-coding the
 * results: "a one-line row is 80pt; a two-line row is 98pt. Do not hard-code either." Heights are
 * computed from the real screen width; row height is content-driven and never appears here at all
 * (see ROW_META_CLEARANCE in rowMetrics.ts for the clearance half of that rule).
 */

/** Left/right gutter for the feature's overlaid text and the §3 row inset. */
export const FEATURE_GUTTER = 20;
export const ROW_GUTTER = 20;

/** §3 feed/search row artwork: 62 × 62, radius 8. */
export const ROW_ART = 62;
export const ROW_ART_RADIUS = 8;
/** Text column starts at x = 94 with a 20pt gutter and 62pt artwork → a 12pt gap. */
export const ROW_ART_GAP = 12;

/** Home feature: full-bleed, height (screen − 40) × 0.49 + 34 (≈205pt at 390pt wide). */
export function featureHeight(screenWidth: number): number {
  return (screenWidth - 40) * 0.49 + 34;
}

/**
 * The feature's name block sits with its BOTTOM 44pt above the image bottom; meta line 1 starts
 * 2pt below it, meta line 2 starts 19pt below it (a 17pt step). The price shares meta 1's
 * baseline, its caption 21pt below.
 */
export const FEATURE_NAME_BLOCK_BOTTOM = 44;
export const FEATURE_META1_BELOW_NAME = 2;
export const FEATURE_META2_BELOW_NAME = 19;
export const FEATURE_META_LINE = FEATURE_META2_BELOW_NAME - FEATURE_META1_BELOW_NAME;
/** Bottom padding under the meta stack: 44 − 2 − two 17pt meta lines = 8. */
export const FEATURE_CONTENT_BOTTOM =
  FEATURE_NAME_BLOCK_BOTTOM - FEATURE_META1_BELOW_NAME - 2 * FEATURE_META_LINE;

/** Listing hero: full-bleed, height screen × 0.62 + 24 (≈266pt at 390pt wide). */
export function heroHeight(screenWidth: number): number {
  return screenWidth * 0.62 + 24;
}

/** Hero: date line 78pt above the image bottom, name 19pt below the date line. */
export const HERO_DATE_BOTTOM = 78;
export const HERO_NAME_GAP = 19;
