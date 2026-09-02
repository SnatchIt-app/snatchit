/**
 * src/lib/media/slots.ts — the named media slot system.
 *
 * WHY THIS EXISTS
 * Today one source asset is poured into six different container ratios across
 * three surfaces, discarding up to 58.5% of the image, with raw width and height
 * constants scattered through screens. A 9:16 nightlife flyer loses 71.7% of
 * itself in the home feed. Nothing decides which part survives.
 *
 * A slot is the single place that answers, for one usage: what shape is the box,
 * how wide is it really, what pixels should we request, do we crop or fit, and
 * what happens when the image is missing or wrong.
 *
 * RULE: screens reference a slot by name. No screen hard-codes an image width,
 * height or aspect ratio again.
 *
 * Evidence and rationale: `docs/product-v2/EVENT_MEDIA_SYSTEM.md`.
 */

import * as v2 from '@/src/theme/v2';

/**
 * How an image fills its frame.
 *
 * `cover` crops to the frame using the focal point. Correct for photography and
 * for artwork whose edges carry nothing.
 *
 * `fit` contains the whole image and fills the remaining area with a blurred,
 * scaled copy of the asset itself, edges feathered into it. Correct for a poster
 * whose lineup type runs to the edge. We never letterbox with black bars: the
 * blurred-self backdrop is what makes `fit` acceptable inside a uniform grid.
 */
export type FitMode = 'cover' | 'fit';

export interface SlotSpec {
  /** width / height. */
  aspectRatio: number;
  /** Layout width in points at the base (1x) size, per breakpoint. */
  layoutWidth: { mobile: number; tablet: number; web: number };
  /** Default fill behaviour when the asset does not declare one. */
  defaultFit: FitMode;
  /** Corner radius. The brand is square; this is 0 everywhere by design. */
  radius: number;
  /** Whether text is placed over this image, which forces a scrim. */
  scrim: 'none' | 'bottom' | 'strong';
  /** Whether the slot should be preloaded. Only true where it is the LCP element. */
  preload: boolean;
}

export const MEDIA_SLOTS = {
  /** The feed unit. Text sits BELOW the image, never on it. */
  DISCOVERY_CARD: {
    aspectRatio: v2.ratio.portrait,
    layoutWidth: { mobile: 168, tablet: 220, web: 260 },
    defaultFit: 'cover',
    radius: v2.radius.none,
    scrim: 'none',
    preload: false,
  },
  /** One per rail. Title and date sit over the image, so it needs a scrim. */
  FEATURED_EVENT: {
    aspectRatio: v2.ratio.featured,
    layoutWidth: { mobile: 360, tablet: 640, web: 880 },
    defaultFit: 'cover',
    radius: v2.radius.none,
    scrim: 'strong',
    preload: true,
  },
  /** The event detail hero. The LCP element on that screen. */
  EVENT_HERO: {
    aspectRatio: v2.ratio.portrait,
    layoutWidth: { mobile: 390, tablet: 768, web: 560 },
    defaultFit: 'fit',
    radius: v2.radius.none,
    scrim: 'bottom',
    preload: true,
  },
  /** Only rendered when an event carries more than one asset. */
  EVENT_GALLERY: {
    aspectRatio: v2.ratio.portrait,
    layoutWidth: { mobile: 300, tablet: 340, web: 380 },
    defaultFit: 'fit',
    radius: v2.radius.none,
    scrim: 'none',
    preload: false,
  },
  VENUE_HERO: {
    aspectRatio: v2.ratio.landscape,
    layoutWidth: { mobile: 390, tablet: 768, web: 1080 },
    defaultFit: 'cover',
    radius: v2.radius.none,
    scrim: 'bottom',
    preload: false,
  },
  /**
   * Checkout currently shows NO image at all on either client, which is the
   * point in the funnel where a buyer most needs to see what they are buying.
   */
  CHECKOUT_THUMBNAIL: {
    aspectRatio: v2.ratio.square,
    layoutWidth: { mobile: 72, tablet: 88, web: 96 },
    defaultFit: 'cover',
    radius: v2.radius.none,
    scrim: 'none',
    preload: false,
  },
  /** A strip on the ticket. The credential is the hero here, not the artwork. */
  TICKET_ART: {
    aspectRatio: v2.ratio.landscape,
    layoutWidth: { mobile: 390, tablet: 560, web: 560 },
    defaultFit: 'cover',
    radius: v2.radius.none,
    scrim: 'strong',
    preload: false,
  },
  /** Dense list. Recognition, not persuasion. */
  SEARCH_RESULT: {
    aspectRatio: v2.ratio.square,
    layoutWidth: { mobile: 64, tablet: 72, web: 80 },
    defaultFit: 'cover',
    radius: v2.radius.none,
    scrim: 'none',
    preload: false,
  },
  /** An operator scanning a list of events. */
  DASHBOARD_THUMBNAIL: {
    aspectRatio: v2.ratio.square,
    layoutWidth: { mobile: 44, tablet: 48, web: 56 },
    defaultFit: 'cover',
    radius: v2.radius.none,
    scrim: 'none',
    preload: false,
  },
  /** Rendered server-side with the wordmark. Dark rail; specified, not built. */
  PROMOTER_SHARE: {
    aspectRatio: v2.ratio.square,
    layoutWidth: { mobile: 1080, tablet: 1080, web: 1080 },
    defaultFit: 'cover',
    radius: v2.radius.none,
    scrim: 'none',
    preload: false,
  },
} as const satisfies Record<string, SlotSpec>;

export type MediaSlotName = keyof typeof MEDIA_SLOTS;
export type Breakpoint = 'mobile' | 'tablet' | 'web';

/** Layout height derived from the slot's width and ratio. Never hard-code it. */
export function slotHeight(slot: MediaSlotName, breakpoint: Breakpoint = 'mobile'): number {
  const spec = MEDIA_SLOTS[slot];
  return Math.round(spec.layoutWidth[breakpoint] / spec.aspectRatio);
}

/**
 * The pixel width to request from the CDN.
 *
 * Two rules, both taken from measured benchmark behaviour:
 *  - The requested width IS the layout width times density, not an approximation
 *    of it. Requesting a round number that is near the box wastes bytes.
 *  - Density is capped at 2. Beyond 2x the visible gain does not pay for the
 *    bytes on a phone.
 */
export function slotPixelWidth(
  slot: MediaSlotName,
  breakpoint: Breakpoint = 'mobile',
  devicePixelRatio = 2,
): number {
  const dpr = Math.min(Math.max(devicePixelRatio, 1), 2);
  return Math.round(MEDIA_SLOTS[slot].layoutWidth[breakpoint] * dpr);
}

/**
 * Quality scales INVERSELY with density, which holds the byte count roughly flat
 * as pixels double. This is a measured benchmark behaviour, not a guess: a 2x
 * asset at half the quality is visually indistinguishable at arm's length and
 * costs about the same to deliver as the 1x asset at full quality.
 */
export function slotQuality(devicePixelRatio = 2): number {
  return devicePixelRatio >= 2 ? 45 : 80;
}
