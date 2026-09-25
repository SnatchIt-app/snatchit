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
 * RULE: `layoutWidth` is a REFERENCE, not a layout. Real consumers pass their
 * measured width (`EventMedia fluid` does the measuring), because the nominal
 * mobile widths here overflow a 375pt device.
 *
 * Evidence and rationale: `docs/product-v2/EVENT_MEDIA_SYSTEM.md`.
 */

import { MEDIA_RADIUS, posterWidth, ROW_ART_RADIUS, ROW_ART_W } from '@/src/lib/design/featureMetrics';
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
  /**
   * REFERENCE width in points, per breakpoint. NOT a layout instruction.
   *
   * These are the widths the slot was designed against, and they are used only
   * when a caller has no measured width to give. They must never be trusted as a
   * layout: `mobile: 390` overflows a 375pt iPhone SE and 13 mini, and leaves a
   * 40pt dead margin on a 430pt Pro Max, and the two-up discovery grid needs 384pt
   * of a 375pt screen.
   *
   * Every real consumer passes its measured width — `EventMedia`'s `fluid` mode
   * measures it for you. See `slotPixelWidth`'s `overrideLayoutWidth`.
   */
  layoutWidth: { mobile: number; tablet: number; web: number };
  /** Default fill behaviour when the asset does not declare one. */
  defaultFit: FitMode;
  /**
   * Corner radius, always a `v2.radius` token.
   *
   * The V2 brand rule was 0 everywhere. V3 (owner 2026-09-24) replaces that blanket zero with a
   * scale, and on these slots it rounds exactly one shape: the 62pt feed-row thumbnail, at
   * `radius.md` — the scale's "row thumbnails" — because the owner's finding on the implemented
   * Home is that the thumbnails must read as ROUNDED, not square. Everything else here stays
   * square, including the two full-bleed V3 slots, whose artwork reaches all four screen edges and
   * would show canvas in the corners if it were rounded. The approved value per slot is pinned in
   * tests/product-v2-foundation.test.ts.
   */
  radius: number;
  /**
   * Whether text is placed over this image, which forces a scrim. `curve` is the V3 measured
   * curve (src/lib/design/scrim.ts): a 0.20 floor by 30% of the height, 0.97 at the baseline,
   * spanning the FULL image height — unlike the V2 partial bands.
   */
  scrim: 'none' | 'bottom' | 'strong' | 'curve';
  /** Whether the slot should be preloaded. Only true where it is the LCP element. */
  preload: boolean;
}

/**
 * THE 4:5 POSTER DIRECTION (owner 2026-09-24).
 *
 * Every slot that carries EVENT ARTWORK is a 4:5 portrait frame, because that is the shape the
 * artwork is made in: nightlife flyers are authored portrait for Instagram. Before this, one
 * poster was poured into four different container ratios — square thumbnails, a 16:9 ticket
 * strip, and two full-bleed landscape formulas — and each one decided for itself which part of
 * the poster to throw away.
 *
 * Three rules make this non-destructive, and they are the reason `defaultFit` is now `fit`
 * everywhere rather than `cover`:
 *  - Nothing is re-cropped. The stored object is never rewritten, and the derivative request is
 *    width-only, which makes Supabase's `resize` inert (see `transformUrl`) — the server returns
 *    the asset's own proportions, scaled.
 *  - Nothing is stretched. `fit` contains the whole poster and fills the slack with a blurred,
 *    scaled copy of the SAME artwork. A poster whose lineup type runs to the edge keeps every
 *    word of it.
 *  - An on-ratio 4:5 asset renders identically under `fit` and `cover` — it fills the frame
 *    exactly and the backdrop is never visible. So `fit` costs nothing where the shape already
 *    agrees, and protects the poster where it does not. That is why the guarantee is
 *    unconditional instead of depending on an asset's declared `contract`.
 *
 * THE LEGACY CONSEQUENCE, stated rather than hidden: the mobile picker historically cropped
 * uploads destructively to 16:9, so for those listings portrait pixels were never stored and
 * cannot be recovered. A legacy asset in a 4:5 frame is therefore a contained 16:9 band with the
 * blurred self-backdrop above and below it. That is the honest rendering of what exists; the
 * alternative would be inventing pixels or cropping the flyer.
 *
 * WHAT IS NOT AN EVENT POSTER, and so is not 4:5:
 *  - `VENUE_HERO` — a photograph of a room, not a poster. Photography has no edge information to
 *    protect, so it stays landscape and `cover`.
 *  - `DASHBOARD_THUMBNAIL` — the operator console (D's surface). No consumer screen renders it;
 *    changing another owner's geometry is not in this package's boundary.
 *  - `PROMOTER_SHARE` — a server-rendered share card at the square size the platforms crop to.
 *    Specified, not built.
 *
 * RADIUS BY ROLE (B's V3 table §4.1: rules 0 · media 8 · chrome 22 · dock 33 · full-bleed 0 ·
 * panels 0). Media frames take `MEDIA_RADIUS`. Three slots take 0 instead, and not because they
 * are exceptions to the scale — they are the "full-bleed 0" row of it: artwork that reaches the
 * screen edges would show canvas in its corners, and artwork clipped by a card's own corners
 * must not round twice.
 */
