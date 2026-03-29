/**
 * src/hooks/useListingRealtime.ts
 *
 * Subscribes to new bids for a given listing via Supabase Realtime.
 * Returns the full bid list (initial + live), computed currentBid,
 * bidCount, highestBidderId, and loading — all updated in real time.
 *
 * supabase-js v2 query order
 * ──────────────────────────
 * .select() MUST come directly after .from() before any filter (.eq, .gt, …).
 *   supabase.from('bids').select('…').eq(…).order(…)
 *
 * Profiles join
 * ─────────────
 * bids.bidder_id → profiles.id FK is in place.
 * PostgREST resolves: select('*, profiles(full_name, display_name, avatar_url)').
 * No fallback — the FK migration must be applied before using this hook.
 *
 * Realtime channel
 * ────────────────
 * Effect depends only on [listingId].  channelRef stores the live channel so
 * cleanup always reaches it regardless of closure scope.
 * Tear-down before create guards against StrictMode double-invoke / Fast Refresh.
 *
 * Reconnect handling
 * ──────────────────
 * On CHANNEL_ERROR / TIMED_OUT → SUBSCRIBED we run a catch-up fetch
 * (.gt created_at) to fill any bids missed while the socket was down.
 * onNewBid is intentionally NOT called for catch-up bids so haptics
 * never re-fire after a reconnect.
 */
import { useEffect, useRef, useState } from 'react';
import { supabase } from '@/src/lib/supabase';
import type { Bid } from '@/src/types';

// ── Types ─────────────────────────────────────────────────────────────────────

type RealtimeResult = {
  bids:            Bid[];
  currentBid:      number;
  bidCount:        number;
  highestBidderId: string | null;
  loading:         boolean;
};

type Options = {
  /**
   * Called ONLY when a realtime INSERT fires and the bid has been merged into
   * the local list.  Never called on initial fetch or reconnect catch-up, so
   * you can safely fire haptics / animations here without false positives on
   * screen entry.
   *
   * @param newBid  The newly inserted bid (full row with profiles join).
   * @param allBids The complete updated list (newest-first), including newBid.
   */
  onNewBid?: (newBid: Bid, allBids: Bid[]) => void;
};

// ── Constants ─────────────────────────────────────────────────────────────────

// FK bids.bidder_id → profiles.id lets PostgREST resolve this join.
// profiles table now has a public SELECT policy for all authenticated users.
const BIDS_SELECT = '*, profiles(full_name, display_name, avatar_url)' as const;

// ─────────────────────────────────────────────────────────────────────────────

