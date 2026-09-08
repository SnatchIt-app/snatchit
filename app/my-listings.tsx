/**
 * app/my-listings.tsx — Seller's listings (V2).
 *
 * PRESENTATION rebuilt on the V2 system; the DATA LAYER is unchanged: the same
 * listings fetch, the per-listing transfer map that drives "send the tickets",
 * hard-load + focus refetch + pull-to-refresh, and the exact delete/cancel rules
 * (no bids → delete; has bids → cancel via `cancel_listing`, both confirmed). The
 * six emoji filter tabs become Active/Send/Sold/Ended/All chips; the card is the
 * V2 SellerListingCard. Closes the seller loop from the redesigned Profile.
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';
import { Alert, FlatList, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { getCoverImageUrl } from '@/src/lib/coverImage';
import SellerListingCard from '@/src/components/SellerListingCard';
import ScreenState from '@/src/components/ScreenState';
import { isNetworkError } from '@/src/hooks/useNetworkStatus';
import { Chip, EmptyState, IconButton, Skeleton } from '@/src/components/ui';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { Listing } from '@/src/types';

type ListingRow = Listing & { coverUrl: string | null };

type FilterKey = 'all' | 'active' | 'needs_action' | 'ended' | 'sold';
const VALID_FILTERS: FilterKey[] = ['all', 'active', 'needs_action', 'ended', 'sold'];

type TransferInfo = { transferId: string; status: string };

export default function MyListingsScreen() {
  const { session } = useAuth();
  const userId = session?.user.id ?? '';
  const insets = useSafeAreaInsets();

  const { filter: filterParam } = useLocalSearchParams<{ filter?: string }>();
  const resolvedInitialFilter: FilterKey =
    filterParam && VALID_FILTERS.includes(filterParam as FilterKey) ? (filterParam as FilterKey) : 'all';

  const [listings, setListings] = useState<ListingRow[]>([]);
  const [transfers, setTransfers] = useState<Map<string, TransferInfo>>(new Map());
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadError, setLoadError] = useState<'offline' | 'error' | null>(null);

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
      setLoadError(isNetworkError(error) ? 'offline' : 'error');
      return;
    }
    setLoadError(null);

    const rows: ListingRow[] = (data as Listing[]).map((listing) => ({
      ...listing,
      coverUrl: getCoverImageUrl(listing.cover_image_path),
    }));
    setListings(rows);

    // Transfer state per listing — drives the "send the tickets" CTA. Read-only.
    const { data: txData } = await supabase
      .from('transfers')
      .select('id, listing_id, status')
      .eq('seller_id', userId);
    const map = new Map<string, TransferInfo>();
    for (const t of (txData ?? []) as { id: string; listing_id: string; status: string }[]) {
      map.set(t.listing_id, { transferId: t.id, status: t.status });
    }
    setTransfers(map);
  }, [userId]);

  useEffect(() => {
    fetchMyListings(false).finally(() => { initialLoadDone.current = true; });
  }, [fetchMyListings]);

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

  // ── Delete / cancel (unchanged rules) ────────────────────────────────────────

  async function performDelete(listing: ListingRow) {
    if (listing.bid_count > 0 || listing.auction_status !== 'active') {
      Alert.alert('Cannot delete', 'This listing has bids and cannot be deleted.');
      return;
    }
    const { error } = await supabase.from('listings').delete().eq('id', listing.id).eq('seller_id', userId);
    if (error) { Alert.alert('Delete failed', error.message); return; }
    setListings((prev) => prev.filter((l) => l.id !== listing.id));
    if (listing.cover_image_path) {
      try {
        await supabase.storage.from('auction-media').remove([listing.cover_image_path]);
      } catch (e) {
        console.warn('[MyListings] cover image cleanup failed:', e);
      }
    }
  }

  async function performCancel(listing: ListingRow) {
    const { error } = await supabase.rpc('cancel_listing', { p_listing_id: listing.id, p_user_id: userId });
    if (error) { Alert.alert('Cancel failed', error.message); return; }
    setListings((prev) =>
      prev.map((l) =>
        l.id === listing.id ? { ...l, auction_status: 'cancelled' as const, ended_at: new Date().toISOString() } : l,
      ),
    );
  }

  function handleDelete(listing: ListingRow) {
    if (listing.bid_count > 0 && listing.auction_status === 'active') {
      Alert.alert('Cancel listing', 'This listing has bids. Cancelling will void all bids. Are you sure?', [
        { text: 'Keep listing', style: 'cancel' },
        { text: 'Cancel listing', style: 'destructive', onPress: () => performCancel(listing) },
      ]);
    } else {
      Alert.alert('Delete listing', `Are you sure you want to delete "${listing.event_name}"? This cannot be undone.`, [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Delete', style: 'destructive', onPress: () => performDelete(listing) },
      ]);
    }
  }

  // ── Filters (unchanged logic) ────────────────────────────────────────────────

  const [filter, setFilter] = useState<FilterKey>(resolvedInitialFilter);

  const needsTicketSend = useCallback(
    (l: ListingRow) => l.status === 'sold' && transfers.get(l.id)?.status === 'pending',
    [transfers],
  );

  const filterCounts = useMemo(() => {
    const c = { all: listings.length, active: 0, needs_action: 0, ended: 0, sold: 0 };
    for (const l of listings) {
      if (l.status === 'sold') {
        c.sold++;
        if (needsTicketSend(l)) c.needs_action++;
      } else if (l.auction_status === 'ended' || l.auction_status === 'cancelled' || new Date(l.ends_at) <= new Date()) {
        c.ended++;
      } else {
        c.active++;
      }
    }
    return c;
  }, [listings, needsTicketSend]);

  const filteredListings = useMemo(() => {
    if (filter === 'all') return listings;
    if (filter === 'active') return listings.filter((l) =>
      l.status !== 'sold' && l.auction_status !== 'ended' && l.auction_status !== 'cancelled' && new Date(l.ends_at) > new Date());
    if (filter === 'needs_action') return listings.filter(needsTicketSend);
    if (filter === 'ended') return listings.filter((l) =>
      l.status !== 'sold' && (l.auction_status === 'ended' || l.auction_status === 'cancelled' || new Date(l.ends_at) <= new Date()));
    return listings.filter((l) => l.status === 'sold');
  }, [listings, filter, needsTicketSend]);

  const TABS: { key: FilterKey; label: string }[] = [
    { key: 'all', label: 'All' },
    { key: 'active', label: 'Active' },
    { key: 'needs_action', label: 'Send tickets' },
    { key: 'sold', label: 'Sold' },
    { key: 'ended', label: 'Ended' },
  ];

  return (
    <View style={s.root}>
      <View style={[s.header, { paddingTop: insets.top + v2.space.sm }]}>
        <IconButton glyph="back" onPress={() => router.back()} accessibilityLabel="Back" />
        <Text style={[textStyle('displaySm'), s.headerTitle]} accessibilityRole="header">My listings</Text>
        <View style={s.headerSpacer} />
      </View>

      {!loading && listings.length > 0 ? (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.filters} keyboardShouldPersistTaps="handled">
          {TABS.map((tab) => (
            <Chip
              key={tab.key}
              label={tab.label}
              count={filterCounts[tab.key] > 0 ? filterCounts[tab.key] : undefined}
              selected={filter === tab.key}
              onPress={() => setFilter(tab.key)}
            />
          ))}
        </ScrollView>
      ) : null}

      {loading ? (
        <View style={s.list}>
          {[0, 1, 2, 3].map((i) => (
            <View key={i} style={s.skelRow}>
              <Skeleton width={76} height={76} />
              <View style={s.skelBody}>
                <Skeleton height={16} width="70%" />
                <Skeleton height={12} width="45%" style={{ marginTop: 8 }} />
                <Skeleton height={12} width="55%" style={{ marginTop: 6 }} />
              </View>
            </View>
          ))}
        </View>
      ) : loadError && listings.length === 0 ? (
        <ScreenState state={loadError} onRetry={() => fetchMyListings(false)} />
      ) : (
        <FlatList
          data={filteredListings}
          keyExtractor={(item) => item.id}
          contentContainerStyle={s.list}
          showsVerticalScrollIndicator={false}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={v2.brand.red} />}
          ListEmptyComponent={
            <EmptyState
              title={
                filter === 'all' ? 'No listings yet'
                  : filter === 'active' ? 'No active auctions'
                  : filter === 'needs_action' ? 'All caught up'
                  : filter === 'ended' ? 'No ended auctions'
                  : 'Nothing sold yet'
              }
              body={
                filter === 'all' ? 'Tap the Create tab to list your first ticket.'
                  : filter === 'needs_action' ? 'No tickets waiting to be sent.'
                  : 'Nothing here yet.'
              }
              action={filter === 'all' ? { label: 'Create a listing', onPress: () => router.push('/(tabs)/create') } : undefined}
            />
          }
          renderItem={({ item }) => {
            const sendPending = needsTicketSend(item);
            const transferId = transfers.get(item.id)?.transferId;
            return (
              <SellerListingCard
                listing={item}
                coverUrl={item.coverUrl}
                needsTicketSend={sendPending}
                onPress={() =>
                  sendPending && transferId
                    ? router.push(`/transfer/send/${transferId}` as never)
                    : router.push(`/listing/${item.id}`)
                }
                onDelete={() => handleDelete(item)}
                onEdit={() => router.push(`/listing/edit/${item.id}` as never)}
              />
            );
          }}
        />
      )}
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },

  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: v2.space.md, paddingBottom: v2.space.sm,
    borderBottomWidth: 1, borderBottomColor: v2.border.default,
  },
  headerTitle: { color: v2.text.primary },
  headerSpacer: { width: 44 },

  filters: { gap: v2.space.sm, paddingHorizontal: v2.space.lg, paddingVertical: v2.space.md },

  list: { paddingHorizontal: v2.space.lg, paddingBottom: 96, paddingTop: v2.space.sm },
  skelRow: { flexDirection: 'row', gap: v2.space.md, paddingVertical: v2.space.sm },
  skelBody: { flex: 1, justifyContent: 'center' },
});
