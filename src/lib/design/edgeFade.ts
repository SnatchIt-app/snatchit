/**
 * src/lib/design/edgeFade.ts — content fading into a solid edge instead of being sliced by it.
 *
 * Build 28's listing showed it: the scroll view ends at the footer's top edge, so whatever line sat
 * there was cut in half just above Place a bid (the listing's own name, on a 6.3" screen at rest).
 * A short gradient from the canvas at 0 to the canvas at 1 over that edge turns the cut into a fade.
 *
 * Built from the exact canvas colour, never `transparent`: a gradient through transparent BLACK greys
 * the middle of the band on a white canvas. Rendered with React Native 0.81's
 * `experimental_backgroundImage`, as the hero scrims already are — no native module.
 */

/** Height of the fade above the footer, in points: about one line of body text. */
export const FOOTER_FADE = 24;

/** `#RGB` or `#RRGGBB` → its channels; anything else → null. */
function channels(hex: string): [number, number, number] | null {
  const m = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) return null;
  const h = m[1].length === 3 ? m[1].split('').map((c) => c + c).join('') : m[1];
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)) as [number, number, number];
}

/**
 * A top-to-bottom gradient from `color` fully transparent to `color` fully opaque. Undefined for a
 * colour that is not hex: no gradient rather than a wrong one — the edge it sits on stays opaque.
 */
export function edgeFade(color: string): string | undefined {
  const c = channels(color);
  if (!c) return undefined;
  const rgb = c.join(',');
  return `linear-gradient(to bottom, rgba(${rgb},0) 0%, rgba(${rgb},1) 100%)`;
}
