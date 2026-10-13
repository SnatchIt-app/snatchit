/**
 * Listing content pre-check (Apple Guideline 1.4.3).
 *
 * Pattern for pattern the app's BANNED_CONTENT_PATTERNS (src/lib/sell/sellState.ts) and the
 * server's listing_prohibited_term() from migration 152, which refuses these terms on every
 * listing insert and text edit, for every caller (hint PROHIBITED_CONTENT). This copy only saves
 * a round trip: the server decides. Matching is by word, so "drugstore" passes here exactly as it
 * passes the server. tests/content-moderation-parity.test.ts pins the lists together.
 */
export const BANNED_CONTENT_PATTERNS: readonly { pattern: RegExp; label: string }[] = [
  { pattern: /\balcohol\b/i, label: "alcohol" },
  { pattern: /\bdrugs?\b/i, label: "drugs" },
  { pattern: /\bweed\b/i, label: "weed" },
  { pattern: /\bcocaine\b/i, label: "cocaine" },
  { pattern: /\bmolly\b/i, label: "molly" },
  { pattern: /\bopen[\s-]?bar\b/i, label: "open bar" },
  { pattern: /\bbottle[\s-]?service\b/i, label: "bottle service" },
  { pattern: /\bfake[\s-]?tickets?\b/i, label: "fake ticket" },
  { pattern: /\bcounterfeit\b/i, label: "counterfeit" },
  { pattern: /\bunderage\b/i, label: "underage" },
];

/**
 * The first banned term across the listing's free-text fields, or null. The fields are joined
 * the way the server joins them (E' \n '), so a term never matches across two fields here
 * unless it would there too.
 */
export function findBannedTerm(fields: readonly (string | null | undefined)[]): string | null {
  const haystack = fields.filter(Boolean).join(" \n ");
  for (const { pattern, label } of BANNED_CONTENT_PATTERNS) {
    if (pattern.test(haystack)) return label;
  }
  return null;
}
