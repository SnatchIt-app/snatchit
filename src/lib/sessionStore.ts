/**
 * src/lib/sessionStore.ts — the session storage adapter, with its backends
 * injected so every persistence boundary can be exercised in a test.
 *
 * Two stores, one secret: a 32-byte key in the Keychain (`secure`) and the
 * encrypted session blob in AsyncStorage (`blob`). Backends report a TYPED
 * outcome instead of throwing, which is what lets the reader tell three very
 * different situations apart:
 *
 *   'unavailable'  the Keychain or AsyncStorage could not be reached right now
 *                  (device locked, first unlock after reboot, restore in flight,
 *                  I/O error). The session is fully recoverable a moment later.
 *                  -> return null for THIS read, keep the ciphertext, touch
 *                     nothing. The app renders signed out; the next launch
 *                     recovers. (Review of 5a6e6ad, blocking: the old catch-all
 *                     deleted the blob here, the D5 symptom by another trigger.)
 *   no key         the Keychain has nothing for this entry (OS restore wiped
 *                  it). The blob can never be read again -> clear it.
 *   undecryptable  the AEAD rejected the blob (tamper, truncation, wrong key)
 *                  -> clear it. Never silently returns garbage.
 *
 * KEY LIFECYCLE. Created once, reused forever, memoised per key so two
 * concurrent first writes cannot mint two keys and orphan one blob. Because
 * the key is never replaced, an interruption between the two writes — in
 * either order — always leaves a blob its key can still open.
 *
 * Nothing here logs a value: the warn calls carry the error only.
 */

import { decryptAny, encryptV3, randomBytes, SessionCipherError } from './sessionCipher';

export type Read<T> = { ok: true; value: T | null } | { ok: false; reason: 'unavailable'; error: unknown };
export type Write = { ok: true } | { ok: false; reason: 'unavailable'; error: unknown };

export interface SecureBackend {
  get(name: string): Promise<Read<string>>;
  set(name: string, hexKey: string): Promise<Write>;
  delete(name: string): Promise<Write>;
}
export interface BlobBackend {
  get(name: string): Promise<Read<string>>;
  set(name: string, blob: string): Promise<Write>;
  remove(name: string): Promise<Write>;
}
export interface SessionStoreDeps {
  secure: SecureBackend;
  blob: BlobBackend;
  warn?: (message: string, error?: unknown) => void;
}

const BLOB_NS = 'ss.v1.';
const KEY_NS = 'ss.key.v1.';
const hexOf = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
const bytesOf = (h: string) => new Uint8Array((h.match(/.{2}/g) ?? []).map((x) => parseInt(x, 16)));

export function secureKeyName(key: string): string {
  return (KEY_NS + key).replace(/[^A-Za-z0-9._-]/g, '_');
}
export function blobKeyName(key: string): string {
  return BLOB_NS + key;
}

export class StorageUnavailable extends Error {
  constructor(public readonly cause: unknown) { super('session storage unavailable'); }
}

export function createSessionStore(deps: SessionStoreDeps) {
  const warn = deps.warn ?? ((m: string, e?: unknown) => console.warn(m, e));
  const keyInFlight = new Map<string, Promise<Uint8Array>>();

  async function loadOrCreateKey(key: string): Promise<Uint8Array> {
    const name = secureKeyName(key);
    const pending = keyInFlight.get(name);
    if (pending) return pending;
    const run = (async () => {
      const r = await deps.secure.get(name);
      if (!r.ok) throw new StorageUnavailable(r.error);
      if (r.value) return bytesOf(r.value);
      const fresh = randomBytes(32);
      const w = await deps.secure.set(name, hexOf(fresh));
      if (!w.ok) throw new StorageUnavailable(w.error);
      return fresh;
    })();
    keyInFlight.set(name, run);
    try { return await run; } finally { keyInFlight.delete(name); }
  }

  async function clear(key: string): Promise<void> {
    await deps.blob.remove(blobKeyName(key));
    await deps.secure.delete(secureKeyName(key));
    await deps.blob.remove(key); // legacy plaintext slot, must never survive
  }

  return {
    async getItem(key: string): Promise<string | null> {
      const b = await deps.blob.get(blobKeyName(key));
      if (!b.ok) { warn('[secureStorage] blob store unavailable; leaving entry intact', b.error); return null; }

      if (b.value) {
        const k = await deps.secure.get(secureKeyName(key));
        if (!k.ok) { warn('[secureStorage] keychain unavailable; leaving entry intact', k.error); return null; }
        if (!k.value) { warn('[secureStorage] no key for entry; clearing'); await clear(key); return null; }
        try {
          const { plaintext, format } = decryptAny(bytesOf(k.value), b.value);
          if (format !== 'v3') {
            // Older generation: rewrite as v3. A failed rewrite is not a failed read.
            await this.setItem(key, plaintext).catch((e: unknown) => warn('[secureStorage] re-encrypt deferred', e));
          }
          return plaintext;
        } catch (e) {
          if (e instanceof SessionCipherError) { warn('[secureStorage] undecryptable entry; clearing', e); await clear(key); return null; }
          warn('[secureStorage] read failed; leaving entry intact', e);
          return null;
        }
      }

      // Backward-compat: a plaintext session left by the pre-encryption adapter.
      const legacy = await deps.blob.get(key);
      if (!legacy.ok) return null;
      if (legacy.value != null) {
        try { await this.setItem(key, legacy.value); await deps.blob.remove(key); }
        catch (e) { warn('[secureStorage] legacy migration deferred', e); }
        return legacy.value;
      }
      return null;
    },

    async setItem(key: string, value: string): Promise<void> {
      const k = await loadOrCreateKey(key);          // Keychain first; never replaced once present
      const w = await deps.blob.set(blobKeyName(key), encryptV3(k, value));
      if (!w.ok) throw new StorageUnavailable(w.error);
      await deps.blob.remove(key);                     // no plaintext copy may survive
    },

    async removeItem(key: string): Promise<void> {
      await clear(key);
    },
  };
}
