/**
 * src/lib/listing/listingRefusal.ts — what a seller is told when deleting, cancelling or editing a
 * listing fails (CFT-703).
 *
 * WHY THIS IS A MODULE. All three actions showed the server's `error.message` raw. For delete that
 * is a foreign-key sentence naming `payments`, `transfers`, `listing_visibility` and the constraint
 * (and, for DEL-2, revealing that hiding exists); for edit it is a check-constraint sentence naming
 * `relation "listings"`. A's refusal catalogue (sprint-control/SERVER_REFUSAL_CATALOGUE_C_20261021.md
 * §1-3, §6-8) lists every refusal each action can meet, with the exact text, SQLSTATE and hint.
 * This module turns that catalogue into one pure decision per action, so the screens hold no
 * server strings and a test can drive every row with the catalogue's verbatim messages.
 *
 * THE RECIPE (catalogue §"Matching recipe"), in order:
 *   1. the `hint`, when there is one — the four marketplace-safety hints go through
 *      `readServerRefusal`, which already owns their K2 sentences;
 *   2. the `code` (SQLSTATE): 23503 for delete, 23514 for edit, 42501 for cancel, PGRST30x (an
 *      expired session) for all three — then, for 23503/23514, the constraint name inside the
 *      message, because the code alone does not say which row it was;
 *   3. an EXACT message, only for the cancel refusals that carry neither hint nor useful code
 *      (CAN-1, CAN-2, CAN-4). Exact, not a prefix or a substring: any rewording falls safely to
 *      the generic line rather than to the wrong sentence;
 *   4. a network failure (`isNetworkError`) gets the connection line; anything else the action's
 *      generic line.
 *
 * The caller logs the raw error with console.warn and never shows it. `refresh` is true where the
 * refusal means the screen was stale (sold, gone, already removed), so the caller re-reads.
 *
 * When A lands stable hints for CAN-1/CAN-2 (catalogue §7, P2), add them at step 1 and keep the
 * exact-text match as the fallback.
 */

import { readServerRefusal } from '@/src/lib/moderation/serverRefusal';
import { isNetworkError } from '@/src/lib/ui/loadState';

export interface ListingActionFailure {
  /** The catalogue ID matched, or the fallback that applied. For tests and the log, never shown. */
  id: string;
  title: string;
  body: string;
  /** The refusal says the screen is out of date: the caller re-reads. */
  refresh: boolean;
}

export const LISTING_REFUSAL_COPY = {
  network: 'Check your connection and try again.',
  signIn: 'Please sign in again.',
  delete: {
    title: 'Delete failed',
    generic: "We couldn't delete this listing. Please try again.",
    /** DEL-1, DEL-4 and any other 23503. */
    checkout: "This listing has had checkout activity, so it can't be deleted. You can cancel it instead.",
    /** DEL-2. */
    hidden: "This listing is no longer shown to buyers and can't be deleted. Contact support@snatchitapp.com if you need it removed.",
    /** DEL-3. */
    sold: "This listing has sold, so it can't be deleted.",
    /** DEL-5: the call succeeded and removed nothing. */
    alreadyRemoved: 'This listing was already removed.',
  },
  cancel: {
    title: 'Cancel failed',
    generic: "We couldn't cancel this listing. Please try again.",
    /** CAN-1. */
    sold: "This listing has already sold, so it can't be cancelled.",
    /** CAN-2. */
    gone: 'This listing is no longer available.',
  },
  edit: {
    title: 'Save failed',
    generic: "Your changes weren't saved. Please try again.",
    eventNameLength: 'Event name can be up to 120 characters.',
    venueLength: 'Venue can be up to 120 characters.',
    restrictionsLength: 'Restrictions can be up to 500 characters.',
  },
} as const;

type Fields = { code: string; message: string };

function fields(error: unknown): Fields {
  if (!error || typeof error !== 'object') return { code: '', message: '' };
  const { code, message } = error as { code?: unknown; message?: unknown };
  return {
    code: typeof code === 'string' ? code : '',
    message: typeof message === 'string' ? message : '',
  };
}

/** The quoted constraint name in a 23503/23514 message, or null. */
function constraintName(message: string): string | null {
  return /violates (?:foreign key|check) constraint "([^"]+)"/.exec(message)?.[1] ?? null;
}

/** §6: an expired or unusable session (PostgREST PGRST30x, "JWT expired"). */
function isExpiredSession(f: Fields): boolean {
  return /^PGRST30\d$/.test(f.code) || f.message === 'JWT expired';
}

function fail(id: string, title: string, body: string, refresh = false): ListingActionFailure {
  return { id, title, body, refresh };
}

/** Step 1, shared: a marketplace-safety hint keeps its own K2 title and sentence. */
function fromHint(error: unknown, ids: Partial<Record<string, string>> = {}): ListingActionFailure | null {
  const r = readServerRefusal(error);
  return r ? fail(ids[r.code] ?? r.code, r.title, r.body) : null;
}

/** Step 4, shared. */
function fallback(error: unknown, title: string, generic: string): ListingActionFailure {
  return isNetworkError(error)
    ? fail('network', title, LISTING_REFUSAL_COPY.network)
    : fail('generic', title, generic);
}

