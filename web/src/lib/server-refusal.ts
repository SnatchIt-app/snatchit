/**
 * The marketplace-safety refusals from migration 152, read the way the app reads them
 * (src/lib/moderation/serverRefusal.ts at RC5).
 *
 * The server refuses a new bid, Buy Now reservation, listing or listing-text edit with ERRCODE
 * P0001: `message` is the person-facing sentence, `hint` a stable code and, for
 * PROHIBITED_CONTENT, `details` the term. We key on the hint, never on the message, and show
 * the canonical sentence held here (POLICY_WORDING.md §2 K2).
 *
 * Anything that is not one of the four hints is not a refusal: `readServerRefusal` answers null
 * and the caller keeps the copy it showed before. BLOCKED_PARTY and ACCOUNT_SUSPENDED invite no
 * retry, and their sentences say nothing about trying again.
 */
export type RefusalCode =
  | "BLOCKED_PARTY"
  | "LISTING_UNAVAILABLE"
  | "ACCOUNT_SUSPENDED"
  | "PROHIBITED_CONTENT";

export type ServerRefusal = { code: RefusalCode; message: string };

export const REFUSAL_COPY = {
  BLOCKED_PARTY: "This listing isn't available to you.",
  LISTING_UNAVAILABLE: "This listing isn't available right now.",
  ACCOUNT_SUSPENDED:
    "Your account is suspended, so you can't bid, buy or create listings. Orders you already have aren't affected. Contact support@snatchitapp.com.",
} as const;

/** K2 PROHIBITED_CONTENT with the term named. Also the web's own pre-check message. */
export function prohibitedContentMessage(term: string): string {
  return `Listings can't mention "${term}". Please revise your event name, venue, or restrictions and try again.`;
}

/** Only if the server named no term at all (neither `details` nor a quoted term in the message). */
export const PROHIBITED_CONTENT_FALLBACK =
  "Listings can't mention that term. Please revise your event name, venue, or restrictions and try again.";

const CODES: readonly string[] = [
  "BLOCKED_PARTY",
  "LISTING_UNAVAILABLE",
  "ACCOUNT_SUSPENDED",
  "PROHIBITED_CONTENT",
];

/** The refusal a PostgREST error carries, or null. The hint must match exactly. */
export function readServerRefusal(error: unknown): ServerRefusal | null {
  if (!error || typeof error !== "object") return null;
  const hint = (error as { hint?: unknown }).hint;
  if (typeof hint !== "string" || !CODES.includes(hint)) return null;
  const code = hint as RefusalCode;

  if (code !== "PROHIBITED_CONTENT") return { code, message: REFUSAL_COPY[code] };

  const details = (error as { details?: unknown }).details;
  const message = (error as { message?: unknown }).message;
  const term =
    typeof details === "string" && details.trim()
      ? details.trim()
      : typeof message === "string"
        ? (/mention "([^"]+)"/.exec(message)?.[1] ?? null)
        : null;
  return { code, message: term ? prohibitedContentMessage(term) : PROHIBITED_CONTENT_FALLBACK };
}
