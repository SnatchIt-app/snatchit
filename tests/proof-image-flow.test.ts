/**
 * F-IMG-1 — ticket-proof images: one picker at a time with visible feedback, recovery
 * from cancel / denial / thrown errors, an upload that survives a failed submit and is
 * reused only for the same account + transfer + file, and a submit whose outcome is
 * settled by the server's status contract (mark_transfer_sent is NOT idempotent and
 * returns void — A, 2026-09-18), never by a button guard alone.
 *
 * Source findings (Build 18 = aad5f75) these tests pin, all traced from source and
 * none yet reproduced on a device (DV-IMG-1..8 stay pending):
 *  1a  pickImage had no in-flight guard and MediaUpload rendered nothing for 'picking';
 *  1b  a thrown picker/permission error left status 'picking' with no message (no
 *      try/catch/finally);
 *  1c  a retry after a failed verb re-uploaded a new object and re-called the verb;
 *  1d  no single-flight on Mark as sent (the receive screen has one, CFT-205);
 *  1e  a network failure during upload showed the raw fetch message;
 *  1f  leaving the send screen lost the selection;  1g  no Open Settings on denial;
 *  1h  proof picks were validated against the auction-media rules, and the content
 *      type came from the file extension, not the asset.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';

import {
  classifyUploadError, createPickGate, extensionFor, objectPath, recallSelection, rememberSelection, reusableUploadPath,
  resolveContentType, runPick, selectionToRecall, settleUpload, sniffImageType, statusAfterUnpicked, UPLOAD_COPY,
  UPLOAD_TIMEOUT_MS, uploadKey, UploadTimeoutError, withUploadTimeout, type PickDeps,
} from '@/src/lib/media/uploadFlow';
import { isAlreadySentRaise, MARK_SENT_COPY, runMarkSent } from '@/src/lib/transfer/markSent';
import { validateImage } from '@/src/utils/validateImage';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

const asset = { uri: 'file:///tmp/a.heic', mimeType: 'image/heic', fileSize: 1_000 };
function deps(over: Partial<PickDeps> = {}): PickDeps & { launches: number } {
  const d = {
    launches: 0,
    requestPermission: vi.fn(async () => ({ granted: true, canAskAgain: true })),
    launch: vi.fn(async () => { d.launches += 1; return { canceled: false as const, assets: [asset] }; }),
    validate: vi.fn(() => ({ valid: true })),
    ...over,
  };
  return d;
}
const later = <T,>(v: T, ms = 5) => new Promise<T>((r) => setTimeout(() => r(v), ms));

describe('1a — one picker at a time', () => {
  it('a second pick while the first is presenting is ignored: one launch, one outcome', async () => {
    const gate = createPickGate();
    const d = deps({ launch: vi.fn(async () => { d.launches += 1; return later({ canceled: false as const, assets: [asset] }); }) });
    const first = runPick(gate, d);
    const second = await runPick(gate, d);
    expect(second).toEqual({ kind: 'busy' });
    const out = await first;
    expect(out).toMatchObject({ kind: 'picked', uri: asset.uri, contentType: 'image/heic' });
    expect(out.kind === 'picked' && out.stamp.length > 0).toBe(true);
    expect(d.launches).toBe(1);
    expect(gate.inFlight).toBe(false);
  });
});

describe('1b — recovery: cancel, denial, thrown errors always release the gate', () => {
  it('cancelled', async () => {
    const gate = createPickGate();
    const d = deps({ launch: vi.fn(async () => ({ canceled: true as const })) });
    expect(await runPick(gate, d)).toEqual({ kind: 'cancelled' });
    expect(gate.inFlight).toBe(false);
  });
  it('denied, with whether the OS will ask again (Open Settings only when it will not)', async () => {
    const gate = createPickGate();
    const d = deps({ requestPermission: vi.fn(async () => ({ granted: false, canAskAgain: false })) });
    expect(await runPick(gate, d)).toEqual({ kind: 'denied', canAskAgain: false });
    expect(d.launch).not.toHaveBeenCalled();
    expect(gate.inFlight).toBe(false);
  });
  it('the picker throws (e.g. another picking in progress, activity gone): an error outcome with product copy, gate released', async () => {
    const gate = createPickGate();
    const d = deps({ launch: vi.fn(async () => { throw new Error('Different image picking in progress. Await other requests first.'); }) });
    expect(await runPick(gate, d)).toEqual({ kind: 'error', message: UPLOAD_COPY.pickerBusy });
    expect(gate.inFlight).toBe(false);
    const d2 = deps({ requestPermission: vi.fn(async () => { throw new Error('Activity which was provided during module initialization is no longer available'); }) });
    expect(await runPick(gate, d2)).toEqual({ kind: 'error', message: UPLOAD_COPY.pickerFailed });
    expect(gate.inFlight).toBe(false);
    // and the next pick works again
    expect(await runPick(gate, deps())).toMatchObject({ kind: 'picked' });
  });
  it('validation failure is an invalid outcome with the validator\'s message', async () => {
    const d = deps({ validate: vi.fn(() => ({ valid: false, error: 'Image must be under 10MB. Yours is 12.0MB.' })) });
    expect(await runPick(createPickGate(), d)).toEqual({ kind: 'invalid', message: 'Image must be under 10MB. Yours is 12.0MB.' });
  });
});

describe('1h — the bytes decide the type; a reported type only screens the pick; a file name never counts', () => {
  const bytes = (...xs: (number | string)[]) => new Uint8Array(xs.flatMap((x) => typeof x === 'string' ? Array.from(x).map((c) => c.charCodeAt(0)) : [x]));
  const ftyp = (brand: string) => bytes(0, 0, 0, 0x18, 'ftyp', brand, 0, 0, 0, 0);
  it('sniffs JPEG, PNG, WebP, HEIC and HEIF; anything else is null', () => {
    expect(sniffImageType(bytes(0xff, 0xd8, 0xff, 0xe0, 0, 0x10))).toBe('image/jpeg');
    expect(sniffImageType(bytes(0x89, 'PNG', 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0x0d))).toBe('image/png');
    expect(sniffImageType(bytes('RIFF', 0x24, 0, 0, 0, 'WEBP', 'VP8 '))).toBe('image/webp');
    expect(sniffImageType(ftyp('heic'))).toBe('image/heic');
    expect(sniffImageType(ftyp('heix'))).toBe('image/heic');
    expect(sniffImageType(ftyp('mif1'))).toBe('image/heif');
    expect(sniffImageType(ftyp('avif'))).toBeNull();                       // AVIF is not on the allow-list
    expect(sniffImageType(bytes('GIF89a', 0, 0, 0, 0, 0, 0))).toBeNull();
    expect(sniffImageType(bytes('%PDF-1.7', 0, 0, 0, 0))).toBeNull();
    expect(sniffImageType(new Uint8Array(0))).toBeNull();
    expect(sniffImageType(bytes(0xff, 0xd8))).toBeNull();                  // truncated
  });
  it('the reported type is normalised; a missing one is null — the file name is not an input at all', () => {
    expect(resolveContentType('image/heic')).toBe('image/heic');
    expect(resolveContentType('image/jpg')).toBe('image/jpeg');
    expect(resolveContentType('IMAGE/PNG ')).toBe('image/png');
    expect(resolveContentType('image/gif')).toBeNull();
    expect(resolveContentType(null)).toBeNull();
    expect(resolveContentType(undefined)).toBeNull();
    expect(resolveContentType.length).toBe(1);
  });
  it('a pick with no reported type is accepted for byte-sniffing at upload, not guessed from its name', async () => {
    const d = deps({ launch: vi.fn(async () => ({ canceled: false as const, assets: [{ uri: 'file:///x/IMG_0001.jpg', mimeType: null, fileSize: 10 }] })) });
    expect(await runPick(createPickGate(), d)).toMatchObject({ kind: 'picked', uri: 'file:///x/IMG_0001.jpg', contentType: null });
  });
  it('a HEIC named .jpg is stored as HEIC: the extension follows the bytes', () => {
    const type = sniffImageType(ftyp('heic'));
    expect(type).toBe('image/heic');
    expect(objectPath({ userId: 'u1', folder: 'proofs', stamp: '1', contentType: type! })).toBe('u1/proofs/1.heic');
  });
  it('a pick whose type is refused is invalid before validation runs', async () => {
    const d = deps({ launch: vi.fn(async () => ({ canceled: false as const, assets: [{ uri: 'file:///x/a.gif', mimeType: 'image/gif', fileSize: 10 }] })) });
    expect(await runPick(createPickGate(), d)).toEqual({ kind: 'invalid', message: UPLOAD_COPY.unsupportedType });
    expect(d.validate).not.toHaveBeenCalled();
  });
  it('validateImage knows the proof-docs bucket: 10 MB and heif allowed there', () => {
    expect(validateImage({ uri: 'x', type: 'image/heif', fileSize: 1 }, 'proof-docs').valid).toBe(true);
    expect(validateImage({ uri: 'x', type: 'image/heif', fileSize: 1 }, 'auction-media').valid).toBe(false);
    expect(validateImage({ uri: 'x', type: 'image/jpeg', fileSize: 11 * 1024 * 1024 }, 'proof-docs').valid).toBe(false);
  });
});

describe('1c — reuse an uploaded object only for the same account, transfer and file', () => {
  const key = uploadKey({ userId: 'u1', bucket: 'proof-docs', folder: 'transfer-evidence', reuseKey: 'tr-1' });
  const rec = { key, uri: 'file:///a.jpg', path: 'u1/transfer-evidence/1.jpg' };
  it('same key + same uri → the path; anything else → null', () => {
    expect(reusableUploadPath(rec, 'file:///a.jpg', key)).toBe(rec.path);
    expect(reusableUploadPath(rec, 'file:///b.jpg', key)).toBeNull();
    expect(reusableUploadPath(rec, 'file:///a.jpg', uploadKey({ userId: 'u2', bucket: 'proof-docs', folder: 'transfer-evidence', reuseKey: 'tr-1' }))).toBeNull();
    expect(reusableUploadPath(rec, 'file:///a.jpg', uploadKey({ userId: 'u1', bucket: 'proof-docs', folder: 'transfer-evidence', reuseKey: 'tr-2' }))).toBeNull();
    expect(reusableUploadPath(null, 'file:///a.jpg', key)).toBeNull();
    expect(reusableUploadPath(rec, null, key)).toBeNull();
  });
});

describe('A ruling (4) — a timeout is not proof of failure: retries never create a second object', () => {
  it('the object path is fixed per selection (account, folder, pick stamp, type), not per attempt', () => {
    const a = objectPath({ userId: 'u1', folder: 'transfer-evidence', stamp: '1789600000000', contentType: 'image/heic' });
    expect(a).toBe('u1/transfer-evidence/1789600000000.heic');
    expect(objectPath({ userId: 'u1', folder: 'transfer-evidence', stamp: '1789600000000', contentType: 'image/heic' })).toBe(a);
    expect(objectPath({ userId: 'u2', folder: 'transfer-evidence', stamp: '1789600000000', contentType: 'image/heic' })).not.toBe(a);
  });
  it('after any upload error — a timeout included — the object\'s existence decides; a status code alone never does', () => {
    expect(settleUpload({ error: null, exists: null })).toBe('uploaded');
    expect(settleUpload({ error: new UploadTimeoutError(1), exists: true })).toBe('uploaded');
    expect(settleUpload({ error: { statusCode: '409', message: 'The resource already exists' }, exists: true })).toBe('uploaded');
    expect(settleUpload({ error: { statusCode: '409', message: 'The resource already exists' }, exists: false })).toBe('failed');
    expect(settleUpload({ error: { statusCode: '409', message: 'The resource already exists' }, exists: null })).toBe('failed');
    expect(settleUpload({ error: new UploadTimeoutError(1), exists: null })).toBe('failed');
  });
});

describe('D review — a fresh pick is never swapped; a cancelled Replace keeps the failure message', () => {
  it('(b) on remount the remembered selection comes back only when nothing is selected now', () => {
    const remembered = { uri: 'file:///old.jpg', stamp: '1', record: null };
    rememberSelection('k1', remembered);
    expect(selectionToRecall({ uri: null }, recallSelection('k1'))).toEqual(remembered);
    expect(selectionToRecall({ uri: 'file:///fresh.jpg' }, recallSelection('k1'))).toBeNull();   // the fresh pick survives
    expect(selectionToRecall({ uri: null }, recallSelection('other'))).toBeNull();
    rememberSelection('k1', null);
    expect(recallSelection('k1')).toBeNull();
  });
  it('(c) a pick that produced no photo restores the prior state — an upload error stays an error', () => {
    expect(statusAfterUnpicked('error', true)).toBe('error');
    expect(statusAfterUnpicked('done', true)).toBe('done');
    expect(statusAfterUnpicked('ready', true)).toBe('ready');
    expect(statusAfterUnpicked('idle', false)).toBe('idle');
    expect(statusAfterUnpicked('picking', true)).toBe('ready');
    expect(statusAfterUnpicked('picking', false)).toBe('idle');
  });
});

describe('1e — upload failures are classified into product copy', () => {
  it('network → offline wording; storage type/size refusals → actionable copy; timeout; else generic', () => {
    expect(classifyUploadError(new Error('Network request failed'))).toEqual({ kind: 'offline', message: UPLOAD_COPY.offline });
    expect(classifyUploadError({ message: 'mime type image/gif is not supported' })).toEqual({ kind: 'unsupported', message: UPLOAD_COPY.unsupportedType });
    expect(classifyUploadError({ message: 'The object exceeded the maximum allowed size', statusCode: '413' })).toEqual({ kind: 'too_large', message: UPLOAD_COPY.tooLarge });
    expect(classifyUploadError(new UploadTimeoutError(1))).toEqual({ kind: 'timeout', message: UPLOAD_COPY.timeout });
    expect(classifyUploadError(new Error('boom'))).toEqual({ kind: 'failed', message: UPLOAD_COPY.uploadFailed });
    for (const c of Object.values(UPLOAD_COPY)) expect(c).toMatch(/try again|choose|open|under|opening|settings/i);   // every message names what to do
  });
  it('B F5: an upload that never settles is bounded — the button cannot spin forever', async () => {
    vi.useFakeTimers();
    try {
      const never = new Promise<string>(() => {});
      const p = withUploadTimeout(never, 1_000);
      const settled = p.then(() => 'resolved', (e) => (e instanceof UploadTimeoutError ? 'timeout' : 'other'));
      await vi.advanceTimersByTimeAsync(1_001);
      expect(await settled).toBe('timeout');
      expect(UPLOAD_TIMEOUT_MS).toBeGreaterThanOrEqual(60_000);
    } finally {
      vi.useRealTimers();
    }
  });
  it('B F3: the stored object\'s extension follows the resolved content type, never the local file name', () => {
    expect(extensionFor('image/jpeg')).toBe('jpg');
    expect(extensionFor('image/png')).toBe('png');
    expect(extensionFor('image/webp')).toBe('webp');
    expect(extensionFor('image/heic')).toBe('heic');
    expect(extensionFor('image/heif')).toBe('heif');
  });
});

describe('Mark as sent — the outcome is settled by the status contract, not the button', () => {
  // 140: the read returns status + stored proof; a sent transfer here carries the uploaded proof.
  type Over = { readStatus?: () => Promise<string | null>; upload?: () => Promise<string | null>; call?: (path: string) => Promise<{ data?: unknown; error: { message: string } | null }> };
  const P = 'u1/transfer-evidence/1.jpg';
  const SENT_STATES = new Set(['seller_sent', 'buyer_confirmed', 'auto_released']);
  const mk = (over: Over = {}) => {
    const readStatus = over.readStatus ?? vi.fn(async () => 'pending');
    return {
      readTransfer: async () => {
        const status = await readStatus();
        return status === null ? null : { status, evidencePath: SENT_STATES.has(status) ? P : null };
      },
      upload: over.upload ?? vi.fn(async () => P),
      call: over.call ?? vi.fn(async () => ({ error: null })),
    };
  };
  it('already sent before we start (a lost response last time): no upload, no call, sent', async () => {
    const d = mk({ readStatus: vi.fn(async () => 'seller_sent') });
    expect(await runMarkSent(d)).toEqual({ kind: 'sent', path: P });   // 140: the stored proof comes back with it
    expect(d.upload).not.toHaveBeenCalled();
    expect(d.call).not.toHaveBeenCalled();
  });
  it('not pending and not sent (expired, cancelled): no call', async () => {
    const d = mk({ readStatus: vi.fn(async () => 'expired') });
    expect(await runMarkSent(d)).toEqual({ kind: 'not_pending', status: 'expired' });
    expect(d.call).not.toHaveBeenCalled();
  });
  it('upload failed: no call, selection is the caller\'s to keep', async () => {
    const d = mk({ upload: vi.fn(async () => null) });
    expect(await runMarkSent(d)).toEqual({ kind: 'upload_failed' });
    expect(d.call).not.toHaveBeenCalled();
  });
  it('the verb raises "already sent" (our earlier call landed): read back → sent, never an error', async () => {
    const reads = ['pending', 'seller_sent'];
    const d = mk({
      readStatus: vi.fn(async () => reads.shift() ?? 'seller_sent'),
      call: vi.fn(async () => ({ error: { message: 'Transfer cannot be marked as sent from current status: seller_sent.' } })),
    });
    expect(await runMarkSent(d)).toEqual({ kind: 'sent', path: 'u1/transfer-evidence/1.jpg' });
    expect(isAlreadySentRaise('Transfer cannot be marked as sent from current status: seller_sent.')).toBe(true);
    expect(isAlreadySentRaise('permission denied')).toBe(false);
  });
  it('the already-sent raise with a failed read-back is unconfirmed, never a failure', async () => {
    const reads: (string | null)[] = ['pending', null];
    const d = mk({
      readStatus: vi.fn(async () => reads.shift() ?? null),
      call: vi.fn(async () => ({ error: { message: 'Transfer cannot be marked as sent from current status: seller_sent.' } })),
    });
    expect(await runMarkSent(d)).toEqual({ kind: 'unconfirmed' });
  });
  it('the verb fails for another reason: failed with the message; nothing shown as sent', async () => {
    const d = mk({ call: vi.fn(async () => ({ error: { message: 'Transfer window has expired.' } })) });
    expect(await runMarkSent(d)).toEqual({ kind: 'failed', message: 'Transfer window has expired.' });
  });
  it('the verb returns no error: success ONLY when the read-back says sent; otherwise unconfirmed', async () => {
    const ok = ['pending', 'seller_sent'];
    expect(await runMarkSent(mk({ readStatus: vi.fn(async () => ok.shift() ?? 'seller_sent') }))).toEqual({ kind: 'sent', path: 'u1/transfer-evidence/1.jpg' });
    const notYet = ['pending', 'pending'];
    expect(await runMarkSent(mk({ readStatus: vi.fn(async () => notYet.shift() ?? 'pending') }))).toEqual({ kind: 'unconfirmed' });
    expect(MARK_SENT_COPY.unconfirmed).toMatch(/refresh/i);
    expect(MARK_SENT_COPY.unconfirmed).not.toMatch(/marked as sent\.$/i);
  });
  it('the verb call throws or times out: never a failure by itself — the read-back decides', async () => {
    const landed = ['pending', 'seller_sent'];
    expect(await runMarkSent(mk({
      readStatus: vi.fn(async () => landed.shift() ?? 'seller_sent'),
      call: vi.fn(async () => { throw new UploadTimeoutError(30_000); }),
    }))).toEqual({ kind: 'sent', path: 'u1/transfer-evidence/1.jpg' });
    const notLanded = ['pending', 'pending'];
    expect(await runMarkSent(mk({
      readStatus: vi.fn(async () => notLanded.shift() ?? 'pending'),
      call: vi.fn(async () => { throw new Error('Network request failed'); }),
    }))).toEqual({ kind: 'unconfirmed' });
  });
  it('a status read that throws is treated as a failed read (null), never as sent', async () => {
    const d = mk({ readStatus: vi.fn(async () => { throw new Error('Network request failed'); }) });
    expect(await runMarkSent(d)).toEqual({ kind: 'unconfirmed' });
  });
  it('a status read that fails is unconfirmed, never sent', async () => {
    const reads: (string | null)[] = ['pending', null];
    expect(await runMarkSent(mk({ readStatus: vi.fn(async () => reads.shift() ?? null) }))).toEqual({ kind: 'unconfirmed' });
  });
});

describe('the surfaces (source contract; the device rows DV-IMG-1..8 prove the behaviour)', () => {
  const hook = stripComments(read('src/hooks/useImageUpload.ts'));
  const media = stripComments(read('src/components/ui/MediaUpload.tsx'));
  const send = stripComments(read('app/transfer/send/[id].tsx'));
  const create = stripComments(read('src/screens/CreateListingScreen.tsx'));

  it('the hook picks through the gated runner, opens Settings on a final denial, keeps the selection on failure, reuses by key', () => {
    expect(hook).toContain('createPickGate()');
    expect(hook).toContain('runPick(');
    expect(hook).toContain('Linking.openSettings()');
    expect(hook).toContain('reusableUploadPath(');
    expect(hook).toContain('classifyUploadError(');
    expect(hook).not.toMatch(/localUri\.split\('\.'\)\.pop\(\)/);   // 1h / B F3: the extension no longer decides the type
    expect(hook).toContain('objectPath(');
    expect(hook).toContain('settleUpload({ error: uploadError, exists })');
    expect(hook).toContain('.exists(path)');
    expect(hook).toContain('ImagePicker.UIImagePickerPreferredAssetRepresentationMode.Compatible');
    // the stored type comes from the bytes: the sniff precedes the path and the upload
    const sniff = hook.indexOf('sniffImageType(bytes)');
    expect(sniff).toBeGreaterThan(-1);
    expect(sniff).toBeLessThan(hook.indexOf('objectPath({ userId, folder, stamp, contentType })'));
    expect(sniff).toBeLessThan(hook.indexOf('.upload(path, bytes,'));
    expect(hook).not.toMatch(/resolveContentType\(/);
    // D (b)/(c): the hook uses the tested rules
    expect(hook).toContain('selectionToRecall(selRef.current, recallSelection(key))');
    expect(hook).toContain('statusAfterUnpicked(prior.status, !!selRef.current.uri)');
    // D (a): the uploaded record is set before it is remembered
    const upStart = hook.indexOf('const uploadImage = useCallback(');
    const rec = hook.indexOf('recordRef.current = { key, uri, path };', upStart);
    expect(rec).toBeGreaterThan(upStart);
    expect(hook.indexOf('remember();', upStart)).toBeGreaterThan(rec);
    expect(hook).toContain('withUploadTimeout(');
    expect(hook).toMatch(/\[localUri, userId, folder, bucket, reuseKey\b/);   // B F4: bucket is a dependency
    expect(hook).toContain('readError');
    // 1b: the picker and the permission request are only ever called inside the gated runner's deps
    const rp = hook.indexOf('runPick(');
    const count = (needle: string) => hook.split(needle).length - 1;
    expect(count('ImagePicker.launchImageLibraryAsync(')).toBe(1);
    expect(count('ImagePicker.requestMediaLibraryPermissionsAsync(')).toBe(1);
    expect(hook.indexOf('ImagePicker.launchImageLibraryAsync(')).toBeGreaterThan(rp);
    expect(hook.indexOf('ImagePicker.requestMediaLibraryPermissionsAsync(')).toBeGreaterThan(rp);
    // 1a: 'picking' is set only after the gate says no picker is open
    const gateCheck = hook.indexOf('if (gate.inFlight) return;');
    expect(gateCheck).toBeGreaterThan(-1);
    expect(hook.indexOf("setStatus('picking')")).toBeGreaterThan(gateCheck);
    expect(hook.indexOf("setStatus('picking')")).toBeLessThan(rp);
    // failure keeps the selection: no setLocalUri(null) on the error path
    const up = hook.indexOf('const uploadImage = useCallback(');
    const upEnd = hook.indexOf('const reset = useCallback(', up);
    expect(hook.slice(up, upEnd)).not.toContain('setLocalUri(null)');
    // 1f: a keyed selection survives unmount/remount
    expect(hook).toContain('rememberSelection(');
    expect(hook).toContain('recallSelection(');
  });
  it('the control shows the picking state and disables its actions while picking', () => {
    expect(media).toContain("status === 'picking'");
    expect(media).toContain('UPLOAD_COPY.opening');
    expect(media).toMatch(/const (picking|isPicking) = status === 'picking'/);
  });
  it('Send tickets: single-flight submit, busy covers picking, the outcome runner, a keyed selection, success only on sent', () => {
    expect(send).toContain('useSingleFlight()');
    expect(send).toContain('flight.run(');
    expect(send).toContain('evidenceUpload.busy');
    expect(send).toContain('runMarkSent(');
    expect(send).toContain('reuseKey: id');
    expect(send).toContain(".select('status, transfer_evidence_path')");
    const run = send.indexOf('runMarkSent(');
    const success = send.indexOf("announceForAccessibility('Marked as sent", run);   // F-28: announced, not a dialog
    expect(success).toBeGreaterThan(run);
    expect(send.slice(run, success)).toContain("kind === 'sent'");
    expect(send).not.toContain("setTransfer((prev) => (prev ? { ...prev, status: 'seller_sent'");   // no local success without the read-back
    expect(send).toContain('MARK_SENT_COPY.unconfirmed');
    expect(send).toContain("label={lastFailed ? 'Try again' : 'Mark as sent'}");
    expect(send).toContain('evidenceUpload.readError()');
    expect(send.slice(run, success)).toContain('evidenceUpload.reset()');
    expect(send).not.toMatch(/const busy = submitting \|\| evidenceUpload\.status === 'uploading'/);
  });
  it('Sell form: the same picker fixes apply — busy covers picking, publish is single-flight', () => {
    expect(create).toContain('coverUpload.busy');
    expect(create).toContain('proofUpload.busy');
    expect(create).toContain('useSingleFlight()');
    expect(create).not.toMatch(/const busy = loading \|\| coverUpload\.status === 'uploading' \|\| proofUpload\.status === 'uploading'/);
    // the upload failure alert reads the hook's current error, not a stale render value
    expect(create).toContain('coverUpload.readError()');
    expect(create).toContain('proofUpload.readError()');
    expect(create).toContain('publishFlight.run(handlePublish)');
  });
});
