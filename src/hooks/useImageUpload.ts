/**
 * src/hooks/useImageUpload.ts — pick one image and upload it to Supabase storage.
 *
 * F-IMG-1 (2026-09-18): the decisions live in src/lib/media/uploadFlow.ts (pure,
 * unit-tested); this hook wires the native picker, storage and alerts to them.
 *  - One picker at a time, with a visible 'picking' state; cancel, denial and a
 *    thrown picker error always end the picking state (1a, 1b). A final denial
 *    offers Open Settings (1g).
 *  - The stored type and extension come from the picked asset, not the file name
 *    (1h, B F3). The object name is fixed when the photo is picked, so a retry after a
 *    timeout or lost response targets the same object and "already exists" counts as
 *    uploaded (A ruling: a timeout is not proof of failure; no duplicate uploads).
 *  - An uploaded object is reused only for the same account, bucket/folder, reuseKey
 *    (e.g. the transfer) and selected file (1c). A failure keeps the selection and
 *    says what to do (1e). With a reuseKey the selection survives leaving the screen
 *    for the rest of the session (1f).
 *  - `readError()` returns the current error for callers that alert right after
 *    `uploadImage()` resolves (the rendered `error` is one render behind).
 *
 * Nothing here deletes an object: cleanup of unreferenced objects is server-side (A).
 */

import * as ImagePicker from 'expo-image-picker';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Linking } from 'react-native';

import {
  classifyUploadError, createPickGate, EmptyFileError, isAlreadyUploaded, objectPath, recallSelection, rememberSelection,
  resolveContentType, reusableUploadPath, runPick, UnsupportedTypeError, UPLOAD_COPY, UPLOAD_TIMEOUT_MS, uploadKey,
  withUploadTimeout, type UploadRecord,
} from '@/src/lib/media/uploadFlow';
import { IMMUTABLE_CACHE_CONTROL } from '@/src/lib/media/url';
import { supabase } from '@/src/lib/supabase';
import { validateImage } from '@/src/utils/validateImage';

export type UploadStatus = 'idle' | 'picking' | 'ready' | 'uploading' | 'done' | 'error';

export type UseImageUploadOptions = {
  userId: string;
  folder: string;
  aspect?: [number, number] | null;
  quality?: number;
  bucket?: 'auction-media' | 'proof-docs';
  /** Scope for reuse and for keeping the selection across a remount (e.g. the transfer id). */
  reuseKey?: string;
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
  readError:   () => string | null;
};

