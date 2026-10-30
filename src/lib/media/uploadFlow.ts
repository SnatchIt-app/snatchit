/**
 * src/lib/media/uploadFlow.ts — the pure half of picking and uploading an image
 * (F-IMG-1, 2026-09-18). No React, no Expo: the hook wires the picker, storage
 * and alerts in; this module decides. Everything here is unit-tested with fake
 * deps; the device rows DV-IMG-1..9 prove the native half.
 *
 *  - runPick: one picker at a time (a gate the hook keeps in a ref), every exit
 *    releases the gate, a thrown picker/permission error becomes an outcome with
 *    product copy instead of an unhandled rejection that leaves the control stuck.
 *  - resolveContentType / sniffImageType / extensionFor: the picker's reported type
 *    only screens a pick early; the stored type and extension come from the file's
 *    own leading bytes, never from its name (owner ruling; A/B review 2026-09-18).
 *  - objectPath / settleUpload: the object name is fixed at pick time, so a retry
 *    after a timeout targets the same object; after any upload error the object's
 *    existence decides (a 409 is not trusted on its own — unobserved, B), so a
 *    timeout is never taken as proof of failure and no second object is made.
 *  - reusableUploadPath: an object already uploaded is reused only while the
 *    account, bucket/folder, transfer (reuseKey) and the selected file are the same.
 *  - classifyUploadError: network / type / size / timeout / empty read → copy.
 *  - withUploadTimeout: storage.upload has no timeout of its own (B F5).
 *  - rememberSelection / recallSelection / selectionToRecall: a keyed selection
 *    survives leaving the screen, and never replaces one the user just made (D).
 *  - statusAfterUnpicked: a cancelled/denied/failed pick restores the prior state,
 *    including an upload error message (D).
 */

export type UploadStatusLike = 'idle' | 'picking' | 'ready' | 'uploading' | 'done' | 'error';

export type PickOutcome =
  | { kind: 'busy' }
  | { kind: 'cancelled' }
  | { kind: 'denied'; canAskAgain: boolean }
  | { kind: 'invalid'; message: string }
  | { kind: 'picked'; uri: string; contentType: string | null; fileSize?: number; stamp: string }
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
const TYPE_EXT: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/heic': 'heic', 'image/heif': 'heif',
};

/** The picker's reported type, normalised to the allow-list; null when absent or not allowed. Never a file name. */
export function resolveContentType(mime: string | null | undefined): string | null {
  const m = (mime ?? '').toLowerCase().trim();
  return m ? IMAGE_TYPES[m] ?? null : null;
}

const HEIC_BRANDS = new Set(['heic', 'heix', 'hevc', 'hevx', 'heim', 'heis']);
const HEIF_BRANDS = new Set(['mif1', 'msf1', 'heif']);
const ascii = (b: Uint8Array, from: number, to: number) => String.fromCharCode(...Array.from(b.subarray(from, to)));

/** The format the bytes actually are (JPEG, PNG, WebP, HEIC/HEIF), or null. */
export function sniffImageType(b: Uint8Array): string | null {
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b.length >= 8 && b[0] === 0x89 && ascii(b, 1, 4) === 'PNG' && b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a) return 'image/png';
  if (b.length >= 12 && ascii(b, 0, 4) === 'RIFF' && ascii(b, 8, 12) === 'WEBP') return 'image/webp';
  if (b.length >= 12 && ascii(b, 4, 8) === 'ftyp') {
    const brand = ascii(b, 8, 12);
    if (HEIC_BRANDS.has(brand)) return 'image/heic';
    if (HEIF_BRANDS.has(brand)) return 'image/heif';
  }
  return null;
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
    // A reported type that is not allowed is refused now; no reported type waits for the bytes at upload.
    const contentType = resolveContentType(a.mimeType);
    if (a.mimeType && !contentType) return { kind: 'invalid', message: UPLOAD_COPY.unsupportedType };
    const check = deps.validate({ uri: a.uri, type: contentType ?? undefined, fileSize: a.fileSize ?? undefined });
    if (!check.valid) return { kind: 'invalid', message: check.error ?? UPLOAD_COPY.unsupportedType };
    return { kind: 'picked', uri: a.uri, contentType, fileSize: a.fileSize ?? undefined, stamp: String(Date.now()) };
  } catch (err) {
    return { kind: 'error', message: pickErrorMessage(err) };
  } finally {
    gate.inFlight = false;
  }
}

/** After a pick that did not produce a photo: the state from before the picker opened. */
export function statusAfterUnpicked(prior: UploadStatusLike, hasSelection: boolean): UploadStatusLike {
  if (prior === 'picking') return hasSelection ? 'ready' : 'idle';
  return prior;
}

/**
 * The object name is fixed when the photo is picked, not when an attempt starts, so a
 * retry after a timeout or a lost response targets the SAME object.
 */
export function objectPath(i: { userId: string; folder: string; stamp: string; contentType: string }): string {
  return `${i.userId}/${i.folder}/${i.stamp}.${extensionFor(i.contentType)}`;
}

/**
 * After an upload attempt: no error → uploaded. Any error, a timeout included → the object's
 * existence decides: present → an attempt landed (uploaded); absent or unknown → failed.
 */
export function settleUpload(i: { error: unknown | null; exists: boolean | null }): 'uploaded' | 'failed' {
  if (i.error == null) return 'uploaded';
  return i.exists === true ? 'uploaded' : 'failed';
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
/** A status read, an existence check or the mark-sent verb: bounded; a timeout only makes the outcome uncertain. */
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
export interface RememberedSelection { uri: string; stamp: string; record: UploadRecord | null }
const selections = new Map<string, RememberedSelection>();

export function rememberSelection(key: string, sel: RememberedSelection | null): void {
  if (sel) selections.set(key, sel); else selections.delete(key);
}
export function recallSelection(key: string): RememberedSelection | null {
  return selections.get(key) ?? null;
}

/** What to restore on (re)mount: the remembered selection only when nothing is selected now (D: never swap a fresh pick). */
export function selectionToRecall(current: { uri: string | null }, remembered: RememberedSelection | null): RememberedSelection | null {
  if (current.uri) return null;
  return remembered;
}
