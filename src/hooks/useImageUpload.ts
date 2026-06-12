/**
 * src/hooks/useImageUpload.ts
 *
 * Image-pick → upload → public-URL pipeline for Supabase Storage
 * bucket "auction-media".
 *
 * WHY WE USE fetch → arrayBuffer() INSTEAD OF fetch → blob()
 * ────────────────────────────────────────────────────────────
 * On React Native / Hermes, fetch(localUri).blob() returns a zero-byte
 * Blob for local "file://" / "ph://" URIs because the JS fetch API is not
 * wired to the native filesystem in Hermes.
 *
 * expo-file-system's readAsStringAsync with EncodingType.Base64 was tried
 * next, but FileSystem.EncodingType is undefined in the installed version,
 * causing a runtime crash: "Cannot read property 'Base64' of undefined".
 *
 * The working fix: fetch(uri).arrayBuffer() — React Native's fetch polyfill
 * does support arrayBuffer() on local URIs in Expo SDK 50+. We then wrap the
 * result in a Uint8Array and pass it directly to supabase.storage.upload().
 * Supabase JS accepts any ArrayBufferView.
 *
 * Storage path convention:
 *   <userId>/<folder>/<timestamp>.<ext>
 *   e.g. "abc-uuid/covers/1715000000000.jpg"
 *
 * Usage:
 *   const cover = useImageUpload({ userId, folder: 'covers' });
 *   await cover.pickImage();                     // open picker
 *   const storagePath = await cover.uploadImage(); // upload
 */

import * as ImagePicker from 'expo-image-picker';
import { useCallback, useState } from 'react';
import { Alert } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { validateImage } from '@/src/utils/validateImage';

// ─── Types ────────────────────────────────────────────────────────────────────

export type UploadStatus = 'idle' | 'picking' | 'ready' | 'uploading' | 'done' | 'error';

export type UseImageUploadOptions = {
  /** Supabase auth user ID — used as the top-level storage folder. */
  userId: string;
  /** Sub-folder within the user's directory, e.g. "covers" | "proofs". */
  folder: string;
  /** Crop aspect ratio. Defaults to [16, 9]. Pass null to skip crop. */
  aspect?: [number, number] | null;
  /** JPEG quality 0–1. Defaults to 0.85. */
  quality?: number;
  /**
   * Storage bucket. Defaults to the public 'auction-media' bucket.
   * Proof-of-ownership uploads use the PRIVATE 'proof-docs' bucket
   * (migration 033) so proof screenshots are never publicly fetchable —
   * only the owner (RLS) and admin review (service role) can read them.
   */
  bucket?: 'auction-media' | 'proof-docs';
};

export type UseImageUploadReturn = {
  localUri:    string | null;
  publicUrl:   string | null;
  storagePath: string | null;
  status:      UploadStatus;
  error:       string | null;
  busy:        boolean;
  pickImage:   () => Promise<void>;
  uploadImage: () => Promise<string | null>;
  reset:       () => void;
};

// ─── Hook ─────────────────────────────────────────────────────────────────────

