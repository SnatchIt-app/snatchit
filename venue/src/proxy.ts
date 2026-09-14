import type { NextRequest } from "next/server";
import { refreshSession } from "@/lib/supabase/proxy";

// Next.js 16: middleware.ts -> proxy.ts. Database mode only: persists a refreshed
// Supabase session to the browser before the page renders. Authorization stays in
// lib/page.ts (entry policy) and in Postgres (RLS).
export async function proxy(request: NextRequest) {
  return refreshSession(request);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
