/**
 * Client-side listing content gate — ported from CreateListingScreen's
 * banned-word scan (mobile checks eventName+venue+restrictions the same
 * way, client-only, no server-side mirror on either platform).
 */
const BANNED_TERMS = [
  "alcohol",
  "drugs",
  "weed",
  "cocaine",
  "molly",
  "open bar",
  "bottle service",
  "fake ticket",
  "fake tickets",
  "counterfeit",
  "underage",
];

export function findBannedTerm(text: string): string | null {
  const lower = text.toLowerCase();
  return BANNED_TERMS.find((term) => lower.includes(term)) ?? null;
}
