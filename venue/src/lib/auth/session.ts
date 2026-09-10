import "server-only";

import { cache } from "react";
import { createSupabaseServerClient, SupabaseConfigError } from "@/lib/supabase/server";

export type AuthedUser = { id: string; email: string | null; aal: "aal1" | "aal2" | null };
export type SessionProbe = { ok: true; user: AuthedUser | null } | { ok: false; kind: "config" | "transport"; message: string };

/**
 * The only authentication primitive server code uses. getClaims() verifies
 * the JWT signature; an absent or invalid session is `user: null`, and a
 * configuration or transport failure is reported as such — never as "signed out".
 */
export const probeSession = cache(async function probeSession(): Promise<SessionProbe> {
  let supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>;
  try {
    supabase = await createSupabaseServerClient();
  } catch (e) {
    return { ok: false, kind: "config", message: e instanceof SupabaseConfigError ? e.message : "Supabase client unavailable" };
  }
  try {
    const { data, error } = await supabase.auth.getClaims();
    if (error) {
      // Auth API unreachable vs. no session: supabase-js surfaces network failures as AuthRetryableFetchError.
      if (error.name === "AuthRetryableFetchError") return { ok: false, kind: "transport", message: error.message };
      return { ok: true, user: null };
    }
    if (!data?.claims?.sub) return { ok: true, user: null };
    const aal: unknown = data.claims.aal;
    return { ok: true, user: { id: data.claims.sub, email: typeof data.claims.email === "string" ? data.claims.email : null, aal: aal === "aal1" ? "aal1" : aal === "aal2" ? "aal2" : null } };
  } catch (e) {
    return { ok: false, kind: "transport", message: e instanceof Error ? e.message : "Auth request failed" };
  }
});
