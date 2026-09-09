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
 *
 * THIS IS THE ONLY MEDIA URL POLICY IN THE APP. `src/lib/coverImage.ts` routes
 * through it, so there is one encoder and one host rule rather than two that
 * disagree. Do not add a second sanitizer.
 *
 * TWO RULES THAT ARE SECURITY, NOT STYLE:
 *
 *  1. PATH SEGMENTS ARE ENCODED INDIVIDUALLY. `encodeURI` leaves `#`, `?`, `&`,
 *     `+` and `=` untouched, so a stored filename containing one of them either
 *     truncates into a fragment, swallows the transformation query string, or
 *     addresses a different object. Filenames come from user uploads, so this is
 *     reachable. `/` separators survive; every other reserved character does not.
 *
 *  2. ABSOLUTE URLS ARE ALLOWLISTED, NOT TRUSTED. `listings.cover_image_url` and
 *     `profiles.avatar_url` are legacy columns holding whole URLs, and their
 *     values are row data. Rendering an arbitrary host would let a row decide
 *     where the app makes requests, which leaks the viewer's IP and puts
 *     unreviewed imagery on screen. Only this project's own Supabase host is
 *     trusted, and a URL that points at its storage API is rewritten back into a
 *     bucket path so that legacy rows get transformations too.
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
      reason: 'no-path' | 'unsafe-path' | 'unsafe-host' | 'no-storage-base';
    };

/**
 * Read lazily rather than importing `supabaseUrl` from `src/lib/supabase`, which
 * would pull client construction into a pure URL module and into every test that
 * touches media. The variable name is deliberately the same one
 * `src/lib/supabase.ts:67` reads, so the two cannot drift.
 */
function storageBase(): string | null {
  const url =
    process.env.EXPO_PUBLIC_SUPABASE_URL ??
    process.env.NEXT_PUBLIC_SUPABASE_URL ??
    process.env.SUPABASE_URL ??
    null;
  return url ? `${url.replace(/\/$/, '')}/storage/v1` : null;
}

/** The origin of `storageBase()`, or null when no Supabase URL is configured. */
function storageOrigin(): string | null {
  const base = storageBase();
  if (!base) return null;
  const m = /^(https?:\/\/[^/]+)/i.exec(base);
  return m ? m[1].toLowerCase() : null;
}

/**
 * Hosts this app will render an absolute image URL from, beyond its own Supabase
 * project (which is always trusted and is added at runtime).
 *
 * Deliberately EMPTY. Snatch It serves every image it owns from its own storage.
 * Adding a host here is a decision about where the product will make requests on
 * a user's behalf, so it belongs in review, not in a row of the database.
 */
export const ADDITIONAL_TRUSTED_MEDIA_HOSTS: readonly string[] = [];

/** Whether an absolute URL may be rendered at all. */
export function isTrustedMediaUrl(value: string): boolean {
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    return false;
  }
  // No http:. A downgraded image request is a downgraded request.
  if (parsed.protocol !== 'https:') return false;
  const host = parsed.host.toLowerCase();
  const own = storageOrigin();
  if (own && `https://${host}` === own) return true;
  return ADDITIONAL_TRUSTED_MEDIA_HOSTS.includes(host);
}

/**
 * Percent-encodes one path segment, leaving an already-encoded segment alone.
 *
 * The idempotency check matters because some stored rows were written by an older
 * upload path that encoded before storing. Blindly re-encoding would turn `%20`
 * into `%2520` and 404 a working image; blindly decoding would corrupt a filename
 * that legitimately contains a percent sign.
 */
function encodeSegment(segment: string): string {
  if (!segment) return segment;
  try {
    const decoded = decodeURIComponent(segment);
    if (decoded !== segment && encodeURIComponent(decoded) === segment) return segment;
  } catch {
    // Not valid percent-encoding, so it is a literal. Fall through and encode it.
  }
  return encodeURIComponent(segment);
}

/**
 * Encodes a bucket-relative object path for use in a URL.
 *
 * `/` separates segments and survives. Everything else that is reserved —
 * `#`, `?`, `&`, `+`, `=`, space — is encoded, which `encodeURI` does not do.
 */
export function encodeStoragePath(path: string): string {
  return path.split('/').map(encodeSegment).join('/');
}

