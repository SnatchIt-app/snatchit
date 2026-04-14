/**
 * app/my-listings.tsx — Seller's Listings screen
 *
 * Shows every listing the authenticated user has created as a seller.
 * Follows the same data-fetching architecture as app/(tabs)/bids.tsx:
 *   - Hard load on mount
 *   - Silent refetch on screen focus (useFocusEffect)
 *   - Pull-to-refresh via RefreshControl
 *
 * Cover images are resolved synchronously via getCoverImageUrl (public bucket).
 * Cards are rendered by the SellerListingCard component.
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { getCoverImageUrl } from '@/src/lib/coverImage';
import SellerListingCard from '@/src/components/SellerListingCard';
import { colors, fontSize, radius, spacing } from '@/src/theme';
import type { Listing } from '@/src/types';

// ─── Extended listing with resolved cover URL ────────────────────────────────

type ListingRow = Listing & { coverUrl: string | null };

// ─── Main Screen ─────────────────────────────────────────────────────────────

type FilterKey = 'all' | 'active' | 'ended' | 'sold';
const VALID_FILTERS: FilterKey[] = ['all', 'active', 'ended', 'sold'];

export default function MyListingsScreen() {
  const { session } = useAuth();
  const userId = session?.user.id ?? '';

  // Accept optional initialFilter from route params (e.g. from Profile stat cards)
  const { filter: filterParam } = useLocalSearchParams<{ filter?: string }>();
  const resolvedInitialFilter: FilterKey =
    filterParam && VALID_FILTERS.includes(filterParam as FilterKey)
      ? (filterParam as FilterKey)
      : 'all';

  const [listings,   setListings]   = useState<ListingRow[]>([]);
  const [loading,    setLoading]    = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const initialLoadDone = useRef(false);

  const fetchMyListings = useCallback(async (silent = false) => {
    if (!userId) return;
    if (!silent) setLoading(true);

    const { data, error } = await supabase
      .from('listings')
      .select('*')
      .eq('seller_id', userId)
      .order('created_at', { ascending: false });

    if (!silent) setLoading(false);

    if (error || !data) {
      console.warn('[MyListings] fetch error:', error?.message);
      return;
    }

    const rows: ListingRow[] = (data as Listing[]).map((listing) => ({
      ...listing,
      coverUrl: getCoverImageUrl(listing.cover_image_path),
    }));

    setListings(rows);
  }, [userId]);

  // Hard load on mount
  useEffect(() => {
    fetchMyListings(false).finally(() => {
      initialLoadDone.current = true;
    });
  }, [fetchMyListings]);

  // Silent refetch when screen regains focus
  useFocusEffect(
    useCallback(() => {
      if (!initialLoadDone.current) return;
      fetchMyListings(true);
    }, [fetchMyListings]),
  );

  async function onRefresh() {
    setRefreshing(true);
    await fetchMyListings(true);
    setRefreshing(false);
  }

  // ── Delete handler ───────────────────────────────────────────────────────────

  /** Actually delete a listing from the DB, clean up storage, and update local state. */
  async function performDelete(listing: ListingRow) {
    // Safety: only allow deletion if no bids and auction still active
    if (listing.bid_count > 0 || listing.auction_status !== 'active') {
      Alert.alert(
        'Cannot Delete',
        'This listing has bids and cannot be deleted.',
      );
      return;
    }

    // 1. Delete from DB (RLS enforces seller_id = auth.uid() server-side)
    const { error } = await supabase
      .from('listings')
      .delete()
      .eq('id', listing.id)
      .eq('seller_id', userId); // double-check ownership client-side

    if (error) {
      Alert.alert('Delete Failed', error.message);
      return;
    }

    // 2. Remove from local state immediately (no refetch needed)
    setListings(prev => prev.filter(l => l.id !== listing.id));

    // 3. Clean up cover image from storage (best-effort, non-blocking)
    if (listing.cover_image_path) {
      try {
        await supabase.storage
          .from('auction-media')
          .remove([listing.cover_image_path]);
      } catch (e) {
        console.warn('[MyListings] cover image cleanup failed:', e);
      }
    }
  }

  // ── Cancel handler (for listings that have bids) ────────────────────────────

  /** Cancel a listing via server-side RPC. Voids bids but keeps the record. */
  async function performCancel(listing: ListingRow) {
    const { error } = await supabase.rpc('cancel_listing', {
      p_listing_id: listing.id,
      p_user_id: userId,
    });

    if (error) {
      Alert.alert('Cancel Failed', error.message);
      return;
    }

    // Update local state — set auction_status to 'cancelled'
    setListings(prev =>
      prev.map(l =>
        l.id === listing.id
          ? { ...l, auction_status: 'cancelled' as const, ended_at: new Date().toISOString() }
          : l,
      ),
    );
  }

  // ── Unified action handler (called by SellerListingCard's onDelete) ─────────

  /**
   * Decides whether to show a delete or cancel dialog based on bid_count.
   *  - No bids → delete confirmation (removes record entirely)
   *  - Has bids → cancel confirmation (sets auction_status = 'cancelled')
   */
  function handleDelete(listing: ListingRow) {
    if (listing.bid_count > 0 && listing.auction_status === 'active') {
      // Has bids → offer cancel instead
      Alert.alert(
        'Cancel Listing',
        'This listing has bids. Cancelling will void all bids. Are you sure?',
        [
          { text: 'Keep Listing', style: 'cancel' },
          {
            text: 'Cancel Listing',
            style: 'destructive',
            onPress: () => performCancel(listing),
          },
        ],
      );
    } else {
      // No bids → delete
      Alert.alert(
        'Delete Listing',
        `Are you sure you want to delete "${listing.event_name}"? This cannot be undone.`,
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Delete',
            style: 'destructive',
            onPress: () => performDelete(listing),
          },
        ],
      );
    }
  }

  // ── Filter state ────────────────────────────────────────────────────────────
  const [filter, setFilter] = useState<FilterKey>(resolvedInitialFilter);

  // Counts are always computed from the FULL array so tab badges stay accurate.
  const filterCounts = useMemo(() => {
    const c = { all: listings.length, active: 0, ended: 0, sold: 0 };
    for (const l of listings) {
      if (l.status === 'sold')                                                            c.sold++;
      else if (l.auction_status === 'ended' || l.auction_status === 'cancelled'
            || new Date(l.ends_at) <= new Date())                                         c.ended++;
      else                                                                                c.active++;
    }
    return c;
  }, [listings]);

  const filteredListings = useMemo(() => {
    if (filter === 'all')    return listings;
    if (filter === 'active') return listings.filter(l =>
      l.status !== 'sold' && l.auction_status !== 'ended' && l.auction_status !== 'cancelled'
        && new Date(l.ends_at) > new Date(),
    );
    if (filter === 'ended')  return listings.filter(l =>
      l.status !== 'sold' && (l.auction_status === 'ended' || l.auction_status === 'cancelled'
        || new Date(l.ends_at) <= new Date()),
    );
    /* sold */ return listings.filter(l => l.status === 'sold');
  }, [listings, filter]);

  return (
    <SafeAreaView style={s.safe}>

      {/* ── Top bar ────────────────────────────────────────────────── */}
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>{'\u2190'}</Text>
        </Pressable>
        <Text style={s.topTitle}>My Listings</Text>
        <View style={s.backBtn} />
      </View>

      {/* ── Filter tabs ──────────────────────────────────────────── */}
      {!loading && listings.length > 0 && (
        <View style={s.filterBarWrap}>
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={s.filterRow}
          >
            {(
              [
                { key: 'all',    label: 'All' },
                { key: 'active', label: 'Active' },
                { key: 'ended',  label: 'Ended' },
                { key: 'sold',   label: 'Sold' },
              ] as const
            ).map((tab) => {
              const active = filter === tab.key;
              const count  = filterCounts[tab.key];
              return (
                <Pressable
                  key={tab.key}
                  style={[s.filterTab, active && s.filterTabActive]}
                  onPress={() => setFilter(tab.key)}
                >
                  <Text style={[s.filterTabText, active && s.filterTabTextActive]}>
                    {tab.label} ({count})
                  </Text>
                </Pressable>
              );
            })}
          </ScrollView>
        </View>
      )}

      {/* ── Content ────────────────────────────────────────────────── */}
      {loading ? (
        <View style={s.loader}>
          <ActivityIndicator color={colors.primary} size="large" />
        </View>
      ) : (
        <FlatList
          data={filteredListings}
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
              <Text style={s.emptyIcon}>
                {filter === 'all' ? '📋' : filter === 'active' ? '🔴' : filter === 'ended' ? '🏁' : '💰'}
              </Text>
              <Text style={s.emptyTitle}>
                {filter === 'all'    ? 'No listings yet'
                  : filter === 'active' ? 'No active auctions'
                  : filter === 'ended'  ? 'No ended auctions'
                  : 'Nothing sold yet'}
              </Text>
              {filter === 'all' && (
                <Text style={s.emptyText}>
                  Tap the + tab to create your first listing
                </Text>
              )}
            </View>
          }
          renderItem={({ item }) => (
            <SellerListingCard
              listing={item}
              coverUrl={item.coverUrl}
              onPress={() => router.push(`/listing/${item.id}`)}
              onDelete={() => handleDelete(item)}
            />
          )}
        />
      )}

    </SafeAreaView>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  safe:      { flex: 1, backgroundColor: colors.bg },

  // Top bar (matches settings screens pattern)
  topBar:    { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
               paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
               borderBottomWidth: 1, borderBottomColor: colors.border },
  backBtn:   { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  backArrow: { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle:  { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  // Filter tabs
  filterBarWrap: {
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  filterRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  filterTab: {
    height: 32,
    paddingHorizontal: 14,
    justifyContent: 'center',
    alignItems: 'center',
    borderRadius: radius.full,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.bgCard,
  },
  filterTabActive: {
    backgroundColor: colors.primarySoft,
    borderColor: colors.primary,
  },
  filterTabText: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    color: colors.textMuted,
    lineHeight: 16,
  },
  filterTabTextActive: {
    color: colors.primary,
  },

  loader: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  list:   { padding: spacing.md, paddingBottom: 120 },

  // Empty state
  empty: {
    flex: 1,
    alignItems: 'center',
    paddingTop: 80,
    gap: spacing.sm,
  },
  emptyIcon:  { fontSize: 48 },
  emptyTitle: { fontSize: fontSize.lg, fontWeight: '700', color: colors.text },
  emptyText:  {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    textAlign: 'center',
    paddingHorizontal: spacing.xl,
  },
});
