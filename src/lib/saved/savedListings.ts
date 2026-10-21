/**
 * src/lib/saved/savedListings.ts — the network half of saved listings: PostgREST on the EXISTING
 * public.saved_listings table, nothing else.
 *
 * Schema used (migration 040, unchanged by every later migration): columns id, user_id, listing_id,
 * created_at; UNIQUE (user_id, listing_id); RLS policies "saved_listings: owner select / owner insert /
 * owner delete", each `user_id = auth.uid()`; no UPDATE policy, and nothing here updates. No RPC, no
 * edge function, no realtime.
 *
 * Same rules as live web (web/src/lib/favorites-actions.ts and favorites.ts):
 *  - save   = INSERT {user_id, listing_id}. A unique violation (23505) means the row is already there
 *             — another device, or a tap that raced — which is the outcome asked for, so it is success.
 *  - remove = DELETE by user_id AND listing_id. Deleting a row that is already gone is also success.
 *  - one listing's state fails CLOSED: a failed read shows "not saved", and a Save from there is safe
 *    because of the 23505 rule.
 * Logs carry the Postgres error code only — never ids or any user data.
 */

import { supabase } from '@/src/lib/supabase';

import { bindSavedOwner } from './savedStore';
import { partitionSaved, type SavedPartition } from './savedState';

/** The Saved screen's one read: the saved row's own columns and the listing, embedded by PostgREST. */
export const SAVED_LIST_SELECT = 'id, listing_id, created_at, listing:listings(*)';

export type SavedOneRead = { ok: true; saved: boolean } | { ok: false };
export type SavedListRead = ({ ok: true } & SavedPartition) | { ok: false; error: unknown };

export async function readListingSaved(userId: string, listingId: string): Promise<SavedOneRead> {
  try {
    const { data, error } = await supabase
      .from('saved_listings')
      .select('id')
      .eq('user_id', userId)
      .eq('listing_id', listingId)
      .maybeSingle();
    if (error) return { ok: false };
    return { ok: true, saved: data != null };
  } catch {
    return { ok: false };
  }
}

/** Saves (`saved` true) or removes one listing for one user. Resolves true on success; never throws. */
export async function writeListingSaved(userId: string, listingId: string, saved: boolean): Promise<boolean> {
  try {
    if (saved) {
      const { error } = await supabase
        .from('saved_listings')
        .insert({ user_id: userId, listing_id: listingId });
      if (error && error.code !== '23505') {
        console.warn('[saved] save failed:', error.code ?? 'unknown');
        return false;
      }
      return true;
    }
    const { error } = await supabase
      .from('saved_listings')
      .delete()
      .eq('user_id', userId)
      .eq('listing_id', listingId);
    if (error) {
      console.warn('[saved] remove failed:', error.code ?? 'unknown');
      return false;
    }
    return true;
  } catch {
    return false;
  }
}

/** The signed-in user's saved rows, newest first (ties broken by id so the order is stable). */
export async function readSavedList(userId: string): Promise<SavedListRead> {
  try {
    const { data, error } = await supabase
      .from('saved_listings')
      .select(SAVED_LIST_SELECT)
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .order('id', { ascending: false });
    if (error) return { ok: false, error };
    return { ok: true, ...partitionSaved(data) };
  } catch (error) {
    return { ok: false, error };
  }
}

let watching = false;

/**
 * Keeps the in-memory store bound to whoever is signed in: a sign-out empties it and a different
 * account replaces it, even when no saved surface is mounted. Installed once, on first use.
 *
 * The callback is SYNCHRONOUS on purpose: auth-js awaits every listener while it holds its lock, and an
 * awaited auth call inside one deadlocked sign-out in Build 17 (see useAuth). This one only empties a Map.
 */
export function watchSavedSignOut(): void {
  if (watching) return;
  try {
    supabase.auth.onAuthStateChange((_event, session) => {
      bindSavedOwner(session?.user?.id ?? null);
    });
    watching = true;
  } catch {
    // No auth client (tests, a broken build): the hooks still bind the owner on every read.
  }
}
