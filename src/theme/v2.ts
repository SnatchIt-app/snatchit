/**
 * src/theme/v2.ts — BRAND LAYER (V2). The mobile runtime's brand tokens.
 *
 * THE SOURCE OF TRUTH for Snatch It's product appearance.
 *
 * `packages/design-tokens/src/brand.ts` carries a byte-identical copy so the web
 * app can consume the same values; `tests/product-v2-foundation.test.ts` fails if
 * the two ever drift. This mirrors the convention the repository already uses for
 * the legacy layer.
 *
 * Every value here was read from the live rendered snatchitapp.com on 2026-09-02
 * (computed styles, not guesses) and cross-checked against `web/src/app/globals.css`
 * and `web/docs/brand-system.md`. Evidence:
 * `docs/product-v2/MARKETING_BRAND_EXTRACTION.md`.
 *
 * WHY THIS FILE EXISTS
 * The repository previously carried two competing systems. `src/index.ts` (the
 * legacy layer, still exported below it for compatibility) was generated FROM the
 * mobile app's theme, which uses a blue-black canvas, a different red and a rounded
 * geometry. The web app then had to override those values back to brand values.
 * The non-brand system was upstream of the correct one. This layer inverts that:
 * the brand is defined once, here, and both clients consume it.
 *
 * MIGRATION POSTURE
 * This layer is ADDITIVE. It does not repaint existing screens. Screens move onto
 * it during the Tier-1 redesign, one at a time, deleting local styles as they go.
 * Nothing imports it by default yet.
 */

/** Canvas and surfaces. Neutral only: there is no blue in Snatch It's blacks. */
export const surface = {
  /** App canvas. Every screen background. */
  canvas: '#000000',
  /** Cards, sheets, rows that need separation from the canvas. */
  surface: '#0A0A0A',
  /** Modals, menus, anything above a surface. */
  elevated: '#111111',
  /** Scrim behind modals and sheets. */
  overlay: 'rgba(0,0,0,0.72)',
} as const;

/** Text. Anything at `muted` or dimmer may not carry task-critical information. */
export const text = {
  primary: '#FFFFFF',
  secondary: 'rgba(255,255,255,0.70)',
  /**
   * 0.55 rather than the marketing site's 0.45. White at 45% on black measures
   * 4.43:1, which fails the 4.5:1 minimum, and this tier carries event dates and
   * venue names on cards, which a user genuinely needs to read. 0.55 measures
   * 6.27:1 (both figures computed, not estimated). The marketing site can be dimmer because its metadata is
   * atmosphere; in the product it is information.
   */
  muted: 'rgba(255,255,255,0.55)',
  faint: 'rgba(255,255,255,0.30)',
  /** Text on brand red. Black on red is a Snatch It signature. */
  inverse: '#000000',
} as const;

export const brand = {
  red: '#FF1A1A',
  redPressed: '#CC0000',
  /** Selected-row tint and badge fill. */
  redSoft: 'rgba(255,26,26,0.10)',
} as const;

/**
 * Hairlines are RED-TINTED on this brand, not gray. `overArt` is the exception:
 * over artwork a red hairline fights the image, so a neutral one is used.
 */
export const border = {
  default: 'rgba(255,26,26,0.15)',
  strong: 'rgba(255,26,26,0.30)',
  overArt: 'rgba(255,255,255,0.10)',
} as const;

/**
 * `error` is deliberately a DIFFERENT red from `brand.red`. In the legacy theme a
 * destructive action and a primary action are the same color, which is a real
 * usability defect rather than a stylistic preference.
 */
export const status = {
  success: '#3DDC84',
  warning: '#FFB020',
  error: '#FF4D4D',
} as const;

/** 4pt base. */
export const space = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
  xxxl: 48,
} as const;

/**
 * Radius 0 is the brand. It is not a preference: every measured element on
 * snatchitapp.com returned `border-radius: 0px`. `pill` exists only for avatars
 * and status dots. There is deliberately no middle value.
 */
