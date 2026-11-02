/**
 * Validates a user-supplied "return to" path before it's used in a redirect.
 * Only same-origin, absolute-from-root paths are accepted — the open-redirect
 * guard for `next` on /login, /mfa and the proxy.
 */
const MAX_LENGTH = 512;

const CONTROL_CHARS = /[\u0000-\u001f\u007f]/;

/**
 * True when the path part (before any "?" or "#") holds a "." or ".." segment,
 * or an empty segment other than a trailing slash ("//" after position 0).
 * "/.//evil.com" passes the single-leading-slash check, but dot-segment
 * removal turns its path into "//evil.com", which a consumer that normalises
 * before resolving reads as protocol-relative. WHATWG URL treats "%2e" as "."
 * inside a segment, so the encoded forms count too. The check only; the path
 * is never rewritten — it is refused.
 */
function hasDotOrEmptySegment(input: string): boolean {
  const path = input.split(/[?#]/, 1)[0].replace(/%2e/gi, ".");
  const segments = path.split("/").slice(1); // after the leading "/"
  return segments.some((s, i) => s === "." || s === ".." || (s === "" && i < segments.length - 1));
}

export function safeInternalPath(input: string | null | undefined, fallback: string): string {
  if (!input) return fallback;
  if (input.length > MAX_LENGTH) return fallback;
  // Must start with exactly one "/": blocks "//evil.com" (protocol-relative)
  // and "http://…". Blocks backslashes ("/\evil.com" is protocol-relative in
  // some browsers) and control characters (ERR_INVALID_CHAR in Location).
  if (CONTROL_CHARS.test(input)) return fallback;
  if (!/^\/(?!\/)[^\s\\]*$/.test(input)) return fallback;
  if (hasDotOrEmptySegment(input)) return fallback;
  // Never bounce back into the auth screens themselves (redirect loops).
  if (input === "/login" || input.startsWith("/login?") || input === "/mfa" || input.startsWith("/mfa?")) {
    return fallback;
  }
  return input;
}
