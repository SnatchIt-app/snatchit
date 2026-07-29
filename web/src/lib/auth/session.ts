import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export type AuthedUser = {
  id: string;
  email: string | null;
};

/**
 * The only authorization primitive server code should use. Verifies the JWT
 * signature (getClaims()) rather than trusting an unvalidated session cookie
 * — never use auth.getSession() for authorization (see proxy.ts).
 */
export async function getAuthedUser(): Promise<AuthedUser | null> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.getClaims();
  if (error || !data?.claims?.sub) return null;
  return {
    id: data.claims.sub,
    email: typeof data.claims.email === "string" ? data.claims.email : null,
  };
}

/** For Server Components/Actions that require an authenticated user. */
export async function requireAuthedUser(): Promise<AuthedUser> {
  const user = await getAuthedUser();
  if (!user) throw new Error("UNAUTHENTICATED");
  return user;
}
