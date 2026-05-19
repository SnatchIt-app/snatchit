/**
 * src/hooks/useBlockedUserIds.ts
 *
 * Caches the current user's set of blocked-seller IDs in memory. Used by
 * the home + explore feeds to filter listings whose seller_id is in the
 * block set.
 *
 * Why a hook rather than RLS-only filtering:
 *   • RLS would hide blocked sellers' listings from EVERY query — including
 *     the user's own bid-history and past purchases. That breaks the
 *     "I can still see what I bought from someone I later blocked" flow.
 *   • Filtering in feed queries keeps blocks scoped to discovery surfaces
 *     while leaving direct-access screens (listing detail, checkout, bids
 *     tab, my-listings) untouched.
 *
 * The cache:
 *   • Loaded once on mount, plus on auth-state change.
 *   • Re-fetched after the consumer calls `refresh()` (e.g. after the user
 *     blocks someone from the listing-detail overflow menu).
 *   • Stays empty for unauthenticated users.
 */
import { useCallback, useEffect, useState } from 'react';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';

export function useBlockedUserIds(): {
  blockedIds: Set<string>;
  refresh:    () => Promise<void>;
  loading:    boolean;
} {
  const { user } = useAuth();
  const userId   = user?.id ?? null;
  const [blockedIds, setBlockedIds] = useState<Set<string>>(new Set());
  const [loading,    setLoading]    = useState(false);

  const refresh = useCallback(async () => {
    if (!userId) {
      setBlockedIds(new Set());
      return;
    }
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('user_blocks')
        .select('blocked_id')
        .eq('blocker_id', userId);
      if (error) {
        console.warn('[useBlockedUserIds] fetch error:', error.message);
        return;
      }
      setBlockedIds(new Set((data ?? []).map(r => r.blocked_id as string)));
    } finally {
      setLoading(false);
    }
  }, [userId]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return { blockedIds, refresh, loading };
}

/**
 * Apply a blocked-set filter to a supabase-js query builder. Pass the
 * Set from useBlockedUserIds(). No-op when the set is empty.
 *
 * Usage:
 *   const { blockedIds } = useBlockedUserIds();
 *   const query = supabase.from('listings').select('*');
 *   const filtered = applyBlockedSellerFilter(query, blockedIds);
 *   const { data } = await filtered;
 */
// PostgrestFilterBuilder is generic; we use `any` here so the helper is a
// transparent pass-through for whatever query shape callers hand us, and
// the caller's destructure `{ data, error }` infers naturally from the
// awaited supabase-js return type.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function applyBlockedSellerFilter<Q extends any>(
  query: Q,
  blockedIds: Set<string>,
): Q {
  if (blockedIds.size === 0) return query;
  const ids = Array.from(blockedIds).join(',');
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (query as any).not('seller_id', 'in', `(${ids})`) as Q;
}
