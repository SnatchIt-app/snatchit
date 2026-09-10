import "server-only";

import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { SUPABASE_ANON_KEY, SUPABASE_URL, keyLooksPrivileged } from "@/lib/env";

export class SupabaseConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SupabaseConfigError";
  }
}

/**
 * Server-side Supabase client using the official @supabase/ssr cookie pattern.
 * Anon key + the signed-in staff member's session cookie. There is no
 * privileged client anywhere in this app, and a service-role key in the
 * public slot is refused rather than used.
 */
export async function createSupabaseServerClient() {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new SupabaseConfigError("NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY are not set");
  }
  if (keyLooksPrivileged(SUPABASE_ANON_KEY)) {
    throw new SupabaseConfigError("NEXT_PUBLIC_SUPABASE_ANON_KEY carries role=service_role — refusing to start a browser-class client with it");
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
          // Server Component render path: cookies are read-only here; the
          // sign-in/sign-out server actions own cookie writes.
        }
      },
    },
  });
}
