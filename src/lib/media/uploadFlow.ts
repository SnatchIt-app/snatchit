/**
 * src/lib/media/uploadFlow.ts — the pure half of picking and uploading an image
 * (F-IMG-1, 2026-09-18). No React, no Expo: the hook wires the picker, storage
 * and alerts in; this module decides. Everything here is unit-tested with fake
 * deps; the device rows DV-IMG-1..8 prove the native half.
 *
 *  - runPick: one picker at a time (a gate the hook keeps in a ref), every exit
 *    releases the gate, a thrown picker/permission error becomes an outcome with
 *    product copy instead of an unhandled rejection that leaves the control stuck.
 *  - resolveContentType / extensionFor: the stored object's type and extension
 *    come from the asset, normalised to the storage allow-list — never from the
 *    local file name (B F3: a HEIF uploaded as image/jpeg with a .jpg name).
 *  - reusableUploadPath: an object already uploaded is reused only while the
 *    account, bucket/folder, transfer (reuseKey) and the selected file are the same.
 *  - classifyUploadError: network / type / size / timeout / empty read → copy.
 *  - withUploadTimeout: storage.upload has no timeout of its own (B F5); a hung
 *    upload must end in an error the user can act on, not a spinner forever.
 *  - rememberSelection / recallSelection: a keyed selection survives leaving the
 *    screen and coming back within the session (1f).
 */

export type PickOutcome =
  | { kind: 'busy' }
  | { kind: 'cancelled' }
  | { kind: 'denied'; canAskAgain: boolean }
  | { kind: 'invalid'; message: string }
  | { kind: 'picked'; uri: string; contentType: string; fileSize?: number; stamp: string }
  | { kind: 'error'; message: string };

export interface PickedAsset { uri: string; mimeType?: string | null; fileSize?: number | null }

export interface PickDeps {
  requestPermission(): Promise<{ granted: boolean; canAskAgain?: boolean }>;
  launch(): Promise<{ canceled: true } | { canceled: false; assets: PickedAsset[] }>;
  validate(file: { uri: string; type?: string; fileSize?: number }): { valid: boolean; error?: string };
}

export interface PickGate { inFlight: boolean }
export function createPickGate(): PickGate { return { inFlight: false }; }

export const UPLOAD_COPY = {
  opening: 'Opening your photos…',
  permission: 'Snatch It needs access to your photo library to add this image. You can allow it in Settings.',
  unsupportedType: "This file type isn't supported. Choose a JPEG, PNG, WebP or HEIC photo.",
  tooLarge: 'This image is over 10 MB. Choose a smaller photo and try again.',
  offline: "You're offline. Check your internet connection and try again.",
  timeout: 'The upload is taking too long. Check your connection and try again.',
  emptyFile: "This photo hasn't finished downloading to your device. Open it in Photos first, then try again.",
  uploadFailed: "Couldn't upload this image. Try again.",
  pickerBusy: 'The photo picker is already open. Choose a photo there, or close it and try again.',
  pickerFailed: "Couldn't open your photos. Try again.",
  noImage: 'Choose an image first, then try again.',
  notSignedIn: 'Sign in again to upload this image, then try again.',
} as const;

const IMAGE_TYPES: Record<string, string> = {
  'image/jpeg': 'image/jpeg', 'image/jpg': 'image/jpeg', 'image/pjpeg': 'image/jpeg',
  'image/png': 'image/png', 'image/webp': 'image/webp', 'image/heic': 'image/heic', 'image/heif': 'image/heif',
};
const EXT_TYPES: Record<string, string> = {
  jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp', heic: 'image/heic', heif: 'image/heif',
};
const TYPE_EXT: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/heic': 'heic', 'image/heif': 'heif',
};

