/**
 * app/(tabs)/bids.tsx — My Bids screen
 *
 * Fetches every bid the logged-in user has placed from Supabase,
 * joins the related listing row so we can show the event name,
 * cover image, and auction status.
 *
 * Card states (C — status badges)
 *  WINNING  — auction active, user's highest bid == listing.current_bid
 *  OUTBID   — auction active, user's highest bid <  listing.current_bid
 *  WON 🏆   — auction_status === 'ended' AND winner_user_id === me
 *  LOST     — auction_status === 'ended' AND winner_user_id !== me
 *  SOLD     — listing.status === 'sold' (Buy Now by someone else)
 *
 * Multiple bids on the same listing are collapsed: the card represents the
 * listing, but we use the user's MAX bid for WINNING/OUTBID detection.
 */

import { router } from 'expo-router';
import { Image } from 'expo-image';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from 'react-native';


import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { getCoverImageUrl } from '@/src/lib/coverImage';
import { colors, fontSize, radius, shadow, spacing } from '@/src/theme';

// ─── Types ────────────────────────────────────────────────────────────────────

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

type BidRow = {
  id: string;
  created_at: string;
  amount: number;
  listing_id: string;
  listing: ListingJoin | null;
  // resolved after fetch
  coverUrl: string | null;
};

type BidStatus = 'winning' | 'outbid' | 'won' | 'lost' | 'sold';

// ─── Helpers ──────────────────────────────────────────────────────────────────

function formatMoney(amount: number): string {
  return `$${Math.round(amount).toLocaleString('en-US')}`;
}