export const MEDIA_SLOTS = {
  /** The two-up feed card. Text sits BELOW the image, never on it. */
  DISCOVERY_CARD: {
    aspectRatio: v2.ratio.portrait,
    layoutWidth: { mobile: 168, tablet: 220, web: 260 },
    defaultFit: 'fit',
    radius: MEDIA_RADIUS,
    scrim: 'none',
    preload: false,
  },
  /** One per rail. Title and date sit over the image, so it needs a scrim. */
  FEATURED_EVENT: {
    aspectRatio: v2.ratio.portrait,
    layoutWidth: { mobile: 360, tablet: 640, web: 880 },
    defaultFit: 'fit',
    radius: MEDIA_RADIUS,
    scrim: 'strong',
    preload: true,
  },
  /** The V2 event detail hero. Full-bleed, so radius 0. */
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
    radius: MEDIA_RADIUS,
    scrim: 'none',
    preload: false,
  },
  /** A venue PHOTOGRAPH, not a poster — see the note above. Landscape, cropped to the frame. */
  VENUE_HERO: {
    aspectRatio: v2.ratio.landscape,
    layoutWidth: { mobile: 390, tablet: 768, web: 1080 },
    defaultFit: 'cover',
    radius: v2.radius.none,
    scrim: 'bottom',
    preload: false,
  },
  /**
   * The poster at the point of purchase — checkout, the order summary, the Bids row. This is
   * where a buyer most needs to see what they are buying, so it shows the whole poster.
   */
  CHECKOUT_THUMBNAIL: {
    aspectRatio: v2.ratio.portrait,
    // 72 / 88 / 96 were this thumbnail's SQUARE EDGE, which is the row's height budget. Left as
    // widths they would hand a caller that passes neither edge a 72 × 90 frame — 18pt taller than
    // the row it sits in. The reference width is the poster width for that height.
    layoutWidth: { mobile: posterWidth(72), tablet: posterWidth(88), web: posterWidth(96) },
    defaultFit: 'fit',
    radius: MEDIA_RADIUS,
    scrim: 'none',
    preload: false,
  },
  /**
   * The poster on the ticket card.
   *
   * Radius 0: it is flush with the card's top edge and the card clips it to the card's own corners
   * (`overflow: hidden` in TicketEventGroup), so rounding it here would draw a second, smaller arc
   * inside the first.
   *
   * SCRIM 'none' (changed with the poster direction, 2026-09-24). The rule for a scrim is "only
   * where text sits on the artwork", and nothing sits on this one: TICKET_ART's single consumer
   * renders `<EventMedia … />` self-closing and puts the title, date and venue in the card BODY
   * below the image. As a 16:9 strip the stray `strong` scrim dimmed the bottom ~125pt of a 193pt
   * band and passed unnoticed; as a 4:5 poster it would black out the bottom ~280pt of a ~430pt
   * poster to make nothing more legible. A scrim with no text over it is not a safety margin, it
   * is just darker artwork.
   */
  TICKET_ART: {
    aspectRatio: v2.ratio.portrait,
    layoutWidth: { mobile: 390, tablet: 560, web: 560 },
    defaultFit: 'fit',
    radius: v2.radius.none,
    scrim: 'none',
    preload: false,
  },
  /** Dense list. Recognition, not persuasion — but still the whole poster. */
  SEARCH_RESULT: {
    aspectRatio: v2.ratio.portrait,
    // Same correction as CHECKOUT_THUMBNAIL: 64 / 72 / 80 were the square edge, not a width.
    layoutWidth: { mobile: posterWidth(64), tablet: posterWidth(72), web: posterWidth(80) },
    defaultFit: 'fit',
    radius: MEDIA_RADIUS,
    scrim: 'none',
    preload: false,
  },
  /** The operator console (D's surface) — see the note above. Unused by any consumer screen. */
  DASHBOARD_THUMBNAIL: {
    aspectRatio: v2.ratio.square,
    layoutWidth: { mobile: 44, tablet: 48, web: 56 },
    defaultFit: 'cover',
    radius: MEDIA_RADIUS,
    scrim: 'none',
    preload: false,
  },
  /**
   * Home feature: a full-bleed 4:5 poster, and NO scrim.
   *
   * The §3 height FORMULA — (w − 40) × 0.49 + 34, a landscape band — is retired, because a formula
   * and a poster ratio cannot both decide the height and the owner's direction is the ratio.
   *
   * SCRIM 'none' (owner 2026-09-25): "Remove the gradient used to support the old text overlay."
   * The gradient was never decoration — it existed to darken a flyer's own printed type enough for
   * ours to sit on top of it. With the identity block moved beneath the poster there is nothing to
   * make legible, so the gradient would only be dimming the artwork the feature exists to show.
   * Note this is the same reasoning that took TICKET_ART's scrim off a day earlier; the rule is
   * that a scrim follows overlaid text, never a slot's size or importance.
   */
  HOME_FEATURE_V3: {
    aspectRatio: v2.ratio.portrait,
    layoutWidth: { mobile: 390, tablet: 768, web: 1080 },
    defaultFit: 'fit',
    radius: v2.radius.none,
    scrim: 'none',
    preload: true,
  },
  /**
   * Listing hero: a full-bleed 4:5 poster, and NO scrim.
   *
   * The w x 0.62 + 24 formula is retired for the same reason as the feature's — a formula and a
   * ratio cannot both decide the height.
   *
   * SCRIM 'none' (owner 2026-09-25): the identity block moved beneath the poster, so the gradient
   * that existed to make overlaid text readable has nothing left to make readable. The navigation
   * controls that remain over the artwork do not rely on it: `IconButton onArt` paints its own
   * rgba(0,0,0,0.55) chip. Third slot to lose a scrim on this rule — a scrim follows overlaid TEXT,
   * never a slot's size or importance.
   */
  LISTING_HERO_V3: {
    aspectRatio: v2.ratio.portrait,
    layoutWidth: { mobile: 390, tablet: 768, web: 560 },
    defaultFit: 'fit',
    radius: v2.radius.none,
    scrim: 'none',
    preload: true,
  },
  /**
   * V3 feed/search row artwork. The row keeps its approved HEIGHT of 62 and the poster ratio
   * derives the width (50), rather than the reverse: a 62-wide poster is 78 tall, which would
   * force the approved one-line row from 80pt to ~94pt and re-open the vertical rhythm of a feed
   * the owner has accepted. Text sits BESIDE it, so no scrim.
   */
  FEED_ROW_ART: {
    aspectRatio: v2.ratio.portrait,
    layoutWidth: { mobile: ROW_ART_W, tablet: ROW_ART_W, web: ROW_ART_W },
    defaultFit: 'fit',
    radius: ROW_ART_RADIUS,
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
  /**
   * The width the component is ACTUALLY laid out at, when it overrides the slot
   * default. Without this a 150pt card still requested the slot's 336px, and a
   * 140pt hero requested 780px, which defeats the whole point of the system.
   */
  overrideLayoutWidth?: number,
): number {
  const dpr = Math.min(Math.max(devicePixelRatio, 1), 2);
  const layout = overrideLayoutWidth ?? MEDIA_SLOTS[slot].layoutWidth[breakpoint];
  return Math.round(layout * dpr);
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