const DELETE_BY_CONSTRAINT: Record<string, { id: string; body: string; refresh: boolean }> = {
  payments_listing_id_fkey: { id: 'DEL-1', body: LISTING_REFUSAL_COPY.delete.checkout, refresh: false },
  listing_visibility_listing_id_fkey: { id: 'DEL-2', body: LISTING_REFUSAL_COPY.delete.hidden, refresh: false },
  transfers_listing_id_fkey: { id: 'DEL-3', body: LISTING_REFUSAL_COPY.delete.sold, refresh: true },
  webhook_retries_listing_id_fkey: { id: 'DEL-4', body: LISTING_REFUSAL_COPY.delete.checkout, refresh: false },
};

/** A delete that returned an error (catalogue §1 DEL-1 to DEL-4, §6). */
export function listingDeleteFailure(error: unknown): ListingActionFailure {
  const { title } = LISTING_REFUSAL_COPY.delete;
  const hinted = fromHint(error);
  if (hinted) return hinted;
  const f = fields(error);
  if (f.code === '23503') {
    const hit = DELETE_BY_CONSTRAINT[constraintName(f.message) ?? ''];
    return hit
      ? fail(hit.id, title, hit.body, hit.refresh)
      : fail('DEL-1', title, LISTING_REFUSAL_COPY.delete.checkout);
  }
  if (isExpiredSession(f)) return fail('session', title, LISTING_REFUSAL_COPY.signIn);
  return fallback(error, title, LISTING_REFUSAL_COPY.delete.generic);
}

/** DEL-5: the delete succeeded and removed no row — gone already, or no longer the caller's. */
export function listingDeleteNoRows(): ListingActionFailure {
  return fail('DEL-5', LISTING_REFUSAL_COPY.delete.title, LISTING_REFUSAL_COPY.delete.alreadyRemoved, true);
}

/** `cancel_listing` refusals, matched exactly as the catalogue lists them (§2). */
const CANCEL_BY_MESSAGE: Record<string, { id: string; body: string; refresh: boolean }> = {
  'This listing has already been sold and cannot be cancelled.': { id: 'CAN-1', body: LISTING_REFUSAL_COPY.cancel.sold, refresh: true },
  'Listing not found.': { id: 'CAN-2', body: LISTING_REFUSAL_COPY.cancel.gone, refresh: true },
  'Unable to identify caller. Ensure the request is authenticated.': { id: 'CAN-4', body: LISTING_REFUSAL_COPY.signIn, refresh: false },
};

/** A `cancel_listing` call that returned an error (catalogue §2, §6). */
export function listingCancelFailure(error: unknown): ListingActionFailure {
  const { title } = LISTING_REFUSAL_COPY.cancel;
  const hinted = fromHint(error);
  if (hinted) return hinted;
  const f = fields(error);
  if (f.code === '42501') return fail('CAN-5', title, LISTING_REFUSAL_COPY.signIn);
  if (isExpiredSession(f)) return fail('session', title, LISTING_REFUSAL_COPY.signIn);
  const hit = Object.prototype.hasOwnProperty.call(CANCEL_BY_MESSAGE, f.message) ? CANCEL_BY_MESSAGE[f.message] : undefined;
  if (hit) return fail(hit.id, title, hit.body, hit.refresh);
  return fallback(error, title, LISTING_REFUSAL_COPY.cancel.generic);
}

const EDIT_BY_CONSTRAINT: Record<string, { id: string; body: string }> = {
  listings_event_name_len_check: { id: 'EDT-3', body: LISTING_REFUSAL_COPY.edit.eventNameLength },
  // The duplicate check sorts later and never reports today (catalogue EDT-3); mapped in case it does.
  listings_event_name_length: { id: 'EDT-3', body: LISTING_REFUSAL_COPY.edit.eventNameLength },
  listings_venue_len_check: { id: 'EDT-4', body: LISTING_REFUSAL_COPY.edit.venueLength },
  listings_restrictions_len_check: { id: 'EDT-5', body: LISTING_REFUSAL_COPY.edit.restrictionsLength },
};

/** A listing-edit UPDATE that returned an error (catalogue §3, §6). */
export function listingEditFailure(error: unknown): ListingActionFailure {
  const { title } = LISTING_REFUSAL_COPY.edit;
  const hinted = fromHint(error, { PROHIBITED_CONTENT: 'EDT-1', ACCOUNT_SUSPENDED: 'EDT-2' });
  if (hinted) return hinted;
  const f = fields(error);
  if (f.code === '23514') {
    const hit = EDIT_BY_CONSTRAINT[constraintName(f.message) ?? ''];
    if (hit) return fail(hit.id, title, hit.body);
    return fail('generic', title, LISTING_REFUSAL_COPY.edit.generic);
  }
  if (isExpiredSession(f)) return fail('session', title, LISTING_REFUSAL_COPY.signIn);
  return fallback(error, title, LISTING_REFUSAL_COPY.edit.generic);
}

/**
 * My Listings' own delete gate (`bid_count > 0 || auction_status !== 'active'`). It used to say
 * "This listing has bids" for every row it stopped, including a no-bid listing that had simply
 * ended or been cancelled. The sentence now names the condition that actually applies.
 */
export function deleteGateCopy(l: { bid_count?: number | null; auction_status?: string | null }): { title: string; body: string } {
  const title = 'Cannot delete';
  if ((l.bid_count ?? 0) > 0) return { title, body: "This listing has bids, so it can't be deleted." };
  if (l.auction_status === 'cancelled') return { title, body: "This listing was cancelled, so it can't be deleted." };
  if (l.auction_status === 'sold') return { title, body: "This listing has sold, so it can't be deleted." };
  return { title, body: "This listing has ended, so it can't be deleted." };
}
