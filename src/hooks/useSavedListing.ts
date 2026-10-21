/**
 * src/hooks/useSavedListing.ts — one listing's Save control: instant, latest tap wins, rolled back
 * with a short announced note when the server refuses (checklist item 11).
 *
 * Returns null — no control at all — whenever the control could not be true:
 *  - `enabled` is false: the caller passes false while auth or the listing is still loading, and on a
 *    listing this viewer cannot read (migration 154: a saver who is not a party gets nothing back);
 *  - nobody is signed in (saved_listings is per account; RLS would refuse a write anyway);
 *  - the store is not bound to this account (a tap could not be saved, so no dead control is drawn);
 *  - the first read for this listing has not answered yet and nothing else has told the store.
 * Any owner change in the store (a sign-out, another account, a rebind after either) starts that
 * over: the control hides and this listing is read again, because the store emptied.
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
  savedGeneration,
  savedOwner,
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
  // The store's owner generation at this render; every owner change re-renders (subscribeSaved).
  const gen = savedGeneration();
  // Read state and the note belong to one owner generation: a rebind empties the store, so both reset.
  const genKey = key ? `${gen}:${key}` : null;
  // The genKey whose first read has answered (either way).
  const [checked, setChecked] = useState<string | null>(null);
  const [note, setNote] = useState<{ key: string; text: string } | null>(null);

  useEffect(() => { watchSavedSignOut(); }, []);
  useEffect(() => subscribeSaved(() => setVersion((v) => v + 1)), []);

  // Bind the store to this account once auth has resolved (an unresolved auth reads as "nobody", which
  // must not empty another screen's state). A different account, or none, empties it.
  useEffect(() => {
    if (enabled) bindSavedOwner(userId ?? null);
  }, [enabled, userId]);

  // One read per (owner generation, account, listing).
  useEffect(() => {
    if (!enabled || !userId || !listingId) return;
    // The bind above (or an auth event) moved the store on since this render: read for the new
    // generation on the render that follows, not twice.
    if (gen !== savedGeneration()) { setVersion((v) => v + 1); return; }
    // Not this account's store (signed out under us, say): its answer could not be recorded.
    if (savedOwner() !== userId) return;
    let live = true;
    readListingSaved(userId, listingId).then((r) => {
      if (!live) return;
      if (r.ok) primeSaved(userId, listingId, r.saved, r.stamp);
      setChecked(`${gen}:${userId}:${listingId}`);
    });
    return () => { live = false; };
  }, [enabled, userId, listingId, gen]);

  useEffect(() => {
    if (!key) return;
    return subscribeSavedRollback((e) => {
      if (`${e.userId}:${e.listingId}` !== key) return;
      const text = rollbackNote(e.failed);
      setNote({ key: `${savedGeneration()}:${key}`, text });
      AccessibilityInfo.announceForAccessibility(text);
    });
  }, [key]);

  const onToggle = useCallback(() => {
    if (!userId || !listingId) return;
    setNote(null);
    toggleSaved(userId, listingId, writeListingSaved);
  }, [userId, listingId]);

  // No dead control on a store that is not this account's: `checked` only ever holds a generation in
  // which this account owned the store (the read is skipped otherwise), and every owner change moves
  // the generation on.
  if (!enabled || !key) return null;
  const shown = savedShownFor(userId, listingId);
  if (shown === undefined && checked !== genKey) return null;
  return { saved: shown ?? false, note: note?.key === genKey ? note.text : null, onToggle };
}