export function useListingRealtime(
  listingId: string,
  startingBid: number,
  options?: Options,
): RealtimeResult {
  const [bids, setBids]       = useState<Bid[]>([]);
  const [loading, setLoading] = useState(true);

  // Always-current list — prevents stale-closure reads in async callbacks.
  const bidsRef = useRef<Bid[]>([]);

  // ISO timestamp of the newest bid we hold — used for reconnect catch-up.
  const lastBidAtRef = useRef<string>('');

  // Last known channel status — lets us detect ERROR → SUBSCRIBED transitions.
  const channelStatusRef = useRef<string>('');

  // Stable reference to the live channel so cleanup can always reach it,
  // even when the closure that created it has gone out of scope.
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null);

  // Keep onNewBid current without adding it to the subscription effect's deps.
  // The subscription effect depends only on [listingId]; adding options here
  // would cause subscribe/unsubscribe on every parent re-render.
  const onNewBidRef = useRef(options?.onNewBid);
  useEffect(() => { onNewBidRef.current = options?.onNewBid; }); // no deps

  useEffect(() => {
    if (!listingId) return;

    // Tear down any previous channel before creating a new one.
    // Guards against StrictMode double-invoke and Fast Refresh leaving a
    // ghost channel open.
    if (channelRef.current) {
      supabase.removeChannel(channelRef.current);
      channelRef.current = null;
    }

    setLoading(true);
    bidsRef.current          = [];
    lastBidAtRef.current     = '';
    channelStatusRef.current = '';
    setBids([]);

    // ── Fetch helper ────────────────────────────────────────────────────────
    // supabase-js v2: .select() must be called immediately after .from().
    // Filters (.eq, .gt, .order) chain after .select().
    async function fetchBids(opts: { since?: string } = {}): Promise<Bid[]> {
      let q = supabase
        .from('bids')
        .select(BIDS_SELECT)
        .eq('listing_id', listingId)
        .order('created_at', { ascending: false });
      if (opts.since) q = q.gt('created_at', opts.since);

      const { data, error } = await q;

      if (error) {
        console.warn('[bids fetch] error:', error.message);
        return [];
      }

      const rows = (data as Bid[]) ?? [];
      return rows;
    }

    // ── 1. Initial full fetch ───────────────────────────────────────────────
    // onNewBid is NOT called here — only realtime INSERTs fire that callback.
    fetchBids().then((rows) => {
      bidsRef.current      = rows;
      lastBidAtRef.current = rows[0]?.created_at ?? '';
      setBids(rows);
      setLoading(false);
    });

    // ── 2. Realtime subscription ────────────────────────────────────────────
    const channel = supabase
      .channel(`bids:${listingId}`)
      .on(
        'postgres_changes',
        {
          event:  'INSERT',
          schema: 'public',
          table:  'bids',
          filter: `listing_id=eq.${listingId}`,
        },
        async (payload) => {
          const bidId = (payload.new as any).id as string;

          // Skip duplicates (INSERT can fire twice on reconnect).
          if (bidsRef.current.some(b => b.id === bidId)) return;

          // Fetch the full row with profiles join.
          // supabase-js v2: .select() before .eq()
          const { data, error: fetchErr } = await supabase
            .from('bids')
            .select(BIDS_SELECT)
            .eq('id', bidId)
            .single();

          if (fetchErr || !data) {
            console.warn('[bids INSERT] fetch error:', fetchErr?.message);
            return;
          }

          const newBid = data as Bid;

          // Prepend (newest-first) and deduplicate by id.
          const updated = [newBid, ...bidsRef.current.filter(b => b.id !== newBid.id)];
          bidsRef.current      = updated;
          lastBidAtRef.current = updated[0]?.created_at ?? '';
          setBids([...updated]);

          // Notify screen — ONLY on genuine realtime INSERT.
          // Not called during initial fetch or reconnect catch-up, so haptics
          // in the callback fire only for new live bids, never on screen entry.
          onNewBidRef.current?.(newBid, updated);
        },
      )
      .subscribe(async (status, err) => {
        const prev = channelStatusRef.current;
        channelStatusRef.current = status;

        if (status === 'SUBSCRIBED') {
          // ── Reconnect catch-up ──────────────────────────────────────────
          // Fetch any bids that arrived while the WebSocket was down.
          // onNewBid is intentionally NOT called for catch-up bids so haptics
          // do not re-fire after a reconnect.
          if (prev === 'CHANNEL_ERROR' || prev === 'TIMED_OUT') {
            const missed = await fetchBids({ since: lastBidAtRef.current });
            if (missed.length > 0) {
              const merged = [
                ...missed.filter(m => !bidsRef.current.some(b => b.id === m.id)),
                ...bidsRef.current,
              ];
              bidsRef.current      = merged;
              lastBidAtRef.current = merged[0]?.created_at ?? '';
              setBids([...merged]);
            }
          }
        }

        if (status === 'CHANNEL_ERROR') {
          // Do NOT call removeChannel — the SDK retries automatically.
          console.warn(`[realtime] CHANNEL_ERROR bids: ${listingId}`, err ?? '');
        }

        if (status === 'TIMED_OUT') {
          console.warn(`[realtime] TIMED_OUT bids: ${listingId}`);
        }
      });

    channelRef.current = channel;

    return () => {
      if (channelRef.current) {
        supabase.removeChannel(channelRef.current);
        channelRef.current = null;
      }
    };
  }, [listingId]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Derived values ──────────────────────────────────────────────────────────
  // List order: newest first (never re-sorted by amount).
  // highestBidderId: bidder of max-amount bid; ties → newest wins (lowest index).
  let highestAmount    = startingBid;
  let highestBidderId: string | null = null;

  if (bids.length > 0) {
    const maxAmt = Math.max(...bids.map(b => b.amount));
    highestAmount = maxAmt;
    const top = bids.find(b => b.amount === maxAmt);
    highestBidderId = top?.bidder_id ?? null;
  }

  return {
    bids,
    currentBid:      highestAmount,
    bidCount:        bids.length,
    highestBidderId,
    loading,
  };
}
