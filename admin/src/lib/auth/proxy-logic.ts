import { safeInternalPath } from "@/lib/auth/redirect";

export type ProxyDecision = { type: "none" } | { type: "redirect"; path: string };

/** Routes reachable without a session. */
const PUBLIC_PATHS = new Set(["/login", "/favicon.ico"]);
/** Routes reachable with a session at any assurance level (aal1 allowed). */
const SESSION_ONLY_PATHS = new Set(["/mfa", "/denied"]);

function isPublic(pathname: string): boolean {
  return PUBLIC_PATHS.has(pathname) || pathname.startsWith("/_next");
}

/**
 * Pure request-gating decision, factored out of proxy.ts so it's testable
 * without mocking NextRequest/NextResponse. proxy.ts is the only caller.
 *
 * Rules:
 *  - anything not public requires a verified session;
 *  - anything not public and not session-only additionally requires aal2;
 *  - an already-aal2 session on /login or /mfa is bounced to `next` (or "/");
 *  - an aal1 session on /login is sent to /mfa (carrying `next`).
 */
export function decideProxyRedirect(input: {
  pathname: string;
  search: string;
  isAuthed: boolean;
  aal: string | null;
  nextParam: string | null;
}): ProxyDecision {
  const { pathname, search, isAuthed, aal, nextParam } = input;

  if (isPublic(pathname)) {
    if (pathname === "/login" && isAuthed) {
      const next = safeInternalPath(nextParam, "/");
      if (aal === "aal2") return { type: "redirect", path: next };
      return { type: "redirect", path: `/mfa?next=${encodeURIComponent(next)}` };
    }
    return { type: "none" };
  }

  if (!isAuthed) {
    const returnTo = safeInternalPath(pathname + search, "/");
    return { type: "redirect", path: `/login?next=${encodeURIComponent(returnTo)}` };
  }

  if (SESSION_ONLY_PATHS.has(pathname)) {
    if (pathname === "/mfa" && aal === "aal2") {
      return { type: "redirect", path: safeInternalPath(nextParam, "/") };
    }
    return { type: "none" };
  }

  if (aal !== "aal2") {
    const returnTo = safeInternalPath(pathname + search, "/");
    return { type: "redirect", path: `/mfa?next=${encodeURIComponent(returnTo)}` };
  }

  return { type: "none" };
}
