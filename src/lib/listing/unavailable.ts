/**
 * src/lib/listing/unavailable.ts — the words for a listing this viewer can no longer read.
 *
 * Migration 154 hides legacy listings from anyone who did not take part in them; their reads come back
 * with zero rows and no error. Zero rows cannot tell "hidden", "deleted" and "never existed" apart, so
 * the copy claims none of them for certain. The action is the live feed, which works from a cold start
 * or a push with nothing to go back to (CFT-605).
 */
export const LISTING_UNAVAILABLE_COPY = {
  title: 'No longer available',
  body: 'This listing may have ended, sold or been removed.',
  action: 'Browse live listings',
} as const;
