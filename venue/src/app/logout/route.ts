import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

/** Sign out (database mode). POST only; clears the session cookie via the SSR client. */
export async function POST(request: Request) {
  try {
    const supabase = await createSupabaseServerClient();
    await supabase.auth.signOut();
  } catch {
    // No configuration: nothing to sign out of.
  }
  return NextResponse.redirect(new URL("/login", request.url), { status: 303 });
}
