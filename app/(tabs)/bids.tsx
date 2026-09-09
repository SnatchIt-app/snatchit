/**
 * app/(tabs)/bids.tsx — Bids and purchases.
 *
 * V2. The DATA LAYER below is unchanged from the previous revision: the same bids
 * query, the same collapse-by-listing (one card per listing at the user's max
 * bid), the same merge of transfers (Buy Now purchases and completed auction wins
 * that have no or stale bid rows), the same refresh and focus behaviour.
 *
 * The presentation is rebuilt. Status, grouping, copy, action and the one price to
 * show per state now live in src/lib/bids/bidState.ts, which is pure and tested.
 * The six-pill filter strip is replaced by two segments, Active and Past, because
 * the dataset is small and the states collapse cleanly into "needs me / settled";
 * within Active the most urgent card sorts to the top. No My Tickets, no ticket
 * object: kernel.tickets is not queried and nothing here claims ticket ownership
 * beyond the transfer state machine the client is already granted.
 */

import { router } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { finalSoldPrice } from '@/src/lib/salePrice';
import { allInFromDollars } from '@/src/lib/money';
import { getCoverImageUrl } from '@/src/lib/coverImage';
import ScreenState from '@/src/components/ScreenState';
import { isNetworkError } from '@/src/hooks/useNetworkStatus';
import { Chip, EmptyState, Skeleton } from '@/src/components/ui';
import { useDockScroll } from '@/src/components/nav/dockContext';
import { useDockClearance } from '@/src/lib/nav/navInsets';
import { BidCard } from '@/src/components/bids/BidCard';
import { bidPresentation, bidGroupOf, bidStatusOf, needsAction, type BidGroup } from '@/src/lib/bids/bidState';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

// ─── Types (data layer — unchanged) ────────────────────────────────────────────

type ListingJoin = {
  id: string;
  event_name: string;
  venue: string;
  ends_at: string;
  current_bid: number;
  // buy-now reservation status
  status: string;
  // auction intelligence fields
  auction_status: 'active' | 'ended' | 'sold';
  winner_user_id: string | null;
  winning_bid_amount: number | null;
  cover_image_path: string | null;
  reserved_until: string | null;
  reserved_by: string | null;
};

type PurchaseTransferStatus =
  | 'pending'
  | 'seller_sent'
  | 'disputed'
  | 'buyer_confirmed'
  | 'auto_released';

type BidRow = {
  /** When set, this row represents a purchase the buyer has made (auction
   *  win + paid, or Buy Now). The transfer's lifecycle drives the badge.
   *  See getBidStatus(). */
  purchaseTransferStatus?: PurchaseTransferStatus;
  /** Transfer id for purchase rows — tap routes to /transfer/receive/[id]. */
  transferId?: string;
  /** True while the buyer still has to provide delivery email/phone. */
  needsDeliveryInfo?: boolean;
  id: string;
  created_at: string;
  amount: number;
  listing_id: string;
  listing: ListingJoin | null;
  // resolved after fetch
  coverUrl: string | null;
};

// ─── Helpers ────────────────────────────────────────────────────────────────

function coverPath(row: BidRow): string | null {
  // getCoverImageUrl was previously resolved into row.coverUrl. EventMedia now
  // resolves the raw path itself (encoding, host allowlist, slot-sized transform),
  // so the card takes the path and the pre-resolved URL is no longer needed.
  return (row.listing as { cover_image_path?: string | null } | null)?.cover_image_path ?? null;
}

function whenLabel(iso: string | undefined): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

// ─── Screen ─────────────────────────────────────────────────────────────────

