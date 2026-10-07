/**
 * src/lib/listing/editAccess.ts — may this seller edit this listing, and if not, what are they told.
 *
 * WHY THIS IS A MODULE. The screen used to decide this inline and then return from the middle of
 * its load effect, leaving `loading` set on two of the four paths; the render guard read "no
 * listing" as "still loading", so all four ended on a spinner that never stopped (E, 2026-10-05).
 * A refusal that the screen cannot render is a refusal the screen cannot be tested on, so the
 * decision and its copy live here and the screen renders what it is handed.
 *
 * The conditions are the screen's own, unchanged: the viewer must be the seller, the listing must
 * have no bids, and its auction must still be active. The server-side
 * `guard_listing_state_columns` and RLS remain the hard wall; this only decides what the seller
 * sees before reaching it.
 */

/** The four refusals, in the order the screen checks them. */
export type EditRefusalKind = 'signed-out' | 'not-found' | 'not-owner' | 'has-bids' | 'inactive';

export interface EditRefusal {
  kind: EditRefusalKind;
  title: string;
  body: string;
}

/** Only the fields the decision reads, so a test can drive it with a plain object. */
export interface EditCandidate {
  seller_id?: string | null;
  bid_count?: number | null;
  auction_status?: string | null;
}

/**
 * One source for these sentences, read by both the alert and the refusal the screen renders.
 *
 * The four event-listing sentences are the screen's existing copy, kept word for word. The
 * signed-out pair is the app's existing treatment for a signed-out viewer, as ListingDetailScreen,
 * the public profile and the report screen already word it.
 */
export const EDIT_REFUSAL_COPY = {
  'signed-out': { title: 'Sign in required', body: 'You need to be signed in to edit a listing.' },
  'not-found': { title: 'Listing not found', body: 'Try again later.' },
  'not-owner': { title: 'Not allowed', body: 'You can only edit your own listings.' },
  'has-bids': { title: 'Cannot edit', body: 'This listing already has bids. Use Cancel from My Listings if you need to remove it.' },
  inactive: { title: 'Cannot edit', body: 'This listing is no longer active.' },
} as const;

/** One refusal, worded from the table above. Exported for the paths that have nothing to read. */
export function editRefusalCopy(kind: EditRefusalKind, body?: string | null): EditRefusal {
  return { kind, title: EDIT_REFUSAL_COPY[kind].title, body: body || EDIT_REFUSAL_COPY[kind].body };
}

/**
 * Why this listing cannot be edited, or null when it can.
 *
 * `readError` is the server's own sentence for a failed or empty read; it replaces the generic
 * body when present, which is what the screen already did.
 */
export function editRefusal(i: {
  listing: EditCandidate | null | undefined;
  viewerId: string | null | undefined;
  readError?: string | null;
}): EditRefusal | null {
  if (!i.viewerId) return editRefusalCopy('signed-out');
  if (!i.listing) return editRefusalCopy('not-found', i.readError);
  if (i.listing.seller_id !== i.viewerId) return editRefusalCopy('not-owner');
  if ((i.listing.bid_count ?? 0) > 0) return editRefusalCopy('has-bids');
  if ((i.listing.auction_status ?? 'active') !== 'active') return editRefusalCopy('inactive');
  return null;
}

/** What the screen is showing. A refusal is terminal: it is never "still loading". */
export type EditPhase = 'loading' | 'refused' | 'ready';

export function editPhase(i: {
  authLoading: boolean;
  loading: boolean;
  refusal: EditRefusal | null;
  listing: unknown | null;
}): EditPhase {
  if (i.refusal) return 'refused';
  if (i.authLoading || i.loading || !i.listing) return 'loading';
  return 'ready';
}
