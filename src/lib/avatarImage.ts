/**
 * src/lib/avatarImage.ts
 *
 * Avatar upload + URL resolution for the "avatars" bucket.
 *
 * Bucket : avatars  (PUBLIC — getPublicUrl, no RLS policies needed)
 * Path   : <userId>/avatar_<timestamp>.<ext>
 *
 * WHY WE USE fetch → arrayBuffer() INSTEAD OF fetch → blob()
 * ────────────────────────────────────────────────────────────
 * On React Native / Hermes, fetch(localUri).blob() returns a zero-byte
 * Blob for local "file://" / "ph://" URIs because Hermes does not wire
 * fetch() to the native filesystem. This caused every avatar upload to
 * land in Supabase Storage as a 0-byte object.
 *
 * expo-file-system's readAsStringAsync was tried next, but FileSystem.EncodingType
 * is undefined in the installed version, causing a runtime crash.
 *
 * Fix: fetch(uri).arrayBuffer() — Expo's fetch polyfill supports arrayBuffer()
 * on local file:// URIs. We wrap the result in Uint8Array and pass to Supabase.
 *
 * SQL required on public.profiles (run once):
 *   ALTER TABLE public.profiles
 *     ADD COLUMN IF NOT EXISTS avatar_path TEXT;
 */

import * as ImagePicker from 'expo-image-picker';
import { Alert } from 'react-native';

import { IMMUTABLE_CACHE_CONTROL, mediaUrlForStoredValue } from '@/src/lib/media/url';
import { supabase } from '@/src/lib/supabase';
import { validateImage } from '@/src/utils/validateImage';

// ─── Constants ────────────────────────────────────────────────────────────────

const BUCKET = 'avatars'; // must match bucket name in Supabase dashboard exactly

// ─── URL resolver ─────────────────────────────────────────────────────────────

/**
 * Convert an avatar storage path to a renderable URL.
 *
 * - null / empty → null  (caller renders initials placeholder)
 * - an absolute URL (legacy `profiles.avatar_url` rows) → rendered only if it is
 *   on a trusted host; one of our own storage URLs is rewritten to a bucket path
 * - path string  → public URL, or a transformed derivative when a width is given
 *
 * Routed through `src/lib/media/url.ts` so avatars obey the same path encoding and
 * the same host allowlist as event artwork. There is one media policy.
 */
export function getAvatarUrl(
  path: string | null | undefined,
  opts: { width?: number; devicePixelRatio?: number } = {},
): string | null {
  return mediaUrlForStoredValue(path, {
    bucket: BUCKET,
    width: opts.width,
    devicePixelRatio: opts.devicePixelRatio,
  });
}

// ─── Upload result type ───────────────────────────────────────────────────────

export type AvatarUploadResult =
  | { ok: true;  storagePath: string; publicUrl: string }
  | { ok: false; error: string };

// ─── Upload pipeline ──────────────────────────────────────────────────────────

/**
 * Full avatar pick → upload → public-URL pipeline.
 *
 * 1. Requests photo library permission.
 * 2. Opens image picker with square 1:1 crop.
 * 3. Reads file bytes via fetch(uri).arrayBuffer() → Uint8Array (RN-safe).
 * 4. Uploads Uint8Array directly to Supabase Storage.
 * 5. Returns { ok: true, storagePath, publicUrl } on success.
 * 6. Returns { ok: false, error } on any failure (never throws).
 */
export async function pickAndUploadAvatar(
  userId: string,
): Promise<AvatarUploadResult> {
  // ── 1. Permission ────────────────────────────────────────────────────────
  const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (status !== 'granted') {
    Alert.alert(
      'Permission required',
      'SnatchIt needs photo library access to update your avatar. Enable it in Settings.',
      [{ text: 'OK' }],
    );
    return { ok: false, error: 'Permission denied.' };
  }

  // ── 2. Pick image (square crop) ──────────────────────────────────────────
  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes:    ['images'],
    allowsEditing: true,
    aspect:        [1, 1],
    quality:       0.85,
    exif:          false,
  });

  if (result.canceled || result.assets.length === 0) {
    return { ok: false, error: 'Cancelled.' };
  }

  const asset    = result.assets[0];
  const localUri = asset.uri;

  // ── 2b. Validate image size & type ─────────────────────────────────────
  const check = validateImage(
    { uri: localUri, type: asset.mimeType ?? undefined, fileSize: asset.fileSize ?? undefined },
    'avatars',
  );
  if (!check.valid) {
    Alert.alert('Image too large or unsupported', check.error!);
    return { ok: false, error: check.error! };
  }

  // ── 3. Build storage path ─────────────────────────────────────────────────
  const ext     = localUri.split('.').pop()?.toLowerCase() ?? 'jpg';
  const safeExt = ['jpg', 'jpeg', 'png', 'webp', 'heic'].includes(ext) ? ext : 'jpg';
  const mime    = `image/${safeExt === 'jpg' ? 'jpeg' : safeExt}`;
  const path    = `${userId}/avatar_${Date.now()}.${safeExt}`;

  // ── 4. Read file bytes via fetch → arrayBuffer (RN-safe) ─────────────────
  // fetch(uri).blob()        → 0 bytes on Hermes (fetch not wired to FS)
  // FileSystem.EncodingType  → undefined crash in installed expo-file-system
  // fetch(uri).arrayBuffer() → works: Expo's fetch polyfill handles file:// URIs
  let bytes: Uint8Array;
  try {
    const res         = await fetch(localUri);
    const arrayBuffer = await res.arrayBuffer();
    bytes             = new Uint8Array(arrayBuffer);
  } catch (readErr) {
    const msg = readErr instanceof Error ? readErr.message : String(readErr);
    console.error('[avatarImage] fetch/arrayBuffer read failed:', msg);
    return { ok: false, error: `Could not read image file: ${msg}` };
  }

  // Guard: 0 bytes means the file wasn't readable (e.g. iCloud stub not downloaded)
  if (bytes.length === 0) {
    return {
      ok:    false,
      error: 'Image file is empty or not yet downloaded to device. ' +
             'Try opening the photo in Photos first.',
    };
  }

  // ── 5. Upload Uint8Array to Supabase Storage ──────────────────────────────
  const { error: uploadError } = await supabase.storage
    .from(BUCKET)
    .upload(path, bytes, {
      contentType:  mime,
      upsert:       true,   // defensive; the timestamped path is already unique
      // Immutable: `avatar_<timestamp>.<ext>` is a new object on every change, and
      // the profile row points at the new path, so nothing needs to re-validate.
      cacheControl: IMMUTABLE_CACHE_CONTROL,
    });

  if (uploadError) {
    console.error('[avatarImage] upload error:', uploadError.message, 'path:', path);
    return { ok: false, error: uploadError.message };
  }

  // ── 6. Derive public URL (synchronous — public bucket) ────────────────────
  const { data: urlData } = supabase.storage.from(BUCKET).getPublicUrl(path);

  return { ok: true, storagePath: path, publicUrl: urlData.publicUrl };
}
