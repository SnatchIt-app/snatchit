/**
 * src/lib/secureStorage.ts — LargeSecureStore, bound to the device.
 *
 * The Supabase-recommended shape: a per-entry key in expo-secure-store
 * (Keychain/Keystore, which has a small value limit) and the encrypted session
 * blob in AsyncStorage. All logic lives in sessionStore.ts with the two backends
 * injected; this file only adapts the native modules into typed outcomes so a
 * thrown error becomes 'unavailable' rather than "delete the session".
 */

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

export const LargeSecureStore = createSessionStore({ secure, blob });
