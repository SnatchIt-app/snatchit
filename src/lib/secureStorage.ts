/**
 * src/lib/secureStorage.ts — LargeSecureStore, bound to the device.
 *
 * The Supabase-recommended shape: a per-entry key in expo-secure-store
 * (Keychain/Keystore, which has a small value limit) and the encrypted session
 * blob in AsyncStorage. All logic lives in sessionStore.ts with the backends
 * injected; this file adapts the native modules into typed outcomes so a
 * thrown error becomes 'unavailable' rather than "delete the session".
 *
 * RANDOMNESS. Hermes ships no `crypto` global. react-native-get-random-values
 * installs `crypto.getRandomValues` backed by SecRandomCopyBytes / the Android
 * SecureRandom; it MUST be imported before any use, and build 13 did exactly
 * that here. Build 14 lost the import when this file became a thin binding and
 * crashed at cold launch. The polyfill is restored as the FIRST import, and the
 * source is handed to the store explicitly rather than reached as a global.
 */

import 'react-native-get-random-values';

import AsyncStorage from '@react-native-async-storage/async-storage';
import * as SecureStore from 'expo-secure-store';

import { createSessionStore, type BlobBackend, type SecureBackend } from './sessionStore';

const unavailable = (error: unknown) => ({ ok: false as const, reason: 'unavailable' as const, error });

const secure: SecureBackend = {
  async get(name) { try { return { ok: true, value: await SecureStore.getItemAsync(name) }; } catch (e) { return unavailable(e); } },
  async set(name, v) { try { await SecureStore.setItemAsync(name, v); return { ok: true }; } catch (e) { return unavailable(e); } },
  async delete(name) { try { await SecureStore.deleteItemAsync(name); return { ok: true }; } catch (e) { return unavailable(e); } },
};

const blob: BlobBackend = {
  async get(name) { try { return { ok: true, value: await AsyncStorage.getItem(name) }; } catch (e) { return unavailable(e); } },
  async set(name, v) { try { await AsyncStorage.setItem(name, v); return { ok: true }; } catch (e) { return unavailable(e); } },
  async remove(name) { try { await AsyncStorage.removeItem(name); return { ok: true }; } catch (e) { return unavailable(e); } },
};

// Polyfilled above. Bound here once so the store never touches the global.
const random = (n: number) => crypto.getRandomValues(new Uint8Array(n));

export const LargeSecureStore = createSessionStore({ secure, blob, random });