export function useImageUpload({
  userId,
  folder,
  aspect  = [16, 9],
  quality = 0.85,
  bucket  = 'auction-media',
  reuseKey,
}: UseImageUploadOptions): UseImageUploadReturn {
  const [localUri,    setLocalUri]    = useState<string | null>(null);
  const [publicUrl,   setPublicUrl]   = useState<string | null>(null);
  const [storagePath, setStoragePath] = useState<string | null>(null);
  const [status,      setStatusState] = useState<UploadStatus>('idle');
  const [error,       setErrorState]  = useState<string | null>(null);

  const gateRef = useRef(createPickGate());
  const statusRef = useRef<UploadStatus>('idle');
  const errorRef = useRef<string | null>(null);
  const selRef = useRef<{ uri: string | null; contentType: string | null; stamp: string | null }>({ uri: null, contentType: null, stamp: null });
  const recordRef = useRef<UploadRecord | null>(null);

  const setStatus = useCallback((s: UploadStatus) => { statusRef.current = s; setStatusState(s); }, []);
  const setError = useCallback((e: string | null) => { errorRef.current = e; setErrorState(e); }, []);
  const key = uploadKey({ userId, bucket, folder, reuseKey });

  const remember = useCallback(() => {
    const { uri, contentType, stamp } = selRef.current;
    if (!reuseKey || !userId) return;
    rememberSelection(key, uri && contentType && stamp ? { uri, contentType, stamp, record: recordRef.current } : null);
  }, [key, reuseKey, userId]);

  // 1f: a keyed selection made earlier this session comes back when the screen does.
  useEffect(() => {
    if (!reuseKey || !userId || selRef.current.uri) return;
    const r = recallSelection(key);
    if (!r) return;
    selRef.current = { uri: r.uri, contentType: r.contentType, stamp: r.stamp };
    recordRef.current = r.record;
    setLocalUri(r.uri);
    setStoragePath(r.record?.path ?? null);
    setStatus(r.record ? 'done' : 'ready');
  }, [key, reuseKey, userId, setStatus]);

  const pickImage = useCallback(async () => {
    const gate = gateRef.current;
    if (gate.inFlight) return;
    const prior = { status: statusRef.current, error: errorRef.current };
    setStatus('picking');
    const out = await runPick(gate, {
      requestPermission: async () => {
        const p = await ImagePicker.requestMediaLibraryPermissionsAsync();
        return { granted: p.status === 'granted', canAskAgain: p.canAskAgain };
      },
      launch: async () => {
        const r = await ImagePicker.launchImageLibraryAsync({
          mediaTypes: ['images'],
          allowsEditing: aspect !== null,
          aspect: aspect ?? undefined,
          quality,
          exif: false,
        });
        return r.canceled ? { canceled: true as const } : { canceled: false as const, assets: r.assets };
      },
      validate: (f) => validateImage(f, bucket),
    });
    if (out.kind === 'picked') {
      selRef.current = { uri: out.uri, contentType: out.contentType, stamp: out.stamp };
      recordRef.current = null;
      setLocalUri(out.uri);
      setPublicUrl(null);
      setStoragePath(null);
      setError(null);
      setStatus('ready');
      remember();
      return;
    }
    // Every other outcome restores what was there before the picker opened.
    setStatus(prior.status === 'picking' ? (selRef.current.uri ? 'ready' : 'idle') : prior.status);
    setError(prior.error);
    if (out.kind === 'denied') {
      Alert.alert('Photo access needed', UPLOAD_COPY.permission, out.canAskAgain
        ? [{ text: 'OK' }]
        : [{ text: 'Not now', style: 'cancel' }, { text: 'Open Settings', onPress: () => { void Linking.openSettings(); } }]);
    } else if (out.kind === 'invalid') {
      Alert.alert('Choose another photo', out.message);
    } else if (out.kind === 'error') {
      Alert.alert("Couldn't open your photos", out.message);
    }
  }, [aspect, quality, bucket, remember, setError, setStatus]);

  const uploadImage = useCallback(async (): Promise<string | null> => {
    const { uri, contentType: pickedType, stamp } = selRef.current;
    if (!localUri || !uri || !stamp) {
      setError(UPLOAD_COPY.noImage);
      setStatus('error');
      return null;
    }
    if (!userId) {
      setError(UPLOAD_COPY.notSignedIn);
      setStatus('error');
      return null;
    }
    const reused = reusableUploadPath(recordRef.current, uri, key);
    if (reused) {
      setStoragePath(reused);
      setError(null);
      setStatus('done');
      return reused;
    }
    setStatus('uploading');
    setError(null);
    try {
      const contentType = pickedType ?? resolveContentType(null, uri);
      if (!contentType) throw new UnsupportedTypeError();
      const path = objectPath({ userId, folder, stamp, contentType });
      const bytes = await withUploadTimeout((async () => {
        const res = await fetch(uri);
        return new Uint8Array(await res.arrayBuffer());
      })(), UPLOAD_TIMEOUT_MS);
      if (bytes.length === 0) throw new EmptyFileError();
      const { error: uploadError } = await withUploadTimeout(
        supabase.storage.from(bucket).upload(path, bytes, {
          contentType,
          upsert: false,   // the name is this selection's; "already exists" = an earlier attempt landed
          cacheControl: IMMUTABLE_CACHE_CONTROL,
        }),
        UPLOAD_TIMEOUT_MS,
      );
      if (uploadError && !isAlreadyUploaded(uploadError)) throw uploadError;
      if (bucket === 'auction-media') {
        setPublicUrl(supabase.storage.from('auction-media').getPublicUrl(path).data.publicUrl);
      } else {
        setPublicUrl(null);
      }
      recordRef.current = { key, uri, path };
      remember();
      setStoragePath(path);
      setStatus('done');
      return path;
    } catch (err: unknown) {
      const c = classifyUploadError(err);
      console.error('[useImageUpload] upload failed:', { kind: c.kind, bucket });
      setError(c.message);
      setStatus('error');   // the selection stays: Retry uses the same photo and the same object name
      return null;
    }
  }, [localUri, userId, folder, bucket, reuseKey, key, remember, setError, setStatus]);

  const reset = useCallback(() => {
    selRef.current = { uri: null, contentType: null, stamp: null };
    recordRef.current = null;
    if (reuseKey && userId) rememberSelection(key, null);
    setLocalUri(null);
    setPublicUrl(null);
    setStoragePath(null);
    setError(null);
    setStatus('idle');
  }, [key, reuseKey, userId, setError, setStatus]);

  const readError = useCallback(() => errorRef.current, []);
  const busy = status === 'picking' || status === 'uploading';

  return { localUri, publicUrl, storagePath, status, error, busy, pickImage, uploadImage, reset, readError };
}
