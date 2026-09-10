/**
 * Validates a user-supplied "return to" path before it is used in a redirect.
 * Same-origin, absolute-from-root paths only (open-redirect guard for `next`).
 */
const MAX_LENGTH = 512;
const CONTROL_CHARS = /[\u0000-\u001f\u007f]/;

export function safeInternalPath(input: string | null | undefined, fallback: string): string {
  if (!input) return fallback;
  if (input.length > MAX_LENGTH) return fallback;
  if (CONTROL_CHARS.test(input)) return fallback;
  if (!/^\/(?!\/)[^\s\\]*$/.test(input)) return fallback;
  if (input === "/login" || input.startsWith("/login?")) return fallback;
  return input;
}
