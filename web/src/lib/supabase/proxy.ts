import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { SUPABASE_ANON_KEY, SUPABASE_URL, hasSupabaseEnv } from "@/lib/env";
import { decideProxyRedirect } from "@/lib/auth/proxy-logic";

/**
 * Refreshes the Supabase session cookie on every matched request and gates
 * /account/*. Public browsing (home, browse, listing) is never touched.
 *
 * getClaims() (not getSession()/getUser()) per current Supabase guidance —
 * it verifies the JWT signature rather than trusting an unverified cookie.
 */
export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });

  if (!hasSupabaseEnv) return supabaseResponse;

  const supabase = createServerClient(SUPABASE_URL!, SUPABASE_ANON_KEY!, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet, headers) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        supabaseResponse = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          supabaseResponse.cookies.set(name, value, options),
        );
        Object.entries(headers).forEach(([key, value]) => supabaseResponse.headers.set(key, value));
      },
    },
  });

  // Do not run code between createServerClient and getClaims() — a stray
  // early return here can randomly log users out.
  const { data } = await supabase.auth.getClaims();

  const decision = decideProxyRedirect({
    pathname: request.nextUrl.pathname,
    search: request.nextUrl.search,
    isAuthed: Boolean(data?.claims),
    nextParam: request.nextUrl.searchParams.get("next"),
  });

  if (decision.type === "redirect") {
    return NextResponse.redirect(new URL(decision.path, request.url));
  }

  return supabaseResponse;
}
