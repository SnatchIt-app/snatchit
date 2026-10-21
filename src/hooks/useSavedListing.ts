/**
 * src/hooks/useSavedListing.ts — one listing's Save control: instant, latest tap wins, rolled back
 * with a short announced note when the server refuses (checklist item 11).
 *
 * Returns null — no control at all — whenever the control could not be true:
 *  - `enabled` is false: the caller passes false while auth or the listing is still loading, and on a
 *    listing this viewer cannot read (migration 154: a saver who is not a party gets nothing back);
 *  - nobody is signed in (saved_listings is per account; RLS would refuse a write anyway);
 *  - the first read for this listing has not answered yet and nothing else has told the store.
 * A failed first read shows the control UNSAVED (fails closed, as web does); saving from there is safe
 * because an insert that finds the row already there counts as saved.
 *
 * The note is web's own sentence for the failed direction, shown until the next tap and announced to
 * a screen reader once (the notifications/preferences pattern at this build). There is no offline
 * queue: a save attempted offline fails, rolls back and says so.
 */

import { useCallback, useEffect, useState } from 'react';
import { AccessibilityInfo } from 'react-native';

import { readListingSaved, watchSavedSignOut, writeListingSaved } from '@/src/lib/saved/savedListings';
import { rollbackNote } from '@/src/lib/saved/savedState';
import {
  bindSavedOwner,
  primeSaved,
  savedShownFor,
  subscribeSaved,
  subscribeSavedRollback,
  toggleSaved,
} from '@/src/lib/saved/savedStore';

export interface SavedListingControl {
  saved: boolean;
  /** The rollback note, or null. */
  note: string | null;
  onToggle: () => void;
}

export interface UseSavedListingArgs {
  userId: string | null | undefined;
  listingId: string | null | undefined;
  /** True only once auth has resolved AND the listing row is loaded and readable. */
  enabled: boolean;
}

export function useSavedListing({ userId, listingId, enabled }: UseSavedListingArgs): SavedListingControl | null {
  const key = userId && listingId ? `${userId}:${listingId}` : null;
  const [, setVersion] = useState(0);
  // The key whose first read has answered (either way).
  const [checked, setChecked] = useState<string | null>(null);
  const [note, setNote] = useState<{ key: string; text: string } | null>(null);

  useEffect(() => { watchSavedSignOut(); }, []);
  useEffect(() => subscribeSaved(() => setVersion((v) => v + 1)), []);

  // Bind the store to this account once auth has resolved (an unresolved auth reads as "nobody", which
  // must not empty another screen's state). A different account, or none, empties it.
  useEffect(() => {
    if (enabled) bindSavedOwner(userId ?? null);
  }, [enabled, userId]);

  useEffect(() => {
    if (!enabled || !userId || !listingId) return;
    let live = true;
    readListingSaved(userId, listingId).then((r) => {
      if (!live) return;
      if (r.ok) primeSaved(userId, listingId, r.saved);
      setChecked(`${userId}:${listingId}`);
    });
    return () => { live = false; };
  }, [enabled, userId, listingId]);

  useEffect(() => {
    if (!key) return;
    return subscribeSavedRollback((e) => {
      if (`${e.userId}:${e.listingId}` !== key) return;
      const text = rollbackNote(e.failed);
      setNote({ key, text });
      AccessibilityInfo.announceForAccessibility(text);
    });
  }, [key]);

  const onToggle = useCallback(() => {
    if (!userId || !listingId) return;
    setNote(null);
    toggleSaved(userId, listingId, writeListingSaved);
  }, [userId, listingId]);

  if (!enabled || !key) return null;
  const shown = savedShownFor(userId, listingId);
  if (shown === undefined && checked !== key) return null;
  return { saved: shown ?? false, note: note?.key === key ? note.text : null, onToggle };
}
