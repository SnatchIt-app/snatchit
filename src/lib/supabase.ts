/**
 * src/lib/supabase.ts
 * Initialises and exports the Supabase client for use across the app.
 *
 * Required .env variables (prefix EXPO_PUBLIC_ so they're bundled by Expo):
 *   EXPO_PUBLIC_SUPABASE_URL
 *   EXPO_PUBLIC_SUPABASE_ANON_KEY
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';
import 'react-native-url-polyfill/auto';

export const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
export const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

// ── Runtime guard ─────────────────────────────────────────────────────────────
// Fail loudly during development so the missing-env problem is obvious.
if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    '[SnatchIt] Supabase env vars are missing.\n' +
    'Add EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY to your .env file.\n' +
    'Get them from: Supabase dashboard → Project Settings → API.'
  );
}

// ── Client ────────────────────────────────────────────────────────────────────
export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    // Persist the session across app restarts using AsyncStorage.
    storage: AsyncStorage,
    persistSession: true,
    // Automatically refresh the JWT before it expires.
    autoRefreshToken: true,
    // Must be false for React Native – there is no browser URL to detect.
    detectSessionInUrl: false,
  },
});
