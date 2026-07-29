import { safeInternalPath } from "@/lib/auth/redirect";

const ACCOUNT_PREFIX = "/account";
const AUTH_ENTRY_PATHS = new Set(["/login", "/signup"]);

export type ProxyDecision =
  | { type: "none" }
  | { type: "redirect"; path: string };

/**
 * Pure request-gating decision, factored out of proxy.ts so it's testable
 * without mocking NextRequest/NextResponse. proxy.ts is the only caller.
 */
export function decideProxyRedirect(input: {
  pathname: string;
  search: string;
  isAuthed: boolean;
  nextParam: string | null;
}): ProxyDecision {
  const { pathname, search, isAuthed, nextParam } = input;

  if (!isAuthed && pathname.startsWith(ACCOUNT_PREFIX)) {
    const returnTo = safeInternalPath(pathname + search, ACCOUNT_PREFIX);
    return { type: "redirect", path: `/login?next=${encodeURIComponent(returnTo)}` };
  }

  if (isAuthed && AUTH_ENTRY_PATHS.has(pathname)) {
    return { type: "redirect", path: safeInternalPath(nextParam, ACCOUNT_PREFIX) };
  }

  return { type: "none" };
}
