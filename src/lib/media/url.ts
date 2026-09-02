/**
 * src/lib/media/url.ts — the one place a renderable image URL is built.
 *
 * WHAT IS WRONG TODAY, and what this fixes:
 *  - Zero image transformations exist anywhere in the repository. Width, quality
 *    and format parameters appear zero times. The largest live object is
 *    6,361,057 bytes and it is shipped whole into a 358x180 point card.
 *  - `web/src/lib/format.ts:coverImageUrl` returns a bucket DIRECTORY URL when the
 *    path is missing, which then reaches `next/image` with `priority` and is
 *    emitted into OpenGraph and JSON-LD. A missing image is published as a broken
 *    one.
 *  - Uploads set `cacheControl: '3600'` on immutable timestamped paths, which is
 *    wrong by a factor of 8,760.
 *
 * SAFETY POSTURE
 * `resolveImage` returns a discriminated result. There is no "return something
 * that looks like a URL and hope". A caller that cannot render must be told so it
 * can draw the branded fallback instead.
 */

import {
  MEDIA_SLOTS,
  slotPixelWidth,
  slotQuality,
  type Breakpoint,
  type FitMode,
  type MediaSlotName,
} from './slots';

/** One year, immutable. Upload paths are timestamped, so the object never changes. */
export const IMMUTABLE_CACHE_CONTROL = '31536000, immutable';

export type MediaBucket = 'auction-media' | 'event-media' | 'avatars';

/**
 * Which media contract an asset was stored under.
 *
 * `legacy` assets went through the old mobile picker, which cropped DESTRUCTIVELY
 * to 16:9 before upload. Their portrait pixels were never stored and cannot be
 * recovered. They must never be re-cropped into a portrait frame; they are fitted
 * instead. This is why the V2 4:5 master is a target for new artwork rather than
 * a retroactive migration.
 *
 * `v2` assets are uploaded under the 4:5 contract with a focal point.
 */
export type MediaContract = 'legacy' | 'v2';

export interface FocalPoint {
  /** 0..1 from the left. */
  x: number;
  /** 0..1 from the top. Defaults above centre: flyers put the headline act high. */
  y: number;
}

export const DEFAULT_FOCAL: FocalPoint = { x: 0.5, y: 0.4 };

export interface MediaAsset {
  /** Bucket-relative storage path, or an absolute URL for very old rows. */
  path: string | null | undefined;
  bucket?: MediaBucket;
  contract?: MediaContract;
  focal?: FocalPoint;
  /** Uploader's choice. Falls back to the slot default. */
  fit?: FitMode;
}

export type ResolvedImage =
  | {
      kind: 'image';
      uri: string;
      /** A tiny blurred copy for the `fit` backdrop and for placeholder use. */
      backdropUri: string;
      width: number;
      height: number;
      fit: FitMode;
      focal: FocalPoint;
    }
  | {
      kind: 'fallback';
      /** Why there is no image. Surfaced in dev, never to a customer. */
      reason: 'no-path' | 'unsafe-path' | 'no-storage-base';
    };

function storageBase(): string | null {
  const url =
    process.env.EXPO_PUBLIC_SUPABASE_URL ??
    process.env.NEXT_PUBLIC_SUPABASE_URL ??
    process.env.SUPABASE_URL ??
    null;
  return url ? `${url.replace(/\/$/, '')}/storage/v1` : null;
}

/**
 * Normalizes a stored value into a bucket-relative object path.
 * Returns null for anything we must not render.
 */
export function normalizePath(raw: string | null | undefined, bucket: MediaBucket): string | null {
  if (!raw) return null;
  const value = raw.trim();
  if (!value) return null;
  // Traversal would normalize away the bucket prefix and reach another bucket.
  if (value.includes('..')) return null;
  if (/^https?:\/\//i.test(value)) return value;
  // Some old rows stored the bucket name as a prefix.
  const prefix = `${bucket}/`;
  const stripped = value.startsWith(prefix) ? value.slice(prefix.length) : value;
  return stripped.replace(/^\/+/, '') || null;
}

/**
 * Builds a Supabase image-transformation URL.
 *
 * `resize=cover` crops to the requested box; `resize=contain` fits inside it. We
 * only ever request a WIDTH, letting height follow the requested resize mode and
 * the slot's own aspect box, because asking for both can produce a second crop we
 * did not author.
 */
export function transformUrl(params: {
  base: string;
  bucket: MediaBucket;
  path: string;
  width: number;
  quality: number;
  resize: 'cover' | 'contain';
}): string {
  const { base, bucket, path, width, quality, resize } = params;
  const q = new URLSearchParams({
    width: String(width),
    quality: String(quality),
    resize,
  });
  return `${base}/render/image/public/${bucket}/${encodeURI(path)}?${q.toString()}`;
}

/** The plain, untransformed public URL. Used only as a last resort. */
export function publicUrl(base: string, bucket: MediaBucket, path: string): string {
  return `${base}/object/public/${bucket}/${encodeURI(path)}`;
}

/**
 * Resolve an asset for a slot. This is the function screens call.
 *
 * A legacy (16:9) asset placed in a portrait slot is FITTED, never re-cropped,
 * because its portrait pixels never existed.
 */
export function resolveImage(
  asset: MediaAsset,
  slot: MediaSlotName,
  opts: { breakpoint?: Breakpoint; devicePixelRatio?: number } = {},
): ResolvedImage {
  const breakpoint = opts.breakpoint ?? 'mobile';
  const dpr = opts.devicePixelRatio ?? 2;
  const bucket = asset.bucket ?? 'auction-media';
  const spec = MEDIA_SLOTS[slot];

  const base = storageBase();
  if (!base) return { kind: 'fallback', reason: 'no-storage-base' };

  const raw = asset.path;
  if (!raw || !raw.trim()) return { kind: 'fallback', reason: 'no-path' };

  const path = normalizePath(raw, bucket);
  if (!path) return { kind: 'fallback', reason: 'unsafe-path' };

  const width = slotPixelWidth(slot, breakpoint, dpr);
  const quality = slotQuality(dpr);

  const contract = asset.contract ?? 'legacy';
  const slotIsPortrait = spec.aspectRatio < 1;
  const legacyInPortraitSlot = contract === 'legacy' && slotIsPortrait;
  const fit: FitMode = legacyInPortraitSlot ? 'fit' : (asset.fit ?? spec.defaultFit);

  // An absolute legacy URL cannot be transformed; render it as-is rather than
  // fabricating a transformation endpoint for a host we do not control.
  const isAbsolute = /^https?:\/\//i.test(path);
  const uri = isAbsolute
    ? path
    : transformUrl({
        base,
        bucket,
        path,
        width,
        quality,
        resize: fit === 'cover' ? 'cover' : 'contain',
      });

  // The backdrop is a deliberately tiny copy of the SAME artwork. It is never a
  // generated or invented image: the original always remains visible on top.
  const backdropUri = isAbsolute
    ? path
    : transformUrl({ base, bucket, path, width: 32, quality: 30, resize: 'cover' });

  return {
    kind: 'image',
    uri,
    backdropUri,
    width,
    height: Math.round(width / spec.aspectRatio),
    fit,
    focal: asset.focal ?? DEFAULT_FOCAL,
  };
}

/** `object-position` for the web, derived from the focal point. */
export function focalToObjectPosition(focal: FocalPoint = DEFAULT_FOCAL): string {
  const pct = (n: number) => `${Math.round(Math.min(Math.max(n, 0), 1) * 100)}%`;
  return `${pct(focal.x)} ${pct(focal.y)}`;
}
