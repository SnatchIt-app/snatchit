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
 * RENDERING: React Native 0.81's `experimental_backgroundImage` draws CSS gradients with no
 * native module — it is what EventMedia's existing V2 scrims already use. `scrimBackgroundImage`
 * below emits this curve as that CSS string; slots with `scrim: 'curve'` apply it. (An earlier
 * note here said expo-linear-gradient was required; it is not, and it is not installed.)
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

/**
 * The curve as a `linear-gradient(...)` string for `experimental_backgroundImage`, spanning the
 * FULL image height — the 0.20 floor by t = 0.30 is the whole point, so this must never be
 * applied to a partial-height band the way the V2 scrims are.
 */
export function scrimBackgroundImage(count = 15): string {
  const stops = scrimStops(count)
    .map((s) => `${s.color} ${+(s.position * 100).toFixed(2)}%`)
    .join(', ');
  return `linear-gradient(to bottom, ${stops})`;
}