export default function BidsScreen() {
  const { session } = useAuth();
  const userId = session?.user.id ?? '';
  const insets = useSafeAreaInsets();
  const dockClearance = useDockClearance();
  const { onScroll: onDockScroll, expand: expandDock } = useDockScroll('bids');

  const [bids,       setBids]       = useState<BidRow[]>([]);
  const [loading,    setLoading]    = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadError,  setLoadError]  = useState<'offline' | 'error' | null>(null);
  const [segment,    setSegment]    = useState<BidGroup>('active');

  const initialLoadDone = useRef(false);

  const fetchMyBids = useCallback(async (silent = false) => {
    if (!userId) return;
    if (!silent) setLoading(true);

    const { data, error } = await supabase
      .from('bids')
      .select(`
        id,
        amount,
        created_at,
        listing_id,
        listing:listings (
          id,
          event_name,
          venue,
          ends_at,
          current_bid,
          status,
          auction_status,
          winner_user_id,
          winning_bid_amount,
          cover_image_path,
          reserved_until,
          reserved_by
        )
      `)
      .eq('bidder_id', userId)
      .order('created_at', { ascending: false });

    if (!silent) setLoading(false);

    if (error || !data) {
      console.warn('[BidsScreen] fetch error:', error?.message);
      setLoadError(isNetworkError(error) ? 'offline' : 'error');
      return;
    }
    setLoadError(null);

    // Collapse multiple bids on the same listing into ONE card.
    // `amount` on the card = user's MAX bid for that listing (used for
    // WINNING vs OUTBID badge logic). Data arrives newest-first so the
    // first entry per listing_id is already the most recent bid row.
    const byListing = new Map<string, BidRow>();

    for (const row of data as any[]) {
      const listing  = Array.isArray(row.listing) ? row.listing[0] : row.listing;
      const coverUrl = getCoverImageUrl(listing?.cover_image_path ?? null);
      const existing = byListing.get(row.listing_id);

      if (!existing) {
        byListing.set(row.listing_id, {
          id:         row.id,
          amount:     row.amount,
          created_at: row.created_at,
          listing_id: row.listing_id,
          listing:    listing ?? null,
          coverUrl,
        });
      } else if (row.amount > existing.amount) {
        // Same listing, higher bid — update the amount for badge accuracy
        byListing.set(row.listing_id, { ...existing, amount: row.amount });
      }
    }

    // ── Merge in PURCHASES (transfers where this user is the buyer) ──────
    // This covers two gaps:
    //   • Buy Now purchases have no bid row → never appeared in Bids tab.
    //   • Auction wins that completed checkout — transfer status drives
    //     the badge instead of the stale listing.status='sold' tile.
    const { data: txData } = await supabase
      .from('transfers')
      .select(`
        id,
        listing_id,
        status,
        created_at,
        delivery_email,
        delivery_phone,
        listing:listings (
          id, event_name, venue, ends_at, current_bid, status, auction_status,
          winner_user_id, winning_bid_amount, buy_now_enabled, buy_now_price,
          cover_image_path, reserved_until, reserved_by
        )
      `)
      .eq('buyer_id', userId)
      .in('status', ['pending','seller_sent','disputed','buyer_confirmed','auto_released'])
      .order('created_at', { ascending: false });

    for (const t of (txData ?? []) as any[]) {
      const listing  = Array.isArray(t.listing) ? t.listing[0] : t.listing;
      const coverUrl = getCoverImageUrl(listing?.cover_image_path ?? null);
      const ts       = t.status as PurchaseTransferStatus;
      const existing = byListing.get(t.listing_id);

      const needsInfo = !t.delivery_email && !t.delivery_phone;
      if (existing) {
        existing.purchaseTransferStatus = ts;
        existing.transferId             = t.id;
        existing.needsDeliveryInfo      = needsInfo;
      } else {
        byListing.set(t.listing_id, {
          id:                       `tx-${t.listing_id}`,
          transferId:               t.id,
          needsDeliveryInfo:        needsInfo,
          // Actual sale price: winning bid (auction) → buy_now_price (Buy Now)
          // → current_bid fallback. Buy Now sales never stamp winning_bid_amount.
          amount:                   listing ? finalSoldPrice(listing) : 0,
          created_at:               t.created_at,
          listing_id:               t.listing_id,
          listing:                  listing ?? null,
          coverUrl,
          purchaseTransferStatus:   ts,
        });
      }
    }

    setBids(Array.from(byListing.values()));
  }, [userId]);

  // Hard load on mount
  useEffect(() => {
    fetchMyBids(false).finally(() => {
      initialLoadDone.current = true;
    });
  }, [fetchMyBids]);

  // Silent refetch when tab regains focus
  useFocusEffect(
    useCallback(() => {
      expandDock(); // arrive with the full dock
      if (!initialLoadDone.current) return;
      fetchMyBids(true);
    }, [fetchMyBids, expandDock]),
  );

  async function onRefresh() {
    setRefreshing(true);
    await fetchMyBids(true);
    setRefreshing(false);
  }

  // ── Grouping (replaces the six-pill filter) ─────────────────────────────────
  const { active, past, needsActionCount } = useMemo(() => {
    const a: BidRow[] = [];
    const p: BidRow[] = [];
    let n = 0;
    for (const bid of bids) {
      const status = bidStatusOf(toInput(bid), userId);
      if (needsAction(status)) n++;
      (bidGroupOf(status) === 'active' ? a : p).push(bid);
    }
    // Most urgent first within Active; Past keeps newest-first from the query.
    a.sort((x, y) =>
      bidPresentation(toInput(x), userId).priority - bidPresentation(toInput(y), userId).priority);
    return { active: a, past: p, needsActionCount: n };
  }, [bids, userId]);

  const shown = segment === 'active' ? active : past;

  // ── Render ──────────────────────────────────────────────────────────────────
  return (
    <View style={s.container}>
      <View style={[s.header, { paddingTop: insets.top + v2.space.sm }]}>
        <Text style={[textStyle('displayMd'), s.title]} accessibilityRole="header">Your bids</Text>
      </View>

      {!loading && bids.length > 0 ? (
        <View style={s.segments}>
          <Chip
            label="Active"
            count={needsActionCount > 0 ? needsActionCount : undefined}
            selected={segment === 'active'}
            onPress={() => setSegment('active')}
          />
          <Chip label="Past" selected={segment === 'past'} onPress={() => setSegment('past')} />
        </View>
      ) : null}

      {loading ? (
        <View style={s.list}>
          {[0, 1, 2, 3].map((i) => (
            <View key={i} style={s.skeletonRow}>
              <Skeleton width={72} height={72} />
              <View style={s.skeletonBody}>
                <Skeleton height={14} width="40%" />
                <Skeleton height={16} width="80%" style={{ marginTop: 8 }} />
                <Skeleton height={12} width="55%" style={{ marginTop: 6 }} />
              </View>
            </View>
          ))}
        </View>
      ) : loadError && bids.length === 0 ? (
        <ScreenState state={loadError} onRetry={() => fetchMyBids(false)} />
      ) : (
        <FlatList
          data={shown}
          keyExtractor={(item) => item.id}
          contentContainerStyle={[s.list, { paddingBottom: dockClearance }]}
          showsVerticalScrollIndicator={false}
          onScroll={onDockScroll}
          scrollEventThrottle={16}
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={v2.brand.red} />
          }
          ListEmptyComponent={
            <EmptyState
              title={segment === 'active' ? 'No active bids' : 'Nothing here yet'}
              body={
                segment === 'active'
                  ? 'Bids you place and tickets you buy show up here.'
                  : 'Ended auctions and completed purchases show up here.'
              }
              action={
                segment === 'active'
                  ? { label: 'Find something', onPress: () => router.push('/(tabs)/home') }
                  : undefined
              }
            />
          }
          renderItem={({ item }) => {
            const p = bidPresentation(toInput(item), userId);
            const target = p.routesToTransfer && item.transferId
              ? `/transfer/receive/${item.transferId}`
              : `/listing/${item.listing_id}`;
            return (
              <BidCard
                eventName={item.listing?.event_name ?? 'Listing'}
                venue={item.listing?.venue ?? ''}
                whenLabel={whenLabel(item.listing?.ends_at)}
                coverPath={coverPath(item)}
                presentation={p}
                priceAllIn={allInFromDollars(p.priceDollars)}
                secondaryAllIn={p.secondaryDollars != null ? allInFromDollars(p.secondaryDollars) : null}
                onPress={() => router.push(target as never)}
              />
            );
          }}
        />
      )}
    </View>
  );
}

