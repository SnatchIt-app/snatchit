import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "@/lib/env";

/**
 * Server-to-server call to a Supabase edge function, relaying the operator's
 * own access token as the Bearer token (same pattern as web/src/lib/
 * edge-functions.ts). The function re-verifies the token itself; the token
 * string is relayed, never used here as an authorization decision.
 *
 * Never carries a service-role key — this app has none.
 */
export type EdgeResult<T = Record<string, unknown>> =
  | { ok: true; status: number; data: T }
  | { ok: false; status: number; error: string; detail?: string; data?: Record<string, unknown>; unreachable: boolean };

export async function callEdgeFunction<T = Record<string, unknown>>(name: string, body: Record<string, unknown>): Promise<EdgeResult<T>> {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return { ok: false, status: 0, error: "Supabase env missing", unreachable: true };
  }
  const supabase = await createSupabaseServerClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session?.access_token) {
    return { ok: false, status: 401, error: "No active session", unreachable: false };
  }

  let res: Response;
  try {
    res = await fetch(`${SUPABASE_URL}/functions/v1/${name}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session.access_token}`,
        apikey: SUPABASE_ANON_KEY,
      },
      body: JSON.stringify(body),
      cache: "no-store",
    });
  } catch (e) {
    return { ok: false, status: 0, error: e instanceof Error ? e.message : "fetch failed", unreachable: true };
  }

  const data: unknown = await res.json().catch(() => ({}));
  const rec = typeof data === "object" && data !== null && !Array.isArray(data) ? (data as Record<string, unknown>) : {};
  if (!res.ok) {
    return {
      ok: false,
      status: res.status,
      error: typeof rec.error === "string" ? rec.error : `${name} failed (${res.status})`,
      detail: typeof rec.detail === "string" ? rec.detail : typeof rec.message === "string" ? rec.message : undefined,
      data: rec,
      // 404 = function not deployed; 503 = gateway has no backend for it.
      unreachable: res.status === 404 || res.status === 503,
    };
  }
  return { ok: true, status: res.status, data: rec as T };
}
