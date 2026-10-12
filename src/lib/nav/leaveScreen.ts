/**
 * src/lib/nav/leaveScreen.ts — the one action a terminal state offers, and why it cannot be inert.
 *
 * A screen that can only refuse needs an exit, and `router.back()` alone is not one: opened from a
 * notification, a deep link or a cold start there is no screen underneath, so the only control on
 * a refusal does nothing when it is pressed. ListingDetailScreen already says this about its own
 * not-found state (CFT-605) and answers it with a destination that always works.
 *
 * So the rule is: go back when there is something to go back to, and otherwise land on the board
 * the screen is opened from. Kept pure and separate from `router` so both halves of a refusal — the
 * alert's OK and the state's action — can be held to the same exit by a test.
 */

export type Exit =
  | { kind: 'back' }
  | { kind: 'replace'; href: string };

export function exitRoute(canGoBack: boolean, fallback: string): Exit {
  return canGoBack ? { kind: 'back' } : { kind: 'replace', href: fallback };
}