/** The asset's own type when it is an allowed image type (normalised), else the extension, else null. */
export function resolveContentType(mime: string | null | undefined, uri: string): string | null {
  const m = (mime ?? '').toLowerCase().trim();
  if (m) return IMAGE_TYPES[m] ?? null;
  const clean = uri.split(/[?#]/)[0];
  const dot = clean.lastIndexOf('.');
  const slash = clean.lastIndexOf('/');
  if (dot < 0 || dot < slash) return null;
  return EXT_TYPES[clean.slice(dot + 1).toLowerCase()] ?? null;
}

export function extensionFor(contentType: string): string {
  return TYPE_EXT[contentType] ?? 'jpg';
}

function pickErrorMessage(err: unknown): string {
  const msg = err instanceof Error ? err.message : String(err ?? '');
  return /picking in progress|another request|E_PICKER_ANOTHER/i.test(msg) ? UPLOAD_COPY.pickerBusy : UPLOAD_COPY.pickerFailed;
}

export async function runPick(gate: PickGate, deps: PickDeps): Promise<PickOutcome> {
  if (gate.inFlight) return { kind: 'busy' };
  gate.inFlight = true;
  try {
    const perm = await deps.requestPermission();
    if (!perm.granted) return { kind: 'denied', canAskAgain: perm.canAskAgain ?? true };
    const r = await deps.launch();
    if (r.canceled || r.assets.length === 0) return { kind: 'cancelled' };
    const a = r.assets[0];
    const contentType = resolveContentType(a.mimeType, a.uri);
    if (!contentType) return { kind: 'invalid', message: UPLOAD_COPY.unsupportedType };
    const check = deps.validate({ uri: a.uri, type: contentType, fileSize: a.fileSize ?? undefined });
    if (!check.valid) return { kind: 'invalid', message: check.error ?? UPLOAD_COPY.unsupportedType };
    return { kind: 'picked', uri: a.uri, contentType, fileSize: a.fileSize ?? undefined, stamp: String(Date.now()) };
  } catch (err) {
    return { kind: 'error', message: pickErrorMessage(err) };
  } finally {
    gate.inFlight = false;
  }
}

/**
 * The object name is fixed when the photo is picked, not when an attempt starts, so a
 * retry after a timeout or a lost response targets the SAME object (A ruling (4): a
 * timeout is not proof the upload failed; no duplicate uploads).
 */
export function objectPath(i: { userId: string; folder: string; stamp: string; contentType: string }): string {
  return `${i.userId}/${i.folder}/${i.stamp}.${extensionFor(i.contentType)}`;
}

/** upsert:false on a name only this selection uses: "already exists" means an earlier attempt landed. */
export function isAlreadyUploaded(err: unknown): boolean {
  const e = (err ?? {}) as { message?: string; statusCode?: string | number; error?: string };
  if (String(e.statusCode ?? '') === '409') return true;
  const msg = err instanceof Error ? err.message : e.message ?? e.error ?? '';
  return /already exists|^duplicate$/i.test(msg);
}

/** One uploaded object and the exact selection it belongs to. */
export interface UploadRecord { key: string; uri: string; path: string }

export function uploadKey(i: { userId: string; bucket: string; folder: string; reuseKey?: string | null }): string {
  return `${i.userId}|${i.bucket}|${i.folder}|${i.reuseKey ?? ''}`;
}

export function reusableUploadPath(rec: UploadRecord | null, uri: string | null, key: string): string | null {
  if (!rec || !uri) return null;
  return rec.key === key && rec.uri === uri ? rec.path : null;
}

export type UploadErrorKind = 'offline' | 'timeout' | 'unsupported' | 'too_large' | 'empty' | 'failed';

export class UploadTimeoutError extends Error {
  constructor(ms: number) { super(`upload timed out after ${ms} ms`); this.name = 'UploadTimeoutError'; }
}
export class EmptyFileError extends Error {
  constructor() { super('File read returned 0 bytes'); this.name = 'EmptyFileError'; }
}
export class UnsupportedTypeError extends Error {
  constructor() { super('unsupported content type'); this.name = 'UnsupportedTypeError'; }
}

export const UPLOAD_TIMEOUT_MS = 120_000;
/** A status read or the mark-sent verb: bounded, and a timeout only makes the outcome uncertain. */
export const REQUEST_TIMEOUT_MS = 30_000;

export function withUploadTimeout<T>(p: PromiseLike<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | null = null;
  const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new UploadTimeoutError(ms)), ms); });
  return Promise.race([Promise.resolve(p), timeout]).finally(() => { if (timer) clearTimeout(timer); });
}

export function classifyUploadError(err: unknown): { kind: UploadErrorKind; message: string } {
  if (err instanceof UploadTimeoutError) return { kind: 'timeout', message: UPLOAD_COPY.timeout };
  if (err instanceof EmptyFileError) return { kind: 'empty', message: UPLOAD_COPY.emptyFile };
  if (err instanceof UnsupportedTypeError) return { kind: 'unsupported', message: UPLOAD_COPY.unsupportedType };
  const e = err as { message?: string; statusCode?: string | number; status?: number } | null;
  const msg = (err instanceof Error ? err.message : e?.message ?? '').toLowerCase();
  const code = String(e?.statusCode ?? e?.status ?? '');
  if (/network request failed|failed to fetch|fetch failed|network error/.test(msg)) return { kind: 'offline', message: UPLOAD_COPY.offline };
  if (/mime type|content.?type|not supported|invalid_mime/.test(msg)) return { kind: 'unsupported', message: UPLOAD_COPY.unsupportedType };
  if (code === '413' || /exceeded the maximum allowed size|payload too large|too large/.test(msg)) return { kind: 'too_large', message: UPLOAD_COPY.tooLarge };
  if (/0 bytes/.test(msg)) return { kind: 'empty', message: UPLOAD_COPY.emptyFile };
  return { kind: 'failed', message: UPLOAD_COPY.uploadFailed };
}

/** A selection kept for the session so leaving the screen and coming back does not lose it (1f). */
export interface RememberedSelection { uri: string; contentType: string; stamp: string; record: UploadRecord | null }
const selections = new Map<string, RememberedSelection>();

export function rememberSelection(key: string, sel: RememberedSelection | null): void {
  if (sel) selections.set(key, sel); else selections.delete(key);
}
export function recallSelection(key: string): RememberedSelection | null {
  return selections.get(key) ?? null;
}