/**
 * If an absolute URL points at this project's own storage API, recover the bucket
 * and object path so the image can be transformed like any other. Returns null for
 * a trusted URL that is not a storage object (rendered as-is) and for anything on
 * an untrusted host (refused by the caller).
 */
export function parseOwnStorageUrl(
  value: string,
): { bucket: MediaBucket; path: string } | null {
  const own = storageOrigin();
  if (!own) return null;
  // Check the RAW value, before parsing. `new URL()` resolves `..` away, so a
  // stored `/auction-media/../avatars/x.png` would arrive here already looking
  // innocent and pointing at a different bucket.
  if (value.includes('..') || /%2e%2e/i.test(value)) return null;
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    return null;
  }
  if (`https://${parsed.host.toLowerCase()}` !== own) return null;
  const m = /^\/storage\/v1\/(?:object|render\/image)\/(?:public|sign)\/([^/]+)\/(.+)$/.exec(
    parsed.pathname,
  );
  if (!m) return null;
  const bucket = decodeURIComponent(m[1]) as MediaBucket;
  // The pathname arrives percent-encoded; decode to the stored form so the single
  // encoder below is the only thing that ever encodes it.
  let path: string;
  try {
    path = m[2].split('/').map((seg) => decodeURIComponent(seg)).join('/');
  } catch {
    path = m[2];
  }
  if (!path || path.includes('..')) return null;
  return { bucket, path };
}

/**
 * What a stored media value actually is. Every caller resolves through this, so
 * the path rules and the host rules are stated exactly once.
 */
export type StoredMedia =
  | { kind: 'path'; bucket: MediaBucket; path: string }
  | { kind: 'absolute'; uri: string }
  | { kind: 'unsafe'; reason: 'no-path' | 'unsafe-path' | 'unsafe-host' };

export function classifyStoredMedia(
  raw: string | null | undefined,
  bucket: MediaBucket,
): StoredMedia {
  if (!raw || !raw.trim()) return { kind: 'unsafe', reason: 'no-path' };
  const value = raw.trim();

  if (/^[a-z][a-z0-9+.-]*:/i.test(value)) {
    // A scheme of any kind: only https, only on a trusted host.
    if (!isTrustedMediaUrl(value)) return { kind: 'unsafe', reason: 'unsafe-host' };
    const own = parseOwnStorageUrl(value);
    if (own) {
      // A row may not redirect a read into a different bucket than the caller
      // asked for. Both buckets are public today, so this is not a data leak —
      // it is a row deciding which bucket the product reads from, which is the
      // caller's decision, not the data's.
      if (own.bucket !== bucket) return { kind: 'unsafe', reason: 'unsafe-path' };
      return { kind: 'path', bucket: own.bucket, path: own.path };
    }
    return { kind: 'absolute', uri: value };
  }

  // Protocol-relative (`//host/x`) is an absolute URL wearing a disguise.
  if (value.startsWith('//')) return { kind: 'unsafe', reason: 'unsafe-host' };

  const path = normalizePath(value, bucket);
  if (!path) return { kind: 'unsafe', reason: 'unsafe-path' };
  return { kind: 'path', bucket, path };
}

/**
 * Normalizes a stored value into a bucket-relative object path.
 * Returns null for anything we must not render.
 *
 * RELATIVE PATHS ONLY. An absolute URL is a host decision, not a path decision,
 * and is handled by `classifyStoredMedia`. This used to return the absolute URL
 * unchanged, which is how an arbitrary host reached the renderer.
 */
export function normalizePath(raw: string | null | undefined, bucket: MediaBucket): string | null {
  if (!raw) return null;
  const value = raw.trim();
  if (!value) return null;
  // Traversal would normalize away the bucket prefix and reach another bucket.
  if (value.includes('..')) return null;
  if (/^[a-z][a-z0-9+.-]*:/i.test(value) || value.startsWith('//')) return null;
  // Some old rows stored the bucket name as a prefix.
  const prefix = `${bucket}/`;
  const stripped = value.startsWith(prefix) ? value.slice(prefix.length) : value;
  return stripped.replace(/^\/+/, '') || null;
}

