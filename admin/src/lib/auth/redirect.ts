/**
 * Validates a user-supplied "return to" path before it's used in a redirect.
 * Only same-origin, absolute-from-root paths are accepted — the open-redirect
 * guard for `next` on /login, /mfa and the proxy.
 */
const MAX_LENGTH = 512;

const CONTROL_CHARS = /[\u0000-\u001f\u007f]/;

export function safeInternalPath(input: string | null | undefined, fallback: string): string {
  if (!input) return fallback;
  if (input.length > MAX_LENGTH) return fallback;
  // Must start with exactly one "/": blocks "//evil.com" (protocol-relative)
  // and "http://…". Blocks backslashes ("/\evil.com" is protocol-relative in
  // some browsers) and control characters (ERR_INVALID_CHAR in Location).
  if (CONTROL_CHARS.test(input)) return fallback;
  if (!/^\/(?!\/)[^\s\\]*$/.test(input)) return fallback;
  // Never bounce back into the auth screens themselves (redirect loops).
  if (input === "/login" || input.startsWith("/login?") || input === "/mfa" || input.startsWith("/mfa?")) {
    return fallback;
  }
  return input;
}
