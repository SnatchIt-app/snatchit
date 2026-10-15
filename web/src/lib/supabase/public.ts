import "server-only";

import { createClient } from "@supabase/supabase-js";
import { SUPABASE_ANON_KEY, SUPABASE_URL } from "@/lib/env";

/**
 * Cookieless anon client for the public catalog: home, browse, related
 * listings, the public events feed and the sitemap.
 *
 * Those surfaces must show exactly what an anonymous visitor may see. Read
 * through the cookie client, a signed-in seller or bidder also gets the
 * listings that RLS lets only participants read (hidden listings), and
 * /api/public/events sends its body with `Cache-Control: public` — the CDN
 * does not vary on cookies, so one participant's request would serve their
 * hidden rows to everyone for the cache window.
 *
 * No session is read, stored or refreshed. Never use this for anything that
 * depends on who the viewer is.
 */
export function createSupabasePublicClient() {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error("Supabase env missing — check NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY");
  }
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}
