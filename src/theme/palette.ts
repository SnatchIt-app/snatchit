/**
 * src/theme/palette.ts — one semantic colour shape, two appearances (owner 2026-09-23).
 *
 * `dark` IS Midnight: it re-exports the v2 token groups untouched, so every existing static
 * style keeps its exact colours and the v2 ↔ design-tokens mirror is not disturbed. `light` is
 * derived from the same hierarchy — same keys, same roles, same red — and is PROVISIONAL: B
 * owns both appearances across the inventory and will confirm or replace these values.
 * Contrast for the body inks is computed in tests (≥ 4.5:1 on canvas, surface and elevated).
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
  readonly onArt: typeof ON_ART;
}

export const dark: Palette = {
  scheme: 'dark',
  surface: v2.surface,
  text: v2.text,
  brand: v2.brand,
  border: v2.border,
  status: v2.status,
  onArt: ON_ART,
};

/** PROVISIONAL light appearance — B confirms or replaces. Roles mirror Midnight one for one. */
export const light: Palette = {
  scheme: 'light',
  surface: {
    canvas: '#FFFFFF',
    surface: '#F4F4F5',
    elevated: '#FFFFFF',
    overlay: 'rgba(0,0,0,0.40)',
  },
  text: {
    primary: '#0E0E10',
    // Computed, not estimated (tests): ≥ 8:1 on white, ≥ 5:1 at muted on the surface grey.
    secondary: 'rgba(14,14,16,0.74)',
    muted: 'rgba(14,14,16,0.62)',
    faint: 'rgba(14,14,16,0.36)',
    /** Text on brand red stays black — the signature holds in both appearances. */
    inverse: '#000000',
  },
  // The same red: black-on-red stays ≥ 5:1. Red TEXT on a white canvas measures ~4:1 (large
  // text only) — flagged for B; the pressed/soft variants follow the dark ratios.
  brand: {
    red: v2.brand.red,
    redPressed: v2.brand.redPressed,
    redSoft: 'rgba(255,26,26,0.08)',
  },
  border: {
    default: 'rgba(255,26,26,0.20)',
    strong: 'rgba(255,26,26,0.40)',
    overArt: v2.border.overArt,
  },
  status: {
    success: '#1B8A4A',
    warning: '#A65E00',
    error: '#D32F2F',
  },
  onArt: ON_ART,
};

export function paletteFor(scheme: Scheme): Palette {
  return scheme === 'light' ? light : dark;
}
