import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { SUPABASE_ANON_KEY, SUPABASE_URL } from "@/lib/env";

/**
 * Server-side Supabase client (Server Components, Route Handlers, Server
 * Actions) using the official @supabase/ssr cookie pattern.
 *
 * Phase-0 scope: anonymous, read-only public queries (listings/profiles have
 * deliberate public SELECT policies). No auth surface exists on web yet.
 *
 * ⚠ For future authenticated routes: never trust getSession() server-side —
 * authorize with supabase.auth.getClaims() (signature-validated) per current
 * Supabase guidance, and re-check row ownership in RLS-backed queries.
 */
export async function createSupabaseServerClient() {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error("Supabase env missing — check NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY");
  }
  const cookieStore = await cookies();

  return createServerClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options),
          );
        } catch {
          // Called from a Server Component — safe to ignore; session refresh
          // will be handled by proxy.ts once auth ships on web.
        }
      },
    },
  });
}
