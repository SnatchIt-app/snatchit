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
 *   2. Starts with "http"   → already a full URL (legacy cover_image_url
 *      rows). Return as-is.
 *   3. Starts with "auction-media/" → accidental bucket-name prefix stored
 *      in old rows. Strip it so the path is bucket-root-relative.
 *   4. Otherwise → treat as a bucket-root-relative Storage object path and
 *      call getPublicUrl(path).
 *
 * No caching is needed: getPublicUrl is a pure URL construction (no fetch),
 * so it is effectively free to call on every render.
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

import { supabase } from '@/src/lib/supabase';

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
): string | null {
  if (!pathOrUrl) return null;

  // ── 1. Already an absolute URL (legacy cover_image_url rows) ─────────────
  if (pathOrUrl.startsWith('http')) return pathOrUrl;

  // ── 2. Strip accidental bucket-name prefix ────────────────────────────────
  // Some rows were stored as "auction-media/<userId>/…" instead of just
  // "<userId>/…". Strip so getPublicUrl receives a clean bucket-relative path.
  const BUCKET_PREFIX = `${BUCKET}/`;
  const cleanPath = pathOrUrl.startsWith(BUCKET_PREFIX)
    ? pathOrUrl.slice(BUCKET_PREFIX.length)
    : pathOrUrl;

  // ── 3. Build public URL (synchronous, zero-cost, no RLS required) ─────────
  const { data } = supabase.storage.from(BUCKET).getPublicUrl(cleanPath);
  return data.publicUrl ?? null;
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
): Promise<Map<string, string | null>> {
  const unique = [...new Set(paths.filter(Boolean))] as string[];
  const entries = unique.map((p) => [p, getCoverImageUrl(p)] as const);
  return new Map(entries);
}