// bidState works on a minimal shape; adapt a BidRow to it. finalSoldPrice is the
// same authority the fetch already uses for a purchase row's amount.
function toInput(row: BidRow) {
  return {
    amount: row.amount,
    purchaseTransferStatus: row.purchaseTransferStatus,
    needsDeliveryInfo: row.needsDeliveryInfo,
    transferId: row.transferId,
    listing: row.listing
      ? {
          status: row.listing.status,
          auction_status: row.listing.auction_status,
          ends_at: row.listing.ends_at,
          current_bid: row.listing.current_bid,
          winner_user_id: row.listing.winner_user_id,
          winning_bid_amount: row.listing.winning_bid_amount,
        }
      : null,
  };
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: v2.surface.canvas },
  header: { paddingHorizontal: v2.space.lg, paddingBottom: v2.space.md },
  title: { color: v2.text.primary },
  segments: {
    flexDirection: 'row',
    gap: v2.space.sm,
    paddingHorizontal: v2.space.lg,
    paddingBottom: v2.space.md,
  },
  list: { paddingHorizontal: v2.space.lg, paddingBottom: 96 },
  skeletonRow: { flexDirection: 'row', gap: v2.space.md, paddingVertical: v2.space.md },
  skeletonBody: { flex: 1, justifyContent: 'center' },
});
