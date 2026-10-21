import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { SUPABASE_ANON_KEY, SUPABASE_URL, hasSupabaseEnv } from "@/lib/env";
import { decideProxyRedirect } from "@/lib/auth/proxy-logic";
import { hostOnlyCookie } from "@/lib/supabase/cookie-options";

/**
 * Moves the session cookies a refresh wrote on the pass-through response onto
 * a redirect, host-only, plus the no-store cache headers @supabase/ssr asked
 * for. Only those: the pass-through's x-middleware-* headers must not reach a
 * redirect. Without this the browser never receives the rotated tokens, keeps
 * the old refresh token, and is signed out once the server refuses it.
 * Each cookie goes through hostOnlyCookie again, whatever wrote it.
 */
export function withSessionCookies(redirect: NextResponse, from: NextResponse, cacheHeaders: Record<string, string>): NextResponse {
  for (const { name, value, ...options } of from.cookies.getAll()) {
    redirect.cookies.set(name, value, hostOnlyCookie(options));
  }
  Object.entries(cacheHeaders).forEach(([key, value]) => redirect.headers.set(key, value));
  return redirect;
}

/**
 * Refreshes the Supabase session cookie on every matched request and gates
 * every console route on a verified session at `aal2`.
 *
 * getClaims() (not getSession()/getUser()) — verifies the JWT signature
 * rather than trusting an unverified cookie. The `aal` claim it returns is
 * the same one `ops.assert_reader()` re-checks in Postgres; the proxy is
 * UX (send the operator to the right screen), the DB is the wall.
 */
export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });
  // @supabase/ssr sends the cache headers with the first cookie write only;
  // keep them so a second setAll, or a redirect, still carries them.
  const cacheHeaders: Record<string, string> = {};

  if (!hasSupabaseEnv) {
    // No env at all: fail closed rather than render an unauthenticated shell.
    const decision = decideProxyRedirect({
      pathname: request.nextUrl.pathname,
      search: request.nextUrl.search,
      isAuthed: false,
      aal: null,
      nextParam: request.nextUrl.searchParams.get("next"),
    });
    if (decision.type === "redirect") {
      return NextResponse.redirect(new URL(decision.path, request.url));
    }
    return supabaseResponse;
  }

  const supabase = createServerClient(SUPABASE_URL!, SUPABASE_ANON_KEY!, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet, headers) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        supabaseResponse = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          // Host-only: never a Domain attribute (lib/supabase/cookie-options.ts).
          supabaseResponse.cookies.set(name, value, hostOnlyCookie(options)),
        );
        Object.assign(cacheHeaders, headers);
        Object.entries(cacheHeaders).forEach(([key, value]) => supabaseResponse.headers.set(key, value));
      },
    },
  });

  // Do not run code between createServerClient and getClaims() — a stray
  // early return here can randomly log users out.
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;

  const decision = decideProxyRedirect({
    pathname: request.nextUrl.pathname,
    search: request.nextUrl.search,
    isAuthed: Boolean(claims?.sub),
    aal: typeof claims?.aal === "string" ? claims.aal : null,
    nextParam: request.nextUrl.searchParams.get("next"),
  });

  if (decision.type === "redirect") {
    // getClaims() may have just refreshed the session: the redirect must carry it.
    return withSessionCookies(NextResponse.redirect(new URL(decision.path, request.url)), supabaseResponse, cacheHeaders);
  }

  return supabaseResponse;
}
