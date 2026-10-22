import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

/**
 * Sign out (database mode). POST only; clears the session cookie via the SSR client.
 *
 * The redirect carries a relative Location (allowed by RFC 9110), so the same build signs out
 * correctly on any host (localhost, a preview URL, venue.snatchitapp.com) and never depends on
 * how the platform reconstructs request.url behind its proxy. 303 makes the browser follow with
 * a GET.
 */
export async function POST() {
  try {
    const supabase = await createSupabaseServerClient();
    await supabase.auth.signOut();
  } catch {
    // No configuration: nothing to sign out of.
  }
  return new NextResponse(null, { status: 303, headers: { Location: "/login" } });
}
