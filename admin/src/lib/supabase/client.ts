"use client";

import { createBrowserClient } from "@supabase/ssr";
import { SUPABASE_ANON_KEY, SUPABASE_URL } from "@/lib/env";
import { SESSION_COOKIES_SECURE } from "@/lib/supabase/cookie-options";

let client: ReturnType<typeof createBrowserClient> | null = null;

/**
 * Browser Supabase client — used only by the MFA enrol/verify flow, which
 * must run in the browser (the TOTP challenge binds to the browser session).
 * Anon/publishable key only. No cookie accessors: @supabase/ssr reads and
 * writes the session through document.cookie, which is why the session
 * cookies are never HttpOnly (lib/supabase/cookie-options.ts). On Vercel the
 * cookies it writes after a verify carry Secure, like the server's.
 */
export function getSupabaseBrowserClient() {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error("Supabase env missing — check NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY");
  }
  client ??= createBrowserClient(SUPABASE_URL, SUPABASE_ANON_KEY, SESSION_COOKIES_SECURE ? { cookieOptions: { secure: true } } : undefined);
  return client;
}
