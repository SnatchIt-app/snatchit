import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import {
  DATA_SOURCE,
  SUPABASE_ANON_KEY,
  SUPABASE_URL,
  keyLooksPrivileged,
} from "@/lib/env";

/**
 * Session refresh for database mode (official @supabase/ssr proxy pattern).
 *
 * Server Components cannot write cookies, so a session refreshed during a page
 * render (lib/supabase/server.ts) would live for that one request only. Hosted
 * Supabase rotates refresh tokens and revokes a reused one after its reuse
 * interval, so the next request would present a spent token and the staff
 * member would be signed out. Running getClaims() here, before the page, lets
 * a refresh write the new session back to the browser.
 *
 * No redirects and no authorization decisions: the page-level entry policy
 * (lib/page.ts) and RLS stay the only gates. Fixture mode never builds a client.
 */
export async function refreshSession(request: NextRequest) {
  let response = NextResponse.next({ request });
  if (
    DATA_SOURCE !== "database" ||
    !SUPABASE_URL ||
    !SUPABASE_ANON_KEY ||
    keyLooksPrivileged(SUPABASE_ANON_KEY)
  ) {
    return response;
  }

  const supabase = createServerClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: {
      fetch: (input: RequestInfo | URL, init?: RequestInit) =>
        fetch(input, { ...init, cache: "no-store" }),
    },
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet, headers) {
        cookiesToSet.forEach(({ name, value }) =>
          request.cookies.set(name, value),
        );
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options),
        );
        Object.entries(headers ?? {}).forEach(([key, value]) =>
          response.headers.set(key, value),
        );
      },
    },
  });

  // Nothing between createServerClient and getClaims(): the refresh must land on `response`.
  try {
    await supabase.auth.getClaims();
  } catch {
    // Transport/config failures are reported by the page itself (DataSourceError); never block the request here.
  }
  return response;
}
