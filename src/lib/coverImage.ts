/**
 * src/lib/coverImage.ts
 *
 * Single source of truth for resolving a Supabase Storage path or URL
 * into a renderable image URL for the "auction-media" bucket.
 *
 * Strategy
 * ────────
 * The "auction-media" bucket is PUBLIC, so we use getPublicUrl — which:
 *   • Is synchronous (no network round-trip).
 *   • Requires zero Storage RLS policies.
 *   • Never returns null / never throws.
 *   • Works correctly with Expo Image's <Image source={{ uri }} />.
 *
 * Input cases handled:
 *   1. null / undefined / '' → return null  (caller shows placeholder).
 *   2. An absolute URL (legacy cover_image_url rows) → rendered ONLY if it is on
 *      a trusted host, and rewritten back into a bucket path when it points at
 *      our own storage so it gets the same treatment as every other image.
 *   3. Starts with "auction-media/" → accidental bucket-name prefix stored
 *      in old rows. Strip it so the path is bucket-root-relative.
 *   4. Otherwise → treat as a bucket-root-relative Storage object path.
 *
 * ONE POLICY, NOT TWO. The path encoding and the absolute-host allowlist live in
 * `src/lib/media/url.ts` and this file calls into them. It previously returned any
 * `http…` value verbatim, which let a database row choose which host the app made
 * requests to. Do not reintroduce a local URL builder here.
 *
 * No caching is needed: URL construction is pure (no fetch), so it is effectively
 * free to call on every render.
 *
 * Usage
 * ─────
 *   import { getCoverImageUrl, resolveCoverUrls } from '@/src/lib/coverImage';
 *
 *   // Single path (sync-safe inside async context):
 *   const url = await getCoverImageUrl(listing.cover_image_path);
 *
 *   // In JSX:
 *   {url ? <Image source={{ uri: url }} /> : <PlaceholderView />}
 *
 *   // Batch (home feed):
 *   const urlMap = await resolveCoverUrls(listings.map(l => l.cover_image_path));
 */

import { mediaUrlForStoredValue } from '@/src/lib/media/url';

const BUCKET = 'auction-media';

/**
 * Resolve a storage path (or already-absolute URL) to a renderable image URL.
 *
 * Accepts both `cover_image_path` (bucket-relative storage path) and
 * `cover_image_url` (absolute URL) column values.
 *
 * @param pathOrUrl  null / undefined / '' → returns null (show placeholder).
 * @returns          Public URL string for <Image source={{ uri }} />, or null.
 */
export function getCoverImageUrl(
  pathOrUrl: string | null | undefined,
  opts: { width?: number; devicePixelRatio?: number } = {},
): string | null {
  return mediaUrlForStoredValue(pathOrUrl, {
    bucket: BUCKET,
    width: opts.width,
    devicePixelRatio: opts.devicePixelRatio,
  });
}

/**
 * Resolve an array of storage paths to public URLs.
 * Returns a Map<rawInputValue, resolvedUrl | null> for O(1) lookup in render.
 *
 * Kept async to maintain the same call signature as before (callers use await).
 * The underlying work is now synchronous so this resolves instantly.
 */
export async function resolveCoverUrls(
  paths: (string | null | undefined)[],
  opts: { width?: number; devicePixelRatio?: number } = {},
): Promise<Map<string, string | null>> {
  const unique = [...new Set(paths.filter(Boolean))] as string[];
  const entries = unique.map((p) => [p, getCoverImageUrl(p, opts)] as const);
  return new Map(entries);
}
