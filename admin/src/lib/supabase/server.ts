import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { SUPABASE_ANON_KEY, SUPABASE_URL } from "@/lib/env";

/**
 * Server-side Supabase client (Server Components, Server Actions) using the
 * official @supabase/ssr cookie pattern. Anon key + the operator's session
 * cookie; there is no privileged client anywhere in this app.
 *
 * Authorize with supabase.auth.getClaims() (signature-validated) — never
 * getSession() — and let the `ops.*` functions re-check role/aal in Postgres.
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
          cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
        } catch {
          // Called from a Server Component — safe to ignore; proxy.ts owns
          // session refresh on the request path.
        }
      },
    },
  });
}