export const radius = {
  none: 0,
  pill: 9999,
} as const;

/**
 * Type. Two families, strictly divided.
 *
 * Oswald carries OUR voice: screen titles, section heads, brand moments. It is
 * uppercase and negatively tracked.
 *
 * Inter carries EVERYTHING ELSE, including all user-generated content. Event
 * titles, venue names and person names are Inter in sentence case, never Oswald
 * and never uppercased, because they arrive in mixed case, often run long, and
 * because a poster already contains display type: a second competing headline
 * reads as a mistake. Both first-party benchmarks set event titles at normal
 * weight for exactly this reason.
 */
export const font = {
  display: 'Oswald_700Bold',
  body: 'Inter_400Regular',
  bodyMedium: 'Inter_500Medium',
  bodySemi: 'Inter_600SemiBold',
  bodyBold: 'Inter_700Bold',
} as const;

export const type = {
  displayXl: { family: font.display, size: 44, lineHeight: 40, letterSpacing: -0.9, uppercase: true },
  displayLg: { family: font.display, size: 34, lineHeight: 32, letterSpacing: -0.7, uppercase: true },
  displayMd: { family: font.display, size: 26, lineHeight: 26, letterSpacing: -0.5, uppercase: true },
  displaySm: { family: font.display, size: 20, lineHeight: 22, letterSpacing: -0.2, uppercase: true },
  /** Row titles and ALL user-generated names. */
  title: { family: font.bodySemi, size: 17, lineHeight: 22, letterSpacing: 0, uppercase: false },
  body: { family: font.body, size: 15, lineHeight: 22, letterSpacing: 0, uppercase: false },
  bodySm: { family: font.body, size: 13, lineHeight: 18, letterSpacing: 0, uppercase: false },
  /** Buttons, tabs, chips. */
  label: { family: font.bodyBold, size: 12, lineHeight: 16, letterSpacing: 2.2, uppercase: true },
  /** Eyebrows and metadata keys. Decoration tier. */
  micro: { family: font.bodyMedium, size: 10, lineHeight: 14, letterSpacing: 3.0, uppercase: true },
  /**
   * Prices. `fontVariant: ['tabular-nums']` must be applied at the Text, or digits
   * jitter as a live bid updates. Declaring the intent in a comment is not enough,
   * so the variant travels with the token.
   */
  price: {
    family: font.bodyBold,
    size: 20,
    lineHeight: 24,
    letterSpacing: 0,
    uppercase: false,
    fontVariant: ['tabular-nums'] as const,
  },
} as const;

/** Motion. Everything collapses under the OS reduced-motion setting. */
export const motion = {
  instant: 90,
  swift: 180,
  settle: 280,
  /**
   * The brand's easing. `easingCss` is for web consumers; React Native's
   * Animated and Reanimated take the four control points, not a CSS string, so
   * both forms are published and neither call site has to guess.
   */
  easingCss: 'cubic-bezier(0.22, 1, 0.36, 1)',
  easingBezier: [0.22, 1, 0.36, 1] as const,
} as const;

/**
 * Image aspect ratios, expressed as width / height.
 *
 * 4:5 (0.8) is the target for NEW venue artwork because nightlife flyers are made
 * portrait for Instagram. It is NOT a retroactive migration: the mobile picker
 * historically cropped destructively to 16:9, so portrait pixels for existing
 * listings were never stored. Legacy assets use `legacyLandscape` and the fit
 * behaviour in the media layer. See `docs/product-v2/EVENT_MEDIA_SYSTEM.md`.
 */
export const ratio = {
  portrait: 4 / 5,
  square: 1,
  featured: 3 / 2,
  landscape: 16 / 9,
  legacyLandscape: 16 / 9,
} as const;

export const brandTokens = {
  surface,
  text,
  brand,
  border,
  status,
  space,
  radius,
  font,
  type,
  motion,
  ratio,
} as const;

export type BrandTokens = typeof brandTokens;
