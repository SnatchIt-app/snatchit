/**
 * Validates a user-supplied "return to" path before it's used in a redirect.
 * Only same-origin, absolute-from-root paths are accepted — this is the
 * open-redirect guard for `next`/`redirect_to` query params on the auth
 * pages and proxy.
 */
const MAX_LENGTH = 512;

export function safeInternalPath(input: string | null | undefined, fallback: string): string {
  if (!input) return fallback;
  if (input.length > MAX_LENGTH) return fallback;
  // Must start with exactly one "/": blocks "//evil.com" (protocol-relative)
  // and "http://…"/"https://…". Blocks backslashes (some browsers treat
  // "/\evil.com" as protocol-relative too) and embedded control characters.
  // \s does not cover NUL, \x01-\x08 or DEL, so those reached a Location
  // header and could 500 with ERR_INVALID_CHAR. Same-origin either way.
  if (/[\u0000-\u001f\u007f]/.test(input)) return fallback;
  if (!/^\/(?!\/)[^\s\\]*$/.test(input)) return fallback;
  if (input.startsWith("/auth/")) return fallback;
  return input;
}