/**
 * Builds a Supabase image-transformation URL.
 *
 * NOTE ON `resize`: it only takes effect when BOTH width and height are given.
 * With a width alone the image is scaled proportionally and `resize` is inert.
 * That is deliberate here: the slot frame does the cropping on the client via
 * `contentFit`, and the server's job is only to stop shipping a multi-megabyte
 * original. The parameter is still sent so that adding a height later changes
 * behaviour in one place rather than everywhere.
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
  return `${base}/render/image/public/${bucket}/${encodeStoragePath(path)}?${q.toString()}`;
}

/** The plain, untransformed public URL. Used only as a last resort. */
export function publicUrl(base: string, bucket: MediaBucket, path: string): string {
  return `${base}/object/public/${bucket}/${encodeStoragePath(path)}`;
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
  opts: {
    breakpoint?: Breakpoint;
    devicePixelRatio?: number;
    /** The real laid-out width, when the caller overrides the slot default. */
    layoutWidth?: number;
  } = {},
): ResolvedImage {
  const breakpoint = opts.breakpoint ?? 'mobile';
  const dpr = opts.devicePixelRatio ?? 2;
  const bucket = asset.bucket ?? 'auction-media';
  const spec = MEDIA_SLOTS[slot];

  const base = storageBase();
  if (!base) return { kind: 'fallback', reason: 'no-storage-base' };

  const stored = classifyStoredMedia(asset.path, bucket);
  if (stored.kind === 'unsafe') return { kind: 'fallback', reason: stored.reason };

  const width = slotPixelWidth(slot, breakpoint, dpr, opts.layoutWidth);
  const quality = slotQuality(dpr);

  const contract = asset.contract ?? 'legacy';
  const slotIsPortrait = spec.aspectRatio < 1;
  const legacyInPortraitSlot = contract === 'legacy' && slotIsPortrait;
  const fit: FitMode = legacyInPortraitSlot ? 'fit' : (asset.fit ?? spec.defaultFit);

  // A trusted absolute URL that is not one of our own storage objects cannot be
  // transformed, so it renders as-is. Anything that IS one of ours was rewritten
  // back into a bucket path by the classifier and gets a slot-sized derivative
  // like every other image, which is what pulls legacy `cover_image_url` rows
  // into the transformation pipeline instead of stranding them on originals.
  const uri =
    stored.kind === 'absolute'
      ? stored.uri
      : transformUrl({
          base,
          bucket: stored.bucket,
          path: stored.path,
          width,
          quality,
          resize: fit === 'cover' ? 'cover' : 'contain',
        });

  // The backdrop is a deliberately tiny copy of the SAME artwork. It is never a
  // generated or invented image: the original always remains visible on top.
  const backdropUri =
    stored.kind === 'absolute'
      ? stored.uri
      : transformUrl({
          base,
          bucket: stored.bucket,
          path: stored.path,
          width: 32,
          quality: 30,
          resize: 'cover',
        });

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

/**
 * The single resolver for a stored media value outside the slot system.
 *
 * `resolveImage` is for artwork rendered through `EventMedia`, where a slot
 * dictates the geometry. This is for the legacy call sites that hold a raw column
 * value and their own layout — `src/lib/coverImage.ts` and avatars — so that they
 * get the same encoder and the same host allowlist rather than a second policy.
 *
 * Pass `width` and the device pixel ratio to receive a transformed derivative.
 * Without a width it returns the plain object URL, which is the pre-existing
 * behaviour and stays the default so that adopting transformations is a decision
 * a call site makes deliberately, with a width it can actually justify.
 */
export function mediaUrlForStoredValue(
  raw: string | null | undefined,
  opts: {
    bucket?: MediaBucket;
    /** Layout width in POINTS. Omit to get the untransformed object URL. */
    width?: number;
    devicePixelRatio?: number;
    quality?: number;
    resize?: 'cover' | 'contain';
  } = {},
): string | null {
  const bucket = opts.bucket ?? 'auction-media';
  const base = storageBase();
  if (!base) return null;

  const stored = classifyStoredMedia(raw, bucket);
  if (stored.kind === 'unsafe') return null;
  if (stored.kind === 'absolute') return stored.uri;

  if (opts.width == null) {
    return publicUrl(base, stored.bucket, stored.path);
  }

  const dpr = Math.min(Math.max(opts.devicePixelRatio ?? 2, 1), 2);
  return transformUrl({
    base,
    bucket: stored.bucket,
    path: stored.path,
    width: Math.round(opts.width * dpr),
    quality: opts.quality ?? slotQuality(dpr),
    resize: opts.resize ?? 'cover',
  });
}