export function useImageUpload({
  userId,
  folder,
  aspect  = [16, 9],
  quality = 0.85,
  bucket  = 'auction-media',
}: UseImageUploadOptions): UseImageUploadReturn {
  const [localUri,    setLocalUri]    = useState<string | null>(null);
  const [publicUrl,   setPublicUrl]   = useState<string | null>(null);
  const [storagePath, setStoragePath] = useState<string | null>(null);
  const [status,      setStatus]      = useState<UploadStatus>('idle');
  const [error,       setError]       = useState<string | null>(null);

  // ── pickImage ───────────────────────────────────────────────────────────────

  const pickImage = useCallback(async () => {
    setStatus('picking');
    setError(null);

    const { status: permStatus } =
      await ImagePicker.requestMediaLibraryPermissionsAsync();

    if (permStatus !== 'granted') {
      setStatus(localUri ? 'ready' : 'idle');
      Alert.alert(
        'Permission required',
        'SnatchIt needs access to your photo library. Enable it in Settings.',
        [{ text: 'OK' }],
      );
      return;
    }

    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes:    ['images'],
      allowsEditing: aspect !== null,
      aspect:        aspect ?? undefined,
      quality,
      exif: false,
    });

    if (result.canceled || result.assets.length === 0) {
      setStatus(localUri ? 'ready' : 'idle');
      return;
    }

    const asset = result.assets[0];
    const check = validateImage(
      { uri: asset.uri, type: asset.mimeType ?? undefined, fileSize: asset.fileSize ?? undefined },
      'auction-media',
    );
    if (!check.valid) {
      setStatus(localUri ? 'ready' : 'idle');
      Alert.alert('Image too large or unsupported', check.error!);
      return;
    }

    setLocalUri(result.assets[0].uri);
    setPublicUrl(null);
    setStoragePath(null);
    setStatus('ready');
  }, [aspect, quality, localUri]);

  // ── uploadImage ─────────────────────────────────────────────────────────────

  const uploadImage = useCallback(async (): Promise<string | null> => {
    if (!localUri) {
      setError('No image selected.');
      setStatus('error');
      return null;
    }
    if (!userId) {
      setError('User is not authenticated.');
      setStatus('error');
      return null;
    }

    setStatus('uploading');
    setError(null);

    try {
      // Derive a safe file extension (fallback → jpg)
      const raw    = localUri.split('.').pop()?.toLowerCase() ?? 'jpg';
      const safeExt = ['jpg', 'jpeg', 'png', 'webp', 'heic'].includes(raw) ? raw : 'jpg';
      const mime    = `image/${safeExt === 'jpg' ? 'jpeg' : safeExt}`;

      // Storage path: <userId>/<folder>/<timestamp>.<ext>
      const path = `${userId}/${folder}/${Date.now()}.${safeExt}`;

      // ── READ BYTES VIA fetch → arrayBuffer (RN-safe) ────────────────────────
      // fetch(uri).blob()        → 0 bytes on Hermes (fetch not wired to FS)
      // FileSystem.EncodingType  → undefined crash in installed expo-file-system
      // fetch(uri).arrayBuffer() → works: Expo's fetch polyfill handles file:// URIs
      const res = await fetch(localUri);
      const arrayBuffer = await res.arrayBuffer();
      const bytes = new Uint8Array(arrayBuffer);

      // Guard: if bytes are still 0 something went wrong reading the file
      if (bytes.length === 0) {
        throw new Error(
          'File read returned 0 bytes. The image may be an iCloud-only asset ' +
          'not yet downloaded to the device — open it in Photos first.',
        );
      }

      // ── UPLOAD UINT8ARRAY TO SUPABASE ────────────────────────────────────────
      const { error: uploadError } = await supabase.storage
        .from(bucket)
        .upload(path, bytes, {
          contentType:  mime,
          upsert:       false,  // timestamp makes each path unique
          cacheControl: '3600',
        });

      if (uploadError) {
        console.error('[useImageUpload] upload error:', {
          message: uploadError.message,
          bucket,
          path,
        });
        throw new Error(uploadError.message);
      }

      // Public URL only exists for the public bucket. Private buckets
      // (proof-docs) return null — callers store the path only.
      if (bucket === 'auction-media') {
        const { data: urlData } = supabase.storage
          .from('auction-media')
          .getPublicUrl(path);
        setPublicUrl(urlData.publicUrl);
      } else {
        setPublicUrl(null);
      }

      setStoragePath(path);
      setStatus('done');
      return path;

    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Unknown upload error.';
      console.error('[useImageUpload] caught:', message);
      setError(message);
      setStatus('error');
      return null;
    }
  }, [localUri, userId, folder]);

  // ── reset ───────────────────────────────────────────────────────────────────

  const reset = useCallback(() => {
    setLocalUri(null);
    setPublicUrl(null);
    setStoragePath(null);
    setStatus('idle');
    setError(null);
  }, []);

  const busy = status === 'picking' || status === 'uploading';

  return { localUri, publicUrl, storagePath, status, error, busy,
           pickImage, uploadImage, reset };
}
