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
 * disk. Every owner change bumps `savedGeneration()`, so a surface can tell its earlier read no longer
 * describes the store and read again.
 *
 * A READ NEVER UNDOES A NEWER TAP. Each read carries the stamp `savedReadStamp()` gave when it was
 * sent; every tap bumps that listing's write epoch. An answer sent before the latest tap on a listing
 * is dropped for that listing, even if it arrives after the tap's write has committed (responses can
 * come back out of order: a slow SELECT can land after a fast DELETE).
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
/** Monotonic tap counter; a read is stamped with its value when sent. Never reset. */
let writeSeq = 0;
/**
 * The writeSeq of each listing's latest tap. Kept across owner changes on purpose: a read sent before
 * a tap stays stale for that listing whoever is bound when it lands (owner checks drop the rest).
 */
const lastWrite = new Map<string, number>();
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

/** The account this store holds, or null. */
export function savedOwner(): string | null {
  return owner;
}

/** Changes on every owner change (sign-out, a different account, or a rebind after either). */
export function savedGeneration(): number {
  return generation;
}

/** Take this when a read is SENT and hand it back with the answer (primeSaved / primeSavedList). */
export function savedReadStamp(): number {
  return writeSeq;
}

/** What to show for this listing, or undefined when this store does not know (or is not this user's). */
export function savedShownFor(userId: string | null | undefined, listingId: string | null | undefined): boolean | undefined {
  if (!userId || !listingId || owner !== userId) return undefined;
  return shown.get(listingId);
}

function prime(listingId: string, saved: boolean, stamp: number): boolean {
  // Sent before this listing's latest tap: it cannot know about that tap, whenever it arrives.
  if ((lastWrite.get(listingId) ?? 0) > stamp) return false;
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

/** Records what the server says about one listing; `stamp` is savedReadStamp() from when it was sent. */
export function primeSaved(userId: string, listingId: string, saved: boolean, stamp: number): void {
  if (!userId || owner !== userId) return;
  if (prime(listingId, saved, stamp)) emit();
}

/**
 * Records a full Saved-list read: every listed id is saved, and a remembered save missing from it is
 * not (the list is every saved_listings row this owner has, readable or not).
 */
export function primeSavedList(userId: string, savedIds: readonly string[], stamp: number): void {
  if (!userId || owner !== userId) return;
  const listed = new Set(savedIds);
  let changed = false;
  for (const id of listed) changed = prime(id, true, stamp) || changed;
  for (const [id, value] of [...shown]) {
    if (value && !listed.has(id)) changed = prime(id, false, stamp) || changed;
  }
  if (changed) emit();
}

/**
 * Flips one listing at once and saves it behind the screen — latest tap wins. Returns the value now
 * shown, or undefined when `userId` is not this store's owner (nothing happens then).
 */
export function toggleSaved(userId: string, listingId: string, write: SavedWriter): boolean | undefined {
  if (!userId || !listingId || owner !== userId) return undefined;
  writeSeq += 1;
  lastWrite.set(listingId, writeSeq);
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
        // The value that failed is the one the server already holds (a save failed, then the remove
        // that replaced it failed too): what is shown is already true, so there is nothing to undo or
        // explain — "Couldn't remove" would be wrong about a listing that is not saved.
        if (failed === committed) {
          if (shown.get(listingId) !== committed) { shown.set(listingId, committed); emit(); }
          return;
        }
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