function timeLabel(endsAt: string): string {
  const diff = new Date(endsAt).getTime() - Date.now();
  if (diff <= 0) return 'Ended';
  const h = Math.floor(diff / 3_600_000);
  const m = Math.floor((diff % 3_600_000) / 60_000);
  if (h > 23) return `${Math.floor(h / 24)}d left`;
  if (h > 0) return `${h}h ${m}m left`;
  return `${m}m left`;
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

/**
 * Determine badge status for a bid row.
 * Priority:
 *   1. listing.status === 'sold' (Buy Now sale)     → 'sold'
 *   2. listing.auction_status === 'ended'            → check winner_user_id
 *   3. auction still live                            → winning vs outbid
 */
function getBidStatus(bid: BidRow, userId: string): BidStatus {
  const listing = bid.listing;
  if (!listing) return 'lost';

  // Buy Now sold (separate from auction ending)
  if (listing.status === 'sold') return 'sold';

  // Auction finalised
  if (listing.auction_status === 'ended') {
    return listing.winner_user_id === userId ? 'won' : 'lost';
  }

  // Auction active but clock may have run out (finalize_auction not called yet)
  const clockExpired = new Date(listing.ends_at) <= new Date();
  if (clockExpired) return 'lost'; // conservative until finalized

  // Still live
  return bid.amount >= listing.current_bid ? 'winning' : 'outbid';
}

const STATUS_LABELS: Record<BidStatus, string> = {
  winning: '● Winning',
  outbid:  '● Outbid',
  won:     '🏆 Won',
  lost:    'Ended',
  sold:    'Sold',
};

const STATUS_COLORS: Record<BidStatus, string> = {
  winning: colors.success,
  outbid:  colors.error,
  won:     '#FFD700',      // gold
  lost:    colors.textMuted,
  sold:    colors.textMuted,
};

// ─── Card ─────────────────────────────────────────────────────────────────────

function BidCard({ bid, userId }: { bid: BidRow; userId: string }) {
  const listing = bid.listing;
  if (!listing) return null;

  const status = getBidStatus(bid, userId);
  const ended  = listing.auction_status === 'ended' || new Date(listing.ends_at) <= new Date();

  return (
    <Pressable
      style={s.card}
      onPress={() => router.push(`/listing/${bid.listing_id}`)}
      android_ripple={{ color: colors.primarySoft }}
    >
      {/* Cover image */}
      <View style={s.imageWrap}>
        {bid.coverUrl ? (
          <Image
            source={{ uri: bid.coverUrl }}
            style={s.image}
            contentFit="cover"
          />
        ) : (
          <View style={[s.image, s.imagePlaceholder]} />
        )}

        {/* Status badge overlay */}
        <View style={[s.statusBadge, { borderColor: STATUS_COLORS[status] }]}>
          <Text style={[s.statusText, { color: STATUS_COLORS[status] }]}>
            {STATUS_LABELS[status]}
          </Text>
        </View>
      </View>

      {/* Body */}
      <View style={s.body}>
        {/* Event + venue */}
        <Text style={s.eventName} numberOfLines={1}>{listing.event_name}</Text>
        <Text style={s.venue} numberOfLines={1}>{listing.venue}</Text>

        {/* Bid info row */}
        <View style={s.bidRow}>
          <View>
            <Text style={s.bidLabel}>Your bid</Text>
            <Text style={s.bidAmount}>{formatMoney(bid.amount)}</Text>
          </View>
          <View style={s.rightCol}>
            <Text style={s.timeText}>
              {ended ? `Ended ${formatDate(listing.ends_at)}` : timeLabel(listing.ends_at)}
            </Text>
            <Text style={s.placedText}>Placed {formatDate(bid.created_at)}</Text>
          </View>
        </View>

        {/* Current bid (when still live) */}
        {!ended && listing.status !== 'sold' && (
          <View style={s.currentBidRow}>
            <Text style={s.currentBidLabel}>Current bid</Text>
            <Text style={[
              s.currentBidValue,
              { color: status === 'winning' ? colors.success : colors.error },
            ]}>
              {formatMoney(listing.current_bid)}
            </Text>
          </View>
        )}

        {/* Winning bid amount (ended auctions) */}
        {listing.auction_status === 'ended' && listing.winning_bid_amount != null && (
          <View style={s.currentBidRow}>
            <Text style={s.currentBidLabel}>Winning bid</Text>
            <Text style={[
              s.currentBidValue,
              { color: status === 'won' ? '#FFD700' : colors.textMuted },
            ]}>
              {formatMoney(listing.winning_bid_amount)}
            </Text>
          </View>
        )}

        {/* Outbid CTA */}
        {status === 'outbid' && (
          <View style={s.outbidBanner}>
            <Text style={s.outbidBannerText}>{"⚡ You've been outbid — tap to rebid"}</Text>
          </View>
        )}

        {/* Won banner */}
        {status === 'won' && (
          <View style={s.wonBanner}>
            <Text style={s.wonBannerText}>🎉 You won — tap to pay</Text>
          </View>
        )}

        {/* Lost banner */}
        {status === 'lost' && (
          <View style={s.soldBanner}>
            <Text style={s.soldBannerText}>Auction ended</Text>
          </View>
        )}

        {/* Sold (Buy Now) banner */}
        {status === 'sold' && (
          <View style={s.soldBanner}>
            <Text style={s.soldBannerText}>🔒 Listing sold via Buy Now</Text>
          </View>
        )}
      </View>
    </Pressable>
  );
}

// ─── Main Screen ──────────────────────────────────────────────────────────────

export default function BidsScreen() {
  const { session } = useAuth();
  const userId = session?.user.id ?? '';

  const [bids,       setBids]       = useState<BidRow[]>([]);
  const [loading,    setLoading]    = useState(true);
  const [refreshing, setRefreshing] = useState(false);

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
      return;
    }

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
      if (!initialLoadDone.current) return;
      fetchMyBids(true);
    }, [fetchMyBids]),
  );

  async function onRefresh() {
    setRefreshing(true);
    await fetchMyBids(true);
    setRefreshing(false);
  }

  // ── Filter state ────────────────────────────────────────────────────────────
  type BidFilter = 'total' | 'winning' | 'outbid' | 'won';
  const [bidFilter, setBidFilter] = useState<BidFilter>('total');

  // ── Summary counts ─────────────────────────────────────────────────────────
  const counts = useMemo(() => {
    const c = { winning: 0, outbid: 0, won: 0, lost: 0 };
    for (const bid of bids) {
      const status = getBidStatus(bid, userId);
      if (status === 'winning') c.winning++;
      else if (status === 'outbid') c.outbid++;
      else if (status === 'won') c.won++;
      else if (status === 'lost') c.lost++;
    }
    return c;
  }, [bids, userId]);

  const filteredBids = useMemo(() => {
    if (bidFilter === 'total') return bids;
    return bids.filter(b => {
      const status = getBidStatus(b, userId);
      if (bidFilter === 'winning') return status === 'winning';
      if (bidFilter === 'outbid')  return status === 'outbid';
      if (bidFilter === 'won')     return status === 'won';
      return true;
    });
  }, [bids, bidFilter, userId]);

  function onPillTap(key: BidFilter) {
    setBidFilter(prev => prev === key ? 'total' : key);
  }

  const PILLS: { key: BidFilter; label: string; count: number; color: string }[] = [
    { key: 'winning', label: 'Winning', count: counts.winning, color: colors.success },
    { key: 'outbid',  label: 'Outbid',  count: counts.outbid,  color: colors.error },
    { key: 'won',     label: 'Won',     count: counts.won,     color: '#FFD700' },
    { key: 'total',   label: 'Total',   count: bids.length,    color: colors.text },
  ];

  return (
    <View style={s.container}>
      {/* ── Header ── */}
      <View style={s.header}>
        <Text style={s.pageTitle}>My Bids</Text>
        <Text style={s.subtitle}>{"Auctions you've bid on"}</Text>
      </View>

      {/* ── Interactive summary pills ── */}
      {!loading && bids.length > 0 && (
        <View style={s.summaryRow}>
          {PILLS.map(({ key, label, count, color }) => {
            const active = bidFilter === key;
            return (
              <Pressable
                key={key}
                style={[
                  s.pill,
                  { borderColor: active ? color : colors.border },
                  active && s.pillActive,
                ]}
                onPress={() => onPillTap(key)}
              >
                <Text style={[s.pillNum, { color }]}>{count}</Text>
                <Text style={[s.pillLabel, { color: active ? color : colors.textMuted }]}>{label}</Text>
              </Pressable>
            );
          })}
        </View>
      )}

      {/* ── Content ── */}
      {loading ? (
        <View style={s.loader}>
          <ActivityIndicator color={colors.primary} size="large" />
        </View>
      ) : (
        <FlatList
          data={filteredBids}
          keyExtractor={(item) => item.id}
          contentContainerStyle={s.list}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={onRefresh}
              tintColor={colors.primary}
            />
          }
          ListEmptyComponent={
            <View style={s.empty}>
              <Text style={s.emptyIcon}>🎯</Text>
              <Text style={s.emptyTitle}>
                {bidFilter === 'total' ? 'No bids yet'
                  : bidFilter === 'winning' ? 'No winning bids'
                  : bidFilter === 'outbid' ? 'No outbid auctions'
                  : 'No won auctions'}
              </Text>
              <Text style={s.emptyText}>
                {bidFilter === 'total'
                  ? 'Head to the Home tab and place your first bid!'
                  : 'Try a different filter.'}
              </Text>
            </View>
          }
          renderItem={({ item }) => <BidCard bid={item} userId={userId} />}
        />
      )}
    </View>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },

  header: {
    paddingTop: 56,
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  pageTitle: { fontSize: fontSize.xl, fontWeight: '800', color: colors.text },
  subtitle:  { fontSize: fontSize.sm, color: colors.textMuted, marginTop: 2 },

  // Summary pills row
  summaryRow: {
    flexDirection: 'row',
    gap: spacing.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  pill: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: spacing.sm,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.bgCard,
  },
  pillActive: {
    backgroundColor: 'rgba(255,255,255,0.06)',
  },
  pillNum:   { fontSize: fontSize.lg, fontWeight: '800' },
  pillLabel: { fontSize: fontSize.xs, fontWeight: '600', marginTop: 2 },

  loader: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  list:   { padding: spacing.md, paddingBottom: 120 },

  // Card
  card: {
    backgroundColor: colors.bgCard,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    marginBottom: spacing.md,
    overflow: 'hidden',
    ...shadow.card,
  },

  imageWrap: { position: 'relative', height: 140 },
  image:     { width: '100%', height: '100%' },
  imagePlaceholder: { backgroundColor: colors.bgInput },

  statusBadge: {
    position: 'absolute',
    top: 10,
    left: 10,
    backgroundColor: 'rgba(0,0,0,0.72)',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: radius.full,
    borderWidth: 1,
  },
  statusText: { fontSize: fontSize.xs, fontWeight: '700' },

  body: { padding: spacing.md },

  eventName: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.text,
    marginBottom: 2,
  },
  venue: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
    marginBottom: spacing.sm,
  },

  bidRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
    marginTop: 4,
  },
  bidLabel:  { fontSize: fontSize.xs, color: colors.textDim, textTransform: 'uppercase', letterSpacing: 0.8 },
  bidAmount: { fontSize: fontSize.lg, fontWeight: '800', color: colors.text },

  rightCol:   { alignItems: 'flex-end', gap: 2 },
  timeText:   { fontSize: fontSize.xs, color: colors.textMuted, fontWeight: '600' },
  placedText: { fontSize: fontSize.xs, color: colors.textDim },

  currentBidRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginTop: spacing.sm,
    paddingTop: spacing.sm,
    borderTopWidth: 1,
    borderTopColor: colors.border,
  },
  currentBidLabel: { fontSize: fontSize.xs, color: colors.textMuted, textTransform: 'uppercase', letterSpacing: 0.8 },
  currentBidValue: { fontSize: fontSize.sm, fontWeight: '800' },

  outbidBanner: {
    marginTop: spacing.sm,
    backgroundColor: 'rgba(255,77,109,0.10)',
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.error,
    paddingVertical: 8,
    alignItems: 'center',
  },
  outbidBannerText: { color: colors.error, fontWeight: '700', fontSize: fontSize.sm },

  wonBanner: {
    marginTop: spacing.sm,
    backgroundColor: 'rgba(255,215,0,0.10)',
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: '#FFD700',
    paddingVertical: 8,
    alignItems: 'center',
  },
  wonBannerText: { color: '#FFD700', fontWeight: '700', fontSize: fontSize.sm },

  soldBanner: {
    marginTop: spacing.sm,
    backgroundColor: colors.bgInput,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.border,
    paddingVertical: 8,
    alignItems: 'center',
  },
  soldBannerText: { color: colors.textMuted, fontWeight: '600', fontSize: fontSize.sm },

  // Empty state
  empty: {
    flex: 1,
    alignItems: 'center',
    paddingTop: 80,
    gap: spacing.sm,
  },
  emptyIcon:  { fontSize: 48 },
  emptyTitle: { fontSize: fontSize.lg, fontWeight: '700', color: colors.text },
  emptyText:  { fontSize: fontSize.sm, color: colors.textMuted, textAlign: 'center', paddingHorizontal: spacing.xl },
});
