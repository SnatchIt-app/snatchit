/**
 * src/theme/palette.ts — one semantic colour shape, two appearances (owner 2026-09-23).
 *
 * `dark` IS Midnight: it re-exports the v2 token groups untouched, so every existing static
 * style keeps its exact colours and the v2 ↔ design-tokens mirror is not disturbed. `light` is
 * B's Daylight column (package 8, `pkg8-appearance-tokens.png`, 2026-09-23) mapped onto the v2
 * key shape: B's `surface.panel` is `surface.surface`, B's `surface.plate` also resolves to it
 * (v2 carries no plate key; the difference is 0.04 in luminance), and B's `border.control` is a
 * new key in BOTH appearances. Contrast is computed in tests, not estimated.
 *
 * Midnight's hairlines are the approved neutral `#28292D` (A-1, owner 2026-09-22) and its canvas
 * stays `#000000` — B withdrew the `#08090A` on the boards as a rendering artefact.
 *
 * `onArt` is deliberately identical in both appearances: text over artwork sits on the image
 * and its scrim, never on the canvas, so it stays white however the canvas flips.
 */

import * as v2 from './v2';

export type Scheme = 'light' | 'dark';

type Group<T> = { readonly [K in keyof T]: string };

export const ON_ART = {
  primary: '#FFFFFF',
  secondary: 'rgba(255,255,255,0.78)',
  muted: 'rgba(255,255,255,0.62)',
} as const;

export interface Palette {
  readonly scheme: Scheme;
  readonly surface: Group<typeof v2.surface>;
  readonly text: Group<typeof v2.text>;
  readonly brand: Group<typeof v2.brand>;
  readonly border: Group<typeof v2.border>;
  readonly status: Group<typeof v2.status>;
  /** The floating dock's translucent material — composited by the dock, never a literal. */
  readonly chrome: Group<typeof v2.chrome>;
  readonly onArt: typeof ON_ART;
}

export const dark: Palette = {
  scheme: 'dark',
  surface: v2.surface,
  text: v2.text,
  brand: v2.brand,
  border: v2.border,
  status: v2.status,
  chrome: v2.chrome,
  onArt: ON_ART,
};

/** Daylight — B's token board. Roles mirror Midnight one for one; elevation flips (panel darker than canvas). */
export const light: Palette = {
  scheme: 'light',
  surface: {
    canvas: '#FFFFFF',
    /** B's `surface.panel` (and its `plate`): sits DARKER than the canvas — elevation reads by contrast. */
    surface: '#F4F4F6',
    elevated: '#FFFFFF',
    overlay: 'rgba(0,0,0,0.40)',
  },
  text: {
    primary: '#0B0C0E',
    secondary: '#4A4D53',
    /** Solved, not mirrored: the lightest value that clears 4.5:1 on the darkest light surface. */
    muted: '#686C73',
    faint: 'rgba(11,12,14,0.36)',
    /** Text on brand red stays black — the signature holds in both appearances. */
    inverse: '#000000',
  },
  // The same red in both: black on #FF1A1A is 5.41:1 whatever sits behind the button, and the
  // fill clears 3:1 against white (3.88:1). B withdrew the Daylight-only red.
  brand: {
    red: v2.brand.red,
    redPressed: v2.brand.redPressed,
    redSoft: 'rgba(255,26,26,0.08)',
  },
  border: {
    /** A divider identifies nothing: listed, not graded (1.32:1). */
    default: '#DFE0E4',
    strong: '#8A8B90',
    /** The edge that identifies a control: 3.40:1 on the canvas, 3.10:1 on the panel. */
    control: '#8A8B90',
    overArt: v2.border.overArt,
  },
  // Re-picked as TEXT colours: #3DDC84 is 1.6:1 and #FFB020 is 1.9:1 on white.
  status: {
    success: '#0B7A3C',
    warning: '#8A5400',
    error: '#C41414',
  },
  // Light glass: the dock floats as a near-white material with a dark hairline; the selected
  // capsule and the avatar dim blend toward the dock fill, as on Midnight, in the other direction.
  chrome: {
    glass: 'rgba(255,255,255,0.84)',
    glassEdge: 'rgba(11,12,14,0.12)',
    glassSelected: 'rgba(11,12,14,0.07)',
    glassDim: 'rgba(255,255,255,0.12)',
  },
  onArt: ON_ART,
};

export function paletteFor(scheme: Scheme): Palette {
  return scheme === 'light' ? light : dark;
}
