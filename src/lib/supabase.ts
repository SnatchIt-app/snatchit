/**
 * src/lib/supabase.ts
 * Initialises and exports the Supabase client for use across the app.
 *
 * Required .env variables (prefix EXPO_PUBLIC_ so they're bundled by Expo):
 *   EXPO_PUBLIC_SUPABASE_URL
 *   EXPO_PUBLIC_SUPABASE_ANON_KEY
 *
 * Storage strategy:
 *   - Native: LargeSecureStore — AES-256 encrypted blob in AsyncStorage, with
 *     the encryption key held in the iOS Keychain / Android Keystore. Fixes
 *     L-1/M9 (plaintext session tokens). Migrates existing plaintext sessions
 *     transparently on first launch (see src/lib/secureStorage.ts).
 *   - Web (browser): localStorage via a thin wrapper
 *   - Web (SSR/static export): in-memory no-op (avoids "window is not defined")
 *
 * Auth flow:
 *   flowType: 'pkce' — the deep-link handler exchanges a `code`/`token_hash`
 *   for a session locally (bound to this device's code_verifier), instead of
 *   trusting raw access/refresh tokens from an inbound URL. Fixes H-5
 *   (deep-link session injection / fixation). See NativeAppShell.native.tsx.
 */

import { Platform } from 'react-native';
import { createClient } from '@supabase/supabase-js';
import 'react-native-url-polyfill/auto';

// ── Platform-safe storage ────────────────────────────────────────────────────

function getStorage() {
  if (Platform.OS !== 'web') {
    // Native: encrypted, Keychain/Keystore-backed session storage.
    // require() keeps expo-secure-store / aes-js out of the web bundle's
    // static analysis (they are native modules with no web implementation).
    // NOTE: storageKey is intentionally left at Supabase's default so the key
    // this adapter receives matches the LEGACY plaintext key it migrates from.
    return require('./secureStorage').LargeSecureStore;
  }

  // Web: guard against SSR / static export where `window` doesn't exist.
  if (typeof window === 'undefined') {
    // No-op storage during static rendering — session won't persist,
    // which is fine because static export only produces HTML shells.
    return {
      getItem: (_key: string) => Promise.resolve(null),
      setItem: (_key: string, _value: string) => Promise.resolve(),
      removeItem: (_key: string) => Promise.resolve(),
    };
  }

  // Browser: thin wrapper around localStorage matching Supabase's expected interface.
  return {
    getItem: (key: string) => Promise.resolve(localStorage.getItem(key)),
    setItem: (key: string, value: string) => {
      localStorage.setItem(key, value);
      return Promise.resolve();
    },
    removeItem: (key: string) => {
      localStorage.removeItem(key);
      return Promise.resolve();
    },
  };
}

// ── Env vars ─────────────────────────────────────────────────────────────────

export const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
export const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

// ── Runtime guard ────────────────────────────────────────────────────────────
// Fail loudly during development so the missing-env problem is obvious.
if (!supabaseUrl || !supabaseAnonKey) {
  // Soft warning, NOT a throw. Throwing at module load terminates the JS
  // runtime before React mounts \u2014 this manifests as an instant iOS launch
  // crash with no useful Console output. Let the app boot with placeholder
  // values so every Supabase call fails with a clear network error that
  // existing UI error states (or ErrorBoundary) can surface.
  console.error(
    '[SnatchIt] Supabase env vars are missing.\n' +
    '  EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY must be set.\n' +
    '  Configure via eas.json env block (preferred) or .env.<profile> file.\n' +
    '  Source: Supabase dashboard \u2192 Project Settings \u2192 API.',
  );
}

// Placeholder values keep createClient from throwing on URL parsing.
const _safeSupabaseUrl  = supabaseUrl  || 'https://missing.supabase.invalid';
const _safeSupabaseAnon = supabaseAnonKey || 'missing-anon-key';

// ── Client ───────────────────────────────────────────────────────────────────
export const supabase = createClient(_safeSupabaseUrl, _safeSupabaseAnon, {
  auth: {
    // Platform-safe storage: AsyncStorage on native, localStorage on web,
    // no-op during SSR/static export.
    storage: getStorage(),
    persistSession: true,
    // Automatically refresh the JWT before it expires.
    autoRefreshToken: true,
    // Must be false for React Native – there is no browser URL to detect.
    // On native the deep-link handler drives exchangeCodeForSession/verifyOtp.
    detectSessionInUrl: Platform.OS === 'web',
    // PKCE: recovery/confirm/OAuth links carry a `code` (or `token_hash`) that
    // is exchanged for a session bound to the code_verifier stored on THIS
    // device — so an attacker-supplied link cannot inject or fixate a session.
    // Fixes H-5. (Web supports PKCE too; detectSessionInUrl completes it.)
    flowType: 'pkce',
  },
});
