/**
 * src/lib/moderation/blockCopy.ts — RC3 S5: the one block confirmation (POLICY_WORDING K1).
 *
 * True only once migration 152 is applied: the server then refuses new bids and Buy Now between
 * blocked users in either direction, and exempts orders that already exist. The sentence is held
 * here so every surface that offers a block — listing detail, profile, and the two order screens —
 * confirms with the same words, and tests pin them once.
 */
export const BLOCK_CONFIRM_BODY =
  "You won't see their listings in Home or Search, and neither of you will be able to bid on or buy the other's listings. Orders you already have together aren't affected, and you can still report them.";

/** The existing pointer to where a block is undone; kept after K1 on every surface. */
export const UNBLOCK_HINT = 'You can unblock anytime in Settings → Blocked users.';

export function blockConfirmTitle(name: string): string {
  return `Block ${name}?`;
}

export function blockConfirmMessage(): string {
  return `${BLOCK_CONFIRM_BODY} ${UNBLOCK_HINT}`;
}
