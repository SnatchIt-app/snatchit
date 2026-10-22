/**
 * src/lib/a11y/announce.ts — when a screen reader should hear text that appeared or changed.
 *
 * iOS doesn't speak an `accessibilityRole="alert"` element when it appears, and
 * `accessibilityLiveRegion` is Android-only, so errors and notices were silent under VoiceOver.
 * `useAnnounceOnce` (src/hooks) speaks them; this is its decision, kept pure so it can be pinned:
 * new words once, never the same words twice in a row, and forgotten once they clear, so the same
 * error after a fresh attempt is heard again. Same rule as CheckoutView's in-flight status.
 */
export function announcementFor(
  last: string | null,
  text: string | null | undefined,
): { say: string | null; last: string | null } {
  const words = text?.trim() ? text : null;
  if (!words) return { say: null, last: null };
  if (words === last) return { say: null, last };
  return { say: words, last: words };
}
