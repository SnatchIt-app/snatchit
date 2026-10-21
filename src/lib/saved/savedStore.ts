/**
 * src/lib/saved/savedStore.ts — the one in-memory saved state, so listing detail and the Saved screen
 * agree (checklist item 53: a saved listing changes everywhere it appears).
 *
 * WHAT IT HOLDS: for the signed-in account only, the saved state each surface should SHOW per listing
 * (a tap shows at once), plus one latest-wins saver per listing (`createCoalescedSaver`, the item-11
 * mechanism the Your-scene screen already uses, reused unchanged). A failed save puts back the last
 * value the server confirmed and reports it, so the surface on screen can say so briefly.
 *
 * PER ACCOUNT, MEMORY ONLY. The store records its owner, answers only for that owner, and empties on
 * any change of owner — sign-out included (`bindSavedOwner(null)`). A late result from the previous
 * account's save neither lands in the new account's state nor is reported. Nothing here is written to
 * disk.
 *
 * Deliberately dependency-free apart from the saver: the network write is passed in, so this file is
 * tested without React Native or Supabase.
 */

import { createCoalescedSaver, type CoalescedSaver } from '@/src/lib/settings/coalescedSave';

/** Persists one listing's saved state for one user; resolves true on success. */
export type SavedWriter = (userId: string, listingId: string, saved: boolean) => Promise<boolean>;

export interface SavedRollback {
  userId: string;
  listingId: string;
  /** The value that failed to save: true = a save failed, false = a remove failed. */
  failed: boolean;
  /** The value shown again: the last one the server confirmed. */
  committed: boolean;
}

let owner: string | null = null;
/** Bumped on every owner change, so a previous account's in-flight save can tell it is stale. */
let generation = 0;
const shown = new Map<string, boolean>();
const savers = new Map<string, CoalescedSaver<boolean>>();
const listeners = new Set<() => void>();
const rollbackListeners = new Set<(e: SavedRollback) => void>();

function emit(): void {
  for (const l of [...listeners]) l();
}

/** The account whose saves this store holds. A different id (or null: signed out) empties it. */
export function bindSavedOwner(userId: string | null | undefined): void {
  const next = userId || null;
  if (next === owner) return;
  owner = next;
  generation += 1;
  shown.clear();
  savers.clear();
  emit();
}

/** What to show for this listing, or undefined when this store does not know (or is not this user's). */
export function savedShownFor(userId: string | null | undefined, listingId: string | null | undefined): boolean | undefined {
  if (!userId || !listingId || owner !== userId) return undefined;
  return shown.get(listingId);
}

function prime(listingId: string, saved: boolean): boolean {
  const saver = savers.get(listingId);
  // A tap still being saved decides; a read that was in flight with it may predate it.
  if (saver?.pending) return false;
  // An idle saver remembers the last value IT confirmed, which a newer read may contradict (the row
  // removed on web, say). Drop it, so the next tap starts from what the server just said.
  if (saver) savers.delete(listingId);
  if (shown.get(listingId) === saved) return false;
  shown.set(listingId, saved);
  return true;
}

/** Records what the server says about one listing. */
export function primeSaved(userId: string, listingId: string, saved: boolean): void {
  if (!userId || owner !== userId) return;
  if (prime(listingId, saved)) emit();
}

/**
 * Records a full Saved-list read: every listed id is saved, and a remembered save missing from it is
 * not (the list is every saved_listings row this owner has, readable or not).
 */
export function primeSavedList(userId: string, savedIds: readonly string[]): void {
  if (!userId || owner !== userId) return;
  const listed = new Set(savedIds);
  let changed = false;
  for (const id of listed) changed = prime(id, true) || changed;
  for (const [id, value] of [...shown]) {
    if (value && !listed.has(id)) changed = prime(id, false) || changed;
  }
  if (changed) emit();
}

/**
 * Flips one listing at once and saves it behind the screen — latest tap wins. Returns the value now
 * shown, or undefined when `userId` is not this store's owner (nothing happens then).
 */
export function toggleSaved(userId: string, listingId: string, write: SavedWriter): boolean | undefined {
  if (!userId || !listingId || owner !== userId) return undefined;
  const current = shown.get(listingId) ?? false;
  const next = !current;
  let saver = savers.get(listingId);
  if (!saver) {
    const gen = generation;
    saver = createCoalescedSaver<boolean>({
      initial: current,
      // A queued write for an account that has since changed is not sent.
      save: (value) => (gen === generation ? write(userId, listingId, value) : Promise.resolve(false)),
      onRollback: (committed, failed) => {
        if (gen !== generation) return;
        shown.set(listingId, committed);
        emit();
        const event: SavedRollback = { userId, listingId, failed, committed };
        for (const l of [...rollbackListeners]) l(event);
      },
    });
    savers.set(listingId, saver);
  }
  shown.set(listingId, next);
  emit();
  saver.submit(next);
  return next;
}

export function subscribeSaved(listener: () => void): () => void {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

export function subscribeSavedRollback(listener: (e: SavedRollback) => void): () => void {
  rollbackListeners.add(listener);
  return () => { rollbackListeners.delete(listener); };
}

/** Test-only visibility. */
export function _savedStoreState(): { owner: string | null; shown: Record<string, boolean> } {
  return { owner, shown: Object.fromEntries(shown) };
}
