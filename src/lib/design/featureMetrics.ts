/**
 * src/lib/design/featureMetrics.ts — the §3 layout values for the V3 home feature, feed/search
 * row and listing hero (owner 2026-09-22; B's package §3).
 *
 * These are DERIVED values and drawn constants, in one module, because §3 forbids hard-coding the
 * results: "a one-line row is 80pt; a two-line row is 98pt. Do not hard-code either." Row height
 * is content-driven and never appears here at all (see ROW_META_CLEARANCE in rowMetrics.ts for the
 * clearance half of that rule).
 *
 * The two §3 height FORMULAS that used to live here were retired by the owner's 4:5 poster
 * direction (2026-09-24) — see the note below. What remains is the row poster's box, the media
 * radius, and the text positions, all of which are measured from an image EDGE rather than from a
 * height, so none of them moved.
 */

import * as v2 from '@/src/theme/v2';

/** Left/right gutter for the feature's overlaid text and the §3 row inset. */
export const FEATURE_GUTTER = 20;
export const ROW_GUTTER = 20;

/**
 * §3 feed/search row artwork — a 4:5 POSTER, 50 × 62 (owner 2026-09-24).
 *
 * §3 drew this thumbnail 62 × 62 and the row heights that were approved with it (a one-line row
 * is 80pt, a two-line row 98pt) were measured against a 62pt-tall image. The poster direction
 * changes the shape, and only one of the two edges can stay fixed:
 *  - hold the WIDTH at 62 and the poster is 78 tall, which drives the one-line row to ~94pt and
 *    re-opens the vertical rhythm of a feed the owner has already accepted;
 *  - hold the HEIGHT at 62 and the poster is 50 wide. Row heights, clearances and the whole
 *    vertical rhythm are untouched; the text column simply starts 12pt further left.
 * The second is the smaller change to accepted work, so `ROW_ART` remains 62 and is now
 * explicitly the artwork's HEIGHT, with the width derived from the ratio in one place.
 *
 * RADIUS — owner 2026-09-24. §3 drew this thumbnail at 8 and the pkg8 home boards MEASURE 8 (a
 * 16px arc at 2×), which agrees with the drawn value and outranks the radius scale's generic
 * `md` — the mapping briefly applied here on 2026-09-24 before the board was measured. Rounded,
 * and exactly as drawn.
 */
export const ROW_ART = 62;
/**
 * The media role of B's V3 radius table §4.1 (rules 0 · media 8 · chrome 22 · dock 33 ·
 * full-bleed 0 · panels 0). Every poster frame that is not full-bleed and not clipped by a
 * parent's corners takes this, from here — so the value has one home and the row thumbnail's
 * drawn 8 and the grid card's 8 cannot drift apart.
 */
export const MEDIA_RADIUS = 8;
export const ROW_ART_RADIUS = MEDIA_RADIUS;
/**
 * The width of a poster that is `height` points tall. The ONE place the 4:5 arithmetic happens
 * outside the media component, so a row can state the edge it actually budgets — its height — and
 * never type a width that has to be recomputed by hand when the ratio changes.
 */
export function posterWidth(height: number): number {
  return Math.round(height * v2.ratio.portrait);
}

/** The row poster's width, derived from its height. Never hard-coded. */
export const ROW_ART_W = posterWidth(ROW_ART);
/** The gap between the poster and the text column. With a 20pt gutter and a 50pt poster the
 *  text column starts at x = 82 (it was 94 when the artwork was 62 wide). */
export const ROW_ART_GAP = 12;
export const ROW_TEXT_X = ROW_GUTTER + ROW_ART_W + ROW_ART_GAP;

/*
 * RETIRED 2026-09-24: `featureHeight(w) = (w − 40) × 0.49 + 34` and `heroHeight(w) = w × 0.62 + 24`.
 *
 * Both were §3 height formulas for a landscape band. The owner's 4:5 poster direction makes the
 * RATIO the height authority for those two slots, and a formula and a ratio cannot both decide
 * one edge. They are deleted rather than left unused so no screen can reach for a landscape
 * height again; the geometry now lives in MEDIA_SLOTS.HOME_FEATURE_V3 / LISTING_HERO_V3.
 *
 * Everything the formulas sat next to SURVIVES, because all of it is measured from the image's
 * BOTTOM edge: a taller frame moves the artwork's top up and leaves the text where it was
 * approved.
 */

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

/** Hero: date line 78pt above the image bottom, name 19pt below the date line. */
export const HERO_DATE_BOTTOM = 78;
export const HERO_NAME_GAP = 19;

/**
 * The OS text scale at which the feature's identity block stops being two columns.
 *
 * WHY IT EXISTS (B's native finding at d5217530, owner-settled 2026-10-06). The block is a row:
 * name and meta on the left, price and its caption in a narrow right-hand column. At a large text
 * scale the two cannot both fit, and the caption — "current bid, all-in" — was the one that lost,
 * truncating to "current bid, al…" and taking the word the all-in pricing rule turns on with it.
 * The clock line was cut the same way one size earlier.
 *
 * 1.3 is at or below the largest STANDARD size, which is where the first cut appeared: a threshold
 * that only caught the accessibility sizes would leave a setting many people use still clipped.
 * Above it the block stacks and every line gets the full width, which is the owner's "adjust its
 * layout" rather than capping how far the text may grow — capping would answer a request for
 * larger text by refusing it.
 */
export const IDENTITY_STACK_SCALE = 1.3;

export function identityStacks(fontScale: number): boolean {
  return fontScale >= IDENTITY_STACK_SCALE;
}
