/**
 * src/lib/a11y/touch.ts — invisible hit area for text-only links.
 *
 * A one-line text link is 16–20pt tall; with `hitSlop={8}` its target was 32–36pt, under the 44pt
 * minimum. 14 above and below brings a 16pt line to 44 without moving a pixel.
 */
export const TEXT_LINK_HIT_SLOP = { top: 14, bottom: 14, left: 8, right: 8 } as const;
