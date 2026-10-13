/**
 * src/lib/moderation/serverRefusal.ts — RC3 S5: the marketplace-safety refusals (migration 152).
 *
 * The server refuses a new bid, Buy Now reservation, listing or listing-text edit with ERRCODE
 * P0001 whose `message` is the user-facing sentence, whose `hint` is a STABLE code, and — for
 * PROHIBITED_CONTENT — whose `details` is the term. The client keys on the hint, never on the
 * message text, and shows the canonical POLICY_WORDING K2 sentence it holds here, so the wording
 * is pinned in one place and a screen never has to read a server string to show it.
 *
 * Anything that is not one of the four hints is NOT a refusal: `readServerRefusal` answers null
 * and the caller keeps the copy it showed before RC3 (the unknown-outcome wording on the bid
 * screen, "Reservation failed", "Save failed", the create screen's generic error).
 *
 * BLOCKED_PARTY and ACCOUNT_SUSPENDED invite no retry: nothing the person can do on the spot
 * changes the answer, so the dialog is OK-only and the sentence says nothing about trying again.
 * PROHIBITED_CONTENT's own sentence asks for a revision and a retry — that is the server's wording.
 */
export type RefusalCode = 'BLOCKED_PARTY' | 'LISTING_UNAVAILABLE' | 'ACCOUNT_SUSPENDED' | 'PROHIBITED_CONTENT';

export type ServerRefusal = {
  code: RefusalCode;
  title: string;
  body: string;
  /** Whether the sentence itself asks the person to try again (only the content refusal does). */
  invitesRetry: boolean;
};

/** POLICY_WORDING.md §2 K2 (A, 2026-10-13) — the server's own sentences, held here verbatim. */
export const REFUSAL_COPY = {
  BLOCKED_PARTY: {
    title: 'Not available',
    body: "This listing isn't available to you.",
  },
  LISTING_UNAVAILABLE: {
    title: 'Not available',
    body: "This listing isn't available right now.",
  },
  ACCOUNT_SUSPENDED: {
    title: 'Account suspended',
    body: "Your account is suspended, so you can't bid, buy or create listings. Orders you already have aren't affected. Contact support@snatchitapp.com.",
  },
  PROHIBITED_CONTENT: {
    title: 'Listing not allowed',
  },
} as const;

/** K2 PROHIBITED_CONTENT with the term the server named. */
export function prohibitedContentBody(term: string): string {
  return `Listings can't mention "${term}". Please revise your event name, venue, or restrictions and try again.`;
}

/** Shown only if the server named no term at all (neither `details` nor a quoted term in the message). */
export const PROHIBITED_CONTENT_FALLBACK =
  "Listings can't mention that term. Please revise your event name, venue, or restrictions and try again.";

const CODES: readonly RefusalCode[] = ['BLOCKED_PARTY', 'LISTING_UNAVAILABLE', 'ACCOUNT_SUSPENDED', 'PROHIBITED_CONTENT'];

/**
 * The refusal a PostgREST / RPC error carries, or null when it is not one of the four. The hint
 * must match exactly (case and whitespace): a sentence alone, a lower-cased code or any other
 * error shape is "unknown", so the caller's existing copy applies.
 */
export function readServerRefusal(error: unknown): ServerRefusal | null {
  if (!error || typeof error !== 'object') return null;
  const hint = (error as { hint?: unknown }).hint;
  if (typeof hint !== 'string' || !(CODES as readonly string[]).includes(hint)) return null;
  const code = hint as RefusalCode;

  if (code !== 'PROHIBITED_CONTENT') {
    return { code, title: REFUSAL_COPY[code].title, body: REFUSAL_COPY[code].body, invitesRetry: false };
  }

  const details = (error as { details?: unknown }).details;
  const message = (error as { message?: unknown }).message;
  const term =
    typeof details === 'string' && details.trim() ? details.trim()
    : typeof message === 'string' ? (/mention "([^"]+)"/.exec(message)?.[1] ?? null)
    : null;
  return {
    code,
    title: REFUSAL_COPY.PROHIBITED_CONTENT.title,
    body: term ? prohibitedContentBody(term) : PROHIBITED_CONTENT_FALLBACK,
    invitesRetry: true,
  };
}
