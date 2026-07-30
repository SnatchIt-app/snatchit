import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "@/lib/env";

/**
 * Server-to-server call to a Supabase edge function, relaying the current
 * user's access token as a Bearer token.
 *
 * Several existing edge functions (create-connect-account, delete-account,
 * create-payment-intent, confirm-payment, confirm-and-release) hardcode
 * their CORS allowlist to snatchitapp.com only — calling them from browser
 * JS on snatchti.com would be blocked. Server-to-server fetch isn't subject
 * to CORS at all, and matches this app's existing pattern of doing all
 * Supabase access through the server client — use this for every edge
 * function call from web, not direct client-side supabase.functions.invoke.
 *
 * getSession() is used only to relay the token string; its validity is
 * re-checked by the edge function itself (auth.getUser(token)), so this
 * never uses getSession() as an authorization decision on its own.
 */
export async function callEdgeFunction<T = Record<string, unknown>>(
  name: string,
  body: Record<string, unknown>,
): Promise<T & { error?: string }> {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error("Supabase env missing");
  }

  const supabase = await createSupabaseServerClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session?.access_token) {
    throw new Error("No active session");
  }

  const res = await fetch(`${SUPABASE_URL}/functions/v1/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${session.access_token}`,
      apikey: SUPABASE_ANON_KEY,
    },
    body: JSON.stringify(body),
    cache: "no-store",
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    return { ...data, error: typeof data?.error === "string" ? data.error : `${name} failed` };
  }
  return data;
}
