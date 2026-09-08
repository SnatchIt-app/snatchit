/**
 * @snatchit/design-tokens — LEGACY LAYER
 *
 * These are the values the mobile app shipped with. They are NOT the Snatch It
 * brand: the canvas is blue-black, the red is `#E10600` rather than `#FF1A1A`,
 * and the geometry is rounded where the brand is square.
 *
 * They remain exported because ~50 shipped screens import them, and repainting
 * every screen at once is not authorized. New work imports the BRAND layer from
 * `./brand` instead; screens migrate one at a time during the Tier-1 redesign.
 *
 * @deprecated for new code. Use `brandTokens` from `@snatchit/design-tokens/brand`.
 */

export const colors = {
  // Backgrounds
  bg:              '#0B0F14',
  bgCard:          '#11161C',
  bgInput:         '#1a2030',
  bgModal:         '#11161C',
  bgOverlay:       'rgba(0,0,0,0.65)',

  // Text
  text:            '#FFFFFF',
  textMuted:       '#8a94a6',
  textPlaceholder: '#4a5568',
  textDim:         '#5a6478',

  // Primary accent — premium red
  primary:         '#E10600',
  primaryMuted:    '#B80000',
  primarySoft:     'rgba(225,6,0,0.15)',
  primaryGlow:     'rgba(225,6,0,0.25)',

  // Kept for backward compat (create.tsx / auth screens use accent)
  accent:          '#E10600',
  accentMuted:     '#B80000',

  // Borders
  border:          '#1C232B',
  borderInput:     '#2e3a50',
  borderActive:    '#E10600',

  // Status
  error:           '#ff4d6d',
  success:         '#4ade80',
  warning:         '#fbbf24',

  // Misc
  badge:           '#ffd700',
} as const;

export const spacing = {
  xs:  4,
  sm:  8,
  md:  16,
  lg:  24,
  xl:  32,
  xxl: 48,
} as const;

export const radius = {
  sm:   6,
  md:   10,
  lg:   16,
  xl:   24,
  full: 9999,
} as const;

export const fontSize = {
  xs:   11,
  sm:   13,
  md:   15,
  lg:   18,
  xl:   24,
  xxl:  32,
  xxxl: 42,
} as const;

export const shadow = {
  card: {
    shadowColor:   '#000',
    shadowOffset:  { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius:  8,
    elevation:     6,
  },
  modal: {
    shadowColor:   '#000',
    shadowOffset:  { width: 0, height: -4 },
    shadowOpacity: 0.4,
    shadowRadius:  12,
    elevation:     12,
  },
} as const;


/*
 * The brand layer is the source of truth for new work. It is exported as a
 * NAMESPACE rather than star-exported, because both layers define `radius` and
 * `font`-adjacent names with deliberately different values (the legacy layer's
 * 6/10/16/24 radius ladder versus the brand's square geometry). Keeping them
 * namespaced makes every call site say which system it is using.
 */
export * as v2 from './brand.ts';
