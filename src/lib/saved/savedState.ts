/**
 * src/lib/saved/savedState.ts — the words and the decisions for saved listings. No I/O, no React.
 *
 * Saved listings live in the EXISTING public.saved_listings table (migration 040): one row per
 * (user, listing), RLS lets an owner select, insert and delete their own rows and nothing else, and
 * there is no UPDATE policy — a save is present or absent. Live web uses the same rows, so a listing
 * saved on one shows up on the other.
 *
 * THE LISTING EMBED CAN BE NULL, and that is normal. Migration 154 leaves saved_listings out of
 * listing_private_party on purpose (pgTAP 221 E1/E2): saving a listing grants no visibility, so a
 * listing hidden from this viewer comes back as a saved row with a NULL embed. Zero information about
 * why survives that read — hidden, ended and sold all look the same — so the screen counts these rows
 * and never says which.
 */

import type { Listing } from '@/src/types';
import type { LoadFailureKind } from '@/src/lib/ui/loadState';

export const SAVED_COPY = {
  /** The control's spoken name. Its on/off state is reported as `selected`, so the name stays put. */
  controlLabel: 'Save listing',
  /** Web's own failure strings (web/src/lib/favorites-actions.ts), one per direction. */
  saveFailed: "Couldn't save this listing. Try again.",
  removeFailed: "Couldn't remove this listing. Try again.",
  screenTitle: 'Saved',
  emptyTitle: 'Nothing saved yet',
  emptyBody: 'Tap the bookmark on any listing to save it here.',
  /** The native wording for the live feed (LISTING_UNAVAILABLE_COPY.action). */
  emptyAction: 'Browse live listings',
  /** The app's one wording for an action refused to a signed-out viewer. */
  signedOutTitle: 'Sign in required',
  signedOutBody: 'You need to be signed in to see your saved listings.',
  signedOutAction: 'Sign in',
  /** A failed QUIET refresh over rows already shown (the BIDS_REFRESH_FAILED_COPY pattern). */
  refreshFailed: {
    offline: "You're offline. Showing your saved listings from earlier.",
    error: "Couldn't refresh your saved listings. Showing what loaded earlier.",
  },
} as const;

/** The note a rollback shows: `failed` is the value that did not save (true = a save, false = a remove). */
export function rollbackNote(failed: boolean): string {
  return failed ? SAVED_COPY.saveFailed : SAVED_COPY.removeFailed;
}

/** "N saved listing(s) no longer available." — a count, never a reason. Null when there are none. */
export function unavailableLine(count: number): string | null {
  if (!(count > 0)) return null;
  return `${count} saved listing${count === 1 ? '' : 's'} no longer available.`;
}

export interface SavedRow {
  /** saved_listings.id */
  id: string;
  listingId: string;
  createdAt: string;
  listing: Listing;
}

export interface SavedPartition {
  /** Readable listings, in the server's order (newest save first). */
  rows: SavedRow[];
  /** Saved rows whose listing this viewer cannot read. */
  unavailableCount: number;
  /** Every saved listing id the read returned, readable or not. */
  savedIds: string[];
}

function embedOf(raw: unknown): Listing | null {
  // A to-one embed is an object; anything else (null, an array, a missing key) is not readable.
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const listing = raw as Partial<Listing>;
  return typeof listing.id === 'string' ? (listing as Listing) : null;
}

/** Splits a saved_listings read into readable rows and a count of the rest. Never throws. */
export function partitionSaved(data: unknown): SavedPartition {
  const rows: SavedRow[] = [];
  const savedIds: string[] = [];
  let unavailableCount = 0;
  if (!Array.isArray(data)) return { rows, unavailableCount, savedIds };
  for (const raw of data) {
    if (!raw || typeof raw !== 'object') continue; // not a saved row at all
    const r = raw as { id?: unknown; listing_id?: unknown; created_at?: unknown; listing?: unknown };
    if (typeof r.listing_id === 'string') savedIds.push(r.listing_id);
    const listing = embedOf(r.listing);
    if (listing && typeof r.id === 'string') {
      rows.push({
        id: r.id,
        listingId: typeof r.listing_id === 'string' ? r.listing_id : listing.id,
        createdAt: typeof r.created_at === 'string' ? r.created_at : '',
        listing,
      });
    } else {
      unavailableCount += 1;
    }
  }
  return { rows, unavailableCount, savedIds };
}

export type SavedLoad =
  | { phase: 'loading' }
  /** The first read failed: nothing to keep. */
  | { phase: 'failed'; failure: LoadFailureKind }
  | { phase: 'ready'; rows: SavedRow[]; unavailableCount: number; refreshFailure: LoadFailureKind | null };

export type SavedView =
  | { kind: 'auth-loading' }
  | { kind: 'signed-out' }
  | { kind: 'loading' }
  | { kind: 'failed'; failure: LoadFailureKind }
  | { kind: 'empty' }
  | { kind: 'list'; rows: SavedRow[]; unavailableLine: string | null; refreshNote: string | null };

/**
 * Which screen the Saved route shows. Genuinely empty, a failed read and signed out are three
 * different screens (the owner's "no data versus failed lookup" rule). `isUnsaved` drops a row the
 * user has unsaved elsewhere (listing detail) since this list loaded.
 */
export function savedView(input: {
  authLoading: boolean;
  userId: string | null | undefined;
  load: SavedLoad;
  isUnsaved: (listingId: string) => boolean;
}): SavedView {
  if (input.authLoading) return { kind: 'auth-loading' };
  if (!input.userId) return { kind: 'signed-out' };
  const { load } = input;
  if (load.phase === 'loading') return { kind: 'loading' };
  if (load.phase === 'failed') return { kind: 'failed', failure: load.failure };
  const rows = load.rows.filter((r) => !input.isUnsaved(r.listingId));
  const line = unavailableLine(load.unavailableCount);
  if (rows.length === 0 && !line) return { kind: 'empty' };
  return {
    kind: 'list',
    rows,
    unavailableLine: line,
    refreshNote: load.refreshFailure ? SAVED_COPY.refreshFailed[load.refreshFailure] : null,
  };
}
