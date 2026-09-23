/**
 * src/lib/design/scrim.ts — the V3 hero scrim curve (owner 2026-09-22; B's package §3).
 *
 * The overlay that makes text over seller artwork legible. The 0.20 FLOOR is the point: a pure
 * gradient starts at zero and leaves the tops of the glyphs over raw image — an over-exposed photo
 * measured 1.73:1 with a floorless gradient and 1.10:1 unscrimmed. With this curve B measured every
 * text band ≥ its threshold (worst 5.17:1) against generated artwork; REAL uploads are acceptance
 * criterion 13 and are a device check.
 *
 *   t < 0.30 : 0.20 × smoothstep(t / 0.30)          — eases in, so there is no visible seam
 *   t ≥ 0.30 : 0.20 + 0.77 × (t − 0.30) / 0.70      — linear to 0.97 at the baseline
 *
 * NOT WIRED YET: rendering this needs a gradient primitive (expo-linear-gradient), which is not in
 * the bundle — adding it is a native-module change that needs the next authorised build. The curve
 * lands here first so the values are pinned and reviewable; the hero applies it in the V3 screen
 * stage that ships with that build.
 */

function smoothstep(x: number): number {
  const c = Math.min(1, Math.max(0, x));
  return c * c * (3 - 2 * c);
}

/** Scrim alpha at position t ∈ [0,1] from the image top (0) to its bottom (1). */
export function scrimAlpha(t: number): number {
  const c = Math.min(1, Math.max(0, t));
  if (c < 0.3) return 0.2 * smoothstep(c / 0.3);
  return 0.2 + 0.77 * ((c - 0.3) / 0.7);
}

/**
 * Evenly spaced gradient stops for a LinearGradient over black, dense enough that the piecewise
 * curve's knee at t = 0.30 cannot show as a band.
 */
export function scrimStops(count = 15): { position: number; color: string }[] {
  const stops: { position: number; color: string }[] = [];
  for (let i = 0; i < count; i++) {
    const t = i / (count - 1);
    stops.push({ position: t, color: `rgba(0,0,0,${scrimAlpha(t).toFixed(4)})` });
  }
  return stops;
}
