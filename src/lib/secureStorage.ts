/**
 * src/lib/secureStorage.ts   (NATIVE ONLY — never imported by the web bundle)
 *
 * LargeSecureStore — the Supabase-recommended encrypted session-storage adapter
 * for React Native. Fixes L-1 / M9 (session token stored in *plaintext*
 * AsyncStorage, readable by anything with filesystem/backup access).
 *
 * Why not just SecureStore directly?
 *   expo-secure-store (iOS Keychain / Android Keystore) has a ~2KB per-item
 *   limit. A Supabase session (access JWT + refresh token + user object) can
 *   exceed that. So we use the hybrid pattern:
 *     • a random AES-256 key per storage key, kept in expo-secure-store
 *       (hardware-backed Keychain/Keystore) — tiny, always < 2KB.
 *     • the session blob AES-256-CTR encrypted and kept in AsyncStorage under
 *       a namespaced key. The ciphertext is useless without the Keychain key.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * BACKWARD COMPATIBILITY (do not remove):
 *   Existing installs have a *plaintext* Supabase session in AsyncStorage under
 *   the RAW supabase storage key (the default `sb-<project-ref>-auth-token`,
 *   plus `...-code-verifier`). This adapter is wired WITHOUT overriding
 *   `storageKey`, so the `key` argument passed to getItem/setItem/removeItem is
 *   EXACTLY that legacy key. On a miss in the encrypted namespace, getItem()
 *   falls back to the legacy plaintext value, re-persists it through the
 *   encrypted path, and deletes the plaintext copy — so users updating the app
 *   are NOT logged out, and their token stops living in cleartext after the
 *   first launch.
 * ─────────────────────────────────────────────────────────────────────────────
 */

// Polyfill global.crypto.getRandomValues for the AES key generation below.
// MUST be imported before any crypto.getRandomValues() call.
import 'react-native-get-random-values';

import AsyncStorage from '@react-native-async-storage/async-storage';
import * as SecureStore from 'expo-secure-store';
import * as aesjs from 'aes-js';

// Namespace for the ENCRYPTED session blob kept in AsyncStorage.
const BLOB_NS = 'ss.v1.';
// Namespace for the per-key AES key kept in expo-secure-store (Keychain/Keystore).
const KEY_NS = 'ss.key.v1.';

/**
 * expo-secure-store keys may only contain [A-Za-z0-9._-]. The default supabase
 * key (`sb-<ref>-auth-token`) already conforms, but sanitize defensively so an
 * unusual custom storageKey can never throw at runtime.
 */
function secureKeyName(key: string): string {
  return (KEY_NS + key).replace(/[^A-Za-z0-9._-]/g, '_');
}

function blobKeyName(key: string): string {
  return BLOB_NS + key;
}

async function encrypt(key: string, value: string): Promise<string> {
  // Fresh random AES-256 key per write. Kept only in the Keychain/Keystore.
  const encryptionKey = crypto.getRandomValues(new Uint8Array(256 / 8));
  const cipher = new aesjs.ModeOfOperation.ctr(encryptionKey, new aesjs.Counter(1));
  const encryptedBytes = cipher.encrypt(aesjs.utils.utf8.toBytes(value));

  await SecureStore.setItemAsync(secureKeyName(key), aesjs.utils.hex.fromBytes(encryptionKey));
  return aesjs.utils.hex.fromBytes(encryptedBytes);
}

async function decrypt(key: string, value: string): Promise<string | null> {
  const encryptionKeyHex = await SecureStore.getItemAsync(secureKeyName(key));
  if (!encryptionKeyHex) return null; // no key → cannot decrypt

  const cipher = new aesjs.ModeOfOperation.ctr(
    aesjs.utils.hex.toBytes(encryptionKeyHex),
    new aesjs.Counter(1),
  );
  const decryptedBytes = cipher.decrypt(aesjs.utils.hex.toBytes(value));
  return aesjs.utils.utf8.fromBytes(decryptedBytes);
}

/**
 * Storage adapter matching the interface Supabase's auth client expects
 * (getItem / setItem / removeItem, all Promise-returning).
 */
export const LargeSecureStore = {
  async getItem(key: string): Promise<string | null> {
    // 1) Preferred path: encrypted blob under the namespaced key.
    const encrypted = await AsyncStorage.getItem(blobKeyName(key));
    if (encrypted) {
      try {
        return await decrypt(key, encrypted);
      } catch (e) {
        // Corrupt / undecryptable (e.g. Keychain key wiped by OS restore).
        // Treat as "no session" rather than crash the app on launch.
        console.warn('[secureStorage] decrypt failed; clearing entry', e);
        await this.removeItem(key);
        return null;
      }
    }

    // 2) Backward-compat: legacy PLAINTEXT session written by the previous
    //    AsyncStorage adapter lived under the RAW supabase key (== `key`).
    //    Migrate it into the encrypted store so the user stays logged in AND
    //    the cleartext copy is removed.
    const legacy = await AsyncStorage.getItem(key);
    if (legacy != null) {
      try {
        await this.setItem(key, legacy);   // encrypt + write namespaced blob
        await AsyncStorage.removeItem(key); // delete plaintext copy
      } catch (e) {
        // Non-fatal: even if migration fails we still return the value so the
        // user is not logged out; migration will be retried next launch.
        console.warn('[secureStorage] legacy migration failed (non-fatal)', e);
      }
      return legacy;
    }

    return null;
  },

  async setItem(key: string, value: string): Promise<void> {
    const encrypted = await encrypt(key, value);
    await AsyncStorage.setItem(blobKeyName(key), encrypted);
    // Defensive: ensure no stale plaintext copy survives under the raw key.
    await AsyncStorage.removeItem(key).catch(() => {});
  },

  async removeItem(key: string): Promise<void> {
    await AsyncStorage.removeItem(blobKeyName(key));
    await SecureStore.deleteItemAsync(secureKeyName(key)).catch(() => {});
    // Also clear any legacy plaintext copy (logout must leave nothing behind).
    await AsyncStorage.removeItem(key).catch(() => {});
  },
};
